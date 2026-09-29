'use strict';

const { configMissing, readBody } = require('./payment-api');
const { createDatePlanService } = require('./date-plan-service');

const BODY_LIMIT = 16 * 1024;
function error(status, code, message) { const value = new Error(message); value.status = status; value.code = code; value.publicMessage = true; return value; }
function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (status === 204) return res.end();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(body));
}
function checkOrigin(req) {
  if (req.headers['sec-fetch-site'] === 'cross-site') throw error(403, 'forbidden', 'Энэ хүсэлтийн эх сурвалж зөвшөөрөгдөөгүй байна.');
  const origin = req.headers.origin;
  if (!origin) return; // Capability auth permits direct clients without cookie authority.
  let url;
  try { url = new URL(origin); } catch (_) { throw error(403, 'forbidden', 'Энэ хүсэлтийн эх сурвалж зөвшөөрөгдөөгүй байна.'); }
  const host = String(req.headers.host || '').toLowerCase();
  const local = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host);
  if (url.origin !== origin || url.host.toLowerCase() !== host || (url.protocol !== 'https:' && !(local && url.protocol === 'http:'))) {
    throw error(403, 'forbidden', 'Энэ хүсэлтийн эх сурвалж зөвшөөрөгдөөгүй байна.');
  }
}
async function readJSON(req) {
  if (!/^application\/json(?:\s*;|$)/i.test(String(req.headers['content-type'] || ''))) throw error(415, 'invalid_content_type', 'JSON хэлбэрээр мэдээлэл илгээнэ үү.');
  const length = Number(req.headers['content-length']);
  if (Number.isFinite(length) && length > BODY_LIMIT) throw error(413, 'body_too_large', 'Илгээсэн мэдээлэл хэт урт байна.');
  let raw;
  if (req.body !== undefined && req.body !== null) {
    raw = Buffer.isBuffer(req.body) ? req.body.toString('utf8') : typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
  } else {
    try { raw = await readBody(req, BODY_LIMIT); }
    catch (cause) {
      if (cause.status === 413) throw error(413, 'body_too_large', 'Илгээсэн мэдээлэл хэт урт байна.');
      throw cause;
    }
  }
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > BODY_LIMIT) throw error(413, 'body_too_large', 'Илгээсэн мэдээлэл хэт урт байна.');
  try { return JSON.parse(raw); } catch (_) { throw error(400, 'invalid_json', 'Илгээсэн мэдээлэл буруу байна.'); }
}

function createDatePlanHandler({ repo, local = false, now = Date.now, rateLimit = 120, rateWindowMs = 60000, catalog } = {}) {
  const service = createDatePlanService({ repo, now, catalog });
  // A bounded per-process abuse guard. Persistent authorization and atomic writes
  // remain in the service/database; hosted edge rate limiting can supplement it.
  const buckets = new Map();
  function checkRate(req) {
    const ip = process.env.VERCEL ? String(req.headers['x-forwarded-for'] || req.socket && req.socket.remoteAddress || '').split(',')[0].trim() : req.socket && req.socket.remoteAddress || 'unknown';
    const timestamp = now();
    if (buckets.size >= 10000) for (const [key, bucket] of buckets) if (bucket.until <= timestamp) buckets.delete(key);
    const previous = buckets.get(ip);
    if (!previous && buckets.size >= 10000) throw error(429, 'rate_limited', 'Түр хүлээгээд дахин оролдоно уу.');
    const bucket = previous && previous.until > timestamp ? previous : { count: 0, until: timestamp + rateWindowMs };
    bucket.count++;
    buckets.set(ip, bucket);
    if (bucket.count > rateLimit) throw error(429, 'rate_limited', 'Хэт олон хүсэлт илгээсэн байна. Түр хүлээгээд дахин оролдоно уу.');
  }
  return async function datePlanHandler(req, res) {
    try {
      checkOrigin(req);
      checkRate(req);
      if (req.method === 'OPTIONS') {
        res.setHeader('Allow', 'GET, POST, OPTIONS');
        return send(res, 204);
      }
      if (!['GET', 'POST'].includes(req.method)) {
        res.setHeader('Allow', 'GET, POST, OPTIONS');
        throw error(405, 'method_not_allowed', 'GET эсвэл POST хүсэлт ашиглана уу.');
      }
      if (!local && configMissing({ wire: false }).length) throw error(503, 'unavailable', 'Болзооны үйлчилгээ түр боломжгүй байна.');
      const authorization = String(req.headers.authorization || '');
      const match = /^Bearer ([A-Za-z0-9_-]{16,128})$/i.exec(authorization);
      const token = match ? match[1] : '';
      let result;
      if (req.method === 'GET') {
        const url = new URL(req.url, 'http://localhost');
        if ([...url.searchParams.keys()].some(key => !['invite_id', 'id'].includes(key))) throw error(400, 'invalid_request', 'Хүсэлтийн мэдээлэл буруу байна.');
        result = await service.get({ invite_id: url.searchParams.get('invite_id'), id: url.searchParams.get('id') }, token);
      } else result = await service.execute(await readJSON(req), token);
      return send(res, 200, result);
    } catch (cause) {
      // Never serialize upstream database errors, documents, or capability tokens.
      const status = cause.publicMessage && [400, 403, 404, 405, 409, 410, 413, 415, 429].includes(cause.status) ? cause.status : 503;
      const message = status < 500 ? cause.message : 'Болзооны үйлчилгээтэй холбогдож чадсангүй. Түр хүлээгээд дахин оролдоно уу.';
      if (status === 429) res.setHeader('Retry-After', String(Math.ceil(rateWindowMs / 1000)));
      return send(res, status, { error: message, user_error: message, code: status < 500 ? cause.code || 'invalid_request' : 'unavailable' });
    }
  };
}

module.exports = { createDatePlanHandler };
