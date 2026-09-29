'use strict';
const api = require('./payment-api');
const { createPaymentFlow } = require('./payment-flow');
function originFor(req) {
  const deploymentHost = process.env.VERCEL_ENV === 'preview' ? process.env.VERCEL_URL : process.env.VERCEL_PROJECT_PRODUCTION_URL || process.env.VERCEL_URL;
  const configured = process.env.PUBLIC_BASE_URL || (deploymentHost && 'https://' + deploymentHost);
  const local = /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(req.headers.host || '');
  const value = configured || (local ? 'http://' + req.headers.host : '');
  const url = new URL(value);
  if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) || url.username || url.password) throw new Error('PUBLIC_BASE_URL must be a trusted HTTPS origin');
  return url.origin;
}
function handlers(repo, local = false) {
  const flow = createPaymentFlow({ repo, wire: api.wireAPI, price: now => api.getPricing(now).price,
    description: api.PAYMENT_DESCRIPTION, wireEnabled: !!api.WIRE_API_KEY,
    testMode: api.WIRE_API_KEY.startsWith('sk_test_'), allowMock: local && api.ALLOW_MOCK_PAYMENT && !api.WIRE_API_KEY });
  const token = (req) => (req.headers.authorization || '').replace(/^Bearer /, '');
  function wrap(method, run, options = {}) {
    return async (req, res) => {
      if (api.handleOptions(req, res)) return;
      if (req.method !== method) return api.sendJSON(res, 405, { error: method + ' only' });
      if (!local) {
        const missing = api.configMissing({ wire: false, webhook: !!options.webhook });
        if (missing.length) return api.sendConfigError(res, missing);
      }
      try { return api.sendJSON(res, 200, await run(req)); }
      catch (e) {
        const status = [400, 403, 404, 409, 413, 429, 503].includes(e.status) ? e.status : 502;
        // Provider/database response bodies may contain credentials or personal data.
        const message = status < 500 ? e.message : 'Төлбөрийн үйлчилгээтэй холбогдож чадсангүй. Түр хүлээгээд дахин шалгана уу.';
        return api.sendJSON(res, status, { error: message, user_error: message, ...(e.code === 'checkout_expired' ? { code: e.code } : {}) });
      }
    };
  }
  return {
    checkout: wrap('POST', async req => flow.checkout(await api.readJSON(req), originFor(req))),
    status: wrap('GET', req => flow.status(new URL(req.url, 'http://localhost').searchParams.get('id'), token(req))),
    webhook: wrap('POST', async req => {
      if (!api.WIRE_WEBHOOK_SECRET) { const e = new Error('Webhook unavailable'); e.status = 503; throw e; }
      const raw = await api.readBody(req);
      if (!api.verifyWireSignature(raw, req.headers['wirepayment-signature'], api.WIRE_WEBHOOK_SECRET)) {
        const e = new Error('invalid or expired signature'); e.status = 403; throw e;
      }
      let event;
      try { event = JSON.parse(raw); } catch (_) { const e = new Error('Invalid JSON'); e.status = 400; throw e; }
      return flow.webhook(event);
    }, { webhook: true }),
    cancel: wrap('POST', async req => { const body = await api.readJSON(req); return flow.cancel(body.intent_id, token(req)); }),
    simulate: wrap('POST', async req => {
      const body = await api.readJSON(req);
      return flow.simulate(body.intent_id, token(req));
    })
  };
}
module.exports = { handlers, originFor };
