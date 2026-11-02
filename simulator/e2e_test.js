const { chromium } = require('playwright-core');
const path = require('path');
const assert = require('assert');

(async () => {
  const browser = await chromium.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto(process.env.LUMAIRIE_SIM_URL || 'http://localhost:8787', { waitUntil: 'networkidle' });
  await page.waitForTimeout(2500);
  console.log(JSON.stringify({
    title: await page.title(),
    semantics: await page.locator('flt-semantics').count(),
    text: (await page.locator('body').innerText()).slice(0, 400),
  }));
  await page.screenshot({ path: path.join(__dirname, 'qa-home.png'), fullPage: true });
  const blank = await page.screenshot({ clip: { x: 826, y: 167, width: 86, height: 144 } });
  const chooserPromise = page.waitForEvent('filechooser');
  await page.mouse.click(868, 554);
  const chooser = await chooserPromise;
  await chooser.setFiles(process.env.LUMAIRIE_TEST_PHOTO ||
    'C:\\Windows\\Web\\Wallpaper\\ThemeA\\img22.jpg');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(__dirname, 'qa-upload.png'), fullPage: true });
  await page.mouse.click(454, 827);
  await page.waitForTimeout(6500);
  await page.screenshot({ path: path.join(__dirname, 'qa-send.png'), fullPage: true });
  const good = await page.screenshot({ clip: { x: 826, y: 167, width: 86, height: 144 } });
  assert(!blank.equals(good), 'Photo transfer did not change the simulated display');
  await page.mouse.click(891, 503);
  await page.mouse.click(453, 826);
  await page.waitForTimeout(3500);
  await page.screenshot({ path: path.join(__dirname, 'qa-corrupt.png'), fullPage: true });
  const afterCorruption = await page.screenshot({ clip: { x: 826, y: 180, width: 86, height: 144 } });
  assert(good.equals(afterCorruption), 'Corrupt transfer changed the previous image');
  await page.mouse.click(963, 517);
  await page.mouse.click(453, 826);
  await page.waitForTimeout(3500);
  await page.screenshot({ path: path.join(__dirname, 'qa-interrupt.png'), fullPage: true });
  const afterInterruption = await page.screenshot({ clip: { x: 826, y: 180, width: 86, height: 144 } });
  assert(good.equals(afterInterruption), 'Interrupted transfer changed the previous image');
  console.log('Photo upload, refresh, corruption retention, and interruption retention passed.');
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });
