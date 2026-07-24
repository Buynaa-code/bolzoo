'use strict';

const {
  PRICE_MNT,
  configMissing,
  crypto,
  handleOptions,
  readJSON,
  sendConfigError,
  sendJSON,
  upsertPayment,
  wireAPI
} = require('../lib/payment-api');

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });

  const missing = configMissing({ wire: true });
  if (missing.length) return sendConfigError(res, missing);

  try {
    const body = await readJSON(req);
    const origin = req.headers.origin || ('https://' + req.headers.host);
    const now = new Date().toISOString();

    const paymentIntent = await wireAPI('POST', '/v1/payment_intents', {
      amount: PRICE_MNT,
      currency: 'MNT',
      automatic_operator: true,
      metadata: { product: 'bolzoo_access_code', tier: 'single' }
    }, crypto.randomUUID());

    const confirmed = await wireAPI(
      'POST',
      '/v1/payment_intents/' + encodeURIComponent(paymentIntent.id) + '/confirm',
      { return_url: origin + '/pay.html?intent=' + encodeURIComponent(paymentIntent.id) },
      crypto.randomUUID()
    );

    const row = await upsertPayment({
      id: paymentIntent.id,
      status: confirmed.status || paymentIntent.status || 'requires_action',
      amount: paymentIntent.amount || PRICE_MNT,
      currency: paymentIntent.currency || 'MNT',
      provider: 'wire',
      provider_intent_id: paymentIntent.id,
      client_secret: paymentIntent.client_secret || null,
      next_action: confirmed.next_action || paymentIntent.next_action || null,
      code: null,
      email: body.email || null,
      created_at: now,
      updated_at: now,
      expires_at: confirmed.expires_at ? new Date(confirmed.expires_at * 1000).toISOString() : null
    });

    return sendJSON(res, 200, {
      intent_id: row.id,
      amount: row.amount,
      status: row.status,
      next_action: row.next_action,
      mode: 'live'
    });
  } catch (e) {
    const status = e.status === 400 ? 400 : e.status === 401 || e.status === 403 ? 502 : 500;
    return sendJSON(res, status, {
      error: e.message || 'Checkout error',
      user_error: 'Төлбөр эхлүүлэх үед алдаа гарлаа. Түр хүлээгээд дахин оролдоно уу.',
      data: e.data || null
    });
  }
};
