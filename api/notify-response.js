'use strict';

const {
  configMissing,
  handleOptions,
  readJSON,
  sendConfigError,
  sendJSON,
  supabaseFetch
} = require('../lib/payment-api');
const { mailConfigured, renderResponseEmail, sendEmail } = require('../lib/mail');

const INVITE_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const KIND = 'response';

// Best-effort dashboard link the owner can click in the email.
function dashboardUrl(req) {
  const host = req.headers && (req.headers['x-forwarded-host'] || req.headers.host);
  const proto = (req.headers && req.headers['x-forwarded-proto']) || 'https';
  if (!host) return '';
  return proto + '://' + host + '/dashboard';
}

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  res.setHeader('Cache-Control', 'private, no-store');

  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  let body;
  try { body = await readJSON(req); }
  catch (e) { return sendJSON(res, e.status || 400, { error: e.message || 'Invalid JSON' }); }

  const inviteId = String(body && body.inviteId || '');
  if (!INVITE_ID_RE.test(inviteId)) return sendJSON(res, 400, { error: 'Invalid invite id' });

  try {
    const rows = await supabaseFetch(
      'GET',
      '/invites?id=eq.' + encodeURIComponent(inviteId) +
        '&select=id,config,private_config,response,responded_at&limit=1'
    );
    const invite = rows && rows[0];
    if (!invite) return sendJSON(res, 404, { error: 'Invite not found' });
    if (!invite.responded_at) {
      return sendJSON(res, 400, { error: 'Invite has no response yet' });
    }
    // Only ship email for a committed answer. Intermediate poster-yes/later
    // saves that don't carry final=true still go through save_response, but
    // shouldn't burn the once-per-invite notification slot.
    const isFinal = invite.response && String(invite.response.final) === 'true';
    if (!isFinal) {
      return sendJSON(res, 200, { sent: false, reason: 'not_final' });
    }

    const toEmail = String((invite.private_config && invite.private_config.responseEmail) || '').trim();
    if (!toEmail) {
      return sendJSON(res, 200, { sent: false, reason: 'no_owner_email' });
    }

    // Claim the outbox slot first. Unique(invite_id, kind) makes retries safe:
    // a second POST hits 409 and we simply report already_sent.
    try {
      await supabaseFetch(
        'POST',
        '/notifications?select=id',
        { invite_id: inviteId, kind: KIND, to_email: toEmail },
        'return=representation'
      );
    } catch (e) {
      if (e.status === 409) return sendJSON(res, 200, { sent: false, reason: 'already_sent' });
      throw e;
    }

    if (!mailConfigured()) {
      // Row is already inserted; leave sent_at null so a future retry job can
      // send it once RESEND_API_KEY is configured.
      return sendJSON(res, 200, { sent: false, reason: 'mail_unconfigured' });
    }

    const cfg = invite.config || {};
    const email = renderResponseEmail({
      recipientName: cfg.recipientName || '',
      senderName:    cfg.senderName || '',
      response:      invite.response || {},
      dashboardUrl:  dashboardUrl(req)
    });

    try {
      await sendEmail({ to: toEmail, subject: email.subject, html: email.html, text: email.text });
      await supabaseFetch(
        'PATCH',
        '/notifications?invite_id=eq.' + encodeURIComponent(inviteId) +
          '&kind=eq.' + encodeURIComponent(KIND),
        { sent_at: new Date().toISOString(), error: null }
      );
      return sendJSON(res, 200, { sent: true });
    } catch (sendErr) {
      const message = (sendErr && sendErr.message) || String(sendErr);
      try {
        await supabaseFetch(
          'PATCH',
          '/notifications?invite_id=eq.' + encodeURIComponent(inviteId) +
            '&kind=eq.' + encodeURIComponent(KIND),
          { error: message.slice(0, 500) }
        );
      } catch (_) { /* swallow — we already have a bigger problem */ }
      return sendJSON(res, 202, { sent: false, reason: 'send_failed', error: message });
    }
  } catch (e) {
    const status = e.status && e.status < 500 ? e.status : 500;
    return sendJSON(res, status, {
      error: status < 500 ? (e.message || 'Notify error') : 'Notify error'
    });
  }
};
