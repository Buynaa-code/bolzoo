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

// ── Lightweight .env loader (zero deps) ─────────────────────────────────────
// Repo root дахь `.env` файлыг уншиж process.env-т нэмнэ.
// Урьтамжлал: shell env > .env.local > .env  (shell утгыг хэзээ ч дардаггүй)
(function loadDotEnv(){
  const setByFile = new Set();
  const files = ['.env', '.env.local'];
  for (const name of files) {
    const p = path.join(__dirname, name);
    let raw;
    try { raw = fs.readFileSync(p, 'utf8'); } catch (_) { continue; }
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim();
      // "quoted" эсвэл 'quoted' утгыг задална
      if ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      // Shell-с ирсэн бол хэвээр үлдэнэ. .env-ээс ирсэн бол .env.local нь дардаг.
      if (process.env[key] === undefined || setByFile.has(key)) {
        process.env[key] = val;
        setByFile.add(key);
      }
    }
  }
})();

const PORT = Number(process.env.PORT || 8080);
const HOST = String(process.env.HOST || '127.0.0.1');
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
const PAYMENT_DESCRIPTION = (String(process.env.PAYMENT_DESCRIPTION || process.env.PAYMENT_MEMO || 'Bolzoo invite access').trim().slice(0, 80) || 'Bolzoo invite access');

function paymentMetadata() {
  return {
    product: 'bolzoo_access_code',
    tier: 'single',
    description: PAYMENT_DESCRIPTION,
    invoice_description: PAYMENT_DESCRIPTION,
    transaction_description: PAYMENT_DESCRIPTION
  };
}

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

