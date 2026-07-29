'use strict';

const {
  configMissing,
  handleOptions,
  sendConfigError,
  sendJSON,
  supabaseFetch
} = require('../lib/payment-api');

const INVITE_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;

// Ulaanbaatar is UTC+08 year-round (no DST). state.time / response.time is a
// local wall time like "18:00" and response.dateISO is local "YYYY-MM-DD".
const UB_OFFSET_MS = 8 * 3600 * 1000;

function pad2(n) { return (n < 10 ? '0' : '') + n; }

function toUtcCompact(y, m, d, hh, mm) {
  // Treat inputs as Ulaanbaatar local wall time. Node's Date constructor
  // interprets Y/M/D as *server* local time, which we can't rely on in a
  // serverless env — build a UTC timestamp explicitly.
  const localMs = Date.UTC(y, m, d, hh, mm, 0);
  const utcMs   = localMs - UB_OFFSET_MS;
  const dt = new Date(utcMs);
  return dt.getUTCFullYear()
       + pad2(dt.getUTCMonth() + 1)
       + pad2(dt.getUTCDate())
       + 'T'
       + pad2(dt.getUTCHours())
       + pad2(dt.getUTCMinutes())
       + '00Z';
}

function parseLocalDateTime(response) {
  // Prefer dateISO (YYYY-MM-DD) if the client sent it, else return null.
  const iso = String(response && response.dateISO || '');
  const match = iso.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (!match) return null;
  const y = parseInt(match[1], 10);
  const m = parseInt(match[2], 10) - 1;
  const d = parseInt(match[3], 10);
  const time = String(response && response.time || '18:00');
  const hm = time.match(/^(\d{1,2}):(\d{1,2})$/);
  const hh = hm ? parseInt(hm[1], 10) : 18;
  const mm = hm ? parseInt(hm[2], 10) : 0;
  return { y: y, m: m, d: d, hh: hh, mm: mm };
}

// RFC 5545 recommends folding long lines at 75 octets, but consumer calendar
// apps forgive shorter lines. We escape the tricky characters instead.
function icsEscape(str) {
  return String(str == null ? '' : str)
    .replace(/\\/g, '\\\\')
    .replace(/\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;');
}

function buildIcs({ inviteId, title, description, location, start, end, host }) {
  const stamp = start; // any UTC stamp works for DTSTAMP
  const uid = inviteId + '@bolzoo';
  const url = host ? ('https://' + host + '/bolzoo.html?id=' + encodeURIComponent(inviteId)) : '';
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//bolzoo//invite-ics//MN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:' + uid,
    'DTSTAMP:' + stamp,
    'DTSTART:' + start,
    'DTEND:'   + end,
    'SUMMARY:' + icsEscape(title),
    (description ? 'DESCRIPTION:' + icsEscape(description) : null),
    (location    ? 'LOCATION:'    + icsEscape(location)    : null),
    (url         ? 'URL:'         + icsEscape(url)         : null),
    'END:VEVENT',
    'END:VCALENDAR'
  ].filter(function(line){ return line !== null; });
  // RFC 5545: every line must end with CRLF, including the last one.
  return lines.join('\r\n') + '\r\n';
}

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  if (req.method !== 'GET') {
    return sendJSON(res, 405, { error: 'GET only' });
  }

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  const url = new URL(req.url, 'https://' + req.headers.host);
  const id = String(url.searchParams.get('id') || '');
  if (!INVITE_ID_RE.test(id)) return sendJSON(res, 400, { error: 'Invalid invite id' });

  try {
    const rows = await supabaseFetch(
      'GET',
      '/invites?id=eq.' + encodeURIComponent(id) +
        '&select=id,config,response,responded_at&limit=1'
    );
    const invite = rows && rows[0];
    if (!invite || !invite.response || !invite.responded_at) {
      return sendJSON(res, 404, { error: 'No confirmed response yet' });
    }
    const answer = String(invite.response.answer || '').toLowerCase();
    if (answer === 'no' || answer === 'later') {
      return sendJSON(res, 404, { error: 'Response is not a confirmed yes' });
    }
    const dt = parseLocalDateTime(invite.response);
    if (!dt) {
      return sendJSON(res, 400, { error: 'Response missing dateISO/time' });
    }

    const start = toUtcCompact(dt.y, dt.m, dt.d, dt.hh, dt.mm);
    const end   = toUtcCompact(dt.y, dt.m, dt.d, dt.hh + 2, dt.mm);
    const cfg   = invite.config || {};
    const title = 'Bolzoo — ' + (cfg.recipientName || 'Болзоо')
                + (invite.response.kind ? ' · ' + invite.response.kind : '');
    const location = cfg.locationName || '';
    const description = (cfg.customNote ? cfg.customNote + '\n' : '')
                      + 'Bolzoo invite: '
                      + (cfg.senderName ? cfg.senderName + ' → ' : '')
                      + (cfg.recipientName || '');

    const ics = buildIcs({
      inviteId:    id,
      title:       title,
      description: description,
      location:    location,
      start:       start,
      end:         end,
      host:        req.headers['x-forwarded-host'] || req.headers.host
    });

    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="bolzoo-' + id + '.ics"');
    res.setHeader('Cache-Control', 'private, no-store');
    res.end(ics);
  } catch (e) {
    const status = e.status && e.status < 500 ? e.status : 500;
    return sendJSON(res, status, { error: status < 500 ? (e.message || 'ICS error') : 'ICS error' });
  }
};

module.exports.parseLocalDateTime = parseLocalDateTime;
module.exports.toUtcCompact       = toUtcCompact;
module.exports.buildIcs           = buildIcs;
module.exports.icsEscape          = icsEscape;
