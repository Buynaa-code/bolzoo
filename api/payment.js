'use strict';

const { sendJSON } = require('../lib/payment-api');
const payments = require('../lib/payment-handlers').handlers(require('../lib/payment-repository'));
const routes = new Map([
  ['checkout', payments.checkout],
  ['payment-status', payments.status],
  ['wire-webhook', payments.webhook],
  ['cancel-payment', payments.cancel],
  // Simulation stays local-only, including when this endpoint is called directly.
  ['dev-mark-paid', async (req, res) => sendJSON(res, 403, { error: 'Mock payment simulation is disabled' })]
]);

module.exports = async (req, res) => {
  let url;
  try { url = new URL(req.url, 'http://localhost'); }
  catch (_) { return sendJSON(res, 404, { error: 'Payment endpoint not found' }); }

  // Vercel may retain the original URL. Prefer its explicit endpoint over any
  // caller-supplied routing query. The destination URL uses the rewrite marker.
  let route = url.pathname.startsWith('/api/') ? url.pathname.slice(5) : '';
  if (url.pathname === '/api/payment') {
    const values = url.searchParams.getAll('payment_route');
    route = values.length === 1 ? values[0] : '';
  }
  const handler = routes.get(route);
  if (!handler) return sendJSON(res, 404, { error: 'Payment endpoint not found' });

  // Do not read/parse the stream here: webhook verification needs signed bytes.
  return handler(req, res);
};
