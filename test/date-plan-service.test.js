'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createDatePlanService } = require('../lib/date-plan-service');
const { createLocalDatePlanRepository, createSupabaseDatePlanRepository } = require('../lib/date-plan-repository');

const catalog = { get: id => id === 'coffee' ? { id, title: 'Кофены болзоо', steps: ['before', 'together', 'after'].map(id => ({ id, title: id, description: 'Хамт хийх зүйл' })) } : null };
const secret = () => crypto.randomBytes(32).toString('hex');
const request = (action, extra = {}) => ({ action, invite_id: 'invite_demo_123', request_id: crypto.randomUUID(), ...extra });
const rejects = (promise, status, code) => assert.rejects(promise, error => error.status === status && (!code || error.code === code));

function fixture(t, config = {}) {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'bolzoo-plan-'));
  t.after(() => fs.rmSync(folder, { recursive: true, force: true }));
  let clock = Date.parse('2026-09-09T10:00:00Z');
  const owner = crypto.randomUUID(), claim = secret(), partner = secret();
  const invite = { id: 'invite_demo_123', owner_token: owner, config: { senderName: 'Нэг', recipientName: 'Хоёр', missionIdeaId: 'coffee', ...config } };
  const options = { file: path.join(folder, 'date_plans.json'), getInvite: id => id === invite.id ? invite : null, now: () => clock };
  const repo = createLocalDatePlanRepository(options);
  const service = createDatePlanService({ repo, catalog, now: () => clock });
  const createBody = request('create', { template_id: 'coffee', claim_token: claim });
  async function create() { return service.execute(createBody, owner); }
  async function claimPlan() { return service.execute(request('claim', { claim_token: claim, participant_token: partner })); }
  async function begin() {
    await create();
    let plan = await claimPlan();
    plan = await service.execute(request('accept', { expected_version: plan.version, expected_revision: plan.revision }), partner);
    return service.execute(request('start', { expected_version: plan.version }), owner);
  }
  return { service, repo, options, invite, owner, claim, partner, createBody, create, claimPlan, begin, advance: ms => { clock += ms; } };
}

test('private persisted plans require creator/claimed partner capabilities and redact every stored secret', async t => {
  const f = fixture(t);
  await rejects(f.service.get({ invite_id: f.invite.id }, ''), 403);
  await rejects(f.service.get({ invite_id: f.invite.id }, f.owner), 404, 'plan_not_found');
  const plan = await f.create();
  assert.equal(plan.role, 'creator');
  assert.equal(plan.state, 'proposed');
  assert.equal(plan.accepted.creator, 1);
  assert.equal(plan.partner_claimed, false);
  await rejects(f.service.get({ id: plan.id }, secret()), 403);
  const persisted = JSON.stringify(await f.repo.getByInvite(f.invite.id));
  assert.equal(persisted.includes(f.claim), false);
  assert.equal(persisted.includes(f.owner), false);
  const output = JSON.stringify(plan);
  for (const forbidden of ['token_hash', 'requests', 'memories', f.owner, f.claim]) assert.equal(output.includes(forbidden), false);
  const restarted = createDatePlanService({ repo: createLocalDatePlanRepository(f.options), catalog });
  assert.deepEqual(await restarted.get({ id: plan.id }, f.owner.toUpperCase()), plan);
  assert.equal(fs.statSync(f.options.file).mode & 0o777, 0o600);
});

test('create retries are idempotent, never overwrite existing proposals, and reject apologies', async t => {
  const f = fixture(t);
  const first = await f.create();
  assert.deepEqual(await f.create(), first);
  await rejects(f.service.execute({ ...f.createBody, title: 'different' }, f.owner), 409, 'replay_conflict');
  await rejects(f.service.execute(request('create', { claim_token: secret(), template_id: 'coffee' }), f.owner), 409, 'plan_exists');
  const apology = fixture(t, { experienceType: 'apology' });
  await rejects(apology.create(), 400, 'apology_invite');
  assert.equal(await apology.repo.getByInvite(apology.invite.id), null);
});

