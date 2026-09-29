'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const http = require('node:http');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const api = require('../lib/payment-api');
const root = path.join(__dirname, '..');
const config = require('../vercel.json');
const secret = 'whsec_router_test';
const clone = value => value && structuredClone(value);

function load(relative, overrides) {
  const filename = path.join(root, relative), module = { exports: {} };
  const nativeRequire = createRequire(filename);
  vm.runInNewContext(fs.readFileSync(filename, 'utf8'), {
    module, exports: module.exports, URL, process,
    require: name => Object.hasOwn(overrides, name) ? overrides[name] : nativeRequire(name)
  }, { filename });
  return module.exports;
}

async function start(t, rewrite) {
  const payments = new Map(), intents = new Map(), events = new Set();
  const repo = {
    get: async id => clone(payments.get(id)),
    findByToken: async hash => clone([...payments.values()].find(row => row.checkout_token_hash === hash)),
    findByProvider: async id => clone([...payments.values()].find(row => row.provider_intent_id === id)),
    async insert(row) { if (!payments.has(row.id)) payments.set(row.id, clone(row)); return clone(payments.get(row.id)); },
    async bindProvider(id, providerId) { const row = payments.get(id); row.provider_intent_id ||= providerId; return clone(row); },
    async reconcile(id, remote) {
      const row = payments.get(id);
      row.status = remote.status; row.next_action = clone(remote.next_action);
      if (row.status === 'succeeded') row.code ||= 'LOV-ROUTER';
      return clone(row);
    },
    hasEvent: async id => events.has(id),
    async recordEvent(event) { events.add(event.id); }
  };
  async function wire(method, route, body) {
    let intent;
    if (route === '/v1/payment_intents') {
      intent = { id: 'pi_router_' + (intents.size + 1), amount: body.amount, currency: 'MNT', livemode: false, status: 'requires_payment_method' };
      intents.set(intent.id, intent);
    } else {
      intent = intents.get(route.split('/')[3]);
      assert.ok(intent);
      if (route.endsWith('/confirm')) { intent.status = 'requires_action'; intent.next_action = { qr: { image_url: 'https://example.test/qr.png' } }; }
      if (route.endsWith('/cancel')) intent.status = 'canceled';
    }
    return clone(intent);
  }
  const handlers = load('lib/payment-handlers.js', {
    './payment-api': { ...api, WIRE_API_KEY: 'sk_test_router', WIRE_WEBHOOK_SECRET: secret, configMissing: () => [], wireAPI: wire }
  });
  const router = load('api/payment.js', { '../lib/payment-handlers': handlers, '../lib/payment-repository': repo });
  const server = http.createServer((req, res) => {
    if (rewrite) {
      const source = new URL(req.url, 'http://localhost');
      const rule = config.rewrites.find(item => item.source === source.pathname);
      if (rule) {
        const destination = new URL(rule.destination, 'http://localhost');
        for (const [key, value] of source.searchParams) destination.searchParams.append(key, value);
        req.url = destination.pathname + destination.search;
      }
    }
    Promise.resolve(router(req, res)).catch(error => { res.statusCode = 500; res.end(String(error)); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const origin = 'http://127.0.0.1:' + server.address().port;
  async function request(route, options = {}) {
    const response = await fetch(origin + route, options);
    const text = await response.text();
    return { status: response.status, headers: response.headers, body: text && JSON.parse(text) };
  }
  return { request, payments, intents, events };
}
const checkoutOptions = token => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ checkout_token: token }) });

