'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createLearningOverviewHandler } = require('../lib/learning-reader');

const token = 'test_operations_only_'.padEnd(43, 'x');
const now = Date.parse('2026-09-29T09:00:00Z');
const env = { MOCH_LEARNING_TOKEN: token, MOCH_LEARNING_ENVIRONMENT: 'production',
  SUPABASE_URL: 'https://project.example.test', SUPABASE_SERVICE_ROLE_KEY: 'test_server_key' };
const period = { from: '2026-09-01T00:00:00Z', to: '2026-09-29T00:00:00Z' };
const route = values => '/api/learning-overview?' + new URLSearchParams(values || period);
const aggregate = patch => ({ read_at: '2026-09-29T09:00:00.000Z', measurement_available: true,
  recorded_count: 2, recorded_amount_mnt: 18923, ...patch });

async function invoke({ url = route(), method = 'GET', headers = { authorization: 'Bearer ' + token },
  settings = env, fetch: request = async () => Response.json(aggregate()), clock = () => now } = {}) {
  const response = { headers: {}, setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    end(body) { this.raw = body; this.body = JSON.parse(body); } };
  await createLearningOverviewHandler({ env: settings, fetch: request, now: clock })({ url, method, headers }, response);
  return response;
}

test('dedicated configuration fails closed without network and never inherits a production origin or environment', async () => {
  const configurations = [{}, ...Object.keys(env).map(key => ({ ...env, [key]: '' })),
    { ...env, MOCH_LEARNING_TOKEN: 'short' }, { ...env, MOCH_LEARNING_ENVIRONMENT: 'staging' },
    { ...env, MOCH_LEARNING_ENVIRONMENT: '', VERCEL_ENV: 'production' },
    { ...env, VERCEL_ENV: 'preview' }, { ...env, VERCEL_ENV: 'development' },
    { ...env, NODE_ENV: 'test' }, { ...env, NODE_ENV: 'development' },
    ...['http://project.example.test', 'https://user:password@project.example.test',
      'https://project.example.test/path', 'https://project.example.test?private=true',
      'https://project.example.test:444'].map(SUPABASE_URL => ({ ...env, SUPABASE_URL }))];
  for (const settings of configurations) {
    const res = await invoke({ settings, fetch: () => { throw new Error('Must not access database'); } });
    assert.equal(res.statusCode, 503);
    assert.deepEqual(res.body, { error: 'measurement_unavailable' });
    assert.equal(res.headers['cache-control'], 'private, no-store, max-age=0');
    assert.equal(res.headers['access-control-allow-origin'], undefined);
    assert.doesNotMatch(res.raw, /test_server_key|project\.example|SUPABASE/);
  }
});

test('only the exact server bearer token permits database access', async () => {
  for (const authorization of [undefined, '', 'Bearer short', 'Bearer ' + 'a'.repeat(32),
    'Bearer ' + token + 'x', 'bearer ' + token, 'Bearer ' + token + ', Bearer ' + token, ['Bearer ' + token]]) {
    let calls = 0;
    const res = await invoke({ headers: { authorization }, fetch: async () => { calls++; return Response.json(aggregate()); } });
    assert.equal(res.statusCode, 401);
    assert.equal(calls, 0);
    assert.deepEqual(res.body, { error: 'unauthorized' });
    assert.equal(res.headers['www-authenticate'], 'Bearer');
  }
});

test('writes and browser preflight are rejected without CORS or database calls', async () => {
  for (const method of ['POST', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD']) {
    const res = await invoke({ method, fetch: () => { throw new Error('Must not read'); } });
    assert.equal(res.statusCode, 405);
    assert.equal(res.headers.allow, 'GET');
    assert.equal(res.headers['cache-control'], 'private, no-store, max-age=0');
    assert.equal(res.headers['access-control-allow-origin'], undefined);
  }
});

test('validated aggregate maps to the analyzer contract, with unknown metrics preserved', async () => {
  let calls = 0;
  const res = await invoke({ fetch: async (url, options) => {
    calls++;
    const target = new URL(url);
    assert.equal(target.origin, env.SUPABASE_URL);
    assert.equal(target.pathname, '/rest/v1/rpc/moch_learning_overview');
    assert.deepEqual(Object.fromEntries(target.searchParams), {
      p_from: '2026-09-01T00:00:00.000Z', p_to: '2026-09-29T00:00:00.000Z'
    });
    assert.equal(options.method, 'GET');
    assert.equal(options.body, undefined);
    assert.equal(options.redirect, 'error');
    assert.equal(options.cache, 'no-store');
    assert.equal(options.headers.Authorization, 'Bearer test_server_key');
    assert.equal(options.headers.apikey, 'test_server_key');
    assert.equal(options.signal.aborted, false);
    return Response.json(aggregate());
  } });
  assert.equal(calls, 1);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, {
    schemaVersion: 1,
    source: { product: 'bolzoo', environment: 'production', readAt: '2026-09-29T09:00:00.000Z',
      period: { from: '2026-09-01T00:00:00.000Z', to: '2026-09-29T00:00:00.000Z' } },
    money: { recordedCount: 2, recordedAmountMnt: 18923, providerVerifiedAmountMnt: null,
      verifiedRefundAmountMnt: null, variableCostMnt: null },
    fulfillment: { paidWithoutLinkCount: null }, funnel: null
  });
  assert.equal(res.headers['referrer-policy'], 'no-referrer');
  assert.equal(res.headers['x-content-type-options'], 'nosniff');
  assert.equal(res.headers.pragma, 'no-cache');
});

