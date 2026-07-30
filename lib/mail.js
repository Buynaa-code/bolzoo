'use strict';

// Thin Resend wrapper. We deliberately avoid the resend-node SDK — one HTTPS
// POST is simpler than pulling in a dependency in a serverless environment.

const env = process.env;
const RESEND_API_KEY = String(env.RESEND_API_KEY || '');
const RESEND_ENDPOINT = String(env.RESEND_ENDPOINT || 'https://api.resend.com/emails').replace(/\/$/, '');
const MAIL_FROM = String(env.MAIL_FROM || 'Bolzoo <notify@bolzoo.mn>').trim();

function mailConfigured() {
  return !!RESEND_API_KEY && !!MAIL_FROM;
}

function mailConfigMissing() {
  const missing = [];
  if (!RESEND_API_KEY) missing.push('RESEND_API_KEY');
  if (!MAIL_FROM) missing.push('MAIL_FROM');
  return missing;
}

function escapeHtml(str) {
  return String(str == null ? '' : str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

async function sendEmail({ to, subject, html, text, replyTo }) {
  if (!mailConfigured()) {
    const err = new Error('Mail provider not configured: ' + mailConfigMissing().join(', '));
    err.code = 'mail_unconfigured';
    throw err;
  }
  if (!to) throw new Error('sendEmail: `to` required');
  if (!subject) throw new Error('sendEmail: `subject` required');

  const body = {
    from:    MAIL_FROM,
    to:      Array.isArray(to) ? to : [to],
    subject: subject
  };
  if (html) body.html = html;
  if (text) body.text = text;
  if (replyTo) body.reply_to = replyTo;

  const response = await fetch(RESEND_ENDPOINT, {
    method:  'POST',
    headers: {
      Authorization:  'Bearer ' + RESEND_API_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  const rawText = await response.text();
  let data = null;
  try { data = rawText ? JSON.parse(rawText) : null; } catch (_) { data = { raw: rawText }; }

  if (!response.ok) {
    const message = (data && (data.message || (data.error && data.error.message))) || ('Resend ' + response.status);
    const err = new Error(message);
    err.status = response.status;
    err.data = data;
    throw err;
  }
  return data || {};
}

// Small template helper — used by notify-response.
function renderResponseEmail({ recipientName, senderName, response, dashboardUrl }) {
  const answer = String((response && response.answer) || 'yes').toLowerCase();
  const label = answer === 'no'    ? 'Уучлаарай, боломжгүй 🥲'
              : answer === 'later' ? 'Одоохондоо амжихгүй, өөр өдөр санал болголоо 💌'
              :                       'Тийм, явъя 💗';

  const lines = [
    (recipientName ? recipientName + ' ' : '') + 'чиний урилгад хариу өглөө.',
    'Хариу: ' + label
  ];
  if (response && response.choice) lines.push('💘 Сонголт: ' + response.choice);
  if (response && response.date) lines.push('📅 Өдөр: ' + response.date);
  if (response && response.time) lines.push('🕐 Цаг: ' + response.time);
  if (response && response.kind) lines.push('💝 Төрөл: ' + response.kind);
  if (dashboardUrl)              lines.push('', 'Дашбоард: ' + dashboardUrl);

  const text = lines.join('\n');

  const html =
    '<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;line-height:1.55;color:#2a1a1f">' +
      '<h2 style="margin:0 0 12px;color:#e2547b">🎉 ' + escapeHtml((recipientName || 'Хүлээн авагч')) + '-с хариу ирлээ</h2>' +
      '<p style="margin:0 0 8px;font-weight:600">' + escapeHtml(label) + '</p>' +
      (response && response.choice ? '<p style="margin:0">💘 <strong>' + escapeHtml(response.choice) + '</strong></p>' : '') +
      (response && response.date ? '<p style="margin:0">📅 <strong>' + escapeHtml(response.date) + '</strong></p>' : '') +
      (response && response.time ? '<p style="margin:0">🕐 <strong>' + escapeHtml(response.time) + '</strong></p>' : '') +
      (response && response.kind ? '<p style="margin:0">💝 <strong>' + escapeHtml(response.kind) + '</strong></p>' : '') +
      (dashboardUrl
        ? '<p style="margin:18px 0 0"><a href="' + escapeHtml(dashboardUrl) + '" style="color:#e2547b;font-weight:700">Дашбоард нээх →</a></p>'
        : '') +
      (senderName ? '<p style="margin:20px 0 0;color:#8a6472;font-size:13px">— ' + escapeHtml(senderName) + '</p>' : '') +
    '</div>';

  return { subject: '💌 ' + (recipientName || 'Урилга') + ' хариу өгсөн', html, text };
}

module.exports = {
  MAIL_FROM,
  RESEND_ENDPOINT,
  escapeHtml,
  mailConfigMissing,
  mailConfigured,
  renderResponseEmail,
  sendEmail
};
