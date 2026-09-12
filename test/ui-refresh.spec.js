const { test, expect } = require('@playwright/test');
const path = require('path');
const { pathToFileURL } = require('url');

test.use({ channel: 'chrome' });

test('首屏说明 SEU 登录流程并把用户带到填写区', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  const seuEntry = page.locator('#hero-seu-entry');
  await expect(seuEntry).toBeVisible();
  await expect(seuEntry).toHaveAttribute('href', 'https://tyxsjpt.seu.edu.cn/h5/#/pages/home/index');
  await expect(seuEntry).toHaveAttribute('target', '_blank');
  await expect(seuEntry).toHaveAttribute('rel', /noopener/);
  await expect(page.locator('.hero-flow-step')).toHaveCount(4);

  await page.locator('#hero-start-tool').click();
  await expect(page.locator('#tab-run')).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('#input-token')).toBeFocused();

  await page.locator('#tab-guide').click();
  await expect(page.locator('#project-reference-strip .reference-shot img')).toHaveCount(3);

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(pageUrl);
  const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  expect(hasHorizontalOverflow).toBe(false);
});
