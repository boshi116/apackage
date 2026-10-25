// Optional integration test; use an expendable English LuCI instance only.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
(async () => {
	const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN || '/usr/bin/google-chrome',
		headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
	try {
		const page = await browser.newPage();
		await page.goto((process.env.LUCI_URL || 'http://127.0.0.1:18082') + '/cgi-bin/luci/admin/system/argon-config-app');
		await page.getByRole('button', { name: 'Log in', exact: true }).waitFor();
		await page.locator('input[name=luci_username]').fill('root');
		await page.locator('input[name=luci_password]').fill(process.env.LUCI_PASSWORD || '');
		await page.getByRole('button', { name: 'Log in', exact: true }).click();
		await page.getByRole('heading', { name: 'Argon theme configuration', exact: true }).waitFor();
		const errors = []; page.on('pageerror', error => errors.push(error.message));
		const source = page.locator('select[id$=".online_wallpaper"]');
		const collection = page.locator('input[id$=".unsplash_collection"]');
		const tag = page.locator('input[id$=".wallhaven_tag"]');
		const key = page.locator('input[id$=".use_api_key"]');
		const exact = page.locator('[id$=".use_exact_resolution"] input[type=checkbox]');
		async function apply() {
			await page.locator('.cbi-page-actions .cbi-button-apply').click();
			await page.getByText('Configuration changes applied.', { exact: false }).waitFor({ timeout: 45000 });
			await page.reload();
			await source.waitFor();
		}
		async function settings() {
			return page.evaluate(async () => {
				const uci = await L.require('uci');
				const s = uci.sections('argon', 'global')[0];
				return { source: s.online_wallpaper, collection: s.unsplash_collection, tag: s.wallhaven_tag, exact: s.use_exact_resolution };
			});
		}
		await source.selectOption('unsplash');
		await key.fill(''); await key.blur();
		assert.ok(await key.evaluate(input => input.classList.contains('cbi-input-invalid')));
		await key.fill('browser-test-access-key');
		await collection.fill('317099, a_b-C');
		await apply();
		assert.equal(await source.inputValue(), 'unsplash');
		assert.equal(await collection.inputValue(), '317099,a_b-C');
		assert.equal((await settings()).source, 'unsplash_317099,a_b-C');
		await collection.fill('123');
		await apply();
		assert.equal((await settings()).source, 'unsplash_123');
		await collection.fill('999');
		await key.fill('');
		await page.getByRole('button', { name: 'Reset', exact: true }).click();
		assert.equal(await collection.inputValue(), '123');
		assert.equal(await key.inputValue(), 'browser-test-access-key');

		await source.selectOption('wallhaven');
		await tag.fill(''); await tag.blur();
		assert.equal(await exact.isVisible(), false);
		await tag.fill('yqg6r7'); await tag.blur();
		assert.ok(await tag.evaluate(input => input.classList.contains('cbi-input-invalid')));
		await tag.fill(' 37 '); await tag.blur();
		await exact.waitFor({ state: 'visible' });
		await key.fill('');
		await exact.uncheck();
		await apply();
		assert.equal((await settings()).source, 'wallhaven_37');
		assert.equal((await settings()).exact, '0');
		assert.equal(await tag.inputValue(), '37');
		assert.equal(await key.inputValue(), '');

		await source.selectOption('bing');
		await apply();
		assert.equal((await settings()).tag, '37');
		assert.equal((await settings()).collection, '123');
		await source.selectOption('wallhaven');
		assert.equal(await tag.inputValue(), '37');
		assert.equal(await exact.isChecked(), false);
		await tag.fill('');
		await apply();
		assert.equal((await settings()).source, 'wallhaven');
		assert.equal(await exact.isVisible(), false);
		assert.deepEqual(errors, []);
		await page.screenshot({ path: '/tmp/argon-wallpaper-filters.png', fullPage: true });
		console.log('PASS: actual LuCI collection roundtrip, filter-only edits, Reset, optional Wallhaven key, required Unsplash key, tag validation, resolution toggle, clearing filters and switching sources');
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
