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
const PAYMENT_DESCRIPTION = (String(env.PAYMENT_DESCRIPTION || env.PAYMENT_MEMO || 'Bolzoo invite access').trim().slice(0, 80) || 'Bolzoo invite access');

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
  const requireWebhook = !!(opts && opts.webhook);
  const missing = [];
  if (!SUPABASE_URL) missing.push('SUPABASE_URL');
  if (!SUPABASE_SERVICE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY эсвэл SUPABASE_SECRET_KEY');
  if (requireWire && !WIRE_API_KEY) missing.push('WIRE_API_KEY');
  if (requireWebhook && !WIRE_WEBHOOK_SECRET) missing.push('WIRE_WEBHOOK_SECRET');
  return missing;
}

function sendConfigError(res, missing) {
  return sendJSON(res, 503, {
    error: 'QPay төлбөрийн backend тохиргоо дутуу байна.',
    user_error: 'QPay төлбөр түр идэвхгүй байна. Админ тохиргоог шалгаад дахин оролдоно уу.',
    missing
  });
}

async function readBody(req, maxBytes) {
  const limit = Number(maxBytes || 64 * 1024);
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) {
      const err = new Error('Request body too large');
      err.status = 413;
      throw err;
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
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

function paymentMetadata() {
  return {
    product: 'bolzoo_access_code',
    tier: 'single',
    description: PAYMENT_DESCRIPTION,
    invoice_description: PAYMENT_DESCRIPTION,
    transaction_description: PAYMENT_DESCRIPTION
  };
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

function verifyWireSignature(payload, sigHeader, secret, toleranceSeconds, nowSeconds) {
  if (!sigHeader || !secret) return false;
  const parts = { v1: [] };
  sigHeader.split(',').forEach((pair) => {
    const idx = pair.indexOf('=');
    if (idx < 0) return;
    const key = pair.slice(0, idx).trim();
    const value = pair.slice(idx + 1).trim();
    if (key === 'v1') parts.v1.push(value);
    else parts[key] = value;
  });
  const timestamp = Number(parts.t);
  const tolerance = Number(toleranceSeconds == null ? 300 : toleranceSeconds);
  const now = Number(nowSeconds == null ? Math.floor(Date.now() / 1000) : nowSeconds);
  if (!Number.isFinite(timestamp) || !parts.v1.length) return false;
  if (tolerance >= 0 && Math.abs(now - timestamp) > tolerance) return false;

  const expected = crypto.createHmac('sha256', secret).update(parts.t + '.' + payload).digest('hex');
  const a = Buffer.from(expected, 'hex');
  return parts.v1.some((signature) => {
    if (!/^[0-9a-f]+$/i.test(signature)) return false;
    const b = Buffer.from(signature, 'hex');
    if (a.length !== b.length) return false;
    try { return crypto.timingSafeEqual(a, b); } catch (_) { return false; }
  });
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
  async function findExisting() {
    const rows = await supabaseFetch(
      'GET',
      '/access_codes?payment_id=eq.' + encodeURIComponent(paymentId) + '&select=code&limit=1'
    );
    return rows && rows[0] && rows[0].code ? rows[0].code : null;
  }

  const existing = await findExisting();
  if (existing) return existing;

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
      return rows && rows[0] ? rows[0].code : code;
    } catch (e) {
      if (e.status === 409) {
        const concurrent = await findExisting();
        if (concurrent) return concurrent;
        continue;
      }
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
    payment_description: PAYMENT_DESCRIPTION,
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
  PAYMENT_DESCRIPTION,
  PRICE_MNT,
  WIRE_API_KEY,
  WIRE_WEBHOOK_SECRET,
  configMissing,
  crypto,
  ensureAccessCode,
  getPayment,
  handleOptions,
  isFinal,
  paymentMetadata,
  paymentPayload,
  readBody,
  readJSON,
  sendConfigError,
  sendJSON,
  supabaseFetch,
  updatePayment,
  upsertPayment,
  verifyWireSignature,
  wireAPI
};
