'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const root = path.join(__dirname, '..');
const secret = () => crypto.randomBytes(32).toString('base64url');
const intent = (inviteId, action, fields = {}) => ({ action, invite_id: inviteId, request_id: crypto.randomUUID(), ...fields });

async function start(t, { hosted = false } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bolzoo-date-http-'));
  const owner = crypto.randomUUID();
  const inviteId = 'date_http_invite';
  const apologyId = 'apology_http_invite';
  fs.writeFileSync(path.join(dir, 'invites.json'), JSON.stringify({
    [inviteId]: { id: inviteId, owner_token: owner, config: { experienceType: 'date', senderName: 'Бат', recipientName: 'Номин', missionIdeaId: 'coffee-questions', campaign: 'newyear100-2026', askTemplate: 'ticket' } },
    [apologyId]: { id: apologyId, owner_token: owner, config: { experienceType: 'apology', recipientName: 'Номин' } }
  }));
  let child;
  let origin;
  async function stop() {
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    const ended = new Promise(resolve => child.once('exit', resolve));
    child.kill();
    await ended;
  }
  async function boot() {
    // The hosted route harness exercises its actual exported handler without
    // loading local .env files or using any real Supabase credentials.
    const args = hosted ? ['-e', `const http=require('node:http');const handler=require('./api/date-plan');const server=http.createServer(handler);server.listen(0,'127.0.0.1',()=>console.log('Create page : http://127.0.0.1:'+server.address().port+'/create.html'));`] : ['server.js'];
    child = spawn(process.execPath, args, {
      cwd: root,
      env: {
        PATH: process.env.PATH, PORT: '0', HOST: '127.0.0.1', BOLZOO_DATA_DIR: dir,
        WIRE_API_KEY: '', ALLOW_MOCK_PAYMENT: '0',
        SUPABASE_SERVICE_ROLE_KEY: '', SUPABASE_SECRET_KEY: '', BOLZOO_SUPABASE_SERVICE_ROLE_KEY: ''
      },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    origin = await new Promise((resolve, reject) => {
      let output = '';
      const timer = setTimeout(() => { child.kill(); reject(new Error('Date plan HTTP server startup timed out: ' + output)); }, 10000);
      child.stdout.on('data', chunk => {
        output += chunk;
        const match = output.match(/Create page\s+:\s+(http:\/\/[^/]+)/);
        if (match) { clearTimeout(timer); resolve(match[1]); }
      });
      child.stderr.on('data', chunk => { output += chunk; });
      child.once('error', cause => { clearTimeout(timer); reject(cause); });
      child.once('exit', code => { clearTimeout(timer); reject(new Error('Date plan HTTP server exited ' + code + ': ' + output)); });
    });
  }
  t.after(async () => { await stop(); fs.rmSync(dir, { recursive: true, force: true }); });
  await boot();
  return { dir, owner, inviteId, apologyId, get origin() { return origin; }, async restart() { await stop(); await boot(); } };
}

async function request(app, { body, token, query = '', route = '/api/date-plan', method = body === undefined ? 'GET' : 'POST', headers = {}, raw } = {}) {
  const response = await fetch(app.origin + route + query, {
    method,
    headers: { ...(body !== undefined || raw !== undefined ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers },
    body: raw !== undefined ? raw : body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let parsed;
  try { parsed = text ? JSON.parse(text) : null; } catch (_) { parsed = text; }
  if (route === '/api/date-plan') {
    assert.match(response.headers.get('cache-control') || '', /\bno-store\b/);
    assert.equal(response.headers.get('access-control-allow-origin'), null, 'private API never grants wildcard or cross-origin access');
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  }
  return { status: response.status, body: parsed, headers: response.headers };
}
function expect(response, status, code) {
  assert.equal(response.status, status, JSON.stringify(response.body));
  if (code) assert.equal(response.body.code, code);
  return response.body;
}
const get = (app, token, id) => request(app, { token, query: id ? '?id=' + id : '?invite_id=' + app.inviteId });
const post = (app, body, token) => request(app, { body, token });
async function setup(app) {
  const claimToken = secret();
  const partner = secret();
  const created = expect(await post(app, intent(app.inviteId, 'create', { template_id: 'coffee-questions', claim_token: claimToken }), app.owner), 200);
  const claimed = expect(await post(app, intent(app.inviteId, 'claim', { claim_token: claimToken, participant_token: partner })), 200);
  return { created, claimed, claimToken, partner };
}

test('real HTTP plan flow preserves consent, optional steps and private memories across restart', async t => {
  const app = await start(t);
  expect(await get(app, app.owner), 404, 'plan_not_found');
  expect(await get(app), 403, 'forbidden');
  const claimToken = secret();
  const partner = secret();
  const createBody = intent(app.inviteId, 'create', {
    template_id: 'coffee-questions', claim_token: claimToken,
    scheduled_at: new Date(Date.now() + 7 * 86400000).toISOString(), location: 'Тохирсон кафе', budget: 'Хоёулаа тохирно'
  });
  const created = expect(await post(app, createBody, app.owner), 200);
  assert.equal(created.role, 'creator');
  assert.equal(created.revision, 1);
  assert.equal(created.state, 'proposed');
  assert.deepEqual(created.accepted, { creator: 1, partner: null });
  assert.equal(created.steps.length, 3);
  expect(await post(app, intent(app.inviteId, 'accept', { expected_version: created.version, expected_revision: created.revision })), 403, 'forbidden');
  expect(await post(app, intent(app.inviteId, 'claim', { claim_token: secret(), participant_token: secret() })), 403, 'forbidden');
  assert.deepEqual(expect(await post(app, createBody, app.owner), 200), created, 'lost create response is retryable');
  expect(await post(app, { ...createBody, title: 'Changed replay' }, app.owner), 409, 'replay_conflict');
  expect(await get(app, crypto.randomUUID()), 403, 'forbidden');
  expect(await get(app, claimToken), 403, 'forbidden');
  const claimBody = intent(app.inviteId, 'claim', { claim_token: claimToken, participant_token: partner });
  let plan = expect(await post(app, claimBody), 200);
  assert.equal(plan.role, 'partner');
  assert.equal(plan.partner_claimed, true);
  assert.deepEqual(expect(await post(app, claimBody), 200), plan);
  assert.equal(expect(await post(app, { ...claimBody, request_id: crypto.randomUUID() }), 200).version, plan.version);
  expect(await post(app, { ...claimBody, request_id: crypto.randomUUID(), participant_token: secret() }), 409, 'claim_used');

  const beforeProposal = plan.version;
  plan = expect(await post(app, intent(app.inviteId, 'propose', { expected_version: plan.version, location: 'Өөр кафе' }), partner), 200);
  assert.equal(plan.revision, 2);
  assert.deepEqual(plan.accepted, { creator: null, partner: 2 });
  expect(await post(app, intent(app.inviteId, 'accept', { expected_version: beforeProposal, expected_revision: 1 }), app.owner), 409, 'conflict');
  expect(await post(app, intent(app.inviteId, 'accept', { expected_version: plan.version, expected_revision: 1 }), app.owner), 409, 'conflict');
  expect(await post(app, intent(app.inviteId, 'start', { expected_version: plan.version }), partner), 409, 'invalid_state');
  plan = expect(await post(app, intent(app.inviteId, 'accept', { expected_version: plan.version, expected_revision: plan.revision }), app.owner), 200);
  assert.equal(plan.state, 'agreed');
  plan = expect(await post(app, intent(app.inviteId, 'start', { expected_version: plan.version }), partner), 200);
  assert.equal(plan.state, 'in_progress');
  plan = expect(await post(app, intent(app.inviteId, 'outcome', { expected_version: plan.version, step_id: 'before', outcome: 'done' }), app.owner), 200);
  plan = expect(await post(app, intent(app.inviteId, 'outcome', { expected_version: plan.version, step_id: 'before', outcome: 'skipped' }), partner), 200);
  assert.deepEqual(plan.steps[0].outcomes, { creator: 'done', partner: 'skipped' });
  assert.deepEqual(plan.steps[1].outcomes, { creator: 'todo', partner: 'todo' });
  plan = expect(await post(app, intent(app.inviteId, 'end', { expected_version: plan.version }), app.owner), 200);
  assert.equal(plan.state, 'ended', 'ending never requires all steps to be completed');
  const creatorMemory = 'Миний хувийн тэмдэглэл — тайван сайхан орой.';
  const partnerMemory = 'Миний өөртөө үлдээх жижиг дурсамж.';
  plan = expect(await post(app, intent(app.inviteId, 'memory', { expected_version: plan.version, text: creatorMemory }), app.owner), 200);
  assert.equal(plan.my_memory, creatorMemory);
  assert.equal(expect(await get(app, partner), 200).my_memory, '');
  plan = expect(await post(app, intent(app.inviteId, 'memory', { expected_version: plan.version, text: partnerMemory }), partner), 200);
  assert.equal(plan.my_memory, partnerMemory);
  const ownerSnapshot = expect(await get(app, app.owner, plan.id), 200);
  assert.equal(ownerSnapshot.my_memory, creatorMemory);
  const publicInvite = expect(await request(app, { route: '/api/invite', query: '?id=' + app.inviteId }), 200);
  assert.equal(publicInvite.config.campaign, 'newyear100-2026');
  assert.equal(publicInvite.config.askTemplate, 'ticket');
  for (const privateValue of [app.owner, partner, claimToken, creatorMemory, partnerMemory]) {
    assert.equal(JSON.stringify(publicInvite).includes(privateValue), false, 'public invitation does not expose private plan data');
  }
  for (const [snapshot, otherMemory] of [[ownerSnapshot, partnerMemory], [plan, creatorMemory]]) {
    const serialized = JSON.stringify(snapshot);
    for (const privateValue of [app.owner, partner, claimToken, otherMemory]) assert.equal(serialized.includes(privateValue), false);
    for (const privateKey of ['document', 'memories', 'requests', 'claim_token_hash', 'participant_token_hash']) assert.equal(Object.hasOwn(snapshot, privateKey), false);
  }
  const storeFile = path.join(app.dir, 'date_plans.json');
  const disk = fs.readFileSync(storeFile, 'utf8');
  for (const privateToken of [partner, claimToken, app.owner]) assert.equal(disk.includes(privateToken), false, 'capabilities are hashed in the plan store');
  assert.equal(fs.statSync(storeFile).mode & 0o777, 0o600);
  await app.restart();
  assert.deepEqual(expect(await get(app, app.owner, plan.id), 200), ownerSnapshot);
  assert.deepEqual(expect(await get(app, partner), 200), plan);
  expect(await post(app, intent(app.inviteId, 'outcome', { expected_version: plan.version, step_id: 'after', outcome: 'done' }), partner), 409, 'invalid_state');
});

test('real HTTP simultaneous proposals produce one winner without silently overwriting the other', async t => {
  const app = await start(t);
  const { claimed, partner } = await setup(app);
  const results = await Promise.all([
    post(app, intent(app.inviteId, 'propose', { expected_version: claimed.version, location: 'Creator proposal' }), app.owner),
    post(app, intent(app.inviteId, 'propose', { expected_version: claimed.version, location: 'Partner proposal' }), partner)
  ]);
  assert.deepEqual(results.map(result => result.status).sort(), [200, 409]);
  const winner = results.find(result => result.status === 200).body;
  expect(results.find(result => result.status === 409), 409, 'conflict');
  const saved = expect(await get(app, app.owner), 200);
  assert.equal(saved.version, claimed.version + 1);
  assert.equal(saved.location, winner.location);
  assert.equal(saved.revision, 2);
});

test('real HTTP rotating a claim revokes the previous participant and old claim links', async t => {
  const app = await start(t);
  const { claimed, partner, claimToken } = await setup(app);
  expect(await post(app, intent(app.inviteId, 'rotate_claim', { expected_version: claimed.version, claim_token: secret() }), partner), 403, 'forbidden');
  const nextClaim = secret();
  const rotated = expect(await post(app, intent(app.inviteId, 'rotate_claim', { expected_version: claimed.version, claim_token: nextClaim }), app.owner), 200);
  assert.equal(rotated.partner_claimed, false);
  assert.equal(rotated.revision, claimed.revision + 1);
  assert.deepEqual(rotated.accepted, { creator: rotated.revision, partner: null });
  expect(await get(app, partner), 403, 'forbidden');
  expect(await post(app, intent(app.inviteId, 'accept', { expected_version: rotated.version, expected_revision: rotated.revision }), partner), 403, 'forbidden');
  expect(await post(app, intent(app.inviteId, 'claim', { claim_token: claimToken, participant_token: partner })), 403, 'forbidden');
  const replacement = secret();
  const reclaimed = expect(await post(app, intent(app.inviteId, 'claim', { claim_token: nextClaim, participant_token: replacement })), 200);
  assert.equal(reclaimed.role, 'partner');
  assert.equal(reclaimed.accepted.partner, null);
  expect(await get(app, partner), 403, 'forbidden');
  expect(await get(app, replacement), 200);
});

test('real HTTP cancellation is terminal and apology invitations cannot create date plans', async t => {
  const app = await start(t);
  expect(await post(app, intent(app.apologyId, 'create', { template_id: 'coffee-questions', claim_token: secret() }), app.owner), 400, 'apology_invite');
  const { claimed, partner } = await setup(app);
  const cancelled = expect(await post(app, intent(app.inviteId, 'cancel', { expected_version: claimed.version }), partner), 200);
  assert.equal(cancelled.state, 'cancelled');
  for (const [action, fields] of [['accept', { expected_revision: cancelled.revision }], ['start', {}], ['propose', { location: 'Cannot reopen' }], ['memory', { text: 'Cannot write' }]]) {
    expect(await post(app, intent(app.inviteId, action, { expected_version: cancelled.version, ...fields }), app.owner), 409, 'invalid_state');
  }
  assert.equal(expect(await get(app, app.owner), 200).version, cancelled.version);
});

test('real HTTP rejects malformed bodies and invalid fields without creating a plan', async t => {
  const app = await start(t);
  expect(await request(app, { method: 'POST', raw: '{', token: app.owner }), 400, 'invalid_json');
  expect(await request(app, { method: 'POST', raw: '{}', token: app.owner, headers: { 'Content-Type': 'text/plain' } }), 415, 'invalid_content_type');
  expect(await request(app, { method: 'POST', raw: JSON.stringify({ text: 'x'.repeat(17000) }), token: app.owner }), 413, 'body_too_large');
  const valid = intent(app.inviteId, 'create', { template_id: 'coffee-questions', claim_token: secret() });
  for (const body of [[], null, { ...valid, request_id: 'short' }, { ...valid, unexpected: true }, { ...valid, template_id: 'nonexistent' }, { ...valid, scheduled_at: '2026-02-30T18:00:00Z' }, { ...valid, scheduled_at: '2026-13-01T18:00:00Z' }, { ...valid, steps: [] }]) {
    expect(await post(app, body, app.owner), 400, 'invalid_request');
  }
  expect(await get(app, app.owner), 404, 'plan_not_found');
  expect(await request(app, { token: app.owner, query: '?invite_id=' + app.inviteId + '&owner_token=' + app.owner }), 400, 'invalid_request');
  expect(await post(app, valid, app.owner), 200);
});

test('real HTTP private route rejects cross-origin requests and preflights before global CORS', async t => {
  const app = await start(t);
  const { created } = await setup(app);
  expect(await request(app, { token: app.owner, query: '?id=' + created.id, headers: { Origin: 'https://untrusted.example' } }), 403, 'forbidden');
  expect(await request(app, { token: app.owner, query: '?id=' + created.id, headers: { 'Sec-Fetch-Site': 'cross-site' } }), 403, 'forbidden');
  expect(await request(app, { method: 'OPTIONS', headers: { Origin: 'https://untrusted.example', 'Access-Control-Request-Method': 'POST' } }), 403, 'forbidden');
  const preflight = await request(app, { method: 'OPTIONS', headers: { Origin: app.origin, 'Access-Control-Request-Method': 'POST' } });
  expect(preflight, 204);
  assert.equal(preflight.headers.get('allow'), 'GET, POST, OPTIONS');
  expect(await request(app, { token: app.owner, query: '?id=' + created.id, headers: { Origin: app.origin } }), 200);
  expect(await request(app, { method: 'DELETE', token: app.owner }), 405, 'method_not_allowed');
});

test('real hosted HTTP handler reports missing database configuration without leaking credentials', async t => {
  const app = await start(t, { hosted: true });
  const response = await get(app, app.owner);
  expect(response, 503, 'unavailable');
  assert.equal(JSON.stringify(response.body).includes('SUPABASE'), false);
  assert.equal(JSON.stringify(response.body).includes(app.owner), false);
});

test('real local invite deletion removes its private aggregate and revokes both participants', async t => {
  const app = await start(t);
  const { created, partner } = await setup(app);
  expect(await request(app, { route: '/rest/v1/rpc/delete_own_invite', body: { p_invite_id: app.inviteId, p_owner_token: app.owner } }), 200);
  expect(await get(app, app.owner, created.id), 403, 'forbidden');
  expect(await get(app, partner, created.id), 403, 'forbidden');
  const saved = JSON.parse(fs.readFileSync(path.join(app.dir, 'date_plans.json'), 'utf8'));
  assert.equal(Object.hasOwn(saved, created.id), false, 'local deletion mirrors PostgreSQL ON DELETE CASCADE');
});
