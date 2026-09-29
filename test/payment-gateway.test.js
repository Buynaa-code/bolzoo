'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createPaymentFlow, amountMinor, validateRemote } = require('../lib/payment-flow');
const campaign = require('../assets/campaign');
const token = () => Date.now() + '-' + crypto.randomBytes(32).toString('hex');
const clone = x => x && structuredClone(x);
function fixture(options = {}) {
  const payments = new Map(), events = new Set(), intents = new Map(), calls = [], cached = new Map(), createBodies = new Map();
  let nextId = 0, issued = 0, loseCreate = false, loseConfirm = false, remoteFailure = false;
  const repo = {
    get: async id => clone(payments.get(id)),
    findByToken: async hash => clone([...payments.values()].find(p => p.checkout_token_hash === hash)),
    findByProvider: async id => clone([...payments.values()].find(p => p.provider_intent_id === id)),
    async insert(row) { if (!payments.has(row.id)) payments.set(row.id, clone(row)); return clone(payments.get(row.id)); },
    async bindProvider(id, providerId) { const row = payments.get(id); if (!row.provider_intent_id) row.provider_intent_id = providerId; return clone(row); },
    async reconcile(id, remote) {
      const p = payments.get(id); validateRemote({ ...p, provider_intent_id: p.provider_intent_id || p.id }, remote);
      if (p.status !== 'succeeded' && (p.status !== 'canceled' || remote.status === 'succeeded')) p.status = remote.status;
      if (p.status === 'succeeded' && !p.code) p.code = 'LOV-' + String(++issued).padStart(6, 'A');
      p.next_action = clone(remote.next_action); return clone(p);
    },
    hasEvent: async id => events.has(id),
    recordEvent: async e => { events.add(e.id); },
    async simulate(id) { const p = payments.get(id); p.status = 'succeeded'; p.code ||= 'LOV-MOCKAA'; return clone(p); },
    async cancelMock(id) { const p = payments.get(id); p.status = 'canceled'; return clone(p); }
  };
  async function wire(method, path, body, key) {
    calls.push({ method, path, body: clone(body), key });
    if (method === 'POST' && cached.has(key)) {
      if (path === '/v1/payment_intents') assert.deepEqual(body, createBodies.get(key), 'provider idempotency retries must preserve the original create body');
      return clone(cached.get(key));
    }
    let pi;
    if (method === 'POST' && path === '/v1/payment_intents') {
      const reservation = [...payments.values()].find(row => row.checkout_token_hash === body.metadata.checkout);
      assert.ok(reservation, 'freeze the authoritative amount before an external provider side effect');
      assert.equal(reservation.amount_minor, body.amount);
      createBodies.set(key, clone(body));
      pi = { id: 'pi_test_' + ++nextId, ...body, status: 'requires_payment_method', livemode: true, expires_at: Math.floor(Date.now()/1000)+600 };
      intents.set(pi.id, pi); cached.set(key, clone(pi));
      if (loseCreate) { loseCreate = false; throw new Error('response lost after create'); }
    } else {
      const id = path.split('/')[3]; pi = intents.get(id);
      if (!pi || remoteFailure) throw new Error('Wire unavailable');
      if (path.endsWith('/confirm')) {
        assert.ok([...payments.values()].some(row => row.provider_intent_id === pi.id), 'must bind the provider before exposing a payable invoice');
        pi.status = 'requires_action'; pi.next_action = { qr: { image_url: 'https://example.com/qr.png', deeplinks: [] } };
        cached.set(key, clone(pi));
        if (loseConfirm) { loseConfirm = false; throw new Error('response lost after confirm'); }
      }
      if (path.endsWith('/cancel')) { if (pi.status !== 'succeeded') pi.status = 'canceled'; cached.set(key, clone(pi)); }
    }
    return clone(pi);
  }
  const flow = createPaymentFlow({ repo, wire, price: 9900, description: 'Bolzoo', wireEnabled: true, ...options });
  return { flow, repo, wire, payments, intents, calls, events, remote(id) { return intents.get(payments.get(id).provider_intent_id); }, get issued(){ return issued; },
    loseCreate(){ loseCreate = true; }, loseConfirm(){ loseConfirm = true; }, remoteFailure(){ remoteFailure = true; } };
}
const checkout = (f,t) => f.flow.checkout({ checkout_token:t, from:'create', amount:1 }, 'https://bolzoo.example');