function verifyWireSignature(payload, sigHeader, secret, toleranceSeconds, nowSeconds) {
  if (!sigHeader || !secret) return false;
  const parts = { v1: [] };
  sigHeader.split(',').forEach(kv => {
    const idx = kv.indexOf('=');
    if (idx < 0) return;
    const key = kv.slice(0, idx).trim();
    const value = kv.slice(idx + 1).trim();
    if (key === 'v1') parts.v1.push(value);
    else parts[key] = value;
  });
  const timestamp = Number(parts.t);
  const tolerance = Number(toleranceSeconds == null ? 300 : toleranceSeconds);
  const now = Number(nowSeconds == null ? Math.floor(Date.now() / 1000) : nowSeconds);
  if (!Number.isFinite(timestamp) || !parts.v1.length) return false;
  if (tolerance >= 0 && Math.abs(now - timestamp) > tolerance) return false;

  const signed   = parts.t + '.' + payload;
  const expected = crypto.createHmac('sha256', secret).update(signed).digest('hex');
  const a = Buffer.from(expected, 'hex');
  return parts.v1.some(signature => {
    if (!/^[0-9a-f]+$/i.test(signature)) return false;
    const b = Buffer.from(signature, 'hex');
    if (a.length !== b.length) return false;
    try { return crypto.timingSafeEqual(a, b); } catch (_) { return false; }
  });
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

function readBody(req, maxBytes) {
  const limit = Number(maxBytes || 64 * 1024);
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', c => {
      size += c.length;
      if (size > limit) {
        const err = new Error('Request body too large');
        err.status = 413;
        reject(err);
        req.destroy();
        return;
      }
      chunks.push(c);
    });
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
    return sendPGError(res, 403, 'Direct invite reads are disabled. Use /api/invite.');
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
    return sendPGError(res, 403, 'Direct access code reads are disabled. Use /api/validate-code.');
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
    const priv  = body.p_private_config;
    if (!invId || String(invId).length < 8) return sendPGError(res, 400, 'Invalid invite id');
    if (!code) return sendPGError(res, 400, 'Access code required');
    const codeRow = codes[code];
    if (!codeRow) return sendPGError(res, 400, 'Invalid access code');
    if (codeRow.used) return sendPGError(res, 400, 'Access code already used');
    if (invites[invId]) return sendPGError(res, 409, 'invite id conflict');

    const nowTs = new Date().toISOString();
    const ownerToken = crypto.randomUUID();
    invites[invId] = {
      id:             invId,
      owner_token:    ownerToken,
      config:         cfg || {},
      private_config: priv || {},
      response:       null,
      opened_at:      null,
      responded_at:   null,
      created_at:     nowTs
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

    const existing = inv.response;
    if (existing && String(existing.final) === 'true') {
      return sendJSON(res, 200, null);   // locked final answer wins
    }
    const clientTs = body.p_client_ts ? String(body.p_client_ts) : null;
    if (clientTs && inv.responded_at && inv.responded_at > clientTs) {
      return sendJSON(res, 200, null);   // stale retry — silently ignore
    }

    const nextResponse = body.p_response == null ? null : body.p_response;
    // Mirror the DB before-update trigger: append the old answer into history
    // whenever it changes so the dashboard timeline is populated in local dev.
    if (existing && JSON.stringify(existing) !== JSON.stringify(nextResponse)) {
      inv.response_history = Array.isArray(inv.response_history) ? inv.response_history : [];
      inv.response_history.push({ response: existing, responded_at: inv.responded_at });
    }
    inv.response = nextResponse;
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

/* ---------- Protected read APIs ---------- */
const INVITE_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const OWNER_TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACCESS_CODE_RE = /^LOV-[A-HJ-NP-Z2-9]{6}$/;

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

function publicInvite(inv) {
  return { id: inv.id, config: pickPublicConfig(inv.config), created_at: inv.created_at };
}

function ownedInvite(inv) {
  return {
    id: inv.id,
    config: inv.config,
    private_config: inv.private_config || {},
    response: inv.response,
    response_history: inv.response_history || [],
    opened_at: inv.opened_at,
    responded_at: inv.responded_at,
    created_at: inv.created_at
  };
}

async function handleInviteAPI(req, res, url) {
  if (req.method === 'GET') {
    const id = String(url.searchParams.get('id') || '');
    if (!INVITE_ID_RE.test(id)) return sendJSON(res, 400, { error: 'Invalid invite id' });
    const inv = invites[id];
    if (!inv) return sendJSON(res, 404, { error: 'Invite not found' });
    return sendJSON(res, 200, publicInvite(inv), { 'Cache-Control': 'private, no-store' });
  }

  if (req.method === 'POST') {
    const bodyText = await readBody(req);
    let body = {};
    try { body = bodyText ? JSON.parse(bodyText) : {}; } catch (_) {
      return sendJSON(res, 400, { error: 'Invalid JSON' });
    }
    const items = Array.isArray(body.items) ? body.items : [];
    if (!items.length || items.length > 100) {
      return sendJSON(res, 400, { error: 'items must contain 1-100 invites' });
    }

    const rows = [];
    for (const item of items) {
      const id = String(item && item.id || '');
      const token = String(item && item.owner_token || '');
      if (!INVITE_ID_RE.test(id) || !OWNER_TOKEN_RE.test(token)) {
        return sendJSON(res, 400, { error: 'Invalid invite ownership data' });
      }
      const inv = invites[id];
      if (inv && inv.owner_token === token) rows.push(ownedInvite(inv));
    }
    return sendJSON(res, 200, rows, { 'Cache-Control': 'private, no-store' });
  }

  return sendJSON(res, 405, { error: 'GET or POST only' });
}

async function handleValidateCodeAPI(req, res) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  const bodyText = await readBody(req);
  let body = {};
  try { body = bodyText ? JSON.parse(bodyText) : {}; } catch (_) {
    return sendJSON(res, 400, { error: 'Invalid JSON' });
  }
  const code = String(body.code || '').trim().toUpperCase();
  if (!ACCESS_CODE_RE.test(code) || !codes[code]) {
    return sendJSON(res, 200, { ok: false, reason: 'not_found' }, { 'Cache-Control': 'private, no-store' });
  }
  if (codes[code].used) {
    return sendJSON(res, 200, { ok: false, reason: 'used' }, { 'Cache-Control': 'private, no-store' });
  }
  return sendJSON(res, 200, { ok: true }, { 'Cache-Control': 'private, no-store' });
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
        description: PAYMENT_DESCRIPTION,
        metadata: paymentMetadata()
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
        payment_description: PAYMENT_DESCRIPTION,
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
    payment_description: PAYMENT_DESCRIPTION,
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
    payment_description: PAYMENT_DESCRIPTION,
    next_action: p.next_action,
    expires_at:  p.expires_at,
    mode:        p.provider === 'mock' ? 'mock' : 'live'
  });
}

