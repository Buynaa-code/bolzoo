#!/usr/bin/env node
/**
 * Bolzoo local dev server.
 *   - Serves static files from ./
 *   - Exposes PostgREST-compatible /rest/v1/invites + /rest/v1/access_codes endpoints
 *   - RPC-like endpoints under /rest/v1/rpc/* to match Supabase functions
 *   - JSON file storage at ./data/{invites,access_codes}.json (auto-created)
 *   - Zero npm dependencies
 *
 * Env:
 *   PORT              (default 8080)
 *   ADMIN_PASSWORD    (default "admin123" — used by admin.html for local dev)
 *
 * Run:   node server.js
 *        PORT=3000 ADMIN_PASSWORD=hunter2 node server.js
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8080);
const ADMIN_PASSWORD = String(process.env.ADMIN_PASSWORD || 'admin123');
const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const INVITES_FILE  = path.join(DATA_DIR, 'invites.json');
const CODES_FILE    = path.join(DATA_DIR, 'access_codes.json');
const PAYMENTS_FILE = path.join(DATA_DIR, 'payments.json');
const EVENTS_FILE   = path.join(DATA_DIR, 'webhook_events.json');

// Self-serve QPay үнэ (MNT ₮). Өөрчлөхөд энд бэлэн.
// PRICE_MNT env var-аар override хийнэ (жишээ: PRICE_MNT=10 node server.js).
const PRICE_MNT = Number(process.env.PRICE_MNT || 9900);

fs.mkdirSync(DATA_DIR, { recursive: true });

function loadJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return fallback; }
}
let invites       = loadJSON(INVITES_FILE, {});
let codes         = loadJSON(CODES_FILE, {});
let payments      = loadJSON(PAYMENTS_FILE, {});
let webhookEvents = loadJSON(EVENTS_FILE, {});

function makeSaver(file, getData) {
  let pending = false;
  return function save() {
    if (pending) return;
    pending = true;
    setImmediate(() => {
      pending = false;
      fs.writeFileSync(file, JSON.stringify(getData(), null, 2));
    });
  };
}
const saveInvites       = makeSaver(INVITES_FILE,  () => invites);
const saveCodes         = makeSaver(CODES_FILE,    () => codes);
const savePayments      = makeSaver(PAYMENTS_FILE, () => payments);
const saveWebhookEvents = makeSaver(EVENTS_FILE,   () => webhookEvents);

/* ---------- wire.mn payment gateway ---------- */
// Set WIRE_API_KEY env to enable live mode. Empty → mock mode for local dev.
const WIRE_API_BASE       = process.env.WIRE_API_BASE || 'https://api.wire.mn';
const WIRE_API_KEY        = String(process.env.WIRE_API_KEY || '');
const WIRE_WEBHOOK_SECRET = String(process.env.WIRE_WEBHOOK_SECRET || '');
const WIRE_ENABLED        = !!WIRE_API_KEY;
const YOUTUBE_API_KEY     = String(process.env.YOUTUBE_API_KEY || process.env.GOOGLE_API_KEY || '');

async function wireAPI(method, apiPath, body, idempotencyKey) {
  if (typeof fetch !== 'function') throw new Error('Node 18+ шаардлагатай (native fetch)');
  const headers = {
    'Authorization': 'Bearer ' + WIRE_API_KEY,
    'Content-Type':  'application/json'
  };
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  const opts = { method, headers };
  if (body != null) opts.body = JSON.stringify(body);
  const r = await fetch(WIRE_API_BASE + apiPath, opts);
  const text = await r.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch (_) { data = { raw: text }; }
  if (!r.ok) {
    const msg = (data.error && data.error.message) || ('Wire ' + r.status);
    const err = new Error(msg);
    err.status = r.status;
    err.data = data;
    throw err;
  }
  return data;
}