test('claims exchange one capability for one identity, tolerate retries, and reject another browser', async t => {
  const f = fixture(t); await f.create();
  const body = request('claim', { claim_token: f.claim, participant_token: f.partner });
  const plan = await f.service.execute(body);
  assert.equal(plan.role, 'partner');
  assert.equal(plan.partner_claimed, true);
  assert.deepEqual(await f.service.execute(body), plan);
  assert.deepEqual(await f.claimPlan(), plan);
  await rejects(f.service.execute(request('claim', { claim_token: f.claim, participant_token: secret() })), 409, 'claim_used');
  await rejects(f.service.execute(request('claim', { claim_token: secret(), participant_token: secret() })), 403);
  await rejects(f.service.get({ invite_id: f.invite.id }, f.claim), 403);
  assert.equal((await f.service.get({ invite_id: f.invite.id }, f.partner)).role, 'partner');
});

test('consent follows exact revisions; proposed changes revoke consent before a date can start', async t => {
  const f = fixture(t); await f.create();
  let plan = await f.claimPlan();
  await rejects(f.service.execute(request('start', { expected_version: plan.version }), f.owner), 409, 'invalid_state');
  plan = await f.service.execute(request('accept', { expected_version: plan.version, expected_revision: plan.revision }), f.partner);
  assert.equal(plan.state, 'agreed');
  plan = await f.service.execute(request('propose', { expected_version: plan.version, location: 'Нийтийн кофе шоп', scheduled_at: '2026-09-10T19:00:00+08:00' }), f.partner);
  assert.equal(plan.revision, 2);
  assert.equal(plan.state, 'proposed');
  assert.deepEqual(plan.accepted, { creator: null, partner: 2 });
  assert.equal(plan.scheduled_at, '2026-09-10T11:00:00.000Z');
  await rejects(f.service.execute(request('accept', { expected_version: plan.version, expected_revision: 1 }), f.owner), 409, 'conflict');
  plan = await f.service.execute(request('accept', { expected_version: plan.version, expected_revision: 2 }), f.owner);
  plan = await f.service.execute(request('start', { expected_version: plan.version }), f.partner);
  assert.equal(plan.state, 'in_progress');
  await rejects(f.service.execute(request('propose', { expected_version: plan.version, location: 'Changed' }), f.owner), 409, 'invalid_state');
});

test('each person controls only their outcomes and private memory; ending never requires completing tasks', async t => {
  const f = fixture(t); let plan = await f.begin();
  plan = await f.service.execute(request('outcome', { expected_version: plan.version, step_id: 'before', outcome: 'skipped' }), f.owner);
  assert.deepEqual(plan.steps[0].outcomes, { creator: 'skipped', partner: 'todo' });
  plan = await f.service.execute(request('outcome', { expected_version: plan.version, step_id: 'before', outcome: 'adapted' }), f.partner);
  assert.deepEqual(plan.steps[0].outcomes, { creator: 'skipped', partner: 'adapted' });
  plan = await f.service.execute(request('memory', { expected_version: plan.version, text: 'Миний хувийн дурсамж' }), f.owner);
  assert.equal(plan.my_memory, 'Миний хувийн дурсамж');
  assert.equal((await f.service.get({ invite_id: f.invite.id }, f.partner)).my_memory, '');
  plan = await f.service.execute(request('end', { expected_version: plan.version }), f.partner);
  assert.equal(plan.state, 'ended');
  plan = await f.service.execute(request('memory', { expected_version: plan.version, text: 'Нөгөө хүний тэмдэглэл' }), f.partner);
  assert.equal(plan.my_memory, 'Нөгөө хүний тэмдэглэл');
  assert.equal((await f.service.get({ invite_id: f.invite.id }, f.owner)).my_memory, 'Миний хувийн дурсамж');
  await rejects(f.service.execute(request('start', { expected_version: plan.version }), f.owner), 409, 'invalid_state');
  await rejects(f.service.execute(request('outcome', { expected_version: plan.version, step_id: 'after', outcome: 'done' }), f.owner), 409, 'invalid_state');
});