async function handleWireWebhook(req, res) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  if (!WIRE_WEBHOOK_SECRET) {
    return sendJSON(res, 503, { error: 'WIRE_WEBHOOK_SECRET is required' });
  }
  const bodyText = await readBody(req);

  const sig = req.headers['wirepayment-signature'] || '';
  if (!verifyWireSignature(bodyText, sig, WIRE_WEBHOOK_SECRET)) {
    return sendJSON(res, 401, { error: 'invalid or expired signature' });
  }

  let event = {};
  try { event = bodyText ? JSON.parse(bodyText) : {}; } catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON' }); }
  const evtId    = event.id || '';
  const type     = event.type || '';
  const data     = event.data || {};
  const object   = data && data.object || {};
  const intentId = object.payment_intent || data.payment_intent || object.id || data.id || event.intent_id;
  if (!evtId) return sendJSON(res, 400, { error: 'event id required' });

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

// Local-dev stub for /api/notify-response. Real email delivery is handled by
// the Vercel serverless function api/notify-response.js. Locally we just log so
// devs can see the flow without needing RESEND_API_KEY.
async function handleNotifyResponse(req, res) {
  if (req.method !== 'POST') return sendJSON(res, 405, { error: 'POST only' });
  const bodyText = await readBody(req);
  let body = {};
  try { body = bodyText ? JSON.parse(bodyText) : {}; } catch (_) {
    return sendJSON(res, 400, { error: 'Invalid JSON' });
  }
  const id = String(body && body.inviteId || '');
  if (!INVITE_ID_RE.test(id)) return sendJSON(res, 400, { error: 'Invalid invite id' });
  const inv = invites[id];
  if (!inv) return sendJSON(res, 404, { error: 'Invite not found' });
  if (!inv.responded_at) return sendJSON(res, 400, { error: 'Invite has no response yet' });
  const resp = inv.response || {};
  const hasDate = !!(resp.date || resp.dateISO);
  const isDecline = String(resp.answer || '').toLowerCase() === 'no';
  if (!hasDate && !isDecline) return sendJSON(res, 200, { sent: false, reason: 'not_committed' });
  const to = (inv.private_config && inv.private_config.responseEmail) || '';
  if (!to) return sendJSON(res, 200, { sent: false, reason: 'no_owner_email' });
  console.log('  📮  [local] notify-response →', to, 'invite', id, JSON.stringify(inv.response));
  return sendJSON(res, 200, { sent: false, reason: 'local_dev_stub', to });
}