function verifyWireSignature(payload, sigHeader, secret) {
  if (!sigHeader || !secret) return false;
  const parts = {};
  sigHeader.split(',').forEach(kv => {
    const [k, v] = kv.split('=');
    if (k && v) parts[k.trim()] = v.trim();
  });
  if (!parts.t || !parts.v1) return false;
  const signed   = parts.t + '.' + payload;
  const expected = crypto.createHmac('sha256', secret).update(signed).digest('hex');
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(parts.v1, 'hex');
  if (a.length !== b.length) return false;
  try { return crypto.timingSafeEqual(a, b); } catch (_) { return false; }
}

function createAccessCodeForPayment(paymentId, mock) {
  let c;
  do { c = genCode(); } while (codes[c]);
  const nowTs = new Date().toISOString();
  codes[c] = {
    code:               c,
    used:               false,
    used_at:            null,
    used_for_invite_id: null,
    note:               (mock ? 'self-serve MOCK ' : 'self-serve ') + paymentId,
    source:             mock ? 'self_service_mock' : 'self_service',
    payment_id:         paymentId,
    created_at:         nowTs
  };
  saveCodes();
  return c;
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg':  'image/svg+xml',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.ico':  'image/x-icon',
  '.woff2':'font/woff2',
  '.woff': 'font/woff',
  '.map':  'application/json'
};

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Prefer,apikey,Authorization'
};

function send(res, code, body, headers = {}) {
  res.writeHead(code, Object.assign({}, CORS, headers));
  res.end(body);
}
function sendJSON(res, code, obj, headers = {}) {
  send(res, code, JSON.stringify(obj), Object.assign({ 'Content-Type': 'application/json; charset=utf-8' }, headers));
}
function sendPGError(res, code, message) {
  return sendJSON(res, code, { code: 'P0001', message: message, details: null, hint: null });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

/* ---------- Filter parser (PostgREST-lite) ---------- */
const RESERVED = new Set(['select', 'order', 'limit', 'offset', 'apikey', 'Prefer']);

function parseFilters(url) {
  const out = {};
  for (const [k, v] of url.searchParams) {
    if (RESERVED.has(k)) continue;
    const m = v.match(/^(eq|neq|gt|lt|gte|lte|is|in|like|ilike)\.(.*)$/s);
    if (!m) continue;
    out[k] = { op: m[1], val: m[2] };
  }
  return out;
}
function matches(row, filters) {
  for (const [key, f] of Object.entries(filters)) {
    const v = row[key];
    switch (f.op) {
      case 'eq':  if (String(v) !== f.val) return false; break;
      case 'neq': if (String(v) === f.val) return false; break;
      case 'is':
        if (f.val === 'null' && v != null) return false;
        if (f.val === 'not.null' && v == null) return false;
        break;
      case 'in': {
        const parts = f.val.replace(/^\(|\)$/g, '').split(',').map(s => decodeURIComponent(s.trim()));
        if (!parts.includes(String(v))) return false;
        break;
      }
      default: return false;
    }
  }
  return true;
}
function stripFieldsForSelect(row, select) {
  const clone = Object.assign({}, row);
  if (!select || !select.split(',').map(s => s.trim()).includes('owner_token')) {
    delete clone.owner_token;
  }
  return clone;
}

/* ---------- Code generation (matches SQL _gen_code) ---------- */
function genCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = 'LOV-';
  const buf = crypto.randomBytes(6);
  for (let i = 0; i < 6; i++) out += chars[buf[i] % chars.length];
  return out;
}