test('stale writes and simultaneous writes cannot silently overwrite another person', async t => {
  const f = fixture(t); let plan = await f.begin();
  const ownerBody = request('outcome', { expected_version: plan.version, step_id: 'before', outcome: 'done' });
  const partnerBody = request('outcome', { expected_version: plan.version, step_id: 'together', outcome: 'skipped' });
  const results = await Promise.allSettled([f.service.execute(ownerBody, f.owner), f.service.execute(partnerBody, f.partner)]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(results.find(result => result.status === 'rejected').reason.code, 'conflict');
  plan = await f.service.get({ invite_id: f.invite.id }, f.owner);
  assert.equal(plan.version, ownerBody.expected_version + 1);
  await rejects(f.service.execute(request('memory', { expected_version: ownerBody.expected_version, text: 'old' }), f.owner), 409, 'conflict');
});

test('simultaneous identical mutations are replayed once, and changed retries are rejected', async t => {
  const f = fixture(t); const plan = await f.begin();
  const body = request('memory', { expected_version: plan.version, text: 'Нэг л удаа' });
  const [first, second] = await Promise.all([f.service.execute(body, f.owner), f.service.execute(body, f.owner)]);
  assert.deepEqual(first, second);
  assert.equal(first.version, plan.version + 1);
  await rejects(f.service.execute({ ...body, text: 'Changed' }, f.owner), 409, 'replay_conflict');
  await rejects(f.service.execute(body, f.partner), 409, 'replay_conflict');
});

test('claim rotation revokes the old partner and both old invitation capabilities, resetting consent', async t => {
  const f = fixture(t); await f.create(); let plan = await f.claimPlan();
  plan = await f.service.execute(request('accept', { expected_version: plan.version, expected_revision: plan.revision }), f.partner);
  const nextClaim = secret();
  await rejects(f.service.execute(request('rotate_claim', { expected_version: plan.version, claim_token: nextClaim }), f.partner), 403);
  plan = await f.service.execute(request('rotate_claim', { expected_version: plan.version, claim_token: nextClaim }), f.owner);
  assert.equal(plan.state, 'proposed');
  assert.equal(plan.partner_claimed, false);
  assert.deepEqual(plan.accepted, { creator: 2, partner: null });
  await rejects(f.service.get({ invite_id: f.invite.id }, f.partner), 403);
  await rejects(f.claimPlan(), 403);
  const nextPartner = secret();
  const claimed = await f.service.execute(request('claim', { claim_token: nextClaim, participant_token: nextPartner }));
  assert.equal(claimed.role, 'partner');
});

test('decline/cancel are terminal and either participant may stop without finishing tasks', async t => {
  for (const action of ['decline', 'cancel']) {
    const f = fixture(t); await f.create(); let plan = await f.claimPlan();
    plan = await f.service.execute(request(action, { expected_version: plan.version }), f.partner);
    assert.equal(plan.state, action === 'decline' ? 'declined' : 'cancelled');
    await rejects(f.service.execute(request('accept', { expected_version: plan.version, expected_revision: plan.revision }), f.owner), 409);
    await rejects(f.service.execute(request('rotate_claim', { expected_version: plan.version, claim_token: secret() }), f.owner), 409);
  }
  const f = fixture(t); const plan = await f.begin();
  assert.equal((await f.service.execute(request('cancel', { expected_version: plan.version }), f.partner)).state, 'cancelled');
});

test('expired plans deny reads and mutation retries; an expired link cannot claim a participant', async t => {
  const f = fixture(t); await f.create();
  f.advance(180 * 86400000);
  await rejects(f.service.get({ invite_id: f.invite.id }, f.owner), 410, 'expired');
  await rejects(f.create(), 410, 'expired');
  await rejects(f.claimPlan(), 410, 'expired');
});

test('strict validation rejects invalid dates, injected identities, arbitrary templates and unbounded text', async t => {
  const f = fixture(t);
  for (const extra of [
    { template_id: 'not-real' }, { scheduled_at: '2026-02-31T10:00:00Z' }, { scheduled_at: '2026-09-10T19:00' },
    { title: '' }, { location: 'x'.repeat(241) }, { budget: {} }, { role: 'partner' }, { owner_token: f.owner },
    { claim_token: crypto.randomUUID() }, { steps: [{ id: 'before', text: 'only one' }] }
  ]) await rejects(f.service.execute({ ...f.createBody, ...extra }, f.owner), 400, 'invalid_request');
  let plan = await f.begin();
  await rejects(f.service.execute(request('outcome', { expected_version: plan.version, role: 'partner', step_id: 'before', outcome: 'done' }), f.owner), 400);
  await rejects(f.service.execute(request('memory', { expected_version: plan.version, text: 'x'.repeat(2001) }), f.owner), 400);
});

test('local storage corruption fails closed and never silently resets private plans', async t => {
  const f = fixture(t); await f.create();
  fs.writeFileSync(f.options.file, '{broken');
  await assert.rejects(f.repo.getByInvite(f.invite.id), SyntaxError);
  assert.equal(fs.readFileSync(f.options.file, 'utf8'), '{broken');
});

test('Supabase adapter uses atomic RPCs and parameterized encoded row filters', async () => {
  const calls = [];
  const row = { id: crypto.randomUUID(), invite_id: 'invite_demo_123', version: 1, document: {} };
  const repo = createSupabaseDatePlanRepository({ fetch: async (...args) => { calls.push(args); return [row]; } });
  assert.deepEqual(await repo.create(row), row);
  assert.deepEqual(calls[0], ['POST', '/rpc/create_date_plan', { p_id: row.id, p_invite_id: row.invite_id, p_document: {} }]);
  await repo.commit(row.id, 4, { value: 1 });
  assert.deepEqual(calls[1], ['POST', '/rpc/commit_date_plan', { p_id: row.id, p_expected_version: 4, p_document: { value: 1 } }]);
  await repo.getByInvite('a&select=*');
  assert.equal(new URL(calls[2][1], 'https://example.test').searchParams.get('invite_id'), 'eq.a&select=*');
  const conflictRepo = createSupabaseDatePlanRepository({ fetch: async () => [] });
  assert.equal(await conflictRepo.commit(row.id, 1, {}), null);
});

test('unclaimed links expire after seven days but stable claimed identities can recover until plan expiry', async t => {
  const f = fixture(t); const initial = await f.create();
  assert.equal(Date.parse(initial.claim_expires_at) - Date.parse(initial.created_at), 7 * 86400000);
  f.advance(7 * 86400000);
  await rejects(f.claimPlan(), 410, 'claim_expired');
  const freshClaim = secret();
  const rotated = await f.service.execute(request('rotate_claim', { expected_version: initial.version, claim_token: freshClaim }), f.owner);
  assert.equal(Date.parse(rotated.claim_expires_at) - Date.parse(initial.claim_expires_at), 7 * 86400000);
  const claimBody = request('claim', { claim_token: freshClaim, participant_token: f.partner });
  const claimed = await f.service.execute(claimBody);
  f.advance(8 * 86400000);
  assert.deepEqual(await f.service.execute(claimBody), claimed);
  assert.deepEqual(await f.service.execute({ ...claimBody, request_id: crypto.randomUUID() }), claimed);
});

test('local invite deletion cascades its private plan and recorded audit never contains private text or tokens', async t => {
  const f = fixture(t); let plan = await f.begin();
  const body = request('memory', { expected_version: plan.version, text: 'private memo should not enter audit' });
  plan = await f.service.execute(body, f.owner);
  await f.service.execute(body, f.owner);
  const row = await f.repo.getByInvite(f.invite.id);
  assert.equal(row.document.audit.length, 5);
  assert.deepEqual(Object.keys(row.document.audit.at(-1)).sort(), ['action', 'at', 'revision', 'role']);
  assert.equal(JSON.stringify(row.document.audit).includes(body.text), false);
  assert.equal(row.document.template_version, 1);
  assert.equal(plan.template_version, 1);
  assert.equal(await f.repo.deleteByInvite(f.invite.id), true);
  assert.equal(await f.repo.getById(plan.id), null);
  assert.equal(await f.repo.deleteByInvite(f.invite.id), false);
});

test('saved template snapshots preserve their version when the live catalogue updates or retires an idea', async t => {
  const f = fixture(t); const original = await f.create();
  const updatedCatalog = { get: id => ['coffee', 'tea'].includes(id) ? {
    id, version: id === 'coffee' ? 2 : 3, title: 'Changed live title',
    steps: ['before', 'together', 'after'].map(id => ({ id, title: 'Changed ' + id }))
  } : null };
  const updatedService = createDatePlanService({ repo: f.repo, catalog: updatedCatalog });
  let plan = await updatedService.execute(request('propose', { expected_version: original.version, location: 'Updated location' }), f.owner);
  assert.equal(plan.template_version, 1);
  assert.equal(plan.title, original.title);
  assert.deepEqual(plan.steps, original.steps);
  const retiredService = createDatePlanService({ repo: f.repo, catalog: { get: () => null } });
  plan = await retiredService.execute(request('propose', { expected_version: plan.version, budget: 'Хамт тохирно' }), f.owner);
  assert.equal(plan.template_id, 'coffee');
  assert.equal(plan.template_version, 1);
  assert.deepEqual(plan.steps, original.steps);
  plan = await updatedService.execute(request('propose', { expected_version: plan.version, template_id: 'tea' }), f.owner);
  assert.equal(plan.template_version, 3);
  assert.equal(plan.title, 'Changed live title');
  assert.equal(plan.steps[0].text, 'Changed before');
});
