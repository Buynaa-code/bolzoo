'use strict';

const {
  PAYMENT_DESCRIPTION,
  PRICE_MNT,
  WIRE_API_KEY,
  WIRE_WEBHOOK_SECRET,
  configMissing,
  handleOptions,
  sendJSON
} = require('../lib/payment-api');

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  return sendJSON(res, 200, {
    ok: true,
    price: PRICE_MNT,
    payment_description: PAYMENT_DESCRIPTION,
    wire: WIRE_API_KEY ? 'live' : 'not_configured',
    wire_webhook_secret: WIRE_WEBHOOK_SECRET ? 'set' : 'unset',
    youtube: (process.env.YOUTUBE_API_KEY || process.env.GOOGLE_API_KEY) ? 'configured' : 'not_configured',
    missing: configMissing({ wire: true })
  });
};
