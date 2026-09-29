'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const campaign = require('../assets/campaign');

test('promotion includes Sep22 and all of Sep23 Ulaanbaatar, with exact millisecond boundaries', () => {
  const start = Date.parse('2026-09-22T00:00:00+08:00'), end = Date.parse('2026-09-24T00:00:00+08:00');
  assert.equal(campaign.ID, 'newyear100-2026');
  assert.equal(Date.parse(campaign.PROMOTION_START_AT), start);
  assert.equal(Date.parse(campaign.PROMOTION_END_AT), end);
  for (const [now, active, price] of [[start - 1, false, 9900], [start, true, 9023], [Date.parse('2026-09-23T00:00:00+08:00'), true, 9023], [end - 1, true, 9023], [end, false, 9900], [end + 1, false, 9900]]) {
    const result = campaign.pricing(now);
    assert.equal(campaign.isActive(now), active);
    assert.equal(result.price, price);
    assert.equal(result.regular_price, 9900);
    assert.equal(result.promotion.active, active);
    assert.equal(result.promotion.timezone, 'Asia/Ulaanbaatar');
  }
  assert.equal(campaign.isActive(NaN), false);
  assert.equal(Date.parse(campaign.NEW_YEAR_AT) - Date.parse(campaign.START_AT), 100 * 86400000);
});

test('regular configured price returns automatically; browser and server share identical pure campaign logic', () => {
  const context = { window: {}, Date, Number, Object };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../assets/campaign.js'), 'utf8'), context);
  const browser = context.window.BolzooCampaign;
  for (const when of ['2026-09-21T15:59:59.999Z', '2026-09-22T16:00:00Z', '2026-09-23T16:00:00Z']) {
    assert.deepEqual(JSON.parse(JSON.stringify(browser.pricing(when, 12500))), campaign.pricing(when, 12500));
  }
  assert.equal(campaign.pricing(campaign.PROMOTION_END_AT, 12500).price, 12500);
});

test('the same hosted health handler changes price after midnight without a module reload or cached response', async () => {
  const handler = require('../api/health');
  const { PRICE_MNT } = require('../lib/payment-api');
  const actualNow = Date.now;
  async function request(at) {
    Date.now = () => at;
    const result = { headers: {} };
    await handler({ method: 'GET', headers: {} }, { setHeader(name, value) { result.headers[name] = value; }, end(value) { result.body = JSON.parse(value); } });
    return result;
  }
  try {
    const before = await request(Date.parse(campaign.PROMOTION_END_AT) - 1);
    const after = await request(Date.parse(campaign.PROMOTION_END_AT));
    assert.equal(before.body.price, 9023); assert.equal(before.body.promotion.active, true);
    assert.equal(after.body.price, PRICE_MNT); assert.equal(after.body.promotion.active, false);
    assert.equal(after.body.regular_price, PRICE_MNT);
    assert.equal(after.body.server_time, '2026-09-23T16:00:00.000Z');
    assert.equal(after.headers['Cache-Control'], 'no-store');
  } finally { Date.now = actualNow; }
});
