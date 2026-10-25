// Optional integration check against an expendable OpenWrt/LuCI container.
// Requires playwright-core and a local Chromium/Chrome installation.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
(async () => {
	const browser = await chromium.launch({
		executablePath: process.env.CHROME_BIN || '/usr/bin/google-chrome',
		headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']
	});
	try {
		const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
		const base = process.env.LUCI_URL || 'http://127.0.0.1:18080';
		await page.goto(base + '/cgi-bin/luci/admin/system/argon-config-app');
		const login = page.getByRole('button', { name: 'Log in', exact: true });
		await login.waitFor();
		await page.locator('input[name=luci_username]').fill('root');
		await page.locator('input[name=luci_password]').fill(process.env.LUCI_PASSWORD || '');
		await login.click();
		await page.getByRole('heading', { name: 'Argon theme configuration', exact: true }).waitFor();
		const errors = [];
		page.on('pageerror', error => errors.push(error.message));
		const lightTab = page.locator('.cbi-tabmenu a').filter({ hasText: /^Light mode$/ });
		await lightTab.click();
		const primary = page.locator('input[id$=".primary"]');
		const original = await primary.inputValue();
		await primary.fill('#123abc');

		const filename = 'browser test #1.png';
		const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64');
		async function upload(name) {
			await page.getByRole('button', { name: 'Upload background', exact: true }).click();
			await page.locator('.modal input[type=file]').setInputFiles({ name, mimeType: 'image/png', buffer: png });
			await page.locator('.modal').getByRole('button', { name: 'Upload', exact: true }).click();
		}
		await upload(filename);
		const row = page.getByRole('row').filter({ hasText: filename });
		await row.waitFor();
		assert.equal(await primary.inputValue(), '#123abc');
		await page.getByRole('button', { name: 'Refresh', exact: true }).click();
		assert.equal(await primary.inputValue(), '#123abc');
		await row.getByRole('button', { name: 'Preview', exact: true }).click();
		await page.locator('.modal img').waitFor();
		await page.waitForFunction(() => document.querySelector('.modal img')?.naturalWidth > 0);
		await page.locator('.modal').getByRole('button', { name: 'Close', exact: true }).click();
		await upload(filename);
		await page.getByText('A file with this name already exists. Rename the file or delete the old one first.', { exact: true }).waitFor();
		assert.equal(await row.count(), 1);
		await upload('blocked.html');
		await page.locator('.alert-message.error').filter({ hasText: 'Supported formats:' }).waitFor();
		await row.getByRole('button', { name: 'Delete', exact: true }).click();
		await page.locator('.modal').getByRole('button', { name: 'Cancel', exact: true }).click();
		assert.equal(await row.count(), 1);
		await row.getByRole('button', { name: 'Delete', exact: true }).click();
		await page.locator('.modal').getByRole('button', { name: 'Delete', exact: true }).click();
		await row.waitFor({ state: 'detached' });
		assert.equal(await primary.inputValue(), '#123abc');

		await page.getByRole('button', { name: 'Reset', exact: true }).click();
		await lightTab.click();
		assert.equal(await primary.inputValue(), original);
		await primary.fill('#123abc');
		await page.getByRole('button', { name: 'Save', exact: true }).click();
		await page.getByRole('button', { name: 'Save', exact: true }).waitFor({ state: 'visible' });
		await lightTab.click();
		assert.equal(await primary.inputValue(), '#123abc');
		await page.locator('.cbi-page-actions .cbi-button-apply').click();
		await page.getByText('Configuration changes applied.', { exact: false }).waitFor({ timeout: 45000 });
		await page.reload();
		await lightTab.click();
		assert.equal(await primary.inputValue(), '#123abc');
		assert.deepEqual(errors, []);
		await page.screenshot({ path: process.env.SCREENSHOT || '/tmp/argon-config-browser.png', fullPage: true });
		console.log('PASS: real LuCI upload, preview, duplicate rejection, invalid format, delete/cancel, refresh, unsaved values, Reset, Save and Save & Apply');
	} finally {
		await browser.close();
	}
})().catch(error => { console.error(error); process.exit(1); });