/* ---------- /rest/v1/invites ---------- */
async function handleInvites(req, res, url) {
  const method = req.method;
  const filters = parseFilters(url);
  const select = url.searchParams.get('select');
  const order  = url.searchParams.get('order');
  const bodyText = ['POST', 'PATCH', 'PUT'].includes(method) ? await readBody(req) : '';
  let body = null;
  if (bodyText) { try { body = JSON.parse(bodyText); } catch (e) { return sendJSON(res, 400, { error: 'Invalid JSON body' }); } }

  if (method === 'POST') {
    // Direct anon inserts are blocked — must use /rpc/create_invite_with_code
    return sendPGError(res, 403, 'Direct invite insert not allowed. Use rpc/create_invite_with_code.');
  }

  if (method === 'GET') {
    let rows = Object.values(invites).filter(r => matches(r, filters));
    if (order) {
      const [col, dir] = order.split('.');
      rows = rows.slice().sort((a, b) => {
        const av = String(a[col] || ''), bv = String(b[col] || '');
        return dir === 'desc' ? bv.localeCompare(av) : av.localeCompare(bv);
      });
    }
    rows = rows.map(r => stripFieldsForSelect(r, select));
    return sendJSON(res, 200, rows);
  }

  if (method === 'PATCH') {
    return sendPGError(res, 403, 'Direct invite update not allowed. Use rpc/save_response or rpc/mark_opened.');
  }

  if (method === 'DELETE') {
    return sendPGError(res, 403, 'Direct invite delete not allowed. Use rpc/delete_own_invite.');
  }

  return sendJSON(res, 405, { error: 'Method not allowed' });
}

/* ---------- /rest/v1/access_codes ---------- */
async function handleCodes(req, res, url) {
  const method = req.method;
  const filters = parseFilters(url);

  if (method === 'GET') {
    let rows = Object.values(codes).filter(r => matches(r, filters));
    return sendJSON(res, 200, rows);
  }
  // No anon insert/update/delete — must use RPCs
  return sendPGError(res, 403, 'access_codes mutations must go through admin RPCs.');
}

/* ---------- /rest/v1/rpc/* ---------- */
async function handleRPC(req, res, url) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'RPC requires POST' });
  const name = url.pathname.replace(/^\/rest\/v1\/rpc\//, '');
  const bodyText = await readBody(req);
  let body = {};
  try { body = bodyText ? JSON.parse(bodyText) : {}; } catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON' }); }

  if (name === 'create_invite_with_code') {
    const invId = body.p_invite_id;
    const cfg   = body.p_config;
    const code  = body.p_access_code;
    if (!invId || String(invId).length < 4) return sendPGError(res, 400, 'Invalid invite id');
    if (!code) return sendPGError(res, 400, 'Access code required');
    const codeRow = codes[code];
    if (!codeRow) return sendPGError(res, 400, 'Invalid access code');
    if (codeRow.used) return sendPGError(res, 400, 'Access code already used');
    if (invites[invId]) return sendPGError(res, 409, 'invite id conflict');

    const nowTs = new Date().toISOString();
    const ownerToken = crypto.randomUUID();
    invites[invId] = {
      id:            invId,
      owner_token:   ownerToken,
      config:        cfg || {},
      response:      null,
      opened_at:     null,
      responded_at:  null,
      created_at:    nowTs
    };
    codeRow.used = true;
    codeRow.used_at = nowTs;
    codeRow.used_for_invite_id = invId;

    saveInvites();
    saveCodes();

    // Supabase returns array of {id, owner_token, created_at}
    return sendJSON(res, 200, [{ id: invId, owner_token: ownerToken, created_at: nowTs }]);
  }

  if (name === 'save_response') {
    const invId = body.p_invite_id;
    if (!invId) return sendPGError(res, 400, 'Invite id required');
    const inv = invites[invId];
    if (!inv) return sendPGError(res, 404, 'Invite not found');
    inv.response = body.p_response == null ? null : body.p_response;
    inv.responded_at = new Date().toISOString();
    saveInvites();
    return sendJSON(res, 200, null);
  }

  if (name === 'mark_opened') {
    const invId = body.p_invite_id;
    if (!invId) return sendJSON(res, 200, null);
    const inv = invites[invId];
    if (inv && !inv.opened_at) { inv.opened_at = new Date().toISOString(); saveInvites(); }
    return sendJSON(res, 200, null);
  }

  if (name === 'delete_own_invite') {
    const invId = body.p_invite_id;
    const token = body.p_owner_token;
    if (!invId || !token) return sendPGError(res, 400, 'invite id and owner token required');
    const inv = invites[invId];
    if (!inv || inv.owner_token !== token) return sendPGError(res, 404, 'Invite not found or wrong owner token');
    delete invites[invId];
    saveInvites();
    return sendJSON(res, 200, null);
  }

  if (name === 'admin_create_codes') {
    if (body.admin_pw !== ADMIN_PASSWORD) return sendPGError(res, 401, 'Invalid admin password');
    const qty = Math.max(1, Math.min(100, Number(body.qty || 1)));
    const note = body.note_ != null ? String(body.note_) : null;
    const created = [];
    for (let i = 0; i < qty; i++) {
      let c;
      do { c = genCode(); } while (codes[c]);
      const row = { code: c, used: false, used_at: null, used_for_invite_id: null, note: note, created_at: new Date().toISOString() };
      codes[c] = row;
      created.push(row);
    }
    saveCodes();
    return sendJSON(res, 200, created);
  }

  if (name === 'admin_list_codes') {
    if (body.admin_pw !== ADMIN_PASSWORD) return sendPGError(res, 401, 'Invalid admin password');
    const rows = Object.values(codes).sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
    return sendJSON(res, 200, rows);
  }

  if (name === 'admin_delete_code') {
    if (body.admin_pw !== ADMIN_PASSWORD) return sendPGError(res, 401, 'Invalid admin password');
    const c = body.p_code;
    if (!codes[c]) return sendPGError(res, 404, 'Code not found');
    if (codes[c].used) return sendPGError(res, 400, 'Cannot delete used code');
    delete codes[c];
    saveCodes();
    return sendJSON(res, 200, null);
  }

  return sendPGError(res, 404, 'Unknown RPC: ' + name);
}

