let testApi;
try {
  testApi = require('@playwright/test');
} catch (error) {
  testApi = require('playwright/test');
}
const { test, expect } = testApi;
const path = require('path');
const fs = require('fs');
const { pathToFileURL } = require('url');

// Synthetic JWT only: keeps the regression test offline and free of credentials.
const TEST_JWT = 'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoidGVzdC11c2VyIiwiZXhwIjoxNzkyNjAyNTcyLCJuYmYiOjE3OTAwMTA1NzJ9.signature';

test.use({ channel: 'chrome' });

test('首屏实际表单与大图教程在桌面和手机均可读', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.route('http://127.0.0.1:17864/health', async (route) => {
    await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ ok: false }) });
  });
  await page.goto(pageUrl);

  await expect(page.locator('#hero-seu-entry')).toHaveCount(0);
  await expect(page.locator('.hero-network-note')).toContainText('网页不能替你启动 .bat');
  await expect(page.locator('.hero-flow-step')).toHaveCount(4);
  await expect(page.locator('.hero-flow-step.is-current')).toHaveCount(1);
  await expect(page.locator('#hero-extract-token')).toBeVisible();
  await expect(page.locator('#token-bridge-status')).toHaveAttribute('role', 'status');
  await expect(page.locator('#token-bridge-status')).toContainText('本地桥接服务未启动');
  await page.route('http://127.0.0.1:17864/scan', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ ok: true, token: TEST_JWT, copied: true })
    });
  });
  await page.locator('#hero-extract-token').click();
  await expect(page.locator('#input-token')).toHaveValue(TEST_JWT);
  await expect(page.locator('#token-bridge-status')).toContainText('Token 已提取并填入当前页面');
  await expect(page.locator('.date-chip[data-date-offset="0"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.date-chip[data-date-offset="0"]')).toHaveClass(/is-selected/);
  await expect(page.locator('#hero-quick-panel #input-token')).toBeVisible();
  await expect(page.locator('#consistency-details')).not.toHaveAttribute('open', '');
  await expect(page.locator('.photo-upload-zone')).toHaveCount(2);
  await expect(page.locator('#preview-image_start')).toHaveAttribute('data-file-target', 'input-image_start');
  await expect(page.locator('.date-chip')).toHaveCount(3);
  await expect(page.locator('#exercise-date-picker')).toBeVisible();
  await page.locator('[data-date-offset="-1"]').click();
  const selectedDate = await page.locator('#exercise-date-picker').inputValue();
  const selectedTimes = await page.evaluate(() => ({
    start: document.querySelector('#exercise-start_time').value.slice(0, 10),
    end: document.querySelector('#exercise-end_time').value.slice(0, 10)
  }));
  expect(selectedDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  expect(selectedTimes.start).toBe(selectedDate);
  expect(selectedTimes.end).toBe(selectedDate);
  await page.locator('#btn-generate-all').click();
  await expect(page.locator('#ml_Alert_Ok')).toBeVisible();
  await expect(page.locator('#exercise-date-picker')).toHaveValue(selectedDate);
  const randomizedDate = await page.locator('#exercise-start_time').inputValue();
  expect(randomizedDate.slice(0, 10)).toBe(selectedDate);
  await expect(page.locator('.date-chip[data-date-offset="-1"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.date-chip[data-date-offset="-1"]')).toHaveClass(/is-selected/);
  await expect(page.locator('.date-chip[data-date-offset="0"]')).toHaveAttribute('aria-pressed', 'false');
  await page.locator('#ml_Alert_Ok').click();
  await page.locator('#consistency-details > summary').click();
  await expect(page.locator('#consistency-enable-auto-check')).toBeChecked();
  await page.locator('#consistency-details > summary').click();
  await expect(page.locator('#consistency-enable-auto-check')).not.toBeChecked();

  const fileChooserPromise = page.waitForEvent('filechooser');
  await page.locator('#preview-image_start').click();
  const fileChooser = await fileChooserPromise;
  expect(fileChooser.isMultiple()).toBe(false);
  await fileChooser.setFiles({
    name: 'start.png',
    mimeType: 'image/png',
    buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64')
  });
  await expect(page.locator('#input-image_start')).toHaveValue(/start\.png/);

  await page.locator('#input-token').fill('bearer placeholder.token.value');
  await expect(page.locator('.hero-flow-step[data-flow-step="1"]')).toHaveClass(/is-complete/);
  await expect(page.locator('.hero-flow-step[data-flow-step="2"]')).toHaveClass(/is-complete/);
  await expect(page.locator('.hero-flow-step[data-flow-step="3"]')).toHaveClass(/is-current/);

  await page.locator('#input-image_end').setInputFiles({
    name: 'end.png',
    mimeType: 'image/png',
    buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64')
  });
  await expect(page.locator('.hero-flow-step[data-flow-step="3"]')).toHaveClass(/is-complete/);
  await expect(page.locator('.hero-flow-step[data-flow-step="4"]')).toHaveClass(/is-current/);
  await expect(page.locator('.hero-flow-step[data-flow-step="4"]')).not.toHaveClass(/is-complete/);
  await page.evaluate(() => window.ml_set_run_submit_status('运动记录提交成功。', 'success'));
  await expect(page.locator('.hero-flow-step[data-flow-step="4"]')).toHaveClass(/is-complete/);
  await page.locator('#exercise-end_time').fill(await page.locator('#exercise-end_time').inputValue());
  await expect(page.locator('.hero-flow-step[data-flow-step="4"]')).not.toHaveClass(/is-complete/);

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
  await expect(page.locator('#run-submit-status')).toHaveAttribute('role', 'status');
  await expect(page.locator('#run-submit-status')).toHaveAttribute('aria-live', 'polite');

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

test('新 Blade-Auth bearer Token 格式可通过本地校验', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  const html = fs.readFileSync(path.resolve(__dirname, '..', 'index.html'), 'utf8');
  expect(html).not.toMatch(/['\"](?:xweb_xhr|Sec-Fetch-[^'\"]+)['\"]\s*:/);
  expect(html).toContain('/api/blade-exercise/exerciseRecord/getStudentInfo');
  expect(html).toContain('/api/blade-exercise/v2/exerciseRecord');
  expect(html).toContain('ml_exercise_record_api + "/saveStartRecord"');
  expect(html).toContain('ml_exercise_record_api + "/saveRecord"');
  expect(html).not.toContain('/api/miniapp/student/checkToken');
  expect(html).toContain('ml_student_tenant_id || ml_system_info.tenant');
  expect(html).toContain('服务端拒绝了当前微信会话凭证（401）');
  // 小程序真实发送的请求头：OAuth 客户端凭据 + blade-requested-with + Blade-Auth
  expect(html).toContain('"Basic d2VjaGF0OndlY2hhdF9zZWNyZXQ="');
  expect(html).toContain('"blade-requested-with": ml_requested_with');
  // 图片上传走 v1 前缀，接口名是 uploadRecordImageStart / End
  expect(html).toContain('ml_exercise_upload_api + "/" + ml_api_name');
  expect(html).toContain('ml_api_name = "uploadRecordImageStart"');
  expect(html).toContain('ml_api_name = "uploadRecordImageEnd"');
  // 写接口必须经过加密请求包装
  expect(html).toContain('await ml_encrypted_post(');
  // 图片地址在 msg 里（data 是空对象 {}），取错字段会让 startImage 变成对象，
  // 服务端报 "Cannot deserialize value of type java.lang.String from Object value"
  expect(html).toContain('typeof response_json_data.msg === "string"');
  expect(html).toContain('throw new Error("上传图片失败：接口未返回照片地址")');
  // 内置场地表的 rule_id / plan_id 属于旧部署，提交前必须用服务端 listRule 覆盖，
  // 否则 saveStartRecord 会因为查不到规则返回 500 服务器异常
  expect(html).toContain('ml_build_route_tables_from_rules');
  expect(html).toContain('await ml_load_route_data_from_server(');
  expect(html).toContain('ml_sync_route_selects');
  // saveRecord 成功时 data 是 null / {}，拿它当成功标志会把成功当成失败
  expect(html).not.toContain('return response_json_data.data;');
  expect(html).toContain('console.log("saveRecord 响应:"');
  // 模拟间隔可调（默认 5 秒），单次与批量共用；旧的固定长等待已移除
  expect(html).toContain('id="input-simulated-delay"');
  expect(html).toContain('id="input-simulated-delay-batch"');
  expect(html).not.toContain('60 + Math.random() * 120');
  expect(html).not.toContain('8000 + Math.floor(Math.random() * 17000)');
  // 时间与轨迹合并成一键生成，且两者必须自洽
  expect(html).not.toContain('id="btn-random-track"');
  expect(html).not.toContain('id="btn-random-time"');
  expect(html).toContain('id="btn-generate-all"');
  expect(html).toContain('ml_generate_time_and_track');
  // 历史记录：提交前按天查重
  expect(html).toContain('getRecordByMonthOrWeek');
  expect(html).toContain('ml_find_existing_record');
  expect(html).toContain('当天已有记录');

  const tokenInput = page.locator('#input-token');
  const validationMessage = page.locator('#token-validation-message');
  await tokenInput.fill(`bearer ${TEST_JWT}`);
  await expect(validationMessage).toBeHidden();

  await page.locator('#tab-batch').click();
  const batchTokenInput = page.locator('#input-token-batch');
  const batchValidationMessage = page.locator('#token-validation-message-batch');
  await batchTokenInput.fill(`| Blade-Auth | bearer ${TEST_JWT} |`);
  await expect(batchValidationMessage).toBeHidden();
});

test('请求头与请求体加解密与小程序实现一致', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  const headers = await page.evaluate(() => window.ml_api_headers(`bearer ${'a.b.c'}`));
  expect(headers['Authorization']).toBe('Basic d2VjaGF0OndlY2hhdF9zZWNyZXQ=');
  expect(headers['blade-requested-with']).toBe('BladeHttpRequest');
  expect(headers['Blade-Auth']).toBe('bearer a.b.c');
  // 小程序从不发送 Tenant-Id，租户由 Token 自身携带
  expect(headers['Tenant-Id']).toBeUndefined();

  const crypto = await page.evaluate(async () => {
    const plainAscii = '{"a":1}';
    const plainChinese = `{"routeName":"九龙湖-桃园田径场","nowStatus":0,"speed":"0'00''"}`;
    return {
      ascii: await window.ml_aes_encrypt(plainAscii),
      chinese: await window.ml_aes_encrypt(plainChinese),
      roundTrip: (await window.ml_aes_decrypt(await window.ml_aes_encrypt(plainChinese))) === plainChinese
    };
  });

  // 固定密钥 + 固定 IV，密文必须是确定值；期望值由小程序的 crypto-js 实现生成
  expect(crypto.ascii).toBe('Z3cqNf4gCJDnin5PTUUr3A==');
  expect(crypto.chinese).toBe('KxyWzm0xwFctJP4Pqr6KRR0Y5KpLQ0WzYLzW4IEOY5IYw7gQ/UPr8u7GIlW/DNRBN9YuWRtvMpsyybjHGp6F8Kv/8M8VcWg7R0naqxYbtyM=');
  expect(crypto.roundTrip).toBe(true);
});

test('模拟间隔可调，单次与批量保持同步', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  const main = page.locator('#input-simulated-delay');
  const batch = page.locator('#input-simulated-delay-batch');
  await expect(main).toHaveValue('5');
  await expect(batch).toHaveValue('5');

  // 单次页面改值 → 批量页面跟着变
  await main.fill('0');
  expect(await batch.inputValue()).toBe('0');
  expect(await page.evaluate(() => window.ml_simulated_delay_ms())).toBe(0);

  // 切到批量页面改值 → 单次页面跟着变
  await page.locator('#tab-batch').click();
  await batch.fill('3');
  expect(await main.inputValue()).toBe('3');
  const delayMs = await page.evaluate(() => window.ml_simulated_delay_ms());
  expect(delayMs).toBeGreaterThanOrEqual(3000);
  expect(delayMs).toBeLessThan(5200);

  // 非法值回落到默认 5 秒
  await batch.fill('-4');
  expect(await main.inputValue()).toBe('5');
});