test('9,900 whole MNT is exactly 990,000 Wire minor units; invalid prices fail closed', () => {
  assert.equal(amountMinor(9900), 990000);
  for (const price of [0, -1, NaN, Infinity, 1.5, 21474837]) assert.throws(() => amountMinor(price));
});
test('client amount ignored, invoice persisted before confirm, browser return retains create intent', async () => {
  const f = fixture(), t = token(); const p = await checkout(f,t);
  assert.equal(p.amount, 9900); assert.equal(p.mode, 'live'); assert.equal(p.code, null);
  assert.equal(f.calls[0].body.amount, 990000);
  const returned = new URL(f.calls.find(c => c.path.endsWith('/confirm')).body.return_url);
  assert.equal(returned.searchParams.get('from'), 'create');
  assert.equal(returned.searchParams.get('intent'), p.intent_id);
  assert.equal(new URLSearchParams(returned.hash.slice(1)).get('payment_token'), t);
  assert.equal(returned.search.includes(t), false);
});
test('concurrent and repeated checkout calls reuse one intent and preserve a fulfilled code', async () => {
  const f = fixture(), t = token();
  const results = await Promise.all([checkout(f,t),checkout(f,t),checkout(f,t)]);
  assert.equal(new Set(results.map(r=>r.intent_id)).size, 1);
  const id = results[0].intent_id; f.remote(id).status = 'succeeded';
  const first = await f.flow.status(id,t); const replay = await checkout(f,t);
  assert.equal(first.code, replay.code); assert.equal(f.issued, 1); assert.equal(f.intents.size, 1);
});
test('lost create and confirm responses can be retried without a second payable invoice', async () => {
  for (const failure of ['loseCreate','loseConfirm']) {
    const f = fixture(), t = token(); f[failure]();
    await assert.rejects(checkout(f,t));
    const result = await checkout(f,t);
    assert.equal(result.status,'requires_action'); assert.equal(f.intents.size,1);
  }
});
test('amount, currency, intent identity and environment must match before a code is issued', async () => {
  for (const patch of [{ amount:9900 }, { amount:'990000' }, { currency:'USD' }, { id:'pi_other' }, { livemode:false }]) {
    const f = fixture(), t = token(), p = await checkout(f,t);
    Object.assign(f.remote(p.intent_id), { status:'succeeded' }, patch);
    await assert.rejects(f.flow.status(p.intent_id,t), /таарахгүй/);
    assert.equal(f.issued,0); assert.equal(f.payments.get(p.intent_id).code,null);
  }
});
test('payment id alone or another checkout token cannot retrieve a new payment code or cancel it', async () => {
  const f = fixture(), t = token(), p = await checkout(f,t);
  for (const bad of [undefined, token(), 'invalid']) {
    await assert.rejects(f.flow.status(p.intent_id,bad), e=>e.status===403);
    await assert.rejects(f.flow.cancel(p.intent_id,bad), e=>e.status===403);
  }
});
test('an early webhook is retried; duplicate and out-of-order events cannot undo success', async () => {
  const f = fixture(), t = token();
  const early = { id:'evt_early',type:'payment_intent.succeeded',data:{id:'pi_test_1'} };
  await assert.rejects(f.flow.webhook(early), e=>e.status===503); assert.equal(f.events.size,0);
  const p = await checkout(f,t); f.remote(p.intent_id).status='succeeded';
  await f.flow.webhook(early); const code = f.payments.get(p.intent_id).code;
  await f.flow.webhook(early);
  f.remote(p.intent_id).status='requires_action';
  await f.flow.webhook({id:'evt_late',type:'charge.failed',data:{object:{id:'ch_bad',payment_intent:f.remote(p.intent_id).id}}});
  assert.equal(f.payments.get(p.intent_id).status,'succeeded');
  assert.equal(f.payments.get(p.intent_id).code,code); assert.equal(f.issued,1);
});
test('a charge success event alone does not fulfill a pending intent; failed attempts remain retryable', async () => {
  const f = fixture(), t = token(), p = await checkout(f,t);
  await f.flow.webhook({id:'evt_charge',type:'charge.succeeded',data:{id:'ch_1',payment_intent:f.remote(p.intent_id).id}});
  assert.equal(f.issued,0); assert.equal((await f.flow.status(p.intent_id,t)).status,'requires_action');
});
test('provider failures are surfaced, not falsely marked paid or acknowledged as processed', async () => {
  const f=fixture(), t=token(), p=await checkout(f,t); f.remoteFailure();
  await assert.rejects(f.flow.status(p.intent_id,t));
  await assert.rejects(f.flow.webhook({id:'evt_retry',type:'payment_intent.succeeded',data:{id:f.remote(p.intent_id).id}}));
  assert.equal(f.events.size,0); assert.equal(f.issued,0);
});
test('mock payment is opt-in, cannot simulate live invoices, cancellation is confirmed by provider', async () => {
  const disabled=fixture({wireEnabled:false}); await assert.rejects(checkout(disabled,token()),e=>e.status===503);
  const live=fixture(), t=token(), p=await checkout(live,t);
  await assert.rejects(live.flow.simulate(p.intent_id,t),e=>e.status===403);
  assert.equal((await live.flow.cancel(p.intent_id,t)).status,'canceled');
  const mock=fixture({wireEnabled:false,allowMock:true}), mt=token(), mp=await checkout(mock,mt);
  assert.equal(mp.mode,'mock'); assert.equal((await mock.flow.simulate(mp.intent_id,mt)).status,'succeeded');
});
test('expired unknown checkout keys never replay outside Wire idempotency retention', async () => {
  const f=fixture(); const old=(Date.now()-48*3600000)+'-'+crypto.randomBytes(32).toString('hex');
  await assert.rejects(checkout(f,old),e=>e.status===409); assert.equal(f.calls.length,0);
});
test('verification ping is acknowledged without creating a payment', async () => {
  const f=fixture(); assert.deepEqual(await f.flow.webhook({id:'evt_ping',type:'endpoint.verification'}),{ok:true,ignored:true});
  assert.equal(f.calls.length,0);
});