/* ---------- /api/checkout | /api/payment-status | /api/wire-webhook ---------- */
async function handleCheckout(req, res) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  const bodyText = await readBody(req);
  let body = {};
  try { body = bodyText ? JSON.parse(bodyText) : {}; } catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON' }); }
  const nowTs = new Date().toISOString();

  if (WIRE_ENABLED) {
    try {
      const pi = await wireAPI('POST', '/v1/payment_intents', {
        amount: PRICE_MNT,
        currency: 'MNT',
        automatic_operator: true,
        metadata: { product: 'bolzoo_access_code', tier: 'single' }
      }, crypto.randomUUID());

      const confirmed = await wireAPI('POST', '/v1/payment_intents/' + pi.id + '/confirm', {
        return_url: (req.headers.origin || '') + '/pay.html?intent=' + pi.id
      }, crypto.randomUUID());

      payments[pi.id] = {
        id:                 pi.id,
        status:             confirmed.status || pi.status || 'requires_action',
        amount:             pi.amount,
        currency:           pi.currency || 'MNT',
        provider:           'wire',
        provider_intent_id: pi.id,
        client_secret:      pi.client_secret || null,
        next_action:        confirmed.next_action || pi.next_action || null,
        code:               null,
        email:              body.email || null,
        created_at:         nowTs,
        updated_at:         nowTs,
        expires_at:         confirmed.expires_at ? new Date(confirmed.expires_at * 1000).toISOString() : null
      };
      savePayments();
      return sendJSON(res, 200, {
        intent_id:   pi.id,
        amount:      pi.amount,
        status:      payments[pi.id].status,
        next_action: payments[pi.id].next_action,
        mode:        'live'
      });
    } catch (e) {
      console.error('Wire checkout error:', e.status || '', e.message);
      return sendJSON(res, 502, { error: e.message || 'Wire API error', data: e.data || null });
    }
  }

  // Mock mode
  const mockId = 'pi_mock_' + crypto.randomBytes(8).toString('hex');
  payments[mockId] = {
    id:                 mockId,
    status:             'requires_action',
    amount:             PRICE_MNT,
    currency:           'MNT',
    provider:           'mock',
    provider_intent_id: null,
    client_secret:      null,
    next_action:        null,
    code:               null,
    email:              body.email || null,
    created_at:         nowTs,
    updated_at:         nowTs,
    expires_at:         new Date(Date.now() + 15 * 60 * 1000).toISOString()
  };
  savePayments();
  return sendJSON(res, 200, {
    intent_id:   mockId,
    amount:      PRICE_MNT,
    status:      'requires_action',
    next_action: null,
    mode:        'mock'
  });
}