test('一键生成的时间与轨迹自洽（时长=距离×配速，且点在场地内）', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  const result = await page.evaluate(async () => {
    const planId = 'test-plan';
    const polygon = [
      { lat: 31.8890, lng: 118.8280 },
      { lat: 31.8890, lng: 118.8300 },
      { lat: 31.8910, lng: 118.8300 },
      { lat: 31.8910, lng: 118.8280 }
    ];
    window.ml_boundary_cache[planId] = { paths: polygon };
    window.ml_choose_route_data = {
      plan_id: planId,
      route_name: '测试场地',
      min_time: 4,
      max_time: 12,
      min_pace: 3.3333,
      max_pace: 10,
      route_distance_km: 1.2,
      rule_start_time: '06:00:00',
      rule_end_time: '22:30:00'
    };
    const outcome = await window.ml_generate_time_and_track();
    const start = document.getElementById('exercise-start_time').value;
    const end = document.getElementById('exercise-end_time').value;
    return {
      durationSeconds: outcome.durationSeconds,
      metaTime: outcome.metadata.totalTime,
      distanceKm: outcome.metadata.totalDistance / 1000,
      trackLength: outcome.track.length,
      inside: outcome.track.every((p) => window.ml_isPointInPolygon(p.lat, p.lng, polygon)),
      start: start,
      end: end
    };
  });

  const paceMinPerKm = result.durationSeconds / 60 / result.distanceKm;
  expect(result.trackLength).toBeGreaterThan(10);
  expect(result.inside).toBe(true);
  expect(result.distanceKm).toBeGreaterThanOrEqual(1.2);
  expect(result.durationSeconds).toBeGreaterThanOrEqual(4 * 60);
  expect(result.durationSeconds).toBeLessThanOrEqual(12 * 60);
  expect(paceMinPerKm).toBeGreaterThanOrEqual(3.3333 - 0.02);
  expect(paceMinPerKm).toBeLessThanOrEqual(10 + 0.02);
  // 轨迹 metadata 与表单时间必须一致
  expect(result.metaTime).toBe(result.durationSeconds);
  const formSeconds = (new Date(result.end) - new Date(result.start)) / 1000;
  expect(Math.abs(formSeconds - result.durationSeconds)).toBeLessThanOrEqual(1);
});

