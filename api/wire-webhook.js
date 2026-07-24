'use strict';

const {
  WIRE_WEBHOOK_SECRET,
  configMissing,
  handleOptions,
  readBody,
  sendConfigError,
  sendJSON,
  updatePayment,
  verifyWireSignature
} = require('../lib/payment-api');

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  try {
    const bodyText = await readBody(req);
    if (WIRE_WEBHOOK_SECRET) {
      const sig = req.headers['wirepayment-signature'] || '';
      if (!verifyWireSignature(bodyText, sig, WIRE_WEBHOOK_SECRET)) {
        return sendJSON(res, 401, { error: 'invalid signature' });
      }
    }

    let event = {};
    try { event = bodyText ? JSON.parse(bodyText) : {}; } catch (_) {
      return sendJSON(res, 400, { error: 'Invalid JSON' });
    }

    const type = event.type || '';
    const data = event.data || {};
    const intentId = (data && (data.id || (data.object && data.object.id))) || event.intent_id;
    if (!intentId) return sendJSON(res, 200, { ok: true, ignored: true });

    const patch = { raw_event: event };
    if (type === 'payment_intent.succeeded' || type === 'charge.succeeded') patch.status = 'succeeded';
    if (type === 'payment_intent.canceled') patch.status = 'canceled';
    if (type === 'payment_intent.payment_failed' || type === 'charge.failed') patch.status = 'failed';
    if (patch.status) await updatePayment(intentId, patch);

    return sendJSON(res, 200, { ok: true });
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.message || 'Webhook error',
      data: e.data || null
    });
  }
};