async function handlePaymentStatus(req, res, url) {
  const id = url.searchParams.get('id');
  if (!id) return sendJSON(res, 400, { error: 'id required' });
  const p = payments[id];
  if (!p) return sendJSON(res, 404, { error: 'Payment not found' });

  // Refresh from wire if still in-flight
  if (p.provider === 'wire' && WIRE_ENABLED && p.status !== 'succeeded' && p.status !== 'canceled') {
    try {
      const remote = await wireAPI('GET', '/v1/payment_intents/' + p.id);
      p.status      = remote.status || p.status;
      p.next_action = remote.next_action || p.next_action;
      p.updated_at  = new Date().toISOString();
      savePayments();
    } catch (e) {
      console.error('Wire poll error:', e.status || '', e.message);
    }
  }

  if (p.status === 'succeeded' && !p.code) {
    p.code = createAccessCodeForPayment(p.id, p.provider === 'mock');
    p.updated_at = new Date().toISOString();
    savePayments();
  }

  return sendJSON(res, 200, {
    intent_id:   p.id,
    status:      p.status,
    code:        p.status === 'succeeded' ? p.code : null,
    amount:      p.amount,
    next_action: p.next_action,
    expires_at:  p.expires_at,
    mode:        p.provider === 'mock' ? 'mock' : 'live'
  });
}

async function handleWireWebhook(req, res) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  const bodyText = await readBody(req);

  if (WIRE_WEBHOOK_SECRET) {
    const sig = req.headers['wirepayment-signature'] || '';
    if (!verifyWireSignature(bodyText, sig, WIRE_WEBHOOK_SECRET)) {
      return sendJSON(res, 401, { error: 'invalid signature' });
    }
  }

  let event = {};
  try { event = bodyText ? JSON.parse(bodyText) : {}; } catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON' }); }
  const evtId    = event.id || '';
  const type     = event.type || '';
  const data     = event.data || {};
  const intentId = (data && (data.id || (data.object && data.object.id))) || event.intent_id;

  console.log('[webhook]', new Date().toISOString(), type || '(no-type)', evtId || '-', intentId || '-');

  // Idempotency: Wire may re-deliver — dedup by event id
  if (evtId && webhookEvents[evtId]) {
    return sendJSON(res, 200, { ok: true, already: true });
  }

  const nowTs = new Date().toISOString();
  if (intentId && (type === 'payment_intent.succeeded' || type === 'charge.succeeded')) {
    const p = payments[intentId];
    if (p) {
      p.status = 'succeeded';
      if (!p.code) p.code = createAccessCodeForPayment(p.id, p.provider === 'mock');
      p.updated_at = nowTs;
      savePayments();
    }
  } else if (intentId && (type === 'payment_intent.canceled')) {
    const p = payments[intentId];
    if (p) { p.status = 'canceled'; p.updated_at = nowTs; savePayments(); }
  } else if (intentId && (type === 'payment_intent.payment_failed' || type === 'charge.failed')) {
    const p = payments[intentId];
    if (p) { p.status = 'failed'; p.updated_at = nowTs; savePayments(); }
  }

  if (evtId) {
    webhookEvents[evtId] = { id: evtId, type: type, intent_id: intentId || null, processed_at: nowTs };
    saveWebhookEvents();
  }

  return sendJSON(res, 200, { ok: true });
}

