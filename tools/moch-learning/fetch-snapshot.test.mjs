import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchSnapshot } from './fetch-snapshot.mjs';

const TOKEN = 'only-local-test-token-0123456789abcdef';

function fixture() {
  const now = Date.now();
  const from = new Date(now - 2 * 86400000).toISOString();
  const to = new Date(now - 86400000).toISOString();
  const snapshot = {
    schemaVersion: 1,
    source: { product: 'bolzoo', environment: 'production', readAt: new Date(now).toISOString(), period: { from, to } },
    money: {
      recordedCount: 4, recordedAmountMnt: 39600, providerVerifiedAmountMnt: null,
      verifiedRefundAmountMnt: null, variableCostMnt: null,
    },
    fulfillment: { paidWithoutLinkCount: null }, funnel: null,
  };
  return { snapshot, args: { url: 'https://bolzoo.example/api/learning-overview', token: TOKEN, from, to } };
}

function json(value) {
  return new Response(JSON.stringify(value), { status: 200, headers: { 'content-type': 'application/json' } });
}

function safeMessage(pattern) {
  return error => {
    assert.match(error.message, pattern);
    assert.doesNotMatch(error.message, /PRIVATE-REMOTE-CONTENT|only-local-test-token|example|https?:|[?&]from=/);
    return true;
  };
}

test('sends only exact query and a bearer header, forbids redirects, returns validated data', async () => {
  const { args, snapshot } = fixture();
  let calls = 0;
  const result = await fetchSnapshot({ ...args, fetchImpl: async (url, options) => {
    calls += 1;
    const parsed = new URL(url);
    assert.equal(parsed.origin + parsed.pathname, args.url);
    assert.deepEqual([...parsed.searchParams.entries()], [['from', args.from], ['to', args.to]]);
    assert.ok(!url.includes(TOKEN));
    assert.deepEqual(options.headers, { Authorization: `Bearer ${TOKEN}`, Accept: 'application/json' });
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'error');
    assert.equal(options.credentials, 'omit');
    assert.equal(options.cache, 'no-store');
    assert.ok(options.signal instanceof AbortSignal);
    return json(snapshot);
  } });
  assert.equal(calls, 1);
  assert.deepEqual(result, snapshot);
  assert.ok(!JSON.stringify(result).includes(TOKEN));
});

test('preserves demo and test environments instead of claiming production', async () => {
  for (const environment of ['demo', 'test']) {
    const { args, snapshot } = fixture();
    snapshot.source.environment = environment;
    const result = await fetchSnapshot({ ...args, fetchImpl: async () => json(snapshot) });
    assert.equal(result.source.environment, environment);
  }
});

test('allows HTTP only at loopback endpoints', async () => {
  for (const host of ['localhost:8080', '127.0.0.1:8080', '127.9.8.7:8080', '[::1]:8080']) {
    const { args, snapshot } = fixture();
    const result = await fetchSnapshot({ ...args, url: `http://${host}/api/learning-overview`, fetchImpl: async () => json(snapshot) });
    assert.equal(result.source.product, 'bolzoo');
  }
});

test('rejects invalid endpoint, credentials and period before any request', async () => {
  const { args } = fixture();
  let calls = 0;
  const fetchImpl = async () => { calls += 1; throw new Error('must not fetch'); };
  const invalidUrls = [
    'http://bolzoo.example/api/learning-overview', 'http://localhost.attacker.example/api/learning-overview',
    'https://user:password@bolzoo.example/api/learning-overview',
    `${args.url}?`, `${args.url}?token=private`, `${args.url}#`, `${args.url}#private`,
    `${args.url}/`, 'https://bolzoo.example/other', 'file:///api/learning-overview', null,
  ];
  for (const url of invalidUrls) {
    await assert.rejects(fetchSnapshot({ ...args, url, fetchImpl }), safeMessage(/Invalid snapshot URL/));
  }
  for (const token of ['', 'short', 'x'.repeat(31), 'x'.repeat(513), `${TOKEN}\r\nOther: private`, null, 'ү'.repeat(32)]) {
    await assert.rejects(fetchSnapshot({ ...args, token, fetchImpl }), safeMessage(/Invalid snapshot credential/));
  }
  for (const period of [
    { from: 'invalid', to: args.to }, { from: args.from, to: args.from },
    { from: args.to, to: args.from }, { from: args.from, to: new Date(Date.now() + 86400000).toISOString() },
  ]) {
    await assert.rejects(fetchSnapshot({ ...args, ...period, fetchImpl }), safeMessage(/Invalid snapshot period/));
  }
  assert.equal(calls, 0);
});

