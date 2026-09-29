'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const campaign = require('../assets/campaign');

test('real server persists a promotion quote before a lost provider response, survives restart, and prices new checkouts at the boundary', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'bolzoo-campaign-http-'));
  const clockFile = path.join(directory, 'test-clock');
  const end = Date.parse(campaign.PROMOTION_END_AT);
  fs.writeFileSync(clockFile, String(end - 1));
  const intents = new Map(), requests = new Map();
  let loseFirstCreate = true, sequence = 0, child, origin;
  const gateway = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString() || '{}');
    let intent;
    if (req.method === 'POST' && req.url === '/v1/payment_intents') {
      const key = req.headers['idempotency-key'];
      if (requests.has(key)) {
        assert.deepEqual(body, requests.get(key).body);
        intent = intents.get(requests.get(key).id);
      } else {
        intent = { id: 'pi_campaign_' + ++sequence, amount: body.amount, currency: body.currency, livemode: false, status: 'requires_payment_method' };
        requests.set(key, { body, id: intent.id }); intents.set(intent.id, intent);
      }
      if (loseFirstCreate) { loseFirstCreate = false; req.socket.destroy(); return; }
    } else {
      intent = intents.get(req.url.split('/')[3]);
      assert.ok(intent, 'all subsequent provider calls must use the bound provider id');
      if (req.url.endsWith('/confirm')) { intent.status = 'requires_action'; intent.next_action = { qr: { image_url: 'https://example.test/qr.png' } }; }
    }
    res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(intent));
  });
  await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
  async function stop() {
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    const stopped = new Promise(resolve => child.once('exit', resolve)); child.kill(); await stopped;
  }
  t.after(async () => { await stop(); await new Promise(resolve => gateway.close(resolve)); fs.rmSync(directory, { recursive: true, force: true }); });
  async function boot() {
    // Test-only clock injection lives outside production code and is controlled
    // by this process, so browser timestamps cannot influence server pricing.
    const bootstrap = "const fs=require('node:fs');Date.now=()=>Number(fs.readFileSync(process.env.TEST_CLOCK_FILE,'utf8'));require('./server.js');";
    child = spawn(process.execPath, ['-e', bootstrap], { cwd: path.join(__dirname, '..'), env: {
      PATH: process.env.PATH, HOST: '127.0.0.1', PORT: '0', PRICE_MNT: '12500', BOLZOO_DATA_DIR: directory,
      TEST_CLOCK_FILE: clockFile, WIRE_API_KEY: 'sk_test_campaign', WIRE_API_BASE: 'http://127.0.0.1:' + gateway.address().port,
      WIRE_WEBHOOK_SECRET: '', ALLOW_MOCK_PAYMENT: '0'
    }, stdio: ['ignore', 'pipe', 'pipe'] });
    origin = await new Promise((resolve, reject) => {
      let output = ''; const timeout = setTimeout(() => reject(new Error('Startup timeout: ' + output)), 10000);
      child.stdout.on('data', chunk => { output += chunk; const match = output.match(/Create page\s+:\s+(http:\/\/[^/]+)/); if (match) { clearTimeout(timeout); resolve(match[1]); } });
      child.stderr.on('data', chunk => { output += chunk; });
      child.once('error', error => { clearTimeout(timeout); reject(error); });
      child.once('exit', code => { clearTimeout(timeout); reject(new Error('Server exited ' + code + ': ' + output)); });
    });
  }
  async function request(route, body) {
    const response = await fetch(origin + route, { method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    return { status: response.status, headers: response.headers, body: await response.json() };
  }
  await boot();
  const firstHealth = await request('/api/health');
  assert.equal(firstHealth.body.price, 9023); assert.equal(firstHealth.body.regular_price, 12500);
  assert.equal(firstHealth.headers.get('cache-control'), 'no-store');
  const checkoutToken = (end - 1) + '-' + crypto.randomBytes(32).toString('hex');
  const uncertain = await request('/api/checkout', { checkout_token: checkoutToken, from: 'create', amount: 1 });
  assert.equal(uncertain.status, 502);
  const reserved = Object.values(JSON.parse(fs.readFileSync(path.join(directory, 'payments.json'), 'utf8')))[0];
  assert.equal(reserved.amount, 9023); assert.equal(reserved.provider_intent_id, null);
  await stop(); fs.writeFileSync(clockFile, String(end)); await boot();
  const afterHealth = await request('/api/health');
  assert.equal(afterHealth.body.price, 12500); assert.equal(afterHealth.body.promotion.active, false);
  assert.equal(afterHealth.body.server_time, '2026-09-23T16:00:00.000Z');
  const recovered = await request('/api/checkout', { checkout_token: checkoutToken, from: 'create', amount: 1 });
  assert.equal(recovered.status, 200); assert.equal(recovered.body.amount, 9023);
  assert.equal(recovered.body.intent_id, reserved.id); assert.equal(recovered.body.status, 'requires_action');
  assert.equal(intents.size, 1);
  const fresh = await request('/api/checkout', { checkout_token: end + '-' + crypto.randomBytes(32).toString('hex'), amount: 9023 });
  assert.equal(fresh.status, 200); assert.equal(fresh.body.amount, 12500);
  assert.equal(intents.size, 2);
  assert.deepEqual([...intents.values()].map(intent => intent.amount), [902300, 1250000]);
});
