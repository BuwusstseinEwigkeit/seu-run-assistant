const { test, expect } = require('@playwright/test');
const path = require('path');
const { pathToFileURL } = require('url');

test.use({ channel: 'chrome' });

test('首屏实际表单与大图教程在桌面和手机均可读', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(pageUrl);

  const seuEntry = page.locator('#hero-seu-entry');
  await expect(seuEntry).toBeVisible();
  await expect(seuEntry).toHaveAttribute('href', 'https://tyxsjpt.seu.edu.cn/h5/#/pages/home/index');
  await expect(seuEntry).toHaveAttribute('target', '_blank');
  await expect(seuEntry).toHaveAttribute('rel', /noopener/);
  await expect(page.locator('.hero-flow-step')).toHaveCount(4);
  await expect(page.locator('#hero-quick-panel #input-token')).toBeVisible();

  const typography = await page.evaluate(() => ({
    bodyFamily: getComputedStyle(document.body).fontFamily,
    displayFamily: getComputedStyle(document.querySelector('.hero-brand-title')).fontFamily,
    displaySize: parseFloat(getComputedStyle(document.querySelector('.hero-brand-title')).fontSize)
  }));
  expect(typography.bodyFamily).toContain('Noto Sans SC Local');
  expect(typography.displayFamily).toContain('Barlow Condensed Local');
  expect(typography.displaySize).toBeGreaterThanOrEqual(72);

  await page.locator('#hero-start-tool').click();
  await expect(page.locator('#tab-run')).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('#input-token')).toBeFocused();

  await page.locator('#tab-guide').click();
  await expect(page.locator('#project-reference-strip .reference-shot img')).toHaveCount(3);
  const firstReferenceSize = await page.locator('#project-reference-strip .reference-shot img').first().boundingBox();
  expect(firstReferenceSize.width).toBeGreaterThanOrEqual(560);

  const referenceImages = page.locator('#project-reference-strip .reference-shot img');
  for (let index = 0; index < await referenceImages.count(); index += 1) {
    await referenceImages.nth(index).scrollIntoViewIfNeeded();
    await expect.poll(() => referenceImages.nth(index).evaluate((image) => (
      image.complete && image.naturalWidth > 0
    ))).toBe(true);
  }
  const referenceRatios = await referenceImages.evaluateAll((images) => (
    images.map((image) => {
      const bounds = image.getBoundingClientRect();
      return {
        natural: image.naturalWidth / image.naturalHeight,
        rendered: bounds.width / bounds.height
      };
    })
  ));
  referenceRatios.forEach(({ natural, rendered }) => {
    expect(Math.abs(rendered - natural)).toBeLessThan(0.03);
  });

  const smallestHelperText = await page.locator('.guide-note, .security-note, .reference-caption small').evaluateAll((elements) => (
    Math.min(...elements.map((element) => parseFloat(getComputedStyle(element).fontSize)))
  ));
  expect(smallestHelperText).toBeGreaterThanOrEqual(13);

  await page.locator('#project-reference-strip .reference-shot').first().click();
  await expect(page.locator('#image-lightbox')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#image-lightbox')).toBeHidden();

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(pageUrl);
  const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  expect(hasHorizontalOverflow).toBe(false);
});
