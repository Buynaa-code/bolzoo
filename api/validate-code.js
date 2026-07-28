'use strict';

const {
  configMissing,
  handleOptions,
  readJSON,
  sendConfigError,
  sendJSON,
  supabaseFetch
} = require('../lib/payment-api');

const ACCESS_CODE_RE = /^LOV-[A-HJ-NP-Z2-9]{6}$/;

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  res.setHeader('Cache-Control', 'private, no-store');

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  try {
    const body = await readJSON(req);
    const code = String(body.code || '').trim().toUpperCase();
    if (!ACCESS_CODE_RE.test(code)) {
      return sendJSON(res, 200, { ok: false, reason: 'not_found' });
    }

    const rows = await supabaseFetch(
      'GET',
      '/access_codes?code=eq.' + encodeURIComponent(code) + '&select=used&limit=1'
    );
    if (!rows || !rows[0]) return sendJSON(res, 200, { ok: false, reason: 'not_found' });
    if (rows[0].used) return sendJSON(res, 200, { ok: false, reason: 'used' });
    return sendJSON(res, 200, { ok: true });
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.status && e.status < 500 ? e.message : 'Code validation error'
    });
  }
};