// Dev-only: simulate a mock payment's success (mock provider only)
async function handleDevMarkPaid(req, res) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  const bodyText = await readBody(req);
  let body = {};
  try { body = bodyText ? JSON.parse(bodyText) : {}; } catch (_) {}
  const intentId = body.intent_id;
  if (!intentId) return sendJSON(res, 400, { error: 'intent_id required' });
  const p = payments[intentId];
  if (!p) return sendJSON(res, 404, { error: 'Payment not found' });
  if (p.provider !== 'mock') return sendJSON(res, 403, { error: 'Only mock payments can be simulated' });

  if (!p.code) p.code = createAccessCodeForPayment(p.id, true);
  p.status = 'succeeded';
  p.updated_at = new Date().toISOString();
  savePayments();
  return sendJSON(res, 200, { ok: true, code: p.code });
}

/* ---------- /api/youtube-search ---------- */
function pickYouTubeThumbnail(thumbnails) {
  const t = thumbnails || {};
  return (t.medium && t.medium.url) || (t.high && t.high.url) || (t.default && t.default.url) || '';
}

function decodeYouTubeEntities(value) {
  return String(value || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function youtubeUserError(data) {
  const err = data && data.error;
  const reason = err && err.errors && err.errors[0] && err.errors[0].reason;
  const details = (err && err.details) || [];
  const detailReason = details.map((d) => d && d.reason).filter(Boolean).join(' ');
  const message = (err && err.message) || '';
  if (reason === 'quotaExceeded' || reason === 'dailyLimitExceeded') {
    return 'Өнөөдрийн YouTube хайлтын quota дууссан байна. Маргааш дахин оролдоно уу.';
  }
  if (/API_KEY_SERVICE_BLOCKED|SERVICE_DISABLED|accessNotConfigured/i.test(detailReason + ' ' + message)) {
    return 'Google Cloud дээр YouTube Data API v3 идэвхжээгүй эсвэл API key restriction хайлтыг блоклосон байна.';
  }
  if (reason === 'keyInvalid' || /API key not valid/i.test(message)) {
    return 'YouTube API key буруу байна. Google Cloud credential-ээ шалгана уу.';
  }
  return 'YouTube хайлт хийх үед алдаа гарлаа.';
}

async function handleYouTubeSearch(req, res, url) {
  if (req.method !== 'GET') return sendJSON(res, 405, { error: 'GET only' });
  if (!YOUTUBE_API_KEY) {
    return sendJSON(res, 503, {
      error: 'YOUTUBE_API_KEY тохируулаагүй байна.',
      user_error: 'YouTube хайлт түр идэвхгүй байна. API key тохиргоог шалгана уу.'
    });
  }

  const q = String(url.searchParams.get('q') || '').trim();
  const max = Math.max(1, Math.min(10, Number(url.searchParams.get('maxResults') || 10)));
  if (q.length < 2) return sendJSON(res, 400, { error: 'Хайх үг хамгийн багадаа 2 тэмдэгт байна.' });

  const params = new URLSearchParams({
    part: 'snippet',
    type: 'video',
    maxResults: String(max),
    q,
    key: YOUTUBE_API_KEY,
    videoEmbeddable: 'true',
    safeSearch: 'none'
  });
  const response = await fetch('https://www.googleapis.com/youtube/v3/search?' + params.toString());
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = data.error && data.error.errors && data.error.errors[0] && data.error.errors[0].reason;
    return sendJSON(res, response.status, {
      error: (data.error && data.error.message) || 'YouTube API error',
      reason: reason || null,
      user_error: youtubeUserError(data)
    });
  }

  const items = (data.items || []).map((item) => {
    const videoId = item.id && item.id.videoId;
    const snippet = item.snippet || {};
    return videoId ? {
      videoId,
      title: decodeYouTubeEntities(snippet.title),
      channelTitle: decodeYouTubeEntities(snippet.channelTitle),
      thumbnail: pickYouTubeThumbnail(snippet.thumbnails),
      publishedAt: snippet.publishedAt || '',
      url: 'https://www.youtube.com/watch?v=' + videoId
    } : null;
  }).filter(Boolean);

  return sendJSON(res, 200, { items }, { 'Cache-Control': 'public, max-age=300' });
}

/* ---------- Static files ---------- */
function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/create.html';
  const filePath = path.join(ROOT, rel);
  if (!filePath.startsWith(ROOT)) return send(res, 403, 'Forbidden');
  fs.stat(filePath, (err, st) => {
    if (err || !st.isFile()) return send(res, 404, 'Not found: ' + rel);
    const ext = path.extname(filePath).toLowerCase();
    const type = MIME[ext] || 'application/octet-stream';
    res.writeHead(200, Object.assign({ 'Content-Type': type, 'Cache-Control': 'no-cache' }, CORS));
    fs.createReadStream(filePath).pipe(res);
  });
}

