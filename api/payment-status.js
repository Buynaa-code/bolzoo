'use strict';

const {
  configMissing,
  ensureAccessCode,
  getPayment,
  handleOptions,
  isFinal,
  paymentPayload,
  sendConfigError,
  sendJSON,
  updatePayment,
  wireAPI
} = require('../lib/payment-api');

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'GET') return sendJSON(res, 405, { error: 'GET only' });

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  try {
    const url = new URL(req.url, 'https://' + req.headers.host);
    const id = url.searchParams.get('id');
    if (!id) return sendJSON(res, 400, { error: 'id required' });

    let payment = await getPayment(id);
    if (!payment) return sendJSON(res, 404, { error: 'Payment not found' });

    if (payment.provider === 'wire' && !isFinal(payment.status)) {
      const missingWire = configMissing({ wire: true }).filter((x) => x === 'WIRE_API_KEY');
      if (!missingWire.length) {
        const remote = await wireAPI('GET', '/v1/payment_intents/' + encodeURIComponent(payment.id));
        payment = await updatePayment(payment.id, {
          status: remote.status || payment.status,
          next_action: remote.next_action || payment.next_action || null,
          expires_at: remote.expires_at ? new Date(remote.expires_at * 1000).toISOString() : payment.expires_at
        }) || payment;
      }
    }

    if (payment.status === 'succeeded' && !payment.code) {
      const code = await ensureAccessCode(payment.id, payment.provider === 'mock');
      payment = await updatePayment(payment.id, { code }) || Object.assign({}, payment, { code });
    }

    return sendJSON(res, 200, paymentPayload(payment));
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.message || 'Payment status error',
      user_error: 'Төлбөрийн төлөв шалгах үед алдаа гарлаа.',
      data: e.data || null
    });
  }
};
