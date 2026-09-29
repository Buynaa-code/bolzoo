'use strict';

// Owner recovery: given a used access code, return the invite id + owner_token
// so the owner can re-hydrate their dashboard on a fresh browser without buying
// another code. Read-only recovery — the caller must already know the code
// (issued to them at purchase), and recovery does not grant any write extras
// beyond what the owner_token already unlocks via /api/invite.

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

    const codeRows = await supabaseFetch(
      'GET',
      '/access_codes?code=eq.' + encodeURIComponent(code) +
        '&select=used,used_for_invite_id&limit=1'
    );
    const codeRow = codeRows && codeRows[0];
    if (!codeRow) return sendJSON(res, 200, { ok: false, reason: 'not_found' });
    if (!codeRow.used || !codeRow.used_for_invite_id) {
      return sendJSON(res, 200, { ok: false, reason: 'not_used_yet' });
    }

    const inviteRows = await supabaseFetch(
      'GET',
      '/invites?id=eq.' + encodeURIComponent(codeRow.used_for_invite_id) +
        '&select=id,owner_token,created_at&limit=1'
    );
    const invite = inviteRows && inviteRows[0];
    if (!invite) return sendJSON(res, 200, { ok: false, reason: 'invite_missing' });

    return sendJSON(res, 200, {
      ok: true,
      id: invite.id,
      owner_token: invite.owner_token,
      created_at: invite.created_at
    });
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.message || 'Recovery error'
    });
  }
};
