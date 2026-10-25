// Optional check; provision a read-only test login on a disposable LuCI instance first.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
(async () => {
	const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN || '/usr/bin/google-chrome',
		headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
	try {
		const page = await browser.newPage();
		await page.goto((process.env.LUCI_URL || 'http://127.0.0.1:18082') + '/cgi-bin/luci/admin/system/argon-config-app');
		await page.locator('input[name=luci_username]').fill(process.env.LUCI_USERNAME || 'argon-viewer');
		await page.locator('input[name=luci_password]').fill(process.env.LUCI_PASSWORD || '');
		await page.getByRole('button', { name: 'Log in', exact: true }).click();
		await page.getByRole('heading', { name: 'Argon theme configuration', exact: true }).waitFor();
		assert.equal(await page.getByRole('button', { name: 'Upload background', exact: true }).isDisabled(), true);
		assert.equal(await page.locator('select[id$=".online_wallpaper"]').isDisabled(), true);
		const deletes = page.getByRole('button', { name: 'Delete', exact: true });
		assert.ok(await deletes.count() > 0);
		for (const button of await deletes.all()) assert.equal(await button.isDisabled(), true);
		const result = await page.evaluate(async () => {
			const rpc = await L.require('rpc');
			const uci = await L.require('uci');
			const remove = rpc.declare({ object: 'luci.argon_config', method: 'remove', params: ['filename'], reject: true });
			const set = rpc.declare({ object: 'uci', method: 'set', params: ['config', 'section', 'values'], reject: true });
			async function denied(call) {
				try { await call(); return ''; }
				catch (error) { return error.message; }
			}
			return {
				remove: await denied(() => remove('upgrade retained #1.png')),
				set: await denied(() => set('argon', uci.sections('argon', 'global')[0]['.name'], { online_wallpaper: 'bing' }))
			};
		});
		assert.match(result.remove, /[Pp]ermission denied|[Aa]ccess denied/);
		assert.match(result.set, /[Pp]ermission denied|[Aa]ccess denied/);
		console.log('PASS: read-only LuCI disables source/upload/delete controls; direct file and UCI mutations are denied.');
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