test('current server time sets each new price while persisted retries retain their amount across both boundaries', async () => {
  let now = Date.parse(campaign.PROMOTION_START_AT) - 1, evaluations = 0;
  const f = fixture({ now: () => now, price: at => { evaluations++; return campaign.pricing(at, 12500).price; } });
  const at = () => now + '-' + crypto.randomBytes(32).toString('hex');
  const firstToken = at(), before = await checkout(f, firstToken);
  assert.equal(before.amount, 12500);
  now++;
  assert.equal((await checkout(f, firstToken)).amount, 12500);
  const promoToken = at(), during = await checkout(f, promoToken);
  assert.equal(during.amount, 9023);
  now = Date.parse(campaign.PROMOTION_END_AT);
  assert.equal((await checkout(f, promoToken)).amount, 9023);
  const after = await checkout(f, at());
  assert.equal(after.amount, 12500);
  assert.equal(evaluations, 3, 'only newly reserved checkouts evaluate current pricing');
  assert.deepEqual(f.calls.filter(call => call.path === '/v1/payment_intents').map(call => call.body.amount), [1250000, 902300, 1250000]);
});

test('lost provider create response can recover after promotion expiry and restart using the durable quoted amount', async () => {
  let now = Date.parse(campaign.PROMOTION_END_AT) - 1;
  const options = { now: () => now, price: at => campaign.pricing(at, 12500).price };
  const f = fixture(options), checkoutToken = now + '-' + crypto.randomBytes(32).toString('hex');
  f.loseCreate();
  await assert.rejects(checkout(f, checkoutToken), /response lost/);
  const reserved = [...f.payments.values()][0];
  assert.equal(reserved.amount, 9023);
  assert.equal(reserved.provider_intent_id, null);
  assert.equal(reserved.status, 'new');
  assert.equal((await f.flow.status(reserved.id, checkoutToken)).next_action, null);
  now++;
  // A fresh orchestrator represents another process/serverless invocation.
  const restarted = createPaymentFlow({ repo: f.repo, wire: f.wire, wireEnabled: true,
    description: 'Changed configuration after restart', ...options });
  const retried = await restarted.checkout({ checkout_token: checkoutToken }, 'https://bolzoo.example');
  assert.equal(retried.amount, 9023);
  assert.equal(retried.intent_id, reserved.id);
  assert.equal(retried.status, 'requires_action');
  assert.equal(f.intents.size, 1);
  assert.equal(f.payments.size, 1);
  const creates = f.calls.filter(call => call.path === '/v1/payment_intents');
  assert.equal(creates.length, 2);
  assert.deepEqual(creates[0].body, creates[1].body);
  assert.equal(creates[0].key, creates[1].key);
});

