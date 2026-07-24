'use strict';

const crypto = require('crypto');

const DEFAULT_SUPABASE_URL = 'https://chmxjljudmwttwhemdri.supabase.co';
const FINAL_STATUSES = new Set(['succeeded', 'canceled', 'failed']);

const env = process.env;
const SUPABASE_URL = String(env.SUPABASE_URL || env.BOLZOO_SUPABASE_URL || DEFAULT_SUPABASE_URL).replace(/\/$/, '');
const SUPABASE_SERVICE_KEY = String(env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SECRET_KEY || env.BOLZOO_SUPABASE_SERVICE_ROLE_KEY || '');
const WIRE_API_BASE = String(env.WIRE_API_BASE || 'https://api.wire.mn').replace(/\/$/, '');
const WIRE_API_KEY = String(env.WIRE_API_KEY || '');
const WIRE_WEBHOOK_SECRET = String(env.WIRE_WEBHOOK_SECRET || '');
const PRICE_MNT = Number(env.PRICE_MNT || 9900);
const ALLOW_MOCK_PAYMENT = env.ALLOW_MOCK_PAYMENT === '1';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Prefer,apikey,Authorization'
};

function sendJSON(res, status, payload) {
  res.statusCode = status;
  Object.keys(CORS).forEach((key) => res.setHeader(key, CORS[key]));
  if (status === 204) return res.end();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function handleOptions(req, res) {
  if (req.method !== 'OPTIONS') return false;
  sendJSON(res, 204);
  return true;
}

function configMissing(opts) {
  const requireWire = !opts || opts.wire !== false;
  const missing = [];
  if (!SUPABASE_URL) missing.push('SUPABASE_URL');
  if (!SUPABASE_SERVICE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY эсвэл SUPABASE_SECRET_KEY');
  if (requireWire && !WIRE_API_KEY) missing.push('WIRE_API_KEY');
  return missing;
}

function sendConfigError(res, missing) {
  return sendJSON(res, 503, {
    error: 'QPay төлбөрийн backend тохиргоо дутуу байна.',
    user_error: 'QPay төлбөр түр идэвхгүй байна. Админ тохиргоог шалгаад дахин оролдоно уу.',
    missing
  });
}

async function readBody(req) {
  let body = '';
  for await (const chunk of req) body += chunk;
  return body;
}

async function readJSON(req) {
  const body = await readBody(req);
  if (!body) return {};
  try {
    return JSON.parse(body);
  } catch (_) {
    const err = new Error('Invalid JSON');
    err.status = 400;
    throw err;
  }
}

function genCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const buf = crypto.randomBytes(6);
  let out = 'LOV-';
  for (let i = 0; i < buf.length; i++) out += chars[buf[i] % chars.length];
  return out;
}

async function supabaseFetch(method, path, body, prefer) {
  const headers = {
    apikey: SUPABASE_SERVICE_KEY,
    Authorization: 'Bearer ' + SUPABASE_SERVICE_KEY,
    'Content-Type': 'application/json'
  };
  if (prefer) headers.Prefer = prefer;
  const opts = { method, headers };
  if (body != null) opts.body = JSON.stringify(body);

  const response = await fetch(SUPABASE_URL + '/rest/v1' + path, opts);
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = { raw: text }; }
  if (!response.ok) {
    const err = new Error((data && (data.message || data.error)) || ('Supabase ' + response.status));
    err.status = response.status;
    err.data = data;
    throw err;
  }
  return data;
}

async function wireAPI(method, apiPath, body, idempotencyKey) {
  const headers = {
    Authorization: 'Bearer ' + WIRE_API_KEY,
    'Content-Type': 'application/json'
  };
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  const opts = { method, headers };
  if (body != null) opts.body = JSON.stringify(body);

  const response = await fetch(WIRE_API_BASE + apiPath, opts);
  const text = await response.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch (_) { data = { raw: text }; }
  if (!response.ok) {
    const err = new Error((data.error && data.error.message) || data.message || ('Wire ' + response.status));
    err.status = response.status;
    err.data = data;
    throw err;
  }
  return data;
}

function verifyWireSignature(payload, sigHeader, secret) {
  if (!sigHeader || !secret) return false;
  const parts = {};
  sigHeader.split(',').forEach((pair) => {
    const idx = pair.indexOf('=');
    if (idx > -1) parts[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
  });
  if (!parts.t || !parts.v1) return false;
  const expected = crypto.createHmac('sha256', secret).update(parts.t + '.' + payload).digest('hex');
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(parts.v1, 'hex');
  if (a.length !== b.length) return false;
  try { return crypto.timingSafeEqual(a, b); } catch (_) { return false; }
}

function paymentSelect() {
  return 'id,status,amount,currency,provider,provider_intent_id,client_secret,next_action,code,email,created_at,updated_at,expires_at';
}

async function upsertPayment(row) {
  const rows = await supabaseFetch(
    'POST',
    '/payments?on_conflict=id&select=' + paymentSelect(),
    row,
    'resolution=merge-duplicates,return=representation'
  );
  return rows && rows[0] ? rows[0] : row;
}

async function getPayment(id) {
  const rows = await supabaseFetch('GET', '/payments?id=eq.' + encodeURIComponent(id) + '&select=' + paymentSelect() + '&limit=1');
  return rows && rows[0] ? rows[0] : null;
}

async function updatePayment(id, patch) {
  const rows = await supabaseFetch(
    'PATCH',
    '/payments?id=eq.' + encodeURIComponent(id) + '&select=' + paymentSelect(),
    Object.assign({}, patch, { updated_at: new Date().toISOString() }),
    'return=representation'
  );
  return rows && rows[0] ? rows[0] : null;
}

async function ensureAccessCode(paymentId, mock) {
  const existing = await supabaseFetch(
    'GET',
    '/access_codes?payment_id=eq.' + encodeURIComponent(paymentId) + '&select=code&limit=1'
  );
  if (existing && existing[0] && existing[0].code) return existing[0].code;

  for (let i = 0; i < 8; i++) {
    const code = genCode();
    try {
      const rows = await supabaseFetch(
        'POST',
        '/access_codes?select=code',
        {
          code,
          used: false,
          used_at: null,
          used_for_invite_id: null,
          note: (mock ? 'self-serve MOCK ' : 'self-serve ') + paymentId,
          source: mock ? 'self_service_mock' : 'self_service',
          payment_id: paymentId
        },
        'return=representation'
      );
      await updatePayment(paymentId, { code });
      return rows && rows[0] ? rows[0].code : code;
    } catch (e) {
      if (e.status === 409) continue;
      throw e;
    }
  }
  throw new Error('Access code collision retry exceeded');
}

function paymentPayload(row) {
  return {
    intent_id: row.id,
    status: row.status,
    code: row.status === 'succeeded' ? row.code || null : null,
    amount: row.amount,
    next_action: row.next_action || null,
    expires_at: row.expires_at || null,
    mode: row.provider === 'mock' ? 'mock' : 'live'
  };
}

function isFinal(status) {
  return FINAL_STATUSES.has(status);
}

module.exports = {
  ALLOW_MOCK_PAYMENT,
  PRICE_MNT,
  WIRE_API_KEY,
  WIRE_WEBHOOK_SECRET,
  configMissing,
  crypto,
  ensureAccessCode,
  getPayment,
  handleOptions,
  isFinal,
  paymentPayload,
  readBody,
  readJSON,
  sendConfigError,
  sendJSON,
  updatePayment,
  upsertPayment,
  verifyWireSignature,
  wireAPI
};
