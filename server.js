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
const INVITES_FILE = path.join(DATA_DIR, 'invites.json');
const CODES_FILE = path.join(DATA_DIR, 'access_codes.json');

fs.mkdirSync(DATA_DIR, { recursive: true });

function loadJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return fallback; }
}
let invites = loadJSON(INVITES_FILE, {});
let codes   = loadJSON(CODES_FILE, {});

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
const saveInvites = makeSaver(INVITES_FILE, () => invites);
const saveCodes   = makeSaver(CODES_FILE,   () => codes);

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
    if (url.pathname === '/api/health') return sendJSON(res, 200, { ok: true, invites: Object.keys(invites).length, codes: Object.keys(codes).length });
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
  console.log('  Admin pw    :  ' + ADMIN_PASSWORD + '  (set ADMIN_PASSWORD env to change)');
  console.log('');
  console.log('  Ctrl+C to stop.');
});

process.on('SIGINT',  () => { console.log('\n👋 Stopping server'); process.exit(0); });
process.on('SIGTERM', () => process.exit(0));