test('按天查重：当天已有记录能被识别出来', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  // 拦掉桥接请求，用固定数据代替真实服务端
  await page.route('http://127.0.0.1:17864/api/**', async (route) => {
    const isRecordQuery = route.request().url().indexOf('getRecordByMonthOrWeek') >= 0;
    const body = isRecordQuery
      ? {
          code: 200,
          success: true,
          data: {
            recordList: [
              { recordId: '1', recordTime: '2026-09-23', routeName: '桃园田径场', exerciseStatus: 1, isUse: 0 }
            ]
          }
        }
      : { code: 200, success: true, data: [] };
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  });

  const result = await page.evaluate(async () => {
    window.ml_student_token = 'dummy-token';
    const sameDay = await window.ml_find_existing_record('2026-09-23');
    const otherDay = await window.ml_find_existing_record('2026-09-24');
    return {
      described: sameDay ? window.ml_describe_record(sameDay) : null,
      describedNotCounted: sameDay ? window.ml_is_counted_record(sameDay) : null,
      otherDay: otherDay
    };
  });

  expect(result.described).toContain('2026-09-23');
  expect(result.described).toContain('桃园田径场');
  // exerciseStatus 0 才是有效，1 是无效；isUse 表示是否已计入次数
  expect(result.described).toContain('无效');
  expect(result.describedNotCounted).toBe(false);
  expect(result.otherDay).toBeNull();
});

