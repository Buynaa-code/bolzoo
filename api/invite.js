'use strict';

const {
  configMissing,
  handleOptions,
  readJSON,
  sendConfigError,
  sendJSON,
  supabaseFetch
} = require('../lib/payment-api');

const INVITE_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const OWNER_TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Only these keys are safe to expose to anyone who knows the invite URL. Any
// owner-only field (email, phone, admin notes) belongs in `private_config` and
// is returned solely by the authenticated POST path.
const PUBLIC_CONFIG_KEYS = [
  'recipientName',
  'senderName',
  'videoId',
  'theme',
  'customNote',
  'locationName',
  'locationUrl',
  'specialLetter',
  'poster'
];

function pickPublicConfig(cfg) {
  const out = {};
  if (!cfg || typeof cfg !== 'object') return out;
  for (const key of PUBLIC_CONFIG_KEYS) {
    if (cfg[key] != null) out[key] = cfg[key];
  }
  return out;
}

function publicInvite(row) {
  return {
    id: row.id,
    config: pickPublicConfig(row.config),
    created_at: row.created_at
  };
}

function ownedInvite(row) {
  return {
    id: row.id,
    config: row.config,
    private_config: row.private_config || {},
    response: row.response,
    response_history: row.response_history || [],
    opened_at: row.opened_at,
    responded_at: row.responded_at,
    created_at: row.created_at
  };
}

module.exports = async function handler(req, res) {
  if (handleOptions(req, res)) return;
  res.setHeader('Cache-Control', 'private, no-store');

  const missing = configMissing({ wire: false });
  if (missing.length) return sendConfigError(res, missing);

  try {
    if (req.method === 'GET') {
      const url = new URL(req.url, 'https://' + req.headers.host);
      const id = String(url.searchParams.get('id') || '');
      if (!INVITE_ID_RE.test(id)) return sendJSON(res, 400, { error: 'Invalid invite id' });

      const rows = await supabaseFetch(
        'GET',
        '/invites?id=eq.' + encodeURIComponent(id) + '&select=id,config,created_at&limit=1'
      );
      if (!rows || !rows[0]) return sendJSON(res, 404, { error: 'Invite not found' });
      return sendJSON(res, 200, publicInvite(rows[0]));
    }

    if (req.method === 'POST') {
      const body = await readJSON(req);
      const items = Array.isArray(body.items) ? body.items : [];
      if (!items.length || items.length > 100) {
        return sendJSON(res, 400, { error: 'items must contain 1-100 invites' });
      }

      const expected = new Map();
      for (const item of items) {
        const id = String(item && item.id || '');
        const token = String(item && item.owner_token || '');
        if (!INVITE_ID_RE.test(id) || !OWNER_TOKEN_RE.test(token)) {
          return sendJSON(res, 400, { error: 'Invalid invite ownership data' });
        }
        expected.set(id, token.toLowerCase());
      }

      const ids = Array.from(expected.keys());
      const rows = await supabaseFetch(
        'GET',
        '/invites?id=in.(' + ids.map(encodeURIComponent).join(',') + ')' +
          '&select=id,owner_token,config,private_config,response,response_history,opened_at,responded_at,created_at'
      );
      const allowed = (rows || [])
        .filter((row) => expected.get(row.id) === String(row.owner_token || '').toLowerCase())
        .map(ownedInvite);

      return sendJSON(res, 200, allowed);
    }

    return sendJSON(res, 405, { error: 'GET or POST only' });
  } catch (e) {
    return sendJSON(res, e.status && e.status < 500 ? e.status : 500, {
      error: e.status && e.status < 500 ? e.message : 'Invite API error'
    });
  }
};
