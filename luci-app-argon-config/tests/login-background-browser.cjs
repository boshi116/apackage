// Optional live/fallback check against a disposable instance configured by the caller.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
(async () => {
	assert.ok(process.env.EXPECT_BACKGROUND, 'Set EXPECT_BACKGROUND to the expected image URL pattern.');
	const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN || '/usr/bin/google-chrome',
		headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
	try {
		const page = await browser.newPage();
		await page.goto((process.env.LUCI_URL || 'http://127.0.0.1:18082') + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
		await page.getByRole('button', { name: 'Log in', exact: true }).waitFor();
		await page.waitForFunction(() => document.querySelector('#main-bg img')?.naturalWidth > 0, null, { timeout: 30000 });
		const image = await page.locator('#main-bg img').evaluate(img => ({ url: img.currentSrc, width: img.naturalWidth, height: img.naturalHeight }));
		assert.match(image.url, new RegExp(process.env.EXPECT_BACKGROUND));
		assert.equal(image.width, Number(process.env.EXPECT_WIDTH));
		assert.equal(image.height, Number(process.env.EXPECT_HEIGHT));
		console.log(`PASS: actual login page decoded the expected ${image.width}x${image.height} background image.`);
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
