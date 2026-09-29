'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Readable } = require('node:stream');
const crypto = require('node:crypto');
const { createDatePlanHandler } = require('../lib/date-plan-handler');

const catalog = { get: id => id === 'coffee' ? { id, title: 'Coffee', steps: ['before', 'together', 'after'].map(id => ({ id, title: id })) } : null };
const owner = '38a2ef18-2b90-4300-9074-c15ce0ce5ba5';
const invite = { id: 'invite_demo_123', owner_token: owner, config: {} };
function makeHandler(options = {}) {
  const repo = { getInvite: async () => invite, getByInvite: async () => null, ...options.repo };
  return createDatePlanHandler({ repo, catalog, local: true, ...options });
}
async function call(handler, { method = 'POST', url = '/api/date-plan', headers = {}, body, chunks = [] } = {}) {
  const req = Readable.from(chunks);
  Object.assign(req, { method, url, headers: { host: 'localhost:8080', 'content-type': 'application/json', ...headers } });
  req.socket = { remoteAddress: '127.0.0.1' };
  if (body !== undefined) req.body = body;
  const result = { headers: {} };
  const res = { setHeader(key, value) { result.headers[key.toLowerCase()] = value; }, end(value) { result.status = this.statusCode; result.body = value ? JSON.parse(value) : null; } };
  await handler(req, res);
  return result;
}
const base = () => ({ action: 'create', invite_id: invite.id, request_id: crypto.randomUUID(), template_id: 'coffee', claim_token: crypto.randomBytes(32).toString('hex') });

test('date-plan API uses private no-store responses and never advertises cross-origin access', async () => {
  const handler = makeHandler();
  const absent = await call(handler, { method: 'GET', url: '/api/date-plan?invite_id=' + invite.id, headers: { authorization: 'Bearer ' + owner } });
  assert.equal(absent.status, 404);
  assert.equal(absent.body.code, 'plan_not_found');
  assert.equal(absent.headers['cache-control'], 'private, no-store');
  assert.equal(absent.headers['referrer-policy'], 'no-referrer');
  assert.equal(absent.headers['x-content-type-options'], 'nosniff');
  assert.equal(absent.headers['access-control-allow-origin'], undefined);
  const unauthenticated = await call(handler, { method: 'GET', url: '/api/date-plan?invite_id=' + invite.id });
  assert.equal(unauthenticated.status, 403);
  assert.equal(unauthenticated.body.code, 'forbidden');
});

test('same-origin browser requests are accepted; cross-origin and cross-site requests fail before persistence', async () => {
  let reads = 0;
  const handler = makeHandler({ repo: { async getInvite() { reads++; return invite; }, async getByInvite() { return null; } } });
  for (const headers of [
    { origin: 'https://attacker.example' }, { origin: 'null' }, { origin: 'http://localhost:8080.evil.test' },
    { origin: 'http://localhost:8080', 'sec-fetch-site': 'cross-site' }, { origin: 'http://user@localhost:8080' }
  ]) assert.equal((await call(handler, { headers, body: base() })).status, 403);
  assert.equal(reads, 0);
  const permitted = await call(handler, { method: 'GET', url: '/api/date-plan?invite_id=' + invite.id, headers: { origin: 'http://localhost:8080', authorization: 'Bearer ' + owner } });
  assert.equal(permitted.status, 404);
  assert.equal(reads, 1);
});

test('JSON content type, request size and parsing are checked for both streams and platform-parsed objects', async () => {
  const handler = makeHandler();
  assert.equal((await call(handler, { headers: { 'content-type': 'text/plain' }, body: base() })).status, 415);
  assert.equal((await call(handler, { body: '{broken' })).status, 400);
  assert.equal((await call(handler, { body: [] })).status, 400);
  assert.equal((await call(handler, { body: null })).status, 400);
  assert.equal((await call(handler, { body: { ...base(), title: 'x'.repeat(20000) } })).status, 413);
  assert.equal((await call(handler, { body: base(), headers: { 'content-length': '17000' } })).status, 413);
  assert.equal((await call(handler, { chunks: [Buffer.from('a'.repeat(9000)), Buffer.from('b'.repeat(9000))] })).status, 413);
  assert.equal((await call(handler, { chunks: [JSON.stringify(base())] })).status, 403);
});

test('database errors are sanitized even when their status looks like a client validation failure', async () => {
  for (const status of [400, 403, 409, 500]) {
    const handler = makeHandler({ repo: { async getInvite() { const error = new Error('service_key=secret private-note'); error.status = status; throw error; }, getByInvite: async () => null } });
    const result = await call(handler, { body: base(), headers: { authorization: 'Bearer ' + owner } });
    assert.equal(result.status, 503);
    assert.equal(result.body.code, 'unavailable');
    assert.equal(JSON.stringify(result).includes('secret'), false);
    assert.equal(JSON.stringify(result).includes('private-note'), false);
  }
});

test('authorization is never taken from URLs or request body fields, and unsupported methods cannot mutate', async () => {
  const handler = makeHandler();
  const query = await call(handler, { method: 'GET', url: '/api/date-plan?invite_id=' + invite.id + '&owner_token=' + owner });
  assert.equal(query.status, 400);
  const field = await call(handler, { body: { ...base(), owner_token: owner } });
  assert.equal(field.status, 400);
  const patch = await call(handler, { method: 'PATCH', body: base() });
  assert.equal(patch.status, 405);
  assert.equal(patch.headers.allow, 'GET, POST, OPTIONS');
  const options = await call(handler, { method: 'OPTIONS', headers: { origin: 'http://localhost:8080' } });
  assert.equal(options.status, 204);
  assert.equal(options.headers['access-control-allow-origin'], undefined);
});

test('abusive request bursts are bounded and recover after the rate window', async () => {
  let now = 100000;
  const handler = makeHandler({ now: () => now, rateLimit: 2, rateWindowMs: 60000 });
  const request = { method: 'GET', url: '/api/date-plan?invite_id=' + invite.id };
  assert.equal((await call(handler, request)).status, 403);
  assert.equal((await call(handler, request)).status, 403);
  const blocked = await call(handler, request);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.headers['retry-after'], '60');
  now += 60000;
  assert.equal((await call(handler, request)).status, 403);
});
