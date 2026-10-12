import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { handleAccountRequest, type AccountActor } from '../src/account';
import { PairService, pairTokenHash } from '../src/pair';
import { handleTogetherRequest } from '../src/together';
import { createAuth, type AuthEnvironment } from '../src/auth';
import { handleRequest } from '../src/index';
type Json = Record<string, unknown>;
const id = () => crypto.randomUUID();
async function user(age = 0): Promise<AccountActor> {
  const actor = { id: id(), email: `${id()}@example.test`, sessionId: id(), sessionCreatedAt: new Date(Date.now() - age).toISOString() };
  const created = actor.sessionCreatedAt;
  await env.DB.prepare('INSERT INTO "user"(id,name,email,emailVerified,image,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?)')
    .bind(actor.id, 'Private Name', actor.email, 1, 'https://example.test/private-avatar.png', created, created).run();
  await env.DB.prepare('INSERT INTO "session"(id,token,userId,createdAt,updatedAt,expiresAt,ipAddress,userAgent) VALUES(?,?,?,?,?,?,?,?)')
    .bind(actor.sessionId, id(), actor.id, created, created, new Date(Date.now() + 86400000).toISOString(), '203.0.113.8', 'Private device').run();
  await new PairService(env.DB).status(actor.id);
  return actor;
}
async function pair(a: AccountActor, b: AccountActor) {
  const service = new PairService(env.DB);
  const token = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  const made = await service.execute(a.id, 'hamtdaa_create_pair_invite', { p_command_id: id(), p_token_hash: await pairTokenHash(token) });
  const invitation = made.invitation as Json;
  const requested = await service.execute(b.id, 'hamtdaa_request_pair', { p_command_id: id(), p_token: token, p_expected_version: invitation.version });
  const command = id();
  const confirmed = await service.execute(a.id, 'hamtdaa_confirm_pair', { p_command_id: command, p_invitation_id: invitation.id, p_expected_version: (requested.invitation as Json).version });
  expect(confirmed.ok).toBe(true);
  return { id: confirmed.pair_id as string, invitation: invitation.id as string, command, service };
}
async function invoke(actor: AccountActor, action = 'export', body: unknown = {}, db = env.DB) {
  const response = await handleAccountRequest(new Request(`https://auth.test/v1/account/${action}`, { method: 'POST' }), { DB: db, BETTER_AUTH_SECRET: env.BETTER_AUTH_SECRET }, actor, body);
  return { response, status: response.status, data: await response.json<Json>() };
}
const erase = (actor: AccountActor, db = env.DB) => invoke(actor, 'delete', { confirmation: 'УСТГАХ' }, db);
async function count(table: string, where: string, ...values: (string | number)[]) {
  return (await env.DB.prepare(`SELECT count(*) n FROM ${table} WHERE ${where}`).bind(...values).first<{ n: number }>())!.n;
}
async function event(actor: AccountActor, pairId: string, title = 'Private date') {
  const eventId = id();
  await env.DB.prepare(`INSERT INTO hamtdaa_calendar_events(id,pair_id,creator_id,title,note,location,starts_at,created_at,updated_at)
    VALUES(?,?,?,?,?,?,?,?,?)`).bind(eventId, pairId, actor.id, title, 'Private note', 'Private place', Date.now(), Date.now(), Date.now()).run();
  return eventId;
}
async function answer(actor: AccountActor, pairId: string, day = '2026-10-06', text = 'Private answer') {
  await env.DB.prepare('INSERT INTO hamtdaa_daily_answers(pair_id,day,user_id,question_id,answer,created_at) VALUES(?,?,?,?,?,?)')
    .bind(pairId, day, actor.id, `question-${day}`, text, Date.now()).run();
}
async function billing(actor: AccountActor) {
  const order = id(); const source = `pi_${id()}`; const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(`INSERT INTO hamtdaa_billing_orders(id,user_id,command_id,plan,duration_seconds,amount_minor,livemode,
    return_url,description,provider_id,state,checkout_url,next_action,created_at,updated_at)
    VALUES(?,?,?,'monthly',2592000,990000,1,'https://auth.test/plans','Plus',?,'succeeded','https://pay.wire.mn/c/private-token','{"secret":"private-next"}',?,?)`)
    .bind(order, actor.id, id(), source, now, now).run();
  await env.DB.prepare(`INSERT INTO hamtdaa_billing_grants(provider,source_id,user_id,transaction_id,product_id,starts_at,expires_at,observed_at,refresh_cipher)
    VALUES('apple',?,?,?,'mn.moch.hamtdaa.plus.monthly',?,?,?,'private-encrypted-proof')`)
    .bind(source, actor.id, source, now, now + 3600, Date.now()).run();
  await env.DB.prepare(`INSERT INTO hamtdaa_billing_transactions(provider,environment,transaction_id,source_id,user_id) VALUES('apple','Production',?,?,?)`)
    .bind(source, source, actor.id).run();
  return { order, source };
}
function beforeBatch(work: () => Promise<void>): D1Database {
  let ran = false;
  return new Proxy(env.DB, { get(target, key) {
    if (key === 'batch') return async (statements: D1PreparedStatement[]) => { if (!ran) { ran = true; await work(); } return target.batch(statements); };
    const value = Reflect.get(target, key); return typeof value === 'function' ? value.bind(target) : value;
  } });
}

