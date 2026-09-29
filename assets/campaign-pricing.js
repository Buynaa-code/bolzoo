(function (root) {
  'use strict';
  // Refresh displayed prices in long-lived tabs; invoices retain their own amount.
  root.BolzooPricing = { watch: function (onPrice) {
    var timer, expiryTimer, busy = false, stopped = false, last, expires = Infinity, requestController;
    function endOffer() {
      clearTimeout(expiryTimer); expiryTimer = null;
      if (stopped || !last || !last.promotion || !last.promotion.active) return;
      last = Object.assign({}, last, {price:last.regular_price, promotion:Object.assign({}, last.promotion, {active:false})});
      expires = Infinity;
      onPrice(last);
    }
    function apply(data, requestDuration) {
      if (stopped || !data || !Number.isSafeInteger(data.price) || data.price <= 0) return;
      var remaining = Infinity;
      if (data.promotion && data.promotion.active) {
        var serverTime = Date.parse(data.server_time), endTime = Date.parse(data.promotion.ends_at);
        if (!Number.isFinite(serverTime) || !Number.isFinite(endTime) || !Number.isSafeInteger(data.regular_price) || data.regular_price < data.price) return;
        remaining = endTime - serverTime - Math.max(0, requestDuration);
      }
      clearTimeout(expiryTimer); expiryTimer = null;
      last = data;
      expires = Number.isFinite(remaining) ? performance.now() + Math.max(0, remaining) : Infinity;
      if (remaining <= 0) { endOffer(); return; }
      onPrice(data);
      // This timer is independent of health requests, including a request that hangs offline.
      if (Number.isFinite(remaining)) expiryTimer = setTimeout(endOffer, Math.min(remaining, 2147483647));
    }
    function refresh() {
      if (busy || stopped) return;
      busy = true;
      clearTimeout(timer);
      if (performance.now() >= expires) endOffer();
      var startedAt = performance.now();
      var controller = new AbortController();
      requestController = controller;
      var timeout = setTimeout(function () { controller.abort(); }, 10000);
      fetch('/api/health', {cache:'no-store', signal:controller.signal}).then(function (r) {
        return r.ok ? r.json() : null;
      }).then(function (data) {
        apply(data, performance.now() - startedAt);
      }).catch(function () {}).finally(function () {
        clearTimeout(timeout); busy = false; requestController = null;
        if (!stopped) timer = setTimeout(refresh, 60000);
      });
    }
    function visible() { if (!document.hidden) refresh(); }
    document.addEventListener('visibilitychange', visible);
    root.addEventListener('pageshow', visible);
    refresh();
    return function () { stopped = true; clearTimeout(timer); clearTimeout(expiryTimer); if(requestController)requestController.abort(); document.removeEventListener('visibilitychange', visible); root.removeEventListener('pageshow', visible); };
  }};
})(window);
