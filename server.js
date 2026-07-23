#!/usr/bin/env node
/**
 * Bolzoo local dev server.
 *   - Serves static files from ./
 *   - Exposes PostgREST-compatible /rest/v1/invites endpoint (matches assets/api.js)
 *   - JSON file storage at ./data/invites.json (auto-created)
 *   - Zero npm dependencies
 *
 * Run:   node server.js       (default port 8080)
 *        PORT=3000 node server.js
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8080);
const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const DATA_FILE = path.join(DATA_DIR, 'invites.json');

fs.mkdirSync(DATA_DIR, { recursive: true });
let invites = {};
try { invites = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); } catch (_) { invites = {}; }

let savePending = false;
function save() {
  if (savePending) return;
  savePending = true;
  setImmediate(() => {
    savePending = false;
    fs.writeFileSync(DATA_FILE, JSON.stringify(invites, null, 2));
  });
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
  // Supabase RLS in our schema forbids anon from seeing owner_token via SELECT.
  // Simulate that: if `select` does not explicitly include owner_token, strip it.
  const clone = Object.assign({}, row);
  if (!select || !select.split(',').map(s => s.trim()).includes('owner_token')) {
    delete clone.owner_token;
  }
  return clone;
}

/* ---------- API ---------- */
async function handleAPI(req, res, url) {
  const method = req.method;
  const filters = parseFilters(url);
  const select = url.searchParams.get('select');
  const order  = url.searchParams.get('order');
  const prefer = String(req.headers.prefer || '');
  const wantsReturn = prefer.includes('return=representation');
  const bodyText = ['POST', 'PATCH', 'PUT'].includes(method) ? await readBody(req) : '';
  let body = null;
  if (bodyText) { try { body = JSON.parse(bodyText); } catch (e) { return sendJSON(res, 400, { error: 'Invalid JSON body' }); } }

  if (method === 'POST') {
    // POST /rest/v1/invites — insert a row
    const b = Array.isArray(body) ? body[0] : body;
    if (!b || !b.id) return sendJSON(res, 400, { error: 'id is required' });
    if (invites[b.id]) return sendJSON(res, 409, { error: 'id conflict' });
    const now = new Date().toISOString();
    const rec = {
      id:            b.id,
      owner_token:   b.owner_token || crypto.randomUUID(),
      config:        b.config || {},
      response:      null,
      opened_at:     null,
      responded_at:  null,
      created_at:    now
    };
    invites[rec.id] = rec;
    save();
    if (wantsReturn) return sendJSON(res, 201, [rec]); // return with owner_token for creator
    return sendJSON(res, 201, []);
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
    const targets = Object.values(invites).filter(r => matches(r, filters));
    for (const r of targets) {
      // Anon cannot modify owner_token or id
      const { id: _1, owner_token: _2, created_at: _3, ...rest } = body || {};
      Object.assign(r, rest);
    }
    save();
    return sendJSON(res, 200, targets.map(r => stripFieldsForSelect(r, select)));
  }

  if (method === 'DELETE') {
    // Requires owner_token filter to match (schema-level check)
    const hasToken = filters.owner_token && filters.owner_token.op === 'eq';
    if (!hasToken) return sendJSON(res, 403, { error: 'owner_token required to delete' });
    const targets = Object.values(invites).filter(r => matches(r, filters));
    targets.forEach(r => { delete invites[r.id]; });
    save();
    return sendJSON(res, 204, '');
  }

  return sendJSON(res, 405, { error: 'Method not allowed' });
}

/* ---------- Static files ---------- */
function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/create.html';
  const filePath = path.join(ROOT, rel);
  // Prevent path traversal
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
    if (url.pathname === '/rest/v1/invites' || url.pathname.startsWith('/rest/v1/invites/')) {
      return await handleAPI(req, res, url);
    }
    if (url.pathname === '/api/health') return sendJSON(res, 200, { ok: true, invites: Object.keys(invites).length });
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
  console.log('  Invite (id) :  ' + url + '/bolzoo.html?id=<ID>');
  console.log('  API health  :  ' + url + '/api/health');
  console.log('  Data file   :  ' + DATA_FILE);
  console.log('');
  console.log('  Ctrl+C to stop.');
});

process.on('SIGINT',  () => { console.log('\n👋 Stopping server'); process.exit(0); });
process.on('SIGTERM', () => process.exit(0));