test('never follows or accepts redirected responses and never prints remote errors', async () => {
  const { args } = fixture();
  for (const status of [301, 302, 307, 308, 401, 403, 500]) {
    let calls = 0;
    await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async (_url, options) => {
      calls += 1;
      assert.equal(options.redirect, 'error');
      return new Response(`PRIVATE-REMOTE-CONTENT ${TOKEN}`, { status, headers: { location: 'https://other.example/private' } });
    } }), safeMessage(/Snapshot request was not accepted/));
    assert.equal(calls, 1);
  }
  const redirected = json(fixture().snapshot);
  Object.defineProperty(redirected, 'redirected', { value: true });
  await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () => redirected }), safeMessage(/not accepted/));
  await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () => {
    throw new Error(`PRIVATE-REMOTE-CONTENT ${TOKEN} https://private.example`);
  } }), safeMessage(/Snapshot request failed/));
});

test('validates product, requested instants, schema, freshness and private-field exclusion', async () => {
  const mutations = [
    [value => { value.source.product = 'mend'; }, /wrong product/],
    [value => { value.source.period.from = new Date(Date.parse(value.source.period.from) + 1).toISOString(); }, /requested period/],
    [value => { value.source.readAt = new Date(Date.now() - 301000).toISOString(); }, /not fresh/],
    [value => { value.source.readAt = new Date(Date.now() + 60000).toISOString(); }, /not fresh/],
    [value => { value.private = 'PRIVATE-REMOTE-CONTENT'; }, /Invalid snapshot response/],
    [value => { value.money.recordedCount = -1; }, /Invalid snapshot response/],
    [value => { delete value.fulfillment; }, /Invalid snapshot response/],
  ];
  for (const [mutate, message] of mutations) {
    const { args, snapshot } = fixture();
    mutate(snapshot);
    await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () => json(snapshot) }), safeMessage(message));
  }
});

test('period matching compares instants, accepting equivalent timezone notation', async () => {
  const { args, snapshot } = fixture();
  snapshot.source.period.from = snapshot.source.period.from.replace('Z', '+00:00');
  snapshot.source.period.to = snapshot.source.period.to.replace('Z', '+00:00');
  const result = await fetchSnapshot({ ...args, fetchImpl: async () => json(snapshot) });
  assert.deepEqual(result.source.period, snapshot.source.period);
});

test('rejects oversized declared and chunked bodies without echoing any payload', async () => {
  const { args } = fixture();
  await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () =>
    new Response('PRIVATE-REMOTE-CONTENT', { headers: { 'content-length': '65537' } })
  }), safeMessage(/Snapshot response is too large/));
  let canceled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(32768));
      controller.enqueue(new Uint8Array(32769));
    },
    cancel() { canceled = true; },
  });
  await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () => new Response(body) }), safeMessage(/Snapshot response is too large/));
  assert.equal(canceled, true);
});

test('accepts exactly 64 KiB, rejects invalid JSON/UTF-8 and broken streams safely', async () => {
  const { args, snapshot } = fixture();
  const text = JSON.stringify(snapshot);
  const padded = text + ' '.repeat(65536 - new TextEncoder().encode(text).length);
  const result = await fetchSnapshot({ ...args, fetchImpl: async () => new Response(padded) });
  assert.deepEqual(result, snapshot);
  for (const body of ['PRIVATE-REMOTE-CONTENT', new Uint8Array([0xff, 0xfe])]) {
    await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () => new Response(body) }), safeMessage(/Invalid snapshot response/));
  }
  const broken = new ReadableStream({ start(controller) { controller.error(new Error(`PRIVATE-REMOTE-CONTENT ${TOKEN}`)); } });
  await assert.rejects(fetchSnapshot({ ...args, fetchImpl: async () => new Response(broken) }), safeMessage(/Snapshot request failed/));
});

test('ten-second deadline aborts even a fetch implementation that ignores its signal', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { args } = fixture();
  let requestSignal;
  const result = fetchSnapshot({ ...args, fetchImpl: (_url, options) => {
    requestSignal = options.signal;
    return new Promise(() => {});
  } });
  const rejection = assert.rejects(result, safeMessage(/Snapshot request timed out/));
  t.mock.timers.tick(9999);
  assert.equal(requestSignal.aborted, false);
  t.mock.timers.tick(1);
  await rejection;
  assert.equal(requestSignal.aborted, true);
});

test('ten-second deadline also stops a response whose body never finishes', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { args } = fixture();
  let canceled = false;
  const body = new ReadableStream({ cancel() { canceled = true; } });
  const result = fetchSnapshot({ ...args, fetchImpl: async () => new Response(body) });
  const rejection = assert.rejects(result, safeMessage(/Snapshot request timed out/));
  await Promise.resolve();
  await Promise.resolve();
  t.mock.timers.tick(10000);
  await rejection;
  assert.equal(canceled, true);
});