for (const rewrite of [false, true]) {
  test('payment router preserves checkout, token authorization and signed raw webhook through ' + (rewrite ? 'configured rewrites' : 'original URLs'), async t => {
    const f = await start(t, rewrite), token = Date.now() + '-' + crypto.randomBytes(32).toString('hex');
    assert.equal((await f.request('/api/checkout')).status, 405);
    assert.equal((await f.request('/api/checkout', { method: 'OPTIONS' })).status, 204);
    const checkout = await f.request('/api/checkout', checkoutOptions(token));
    assert.equal(checkout.status, 200); assert.equal(checkout.headers.get('cache-control'), 'no-store');
    const id = checkout.body.intent_id;
    assert.equal((await f.request('/api/payment-status?id=' + id)).status, 403);
    assert.equal((await f.request('/api/cancel-payment', { method: 'POST', body: JSON.stringify({ intent_id: id }) })).status, 403);
    const row = f.payments.get(id), remote = f.intents.get(row.provider_intent_id);
    remote.status = 'succeeded';
    const raw = '{ "id": "evt_router", "type": "payment_intent.succeeded", "data": { "id": "' + remote.id + '" } }\n';
    const timestamp = Math.floor(Date.now() / 1000);
    const digest = crypto.createHmac('sha256', secret).update(timestamp + '.' + raw).digest('hex');
    const signature = 't=' + timestamp + ',v1=' + digest;
    const signed = { method: 'POST', headers: { 'Content-Type': 'application/json', 'WirePayment-Signature': signature }, body: raw };
    assert.equal((await f.request('/api/wire-webhook', { ...signed, body: JSON.stringify(JSON.parse(raw)) })).status, 403);
    assert.equal((await f.request('/api/wire-webhook', signed)).status, 200);
    assert.ok(f.events.has('evt_router'));
    const paid = await f.request('/api/payment-status?id=' + id, { headers: { Authorization: 'Bearer ' + token } });
    assert.equal(paid.status, 200); assert.equal(paid.body.code, 'LOV-ROUTER');
    assert.equal((await f.request('/api/dev-mark-paid', { method: 'POST', body: JSON.stringify({ intent_id: id }) })).status, 403);

    const cancelToken = Date.now() + '-' + crypto.randomBytes(32).toString('hex');
    const pending = await f.request('/api/checkout', checkoutOptions(cancelToken));
    const cancelled = await f.request('/api/cancel-payment', { method: 'POST', headers: { Authorization: 'Bearer ' + cancelToken }, body: JSON.stringify({ intent_id: pending.body.intent_id }) });
    assert.equal(cancelled.status, 200); assert.equal(cancelled.body.status, 'canceled');
  });
}

test('direct payment router fails closed for missing, duplicate and unlisted operations; query cannot reroute an original endpoint', async t => {
  const f = await start(t, false);
  for (const route of ['/api/payment', '/api/payment?payment_route=simulate', '/api/payment?payment_route=constructor', '/api/payment?payment_route=__proto__', '/api/payment?payment_route=checkout&payment_route=wire-webhook', '/api/health?payment_route=checkout']) {
    assert.equal((await f.request(route)).status, 404, route);
  }
  assert.equal((await f.request('/api/payment?payment_route=checkout')).status, 405);
  assert.equal((await f.request('/api/dev-mark-paid?payment_route=checkout')).status, 403);
  assert.equal(f.payments.size, 0);
});

test('production package keeps ten API functions including the private learning reader and explicit legacy rewrites', () => {
  const ignored = new Set(fs.readFileSync(path.join(root, '.vercelignore'), 'utf8').split(/\r?\n/).filter(line => line && !line.startsWith('#')));
  const routes = ['checkout', 'payment-status', 'wire-webhook', 'cancel-payment', 'dev-mark-paid'];
  for (const route of routes) {
    assert.ok(fs.existsSync(path.join(root, 'api', route + '.js')), 'local wrapper remains');
    assert.ok(ignored.has('api/' + route + '.js'));
    assert.deepEqual(config.rewrites.find(rule => rule.source === '/api/' + route), { source: '/api/' + route, destination: '/api/payment?payment_route=' + route });
  }
  const deployed = fs.readdirSync(path.join(root, 'api')).filter(file => file.endsWith('.js') && !ignored.has('api/' + file));
  assert.equal(deployed.length, 10); assert.ok(deployed.includes('payment.js')); assert.ok(deployed.includes('health.js'));
  assert.ok(deployed.includes('learning-overview.js'));
  assert.equal(config.env.NODEJS_HELPERS, '0'); assert.equal(config.build.env.NODEJS_HELPERS, '0');
  assert.equal(config.rewrites.some(rule => rule.source.startsWith('/assets') || rule.source === '/api/health' || rule.source === '/api/:path*'), false);
  assert.deepEqual(config.rewrites.find(rule => rule.source === '/'), { source: '/', destination: '/create' });
});
