'use strict';

// Private, aggregate-only operations reader. Deliberately independent of the
// payment helper: that helper has a production URL fallback and permissive CORS.
const { createHash, timingSafeEqual } = require('node:crypto');
const MAX_PERIOD_MS = 31 * 86400000;
const MAX_RESPONSE_BYTES = 16384;
const TOKEN = /^[A-Za-z0-9_-]{32,256}$/;

function parseInstant(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return null;
  const [, y, m, d, h, min, sec, , zone] = match;
  const year = Number(y), month = Number(m), day = Number(d);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > days[month - 1] ||
      Number(h) > 23 || Number(min) > 59 || Number(sec) > 59) return null;
  if (zone !== 'Z') {
    const hours = Number(zone.slice(1, 3)), minutes = Number(zone.slice(4, 6));
    if (hours > 14 || minutes > 59 || (hours === 14 && minutes !== 0)) return null;
  }
  const result = Date.parse(value);
  return Number.isFinite(result) ? result : null;
}

function configuration(env) {
  const token = env.MOCH_LEARNING_TOKEN;
  const environment = env.MOCH_LEARNING_ENVIRONMENT;
  const origin = env.SUPABASE_URL || env.BOLZOO_SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SECRET_KEY || env.BOLZOO_SUPABASE_SERVICE_ROLE_KEY;
  if (typeof token !== 'string' || !TOKEN.test(token) ||
      !['production', 'test', 'demo'].includes(environment) ||
      typeof origin !== 'string' || typeof key !== 'string' || !key.trim()) return null;
  // A copied production variable must not turn a known preview/development
  // deployment into production evidence. On non-Vercel hosts the explicit
  // MOCH_LEARNING_ENVIRONMENT value is the operator's authoritative setting.
  if (environment === 'production' && (
    (env.VERCEL_ENV && env.VERCEL_ENV !== 'production') ||
    (env.NODE_ENV && env.NODE_ENV !== 'production')
  )) return null;
  try {
    const url = new URL(origin);
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        (url.pathname !== '/' && url.pathname !== '') || url.search || url.hash) return null;
    // Only server configuration chooses this destination; callers cannot supply
    // a database URL. No existing hard-coded production URL is inherited.
    return { token, environment, origin: url.origin, key };
  } catch (_) { return null; }
}

function authorized(header, token) {
  if (typeof header !== 'string') return false;
  const match = /^Bearer ([A-Za-z0-9_-]{32,256})$/.exec(header);
  if (!match) return false;
  // Fixed-size hashes allow timingSafeEqual even for unequal token lengths.
  const digest = value => createHash('sha256').update(value, 'utf8').digest();
  return timingSafeEqual(digest(match[1]), digest(token));
}

async function boundedJSON(response) {
  if (!response.ok || !response.body || !/application\/json\b/i.test(response.headers.get('content-type') || '')) {
    if (response.body) await response.body.cancel().catch(() => {});
    throw new Error('Unavailable aggregate');
  }
  const reader = response.body.getReader(), chunks = [];
  let length = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > MAX_RESPONSE_BYTES) throw new Error('Unavailable aggregate');
      chunks.push(Buffer.from(part.value));
    }
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function validateAggregate(value, period, now) {
  const keys = ['read_at', 'measurement_available', 'recorded_count', 'recorded_amount_mnt'];
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== keys.length || Object.keys(value).some(key => !keys.includes(key))) {
    throw new Error('Unavailable aggregate');
  }
  const readAt = parseInstant(value.read_at);
  // The RPC supplies its database-server timestamp, not a caller's timestamp.
  // Refuse cached, future-dated, or inconsistent responses; clock disagreement
  // means unavailable rather than manufacturing a current read timestamp.
  if (readAt === null || readAt < period.to || readAt > now || now - readAt > 300000 ||
      typeof value.measurement_available !== 'boolean') throw new Error('Unavailable aggregate');
  if (!value.measurement_available) {
    if (value.recorded_count !== null || value.recorded_amount_mnt !== null) throw new Error('Unavailable aggregate');
    return null;
  }
  for (const key of ['recorded_count', 'recorded_amount_mnt']) {
    if (!Number.isSafeInteger(value[key]) || value[key] < 0) throw new Error('Unavailable aggregate');
  }
  if (value.recorded_count === 0 && value.recorded_amount_mnt !== 0) throw new Error('Unavailable aggregate');
  return { readAt: new Date(readAt).toISOString(), count: value.recorded_count, amount: value.recorded_amount_mnt };
}

function send(res, status, value) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'private, no-store, max-age=0');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  return res.end(JSON.stringify(value));
}

function createLearningOverviewHandler({ env = process.env, fetch: request = globalThis.fetch, now = Date.now } = {}) {
  return async function learningOverview(req, res) {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return send(res, 405, { error: 'method_not_allowed' });
    }
    const config = configuration(env);
    if (!config) return send(res, 503, { error: 'measurement_unavailable' });
    if (!authorized(req.headers.authorization, config.token)) {
      res.setHeader('WWW-Authenticate', 'Bearer');
      return send(res, 401, { error: 'unauthorized' });
    }
    let url;
    try { url = new URL(req.url, 'https://local.invalid'); }
    catch (_) { return send(res, 400, { error: 'invalid_period' }); }
    if (url.pathname !== '/api/learning-overview') return send(res, 404, { error: 'not_found' });
    const params = url.searchParams;
    if ([...params.keys()].some(key => !['from', 'to'].includes(key)) ||
        params.getAll('from').length !== 1 || params.getAll('to').length !== 1) {
      return send(res, 400, { error: 'invalid_period' });
    }
    const from = parseInstant(params.get('from')), to = parseInstant(params.get('to'));
    const requestTime = now();
    if (from === null || to === null || from >= to || to > requestTime || to - from > MAX_PERIOD_MS) {
      return send(res, 400, { error: 'invalid_period' });
    }
    const period = { from: new Date(from).toISOString(), to: new Date(to).toISOString() };
    try {
      const rpc = new URL(config.origin + '/rest/v1/rpc/moch_learning_overview');
      rpc.searchParams.set('p_from', period.from);
      rpc.searchParams.set('p_to', period.to);
      const response = await request(rpc.href, {
        method: 'GET', redirect: 'error', cache: 'no-store',
        signal: AbortSignal.timeout(8000),
        headers: { Accept: 'application/json', apikey: config.key, Authorization: 'Bearer ' + config.key }
      });
      const aggregate = validateAggregate(await boundedJSON(response), { from, to }, now());
      if (!aggregate) return send(res, 503, { error: 'measurement_unavailable' });
      return send(res, 200, {
        schemaVersion: 1,
        source: { product: 'bolzoo', environment: config.environment, readAt: aggregate.readAt, period },
        money: { recordedCount: aggregate.count, recordedAmountMnt: aggregate.amount,
          providerVerifiedAmountMnt: null, verifiedRefundAmountMnt: null, variableCostMnt: null },
        fulfillment: { paidWithoutLinkCount: null },
        funnel: null
      });
    } catch (_) {
      // Never emit SQL errors, upstream bodies, headers, credentials, or rows.
      return send(res, 503, { error: 'measurement_unavailable' });
    }
  };
}

module.exports = { createLearningOverviewHandler };
