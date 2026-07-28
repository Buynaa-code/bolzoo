'use strict';

const {
  WIRE_WEBHOOK_SECRET,
  configMissing,
  handleOptions,
  readBody,
  sendConfigError,
  sendJSON,
  supabaseFetch,
  verifyWireSignature
} = require('../lib/payment-api');

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });

  const missing = configMissing({ wire: false, webhook: true });
  if (missing.length) return sendConfigError(res, missing);

  try {
    const bodyText = await readBody(req);
    const sig = req.headers['wirepayment-signature'] || '';
    if (!verifyWireSignature(bodyText, sig, WIRE_WEBHOOK_SECRET)) {
      return sendJSON(res, 401, { error: 'invalid or expired signature' });
    }

    let event = {};
    try { event = bodyText ? JSON.parse(bodyText) : {}; } catch (_) {
      return sendJSON(res, 400, { error: 'Invalid JSON' });
    }

    const eventId = event.id;
    const type = event.type || '';
    const data = event.data || {};
    const object = data && data.object || {};
    const intentId = object.payment_intent || data.payment_intent || object.id || data.id || event.intent_id;
    if (!eventId) return sendJSON(res, 400, { error: 'event id required' });

    const rows = await supabaseFetch('POST', '/rpc/process_wire_event', {
      p_event_id: eventId,
      p_type: type,
      p_intent_id: intentId || null,
      p_raw: event
    });
    const result = rows && rows[0] ? rows[0] : {};

    return sendJSON(res, 200, {
      ok: true,
      already_processed: result.processed === false,
      payment_found: result.payment_found !== false
    });
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.message || 'Webhook error',
      data: e.data || null
    });
  }
};