test('backdated client checkout timestamps never extend the discount for a new reservation', async () => {
  const now = Date.parse(campaign.PROMOTION_END_AT), oldToken = (now - 3600000) + '-' + crypto.randomBytes(32).toString('hex');
  const f = fixture({ now: () => now, price: at => campaign.pricing(at, 9900).price });
  const result = await f.flow.checkout({ checkout_token: oldToken, amount: 9023, price: 9023, campaign: campaign.ID }, 'https://bolzoo.example');
  assert.equal(result.amount, 9900);
  assert.equal(f.calls[0].body.amount, 990000);
});

test('concurrent checkout reservations straddling expiry use one captured amount and one payable invoice', async () => {
  let now = Date.parse(campaign.PROMOTION_END_AT) - 1;
  const evaluated = [];
  const f = fixture({ now: () => now, price: at => { const result = campaign.pricing(at).price; evaluated.push(result); now = Date.parse(campaign.PROMOTION_END_AT); return result; } });
  const checkoutToken = now + '-' + crypto.randomBytes(32).toString('hex');
  const [one, two] = await Promise.all([checkout(f, checkoutToken), checkout(f, checkoutToken)]);
  assert.deepEqual(evaluated, [9023, 9900], 'racing candidates may see different current prices; only the first reservation wins');
  assert.equal(one.amount, 9023); assert.equal(two.amount, 9023);
  assert.equal(one.intent_id, two.intent_id); assert.equal(f.intents.size, 1); assert.equal(f.payments.size, 1);
  assert.ok(f.calls.filter(call => call.path === '/v1/payment_intents').every(call => call.body.amount === 902300));
});

test('unbound reservations cancel through the same provider intent and never retry outside retention', async () => {
  let now = Date.parse(campaign.PROMOTION_END_AT) - 1;
  const f = fixture({ now: () => now, price: at => campaign.pricing(at).price });
  const checkoutToken = now + '-' + crypto.randomBytes(32).toString('hex');
  f.loseCreate(); await assert.rejects(checkout(f, checkoutToken));
  const row = [...f.payments.values()][0];
  now++;
  const cancelled = await f.flow.cancel(row.id, checkoutToken);
  assert.equal(cancelled.status, 'canceled'); assert.equal(cancelled.amount, 9023); assert.equal(f.intents.size, 1);
  assert.equal((await checkout(f, checkoutToken)).status, 'canceled');
  const later = fixture({ now: () => now, price: at => campaign.pricing(at).price });
  const laterToken = now + '-' + crypto.randomBytes(32).toString('hex');
  later.loseCreate(); await assert.rejects(checkout(later, laterToken));
  const count = later.calls.length; now += 47 * 3600000 + 1;
  await assert.rejects(checkout(later, laterToken), error => error.code === 'checkout_expired');
  assert.equal(later.calls.length, count);
});

test('legacy invoices whose internal id equals provider id remain recoverable without a new reservation', async () => {
  const f = fixture(), checkoutToken = token();
  const row = { id: 'pi_legacy', provider_intent_id: 'pi_legacy', provider: 'wire', status: 'requires_action', amount: 9900, amount_minor: 990000, currency: 'MNT', livemode: true, checkout_token_hash: crypto.createHash('sha256').update(checkoutToken).digest('hex') };
  f.payments.set(row.id, row); f.intents.set(row.id, { id: row.id, amount: row.amount_minor, currency: 'MNT', livemode: true, status: 'requires_action' });
  assert.equal((await checkout(f, checkoutToken)).intent_id, row.id);
  assert.equal((await f.flow.status(row.id, checkoutToken)).amount, 9900);
  assert.equal(f.calls.some(call => call.path === '/v1/payment_intents'), false);
  row.provider_intent_id = null;
  assert.equal((await checkout(f, checkoutToken)).intent_id, row.id);
  assert.equal((await f.flow.status(row.id, checkoutToken)).amount, 9900);
  assert.equal(f.calls.some(call => call.path === '/v1/payment_intents'), false);
});