test('历史记录面板展开后渲染记录', async ({ page }) => {
  const pageUrl = pathToFileURL(path.resolve(__dirname, '..', 'index.html')).href;
  await page.goto(pageUrl);

  await expect(page.locator('#history-record-list')).toContainText('尚未加载');
  await expect(page.locator('#history-summary-note')).toBeVisible();

  await page.route('http://127.0.0.1:17864/api/**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        code: 200,
        success: true,
        data: {
          recordList: [
            { recordId: '1', recordTime: '2026-09-23', routeName: '桃园田径场', routeRule: '2026~2027学年1学期锻炼任务', strExerciseTimes: '00:09:06', routeKilometre: '1.330', exerciseStatus: 0, isUse: 1 },
            { recordId: '2', recordTime: '2026-09-22', routeName: '橘园田径场', routeRule: '2026~2027学年1学期锻炼任务', strExerciseTimes: '00:07:00', routeKilometre: '1.200', exerciseStatus: 1, isUse: 0 }
          ]
        }
      })
    });
  });

  await page.evaluate(() => { window.ml_student_token = 'dummy-token'; });
  await page.locator('#history-details > summary').click();

  const list = page.locator('#history-record-list li');
  await expect(list).toHaveCount(2);
  // exerciseStatus 0 = 有效（不是 2），并带上规则名称与用时
  await expect(list.nth(0)).toContainText('2026-09-23');
  await expect(list.nth(0)).toContainText('有效');
  await expect(list.nth(0)).toContainText('2026~2027学年1学期锻炼任务');
  await expect(list.nth(0)).toContainText('00:09:06');
  await expect(list.nth(0)).toHaveClass(/text-success/);
  await expect(list.nth(1)).toContainText('无效');
  await expect(list.nth(1)).toContainText('00:07:00');
  await expect(list.nth(1)).toHaveClass(/text-danger/);
  await expect(page.locator('#history-summary-note')).toContainText('2 条记录');
});
