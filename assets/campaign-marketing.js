/* Public campaign banners use the current server offer, never the device date. */
(function (root) {
  'use strict';
  var doc = root.document;
  if (!doc) return;
  var banners = Array.from(doc.querySelectorAll('[data-campaign-banner]'));
  if (!banners.length) return;
  var campaign = root.BolzooCampaign;
  var snapshot = null;
  var expiryTimer = null;
  var refreshTimer = null;
  var pending = null;
  var destroyed = false;
  function monotonicNow() { return root.performance.now(); }
  function node(tag, className, value) {
    var el = doc.createElement(tag);
    if (className) el.className = className;
    if (value !== undefined) el.textContent = value;
    return el;
  }
  function price(value) { return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '₮'; }
  function clearOffer() {
    snapshot = null;
    root.clearTimeout(expiryTimer); expiryTimer = null;
    banners.forEach(function (banner) { banner.hidden = true; banner.replaceChildren(); });
  }
  function remaining() {
    return snapshot ? snapshot.endsAt - snapshot.serverAt - Math.max(0, monotonicNow() - snapshot.receivedAt) : 0;
  }
  function expireAtBoundary() {
    root.clearTimeout(expiryTimer);
    var left = remaining();
    if (left <= 0) { clearOffer(); return; }
    expiryTimer = root.setTimeout(expireAtBoundary, Math.min(left, 2147483647));
  }
  function render() {
    if (!snapshot || remaining() <= 0) { clearOffer(); return; }
    banners.forEach(function (banner) {
      banner.replaceChildren();
      banner.setAttribute('aria-label', 'Шинэ жилийн 100 хоногийн урамшуулал');
      var copy = node('div', 'campaign-copy');
      copy.appendChild(node('p', 'campaign-kicker', '9/23-ААС ТООЛОХОД · ШИНЭ ОН ХҮРТЭЛ'));
      var title = node('h2', 'campaign-title', '100 хоногийн дараа шинэ он.');
      title.appendChild(node('span', '', 'Анхны алхмаа өнөөдөр.'));
      copy.appendChild(title);
      copy.appendChild(node('p', 'campaign-dates', '9/22–9/23 · Ердөө 2 хоног'));
      var offer = node('div', 'campaign-offer');
      var prices = node('p', 'campaign-prices');
      prices.appendChild(node('span', 'campaign-price-label', 'Урилгаа бэлдэх'));
      if (snapshot.regularPrice > snapshot.price) {
        var previous = node('del', 'campaign-previous', price(snapshot.regularPrice));
        previous.setAttribute('aria-label', 'Энгийн үнэ ' + price(snapshot.regularPrice));
        prices.appendChild(previous);
      }
      var current = node('strong', 'campaign-current', price(snapshot.price));
      current.setAttribute('aria-label', 'Урамшууллын үнэ ' + price(snapshot.price));
      prices.appendChild(current); offer.appendChild(prices);
      var link = node('a', 'campaign-cta', '9/23-нд багтаад крашаа болзоонд уриарай');
      var target = banner.getAttribute('data-campaign-link') || '/ideas.html';
      link.href = /^(?:\/(?!\/)|#)/.test(target) ? target : '/ideas.html';
      offer.appendChild(link);
      offer.appendChild(node('p', 'campaign-deadline', '9/24-ний 00:00 хүртэл · Улаанбаатарын цагаар'));
      banner.append(copy, offer); banner.hidden = false;
    });
    expireAtBoundary();
  }
  function validate(data, elapsed) {
    var offer = data && data.promotion;
    var serverAt = Date.parse(data && data.server_time);
    var endsAt = Date.parse(offer && offer.ends_at);
    var campaignEnd = Date.parse(campaign && campaign.PROMOTION_END_AT);
    if (!campaign || !offer || offer.id !== campaign.ID || offer.active !== true ||
      !Number.isFinite(serverAt) || !Number.isFinite(endsAt) || !Number.isFinite(campaignEnd) ||
      !campaign.isActive(serverAt) || !Number.isInteger(data.price) || data.price !== campaign.PROMOTION_PRICE ||
      !Number.isInteger(data.regular_price) || data.regular_price < data.price) return null;
    // Count the entire request duration conservatively; a slow response cannot extend an offer.
    serverAt += Math.max(0, elapsed);
    endsAt = Math.min(endsAt, campaignEnd);
    if (serverAt >= endsAt) return null;
    return {serverAt:serverAt, receivedAt:monotonicNow(), endsAt:endsAt, price:data.price, regularPrice:data.regular_price};
  }
  function scheduleRefresh() {
    root.clearTimeout(refreshTimer);
    if (!destroyed) refreshTimer = root.setTimeout(function () { refreshTimer = null; refresh(); }, 60000);
  }
  function refresh() {
    if (destroyed) return Promise.resolve();
    if (pending) return pending;
    if (!campaign || typeof root.fetch !== 'function') { clearOffer(); return Promise.resolve(); }
    var startedAt = monotonicNow();
    pending = Promise.resolve().then(function () {
      return root.fetch('/api/health', {cache:'no-store', credentials:'same-origin', headers:{Accept:'application/json'}});
    }).then(function (response) {
      if (!response.ok) throw new Error('offer_unavailable');
      return response.json();
    }).then(function (data) {
      if (destroyed) return;
      snapshot = validate(data, monotonicNow() - startedAt);
      if (snapshot) render(); else clearOffer();
    }).catch(function () { if (!destroyed) clearOffer(); }).finally(function () {
      pending = null; scheduleRefresh();
    });
    return pending;
  }
  function resume() {
    if (doc.visibilityState === 'hidden') return;
    // A restored tab must recheck before presenting a previously seen offer.
    clearOffer(); refresh();
  }
  function destroy() {
    destroyed = true; clearOffer(); root.clearTimeout(refreshTimer);
    doc.removeEventListener('visibilitychange', resume); root.removeEventListener('pageshow', resume);
  }
  clearOffer();
  root.BolzooCampaignMarketing = Object.freeze({refresh:refresh, destroy:destroy});
  doc.addEventListener('visibilitychange', resume); root.addEventListener('pageshow', resume);
  refresh();
}(typeof window !== 'undefined' ? window : this));