test('environment is server-owned and UTC offsets normalize to identical instants', async () => {
  const res = await invoke({ settings: { ...env, MOCH_LEARNING_ENVIRONMENT: 'test', VERCEL_ENV: 'preview' },
    url: route({ from: '2026-09-01T08:00:00+08:00', to: '2026-09-29T08:00:00+08:00' }) });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.source.environment, 'test');
  assert.equal(res.body.source.period.from, '2026-09-01T00:00:00.000Z');
  assert.equal((await invoke({ url: route({ ...period, environment: 'production' }) })).statusCode, 400);
  assert.equal((await invoke({ settings: { ...env, VERCEL_ENV: 'production', NODE_ENV: 'production' } })).statusCode, 200);
});

test('range validation rejects ambiguous, malformed, future and oversized windows before reading', async () => {
  const invalid = [
    '/api/learning-overview', route({ from: period.from }),
    route() + '&from=2026-09-02T00:00:00Z', route() + '&to=2026-09-20T00:00:00Z',
    route() + '&select=*', route() + '&readAt=2026-10-01T00:00:00Z',
    ...['2026-02-29T00:00:00Z', '2026-04-31T00:00:00Z', '2026-00-01T00:00:00Z',
      '2026-09-01', '2026-09-01T00:00:00', '2026-09-01T24:00:00Z',
      '2026-09-01T00:00:00+14:01', '2026-09-01T00:00:00+08:60', '0000-09-01T00:00:00Z']
      .map(from => route({ ...period, from })),
    route({ from: period.to, to: period.from }), route({ from: period.to, to: period.to }),
    route({ ...period, to: '2026-09-29T09:00:00.001Z' }),
    route({ from: '2026-08-28T23:59:59.999Z', to: period.to })
  ];
  for (const url of invalid) {
    let calls = 0;
    const res = await invoke({ url, fetch: async () => { calls++; return Response.json(aggregate()); } });
    assert.equal(res.statusCode, 400, url);
    assert.equal(calls, 0);
  }
  assert.equal((await invoke({ url: route({ from: '2026-08-29T00:00:00Z', to: period.to }) })).statusCode, 200);
  assert.equal((await invoke({ url: '/api/other?' + new URLSearchParams(period) })).statusCode, 404);
});

test('unavailable coverage never becomes a measured zero or a partial successful report', async () => {
  const res = await invoke({ fetch: async () => Response.json(aggregate({ measurement_available: false,
    recorded_count: null, recorded_amount_mnt: null })) });
  assert.equal(res.statusCode, 503);
  assert.deepEqual(res.body, { error: 'measurement_unavailable' });
  const empty = await invoke({ fetch: async () => Response.json(aggregate({ recorded_count: 0, recorded_amount_mnt: 0 })) });
  assert.equal(empty.statusCode, 200);
  assert.equal(empty.body.money.recordedCount, 0);
  assert.equal(empty.body.money.recordedAmountMnt, 0);
});

test('unsafe or malformed aggregates, old responses, and upstream errors remain private', async () => {
  const bad = [[], null, { ...aggregate(), private_customer: 'private@example.test' },
    aggregate({ recorded_count: '2' }), aggregate({ recorded_amount_mnt: -1 }),
    aggregate({ recorded_amount_mnt: Number.MAX_SAFE_INTEGER + 1 }), aggregate({ recorded_count: 0 }),
    aggregate({ measurement_available: false }), aggregate({ measurement_available: 'true' }),
    aggregate({ read_at: '2026-09-29T09:00:00.001Z' }), aggregate({ read_at: '2026-09-29T08:54:59.999Z' }),
    aggregate({ read_at: '2026-02-30T00:00:00Z' }), aggregate({ read_at: '2026-08-01T00:00:00Z' })];
  const responses = [...bad.map(value => () => Response.json(value)),
    () => new Response('private@example.test', { status: 500 }),
    () => new Response('not JSON private@example.test', { headers: { 'Content-Type': 'application/json' } }),
    () => Response.json({ padding: 'private@example.test'.repeat(2000) }),
    () => new Response('{}', { headers: { 'Content-Type': 'text/html' } }),
    () => { throw new Error('SQL password=private@example.test'); }];
  for (const response of responses) {
    const res = await invoke({ fetch: async () => response() });
    assert.equal(res.statusCode, 503);
    assert.deepEqual(res.body, { error: 'measurement_unavailable' });
    assert.doesNotMatch(res.raw, /private|password|SQL/);
  }
});
