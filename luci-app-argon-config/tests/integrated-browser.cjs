// Optional compatibility check against a disposable English LuCI + Argon 3 instance.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
(async () => {
	const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN || '/usr/bin/google-chrome',
		headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
	try {
		const base = process.env.LUCI_URL || 'http://127.0.0.1:18084';
		const page = await browser.newPage();
		const errors = [];
		page.on('pageerror', error => errors.push(error.message));
		await page.goto(base + '/cgi-bin/luci/admin/system/argon-config');
		await page.locator('input[name=luci_username]').fill('root');
		await page.locator('input[name=luci_password]').fill(process.env.LUCI_PASSWORD || '');
		await page.getByRole('button', { name: 'Log in', exact: true }).click();
		await page.getByRole('heading', { name: 'Argon theme configuration', exact: true }).waitFor();
		const primary = page.locator('input[id$=".primary"]');
		await primary.waitFor();
		assert.equal(await primary.inputValue(), process.env.EXPECT_PRIMARY || '#345def');
		assert.equal(await page.locator('a[href$="/admin/system/argon-config"]').count(), 1);
		assert.equal(await page.locator('a[href*="/admin/system/argon-config-app"]').count(), 0);
		const standalone = await page.request.get(base + '/cgi-bin/luci/admin/system/argon-config-app');
		assert.equal(standalone.status(), 404);
		assert.deepEqual(errors, []);
		console.log('PASS: Argon 3 native settings open with preserved color, one menu entry, hidden standalone route and no JavaScript errors.');
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