// Local dev mirror of api/invite-ics.js — reads from the local invites JSON
// store so the .ics link on bolzoo.html works without a Vercel deploy.
const inviteIcs = require('./api/invite-ics');
async function handleInviteIcs(req, res, url) {
  if (req.method !== 'GET') return sendJSON(res, 405, { error: 'GET only' });
  const id = String(url.searchParams.get('id') || '');
  if (!INVITE_ID_RE.test(id)) return sendJSON(res, 400, { error: 'Invalid invite id' });
  const inv = invites[id];
  if (!inv || !inv.response || !inv.responded_at) {
    return sendJSON(res, 404, { error: 'No confirmed response yet' });
  }
  const answer = String((inv.response && inv.response.answer) || '').toLowerCase();
  if (answer === 'no' || answer === 'later') {
    return sendJSON(res, 404, { error: 'Response is not a confirmed yes' });
  }
  const dt = inviteIcs.parseLocalDateTime(inv.response);
  if (!dt) return sendJSON(res, 400, { error: 'Response missing dateISO/time' });
  const start = inviteIcs.toUtcCompact(dt.y, dt.m, dt.d, dt.hh, dt.mm);
  const end   = inviteIcs.toUtcCompact(dt.y, dt.m, dt.d, dt.hh + 2, dt.mm);
  const cfg = inv.config || {};
  const title = 'Bolzoo — ' + (cfg.recipientName || 'Болзоо')
              + (inv.response.kind ? ' · ' + inv.response.kind : '');
  const ics = inviteIcs.buildIcs({
    inviteId:    id,
    title:       title,
    description: (cfg.customNote ? cfg.customNote + '\n' : '') + 'Bolzoo invite',
    location:    cfg.locationName || '',
    start:       start,
    end:         end,
    host:        req.headers.host
  });
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="bolzoo-' + id + '.ics"');
  res.setHeader('Cache-Control', 'private, no-store');
  res.end(ics);
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
const PUBLIC_FILES = new Set([
  '/admin.html',
  '/bolzoo.html',
  '/create.html',
  '/dashboard.html',
  '/pay.html'
]);

function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/create.html';
  if (!PUBLIC_FILES.has(rel) && !rel.startsWith('/assets/') && !rel.startsWith('/marketing/')) {
    return send(res, 404, 'Not found');
  }
  const filePath = path.join(ROOT, rel);
  const relativePath = path.relative(ROOT, filePath);
  if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) return send(res, 403, 'Forbidden');
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
    if (url.pathname === '/api/health') return sendJSON(res, 200, { ok: true, invites: Object.keys(invites).length, codes: Object.keys(codes).length, payments: Object.keys(payments).length, webhook_events: Object.keys(webhookEvents).length, wire: WIRE_ENABLED ? 'live' : 'mock', wire_webhook_secret: WIRE_WEBHOOK_SECRET ? 'set' : 'unset', youtube: YOUTUBE_API_KEY ? 'configured' : 'not_configured', price: PRICE_MNT, payment_description: PAYMENT_DESCRIPTION });
    if (url.pathname === '/api/invite')          return await handleInviteAPI(req, res, url);
    if (url.pathname === '/api/validate-code')   return await handleValidateCodeAPI(req, res);
    if (url.pathname === '/api/checkout')        return await handleCheckout(req, res);
    if (url.pathname === '/api/payment-status')  return await handlePaymentStatus(req, res, url);
    if (url.pathname === '/api/wire-webhook')    return await handleWireWebhook(req, res);
    if (url.pathname === '/api/dev-mark-paid')   return await handleDevMarkPaid(req, res);
    if (url.pathname === '/api/notify-response') return await handleNotifyResponse(req, res);
    if (url.pathname === '/api/invite-ics')      return await handleInviteIcs(req, res, url);
    if (url.pathname === '/api/youtube-search')  return await handleYouTubeSearch(req, res, url);
    return serveStatic(req, res, url);
  } catch (e) {
    console.error('Server error:', e);
    sendJSON(res, 500, { error: e.message });
  }
});

server.listen(PORT, HOST, () => {
  const url = `http://${HOST}:${PORT}`;
  console.log('');
  console.log('  💌  Bolzoo dev server');
  console.log('  ─────────────────────────────────────');
  console.log('  Create page :  ' + url + '/create.html');
  console.log('  Dashboard   :  ' + url + '/dashboard.html');
  console.log('  Admin page  :  ' + url + '/admin.html');
  console.log('  Invite (id) :  ' + url + '/bolzoo.html?id=<ID>');
  console.log('  API health  :  ' + url + '/api/health');
  console.log('  Pay page    :  ' + url + '/pay.html');
  console.log('  Admin auth  :  ' + (process.env.ADMIN_PASSWORD ? 'custom password configured' : 'local default in use'));
  console.log('  Wire mode   :  ' + (WIRE_ENABLED ? '🟢 live (WIRE_API_KEY тохирсон)' : '🧪 mock (WIRE_API_KEY тохируулаагүй)'));
  console.log('  YouTube key :  ' + (YOUTUBE_API_KEY ? '🟢 тохирсон' : '⚪ тохируулаагүй (хайлт 503 буцаана)'));
  console.log('  Price       :  ' + PRICE_MNT.toLocaleString() + ' ₮');
  console.log('');
  console.log('  Ctrl+C to stop.');
});

process.on('SIGINT',  () => { console.log('\n👋 Stopping server'); process.exit(0); });
process.on('SIGTERM', () => process.exit(0));
