/* Shared campaign dates are instants; all public boundaries use Ulaanbaatar time. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.BolzooCampaign = factory();
}(typeof window !== 'undefined' ? window : this, function () {
  'use strict';
  var ID = 'newyear100-2026';
  var PROMOTION_PRICE = 9023;
  var PROMOTION_START_AT = '2026-09-21T16:00:00Z';
  var PROMOTION_END_AT = '2026-09-23T16:00:00Z';
  var START_AT = '2026-09-22T16:00:00Z';
  var NEW_YEAR_AT = '2026-12-31T16:00:00Z';
  var start = Date.parse(PROMOTION_START_AT), end = Date.parse(PROMOTION_END_AT);
  function timestamp(now) { return now === undefined ? Date.now() : typeof now === 'string' ? Date.parse(now) : Number(now); }
  function isActive(now) { var at = timestamp(now); return Number.isFinite(at) && at >= start && at < end; }
  function pricing(now, regularPrice) {
    if (regularPrice === undefined) regularPrice = 9900;
    var active = isActive(now);
    return { price: active ? PROMOTION_PRICE : regularPrice, regular_price: regularPrice,
      promotion: { id: ID, title: 'Шинэ он хүртэл 100 хоног', starts_at: PROMOTION_START_AT, ends_at: PROMOTION_END_AT, timezone: 'Asia/Ulaanbaatar', active: active } };
  }
  return Object.freeze({ ID: ID, PROMOTION_PRICE: PROMOTION_PRICE, PROMOTION_START_AT: PROMOTION_START_AT,
    PROMOTION_END_AT: PROMOTION_END_AT, START_AT: START_AT, NEW_YEAR_AT: NEW_YEAR_AT, isActive: isActive, pricing: pricing });
}));