describe('Cloudflare account export and deletion on real D1', () => {
  it('deletes through the complete native HTTP API after a real OTP-created ISO session', async () => {
    const email = `${id()}@example.test`;
    const deliveries: EmailMessageBuilder[] = [];
    const config: AuthEnvironment = { ...env, SIGNUP_ENABLED: 'true', EMAIL: { async send(message) {
      if ('subject' in message) deliveries.push(message); return { messageId: id() };
    } } };
    let token: string | undefined;
    const call = (path: string, body?: Json) => handleRequest(new Request(`https://auth.test${path}`, {
      method: body ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': '203.0.113.231',
        ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    }), config);
    expect((await call('/v1/auth/request-code', { email })).status).toBe(200);
    const code = deliveries.at(-1)!.text!.match(/\b\d{6}\b/)![0];
    const verified = await call('/v1/auth/verify-code', { email, code });
    expect(verified.status).toBe(200);
    const session = await verified.json<Json>();
    token = session.token as string;
    const actorId = (session.user as Json).id as string;
    const native = await env.DB.prepare('SELECT typeof(createdAt) kind,createdAt,expiresAt FROM "session" WHERE userId=?')
      .bind(actorId).first<{ kind: string; createdAt: string; expiresAt: string }>();
    expect(native!.kind).toBe('text');
    expect(native!.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    expect(Date.parse(native!.expiresAt)).toBeGreaterThan(Date.now());
    expect((await call('/v1/together/state', { month: '2026-10' })).status).toBe(200);
    expect((await call('/v1/account/export', {})).status).toBe(200);
    const deleted = await call('/v1/account/delete', { confirmation: 'УСТГАХ' });
    expect(deleted.status).toBe(200);
    expect(await deleted.json()).toMatchObject({ ok: true, deleted: true });
    expect((await call('/v1/auth/session')).status).toBe(401);
    expect(await count('"session"', 'userId=?', actorId)).toBe(0);
    expect(await count('"user"', 'email=?', email)).toBe(0);
  });
  it('exports own profile and current pair without credentials or partner email', async () => {
    const a = await user(), b = await user(); const linked = await pair(a, b);
    const result = await invoke(a);
    expect(result.status).toBe(200);
    expect(result.response.headers.get('cache-control')).toContain('no-store');
    const data = result.data.export as Json;
    expect(data.account).toMatchObject({ id: a.id, email: a.email, name: 'Private Name' });
    expect(data.pair).toMatchObject({ id: linked.id, partner_id: b.id });
    const serialized = JSON.stringify(data);
    expect(serialized).not.toContain(b.email);
    expect(serialized).not.toContain('Private device');
    expect(data.sections).toEqual(['profile', 'calendar', 'daily_answers', 'billing_orders', 'billing_subscriptions']);
  });
  it('exports a partner answer only after both answer the same question', async () => {
    const a = await user(), b = await user(); const linked = await pair(a, b);
    await answer(b, linked.id, '2026-10-06', 'Partner secret');
    expect(((await invoke(a, 'export', { section: 'daily_answers' })).data.export as Json).data).toEqual([]);
    await answer(a, linked.id, '2026-10-06', 'My answer');
    expect((((await invoke(a, 'export', { section: 'daily_answers' })).data.export as Json).data as Json[])).toHaveLength(2);
    await answer(b, linked.id, '2026-10-07', 'Different question secret');
    await env.DB.prepare('INSERT INTO hamtdaa_daily_answers(pair_id,day,user_id,question_id,answer,created_at) VALUES(?,?,?,?,?,?)')
      .bind(linked.id, '2026-10-07', a.id, 'different-question', 'Mine', Date.now()).run();
    expect(JSON.stringify((await invoke(a, 'export', { section: 'daily_answers' })).data)).not.toContain('Different question secret');
  });
  it('keeps only own historical data exportable after unlink and re-pair', async () => {
    const a = await user(), b = await user(), c = await user(); const old = await pair(a, b);
    await event(a, old.id, 'My old date'); await event(b, old.id, 'Ex private date');
    await answer(a, old.id, undefined, 'Mine'); await answer(b, old.id, undefined, 'Ex answer');
    expect((await old.service.execute(a.id, 'hamtdaa_unlink_pair', { p_command_id: id(), p_pair_id: old.id, p_expected_version: 1 })).ok).toBe(true);
    const next = await pair(a, c); await event(c, next.id, 'Current shared date');
    const calendar = JSON.stringify((await invoke(a, 'export', { section: 'calendar' })).data);
    expect(calendar).toContain('My old date'); expect(calendar).toContain('Current shared date'); expect(calendar).not.toContain('Ex private date');
    const answers = JSON.stringify((await invoke(a, 'export', { section: 'daily_answers' })).data);
    expect(answers).toContain('Mine'); expect(answers).not.toContain('Ex answer');
  });
  it('keyset paginates all rows and does not trust cursor identity', async () => {
    const a = await user(), b = await user(), outside = await user(); const linked = await pair(a, b);
    for (let i = 0; i < 53; i++) await event(a, linked.id, `Date ${i}`);
    const first = (await invoke(a, 'export', { section: 'calendar' })).data.export as Json;
    expect((first.data as Json[])).toHaveLength(50); expect(first.next_cursor).toBeTypeOf('string');
    const second = (await invoke(a, 'export', { section: 'calendar', cursor: first.next_cursor })).data.export as Json;
    expect((second.data as Json[])).toHaveLength(3); expect(second.next_cursor).toBeNull();
    expect(new Set([...(first.data as Json[]), ...(second.data as Json[])].map(row => row.id)).size).toBe(53);
    const foreign = (await invoke(outside, 'export', { section: 'calendar', cursor: first.next_cursor })).data.export as Json;
    expect(foreign.data).toEqual([]);
    expect((await invoke(a, 'export', { section: 'daily_answers', cursor: first.next_cursor })).status).toBe(400);
  });
  it('exports financial receipts but excludes provider proof and checkout secrets', async () => {
    const a = await user(); await billing(a);
    const receipt = await invoke(a, 'export', { section: 'billing_orders' });
    const subscription = await invoke(a, 'export', { section: 'billing_subscriptions' });
    const serialized = JSON.stringify([receipt.data, subscription.data]);
    expect(serialized).toContain('990000'); expect(serialized).toContain('mn.moch.hamtdaa.plus.monthly');
    for (const secret of ['private-token', 'private-next', 'private-encrypted-proof', 'refresh_cipher', 'checkout_url']) expect(serialized).not.toContain(secret);
  });
  it('rejects forged input, missing actor and stale/future deletion sessions', async () => {
    const a = await user();
    for (const body of [null, [], { user_id: a.id }, { section: 'all' }, { section: 'profile', cursor: 'broken' }]) expect((await invoke(a, 'export', body)).status).toBe(400);
    for (const body of [{}, { confirmation: 'DELETE' }, { confirmation: 'УСТГАХ', actor: a.id }]) expect((await invoke(a, 'delete', body)).status).toBe(400);
    for (const created of [new Date(Date.now() - 601000).toISOString(), new Date(Date.now() + 60000).toISOString(), 'invalid']) {
      expect((await erase({ ...a, sessionCreatedAt: created })).data.code).toBe('reauthentication_required');
    }
    expect((await invoke({ ...a, id: id() })).status).toBe(401);
    expect((await invoke({ ...a, email: 'wrong@example.test' })).status).toBe(401);
    expect(await count('"user"', 'email=?', a.email)).toBe(1);
  });
  it('atomically erases personal/authored content and unlinks partner while retaining opaque accounting', async () => {
    const a = await user(), b = await user(); const linked = await pair(a, b); const payment = await billing(a);
    await event(a, linked.id, 'Delete mine'); const theirs = await event(b, linked.id, 'Keep partner authored');
    await answer(a, linked.id); await answer(b, linked.id);
    await env.DB.prepare('INSERT INTO "account"(id,accountId,providerId,userId,accessToken,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?)')
      .bind(id(), 'private-provider-account', 'test', a.id, 'private-access-token', Date.now(), Date.now()).run();
    const result = await erase(a);
    expect(result.data).toMatchObject({ ok: true, deleted: true });
    const scrubbed = await env.DB.prepare('SELECT * FROM "user" WHERE id=?').bind(a.id).first<Json>();
    expect(scrubbed).toMatchObject({ name: 'Deleted account', emailVerified: 0, image: null });
    expect(scrubbed!.email).toMatch(/^deleted-.*@deleted\.invalid$/);
    expect(await count('"user"', 'email=?', a.email)).toBe(0);
    expect(await count('"session"', 'userId=?', a.id)).toBe(0); expect(await count('"account"', 'userId=?', a.id)).toBe(0);
    expect(await count('hamtdaa_calendar_events', 'creator_id=?', a.id)).toBe(0);
    expect(await count('hamtdaa_calendar_events', 'id=?', theirs)).toBe(1);
    expect(await count('hamtdaa_daily_answers', 'user_id=?', a.id)).toBe(0);
    expect(await count('hamtdaa_pair_members', 'user_id=?', a.id)).toBe(0);
    expect(await count('hamtdaa_pair_members', 'pair_id=? AND revoked_at IS NULL', linked.id)).toBe(0);
    expect(await count('hamtdaa_pair_receipts', 'user_id=?', a.id)).toBe(0);
    expect((await linked.service.status(b.id)).pair).toBeNull();
    expect(await env.DB.prepare('SELECT refresh_cipher,is_active FROM hamtdaa_billing_grants WHERE source_id=?').bind(payment.source).first())
      .toEqual({ refresh_cipher: null, is_active: 0 });
    expect(await env.DB.prepare('SELECT checkout_url,next_action,state FROM hamtdaa_billing_orders WHERE id=?').bind(payment.order).first())
      .toEqual({ checkout_url: null, next_action: null, state: 'succeeded' });
    expect(await count('hamtdaa_billing_transactions', 'user_id=?', a.id)).toBe(1);
    expect((await erase(a)).status).toBe(401); expect((await invoke(a)).status).toBe(401);
    const c = await user(); expect((await pair(b, c)).id).toBeTruthy();
  });
  it('fences delayed auth/session and native billing writes after deletion', async () => {
    const a = await user(); const payment = await billing(a); expect((await erase(a)).status).toBe(200);
    await expect(env.DB.prepare('INSERT INTO "session"(id,token,userId,createdAt,updatedAt,expiresAt) VALUES(?,?,?,?,?,?)')
      .bind(id(), id(), a.id, Date.now(), Date.now(), Date.now() + 3600000).run()).rejects.toThrow('account_deleted');
    await expect(env.DB.prepare('UPDATE "user" SET emailVerified=1 WHERE id=?').bind(a.id).run()).rejects.toThrow('account_deleted');
    await expect(env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='active' WHERE user_id=?").bind(a.id).run()).rejects.toThrow('account_deleted');
    await env.DB.prepare("UPDATE hamtdaa_billing_grants SET refresh_cipher='late-proof',is_active=1 WHERE source_id=?").bind(payment.source).run();
    expect(await env.DB.prepare('SELECT refresh_cipher,is_active FROM hamtdaa_billing_grants WHERE source_id=?').bind(payment.source).first()).toEqual({ refresh_cipher: null, is_active: 0 });
    await env.DB.prepare("UPDATE hamtdaa_billing_orders SET checkout_url='https://pay.wire.mn/c/late',next_action='{}',state='refunded' WHERE id=?").bind(payment.order).run();
    expect(await env.DB.prepare('SELECT checkout_url,next_action,state FROM hamtdaa_billing_orders WHERE id=?').bind(payment.order).first()).toEqual({ checkout_url: null, next_action: null, state: 'refunded' });
  });
  it('does not weaken checkout immutability for active accounts', async () => {
    const a = await user(); const payment = await billing(a);
    await expect(env.DB.prepare('UPDATE hamtdaa_billing_orders SET checkout_url=NULL WHERE id=?').bind(payment.order).run()).rejects.toThrow('billing_order_immutable');
  });
  it('rolls the whole deletion back on a storage failure', async () => {
    const a = await user(), b = await user(); const linked = await pair(a, b); await event(a, linked.id);
    await env.DB.exec("CREATE TRIGGER test_account_failure BEFORE DELETE ON hamtdaa_calendar_events BEGIN SELECT RAISE(ABORT,'test_failure'); END;");
    try { expect((await erase(a)).status).toBe(503); }
    finally { await env.DB.exec('DROP TRIGGER test_account_failure;'); }
    expect(await count('hamtdaa_deleted_accounts', 'user_id=?', a.id)).toBe(0);
    expect(await count('"user"', 'email=? AND emailVerified=1', a.email)).toBe(1);
    expect(await count('"session"', 'userId=?', a.id)).toBe(1);
    expect((await linked.service.status(b.id)).pair).not.toBeNull();
    expect((await erase(a)).status).toBe(200);
  });
  it('rechecks session and pair visibility at transaction time', async () => {
    const a = await user(), b = await user(); const linked = await pair(a, b); await event(b, linked.id, 'Partner only');
    const unlinked = beforeBatch(async () => { expect((await linked.service.execute(a.id, 'hamtdaa_unlink_pair', { p_command_id: id(), p_pair_id: linked.id, p_expected_version: 1 })).ok).toBe(true); });
    expect(((await invoke(a, 'export', { section: 'calendar' }, unlinked)).data.export as Json).data).toEqual([]);
    const revoked = beforeBatch(async () => { await env.DB.prepare('DELETE FROM "session" WHERE userId=?').bind(a.id).run(); });
    expect((await erase(a, revoked)).data.code).toBe('reauthentication_required');
    expect(await count('"user"', 'email=? AND emailVerified=1', a.email)).toBe(1);
  });
  it('rejects an in-flight calendar mutation after the deletion transaction', async () => {
    const a = await user(), b = await user(); const linked = await pair(a, b);
    const body = { command_id: id(), expected_pair_id: linked.id, title: 'Late private content', note: '', location: '', starts_at: '2026-10-16T12:00:00Z', ends_at: null };
    const db = beforeBatch(async () => { expect((await erase(a)).status).toBe(200); });
    const response = await handleTogetherRequest(new Request('https://auth.test/v1/together/calendar/create', { method: 'POST' }), { DB: db }, a.id, body);
    expect(response.status).not.toBe(200);
    expect(await count('hamtdaa_calendar_events', 'creator_id=?', a.id)).toBe(0);
    expect(await count('hamtdaa_together_receipts', 'user_id=?', a.id)).toBe(0);
  });
  it('cannot substitute another live session created in the same millisecond', async () => {
    const a = await user(); const created = a.sessionCreatedAt; const secondId = id();
    await env.DB.prepare('INSERT INTO "session"(id,token,userId,createdAt,updatedAt,expiresAt) VALUES(?,?,?,?,?,?)')
      .bind(secondId, id(), a.id, created, created, new Date(Date.now() + 3600000).toISOString()).run();
    const revoked = beforeBatch(async () => { await env.DB.prepare('DELETE FROM "session" WHERE id=?').bind(a.sessionId).run(); });
    expect((await erase(a, revoked)).data.code).toBe('reauthentication_required');
    expect(await count('hamtdaa_deleted_accounts', 'user_id=?', a.id)).toBe(0);
    expect(await count('"session"', 'id=?', secondId)).toBe(1);
    expect((await erase({ ...a, sessionId: secondId })).status).toBe(200);
  });
  it('removes the existing OTP only and permits original email to register a new identity', async () => {
    const a = await user(), other = await user(); const deliveries: EmailMessageBuilder[] = [];
    const config: AuthEnvironment = { ...env, SIGNUP_ENABLED: 'true', EMAIL: { async send(message) {
      if ('subject' in message) deliveries.push(message); return { messageId: id() };
    } } };
    const auth = createAuth(config);
    const send = (email: string, otp?: string) => auth.handler(new Request(`https://auth.test/api/auth/${otp ? 'sign-in/email-otp' : 'email-otp/send-verification-otp'}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': '203.0.113.230' },
      body: JSON.stringify(otp ? { email, otp } : { email, type: 'sign-in' }),
    }));
    expect((await send(a.email)).status).toBe(200);
    const oldCode = deliveries.at(-1)!.text!.match(/\b\d{6}\b/)![0];
    expect((await send(other.email)).status).toBe(200);
    const otherCode = deliveries.at(-1)!.text!.match(/\b\d{6}\b/)![0];
    expect((await erase(a)).status).toBe(200);
    expect((await send(a.email, oldCode)).status).not.toBe(200);
    expect((await send(other.email, otherCode)).status).toBe(200);
    expect((await send(a.email)).status).toBe(200);
    const newCode = deliveries.at(-1)!.text!.match(/\b\d{6}\b/)![0];
    const registration = await send(a.email, newCode); expect(registration.status).toBe(200);
    expect((await registration.json<{ user: { id: string } }>()).user.id).not.toBe(a.id);
  });
});