/* ---------- Router ---------- */
const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') return send(res, 204, '');
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (url.pathname.startsWith('/rest/v1/rpc/')) return await handleRPC(req, res, url);
    if (url.pathname === '/rest/v1/invites' || url.pathname.startsWith('/rest/v1/invites/')) return await handleInvites(req, res, url);
    if (url.pathname === '/rest/v1/access_codes' || url.pathname.startsWith('/rest/v1/access_codes/')) return await handleCodes(req, res, url);
    if (url.pathname === '/api/health') return sendJSON(res, 200, { ok: true, invites: Object.keys(invites).length, codes: Object.keys(codes).length, payments: Object.keys(payments).length, webhook_events: Object.keys(webhookEvents).length, wire: WIRE_ENABLED ? 'live' : 'mock', wire_webhook_secret: WIRE_WEBHOOK_SECRET ? 'set' : 'unset', youtube: YOUTUBE_API_KEY ? 'configured' : 'not_configured', price: PRICE_MNT });
    if (url.pathname === '/api/checkout')        return await handleCheckout(req, res);
    if (url.pathname === '/api/payment-status')  return await handlePaymentStatus(req, res, url);
    if (url.pathname === '/api/wire-webhook')    return await handleWireWebhook(req, res);
    if (url.pathname === '/api/dev-mark-paid')   return await handleDevMarkPaid(req, res);
    if (url.pathname === '/api/youtube-search')  return await handleYouTubeSearch(req, res, url);
    return serveStatic(req, res, url);
  } catch (e) {
    console.error('Server error:', e);
    sendJSON(res, 500, { error: e.message });
  }
});

server.listen(PORT, () => {
  const url = `http://localhost:${PORT}`;
  console.log('');
  console.log('  💌  Bolzoo dev server');
  console.log('  ─────────────────────────────────────');
  console.log('  Create page :  ' + url + '/create.html');
  console.log('  Dashboard   :  ' + url + '/dashboard.html');
  console.log('  Admin page  :  ' + url + '/admin.html');
  console.log('  Invite (id) :  ' + url + '/bolzoo.html?id=<ID>');
  console.log('  API health  :  ' + url + '/api/health');
  console.log('  Pay page    :  ' + url + '/pay.html');
  console.log('  Admin pw    :  ' + ADMIN_PASSWORD + '  (set ADMIN_PASSWORD env to change)');
  console.log('  Wire mode   :  ' + (WIRE_ENABLED ? '🟢 live (WIRE_API_KEY тохирсон)' : '🧪 mock (WIRE_API_KEY тохируулаагүй)'));
  console.log('  Price       :  ' + PRICE_MNT.toLocaleString() + ' ₮');
  console.log('');
  console.log('  Ctrl+C to stop.');
});

process.on('SIGINT',  () => { console.log('\n👋 Stopping server'); process.exit(0); });
process.on('SIGTERM', () => process.exit(0));
