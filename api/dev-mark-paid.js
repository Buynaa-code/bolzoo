'use strict';

const {
  ALLOW_MOCK_PAYMENT,
  configMissing,
  ensureAccessCode,
  getPayment,
  handleOptions,
  readJSON,
  sendConfigError,
  sendJSON,
  updatePayment
} = require('../lib/payment-api');

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  if (!ALLOW_MOCK_PAYMENT) return sendJSON(res, 403, { error: 'Mock payment simulation is disabled' });

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  try {
    const body = await readJSON(req);
    const id = body.intent_id;
    if (!id) return sendJSON(res, 400, { error: 'intent_id required' });

    let payment = await getPayment(id);
    if (!payment) return sendJSON(res, 404, { error: 'Payment not found' });
    if (payment.provider !== 'mock') return sendJSON(res, 403, { error: 'Only mock payments can be simulated' });

    const code = payment.code || await ensureAccessCode(payment.id, true);
    payment = await updatePayment(payment.id, { status: 'succeeded', code }) || payment;
    return sendJSON(res, 200, { ok: true, code: payment.code || code });
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.message || 'Mock payment error',
      data: e.data || null
    });
  }
};
