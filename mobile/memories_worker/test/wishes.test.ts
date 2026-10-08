import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { Miniflare, convertV4MiniflareOptions, Response as MFResponse } from 'miniflare';
import { handleWishesRequest } from '../src/wishes.js';

const PAIR = '10000000-0000-4000-8000-000000000001';
const OTHER_PAIR = '10000000-0000-4000-8000-000000000002';
let mf: Miniflare;
let db: D1Database;
type Wish = { id: string; version: number; creator_id: string; status: string; my_liked: boolean; partner_liked: boolean; event_id: string | null; event_starts_at: string | null; event_status: string | null; title: string };
type Payload = { ok: boolean; code?: string; wish: Wish; wishes: Wish[]; event_id: string; deleted: boolean; likes: { wish_id: string; liked: boolean }[] };
const command = () => crypto.randomUUID();
const createBody = (overrides = {}) => ({ expected_pair_id: PAIR, command_id: command(), title: 'Од харах', note: 'Хамтдаа', location: 'Тэрэлж', category: 'outdoor', budget: 'low', ...overrides });
const mutateBody = (wish: Wish, overrides = {}) => ({ expected_pair_id: PAIR, command_id: command(), id: wish.id, expected_version: wish.version, ...overrides });
const planBody = (wish: Wish, overrides = {}) => ({ ...mutateBody(wish), starts_at: '2026-10-01T08:00:00.000Z', ends_at: null, ...overrides });
async function request(path: string, body: unknown, actor = 'alice', headers: Record<string, string> = {}) {
  const response = await mf.dispatchFetch(`https://wishes.test/v1/wishes/${path}`, { method: 'POST', headers: { Authorization: `Bearer ${actor.padEnd(20, '_')}`, 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return new Response(await response.arrayBuffer(), { status: response.status, headers: response.headers });
}
async function payload(response: Response) { return await response.json() as Payload; }
async function success(path: string, body: unknown, actor = 'alice') { const r = await request(path, body, actor); const p = await payload(r); assert.equal(r.status, 200, JSON.stringify(p)); return p; }
async function newWish(overrides = {}, actor = 'alice') { return (await success('create', createBody(overrides), actor)).wish; }
async function mutual() { const wish = await newWish(); return (await success('like', mutateBody(wish, { liked: true }), 'bob')).wish; }
async function count(table: string) { return (await db.prepare(`SELECT count(*) n FROM ${table}`).first<{ n: number }>())!.n; }
async function cleanup() {
  await db.batch(['DELETE FROM hamtdaa_wishes', 'DELETE FROM hamtdaa_wish_receipts', 'DELETE FROM hamtdaa_wish_quotas', 'DELETE FROM hamtdaa_calendar_events', 'DELETE FROM hamtdaa_together_receipts', 'DELETE FROM hamtdaa_together_quotas', 'DELETE FROM hamtdaa_deleted_accounts', 'DELETE FROM hamtdaa_blocks', "UPDATE hamtdaa_profiles SET account_state='active'", 'UPDATE "user" SET emailVerified=1', "UPDATE hamtdaa_pairs SET state='active',unlinked_at=NULL", 'UPDATE hamtdaa_pair_members SET revoked_at=NULL'].map(sql => db.prepare(sql)));
}
before(async () => {
  mf = new Miniflare(convertV4MiniflareOptions({ modules: true, scriptPath: 'dist/index.js', compatibilityDate: '2026-10-08', compatibilityFlags: ['nodejs_compat'], d1Databases: ['DB'], r2Buckets: ['PHOTOS'], serviceBindings: { AUTH: async req => {
    const actor = req.headers.get('Authorization')!.slice(7).replace(/_+$/, '');
    if (actor === 'invalid') return new MFResponse('{}', { status: 401 });
    return MFResponse.json({ ok: true, user: { id: actor, email: `${actor}@example.test` }, expires_at: '2099-01-01T00:00:00Z' });
  } }}));
  // Miniflare exposes its cross-process D1 proxy with a different generic type.
  db = await mf.getD1Database('DB') as unknown as D1Database;
  for (const file of ['test/base.sql', '../cloudflare/migrations/0004_together.sql', 'migrations/0001_memories.sql', 'migrations/0002_wishes.sql']) {
    const statements: string[] = JSON.parse(execFileSync('python3', ['-c', 'import sqlite3,json,sys\nbuf=""; out=[]\nfor line in sys.stdin:\n buf+=line\n if sqlite3.complete_statement(buf):\n  out.append(buf); buf=""\nprint(json.dumps(out))'], { input: readFileSync(file, 'utf8'), encoding: 'utf8' }));
    for (const sql of statements) await db.prepare(sql).run();
  }
  for (const actor of ['alice', 'bob', 'mallory', 'eve']) {
    await db.prepare('INSERT INTO "user"(id,email,emailVerified) VALUES(?,?,1)').bind(actor, `${actor}@example.test`).run();
    await db.prepare('INSERT INTO hamtdaa_profiles(user_id) VALUES(?)').bind(actor).run();
  }
  for (const [pair, first, second] of [[PAIR, 'alice', 'bob'], [OTHER_PAIR, 'mallory', 'eve']]) {
    await db.prepare("INSERT INTO hamtdaa_pairs(id,state) VALUES(?,'active')").bind(pair).run();
    await db.prepare('INSERT INTO hamtdaa_pair_members(pair_id,user_id,slot) VALUES(?,?,1),(?,?,2)').bind(pair, first, pair, second).run();
  }
});
after(async () => { await mf?.dispose(); });

test('wish create/list are private, creator auto-likes, explicit likes and deletes are idempotent', async () => {
  await cleanup(); const body = createBody(); const a = await success('create', body); const wish = a.wish;
  assert.equal(wish.my_liked, true); assert.equal(wish.partner_liked, false); assert.equal(wish.status, 'idea');
  assert.equal((await success('create', body)).wish.id, wish.id);
  assert.equal((await request('create', { ...body, title: 'Changed' })).status, 409);
  const bobList = await success('list', { expected_pair_id: PAIR }, 'bob');
  assert.equal(bobList.wishes[0].my_liked, false); assert.equal(bobList.wishes[0].partner_liked, true);
  assert.equal((await request('list', { expected_pair_id: PAIR }, 'mallory')).status, 409);
  assert.equal((await request('list', { expected_pair_id: PAIR }, 'invalid')).status, 401);
  assert.equal((await request('list', { expected_pair_id: PAIR }, 'alice', { Origin: 'https://evil.test' })).status, 403);
  const like = mutateBody(wish, { liked: true });
  const liked = (await success('like', like, 'bob')).wish;
  assert.equal(liked.my_liked, true); assert.equal(liked.partner_liked, true);
  assert.equal((await success('like', like, 'bob')).wish.version, liked.version);
  assert.equal((await request('like', { ...like, liked: false }, 'bob')).status, 409);
  assert.equal((await request('delete', mutateBody(liked), 'bob')).status, 403);
  const deletion = mutateBody(liked); assert.equal((await success('delete', deletion)).deleted, true);
  assert.equal((await success('delete', deletion)).deleted, true); assert.equal(await count('hamtdaa_wish_likes'), 0);
  assert.equal((await request('create', body)).status, 410);
});

test('either partner plans a mutual wish into one compatible pending calendar invitation', async () => {
  for (const actor of ['alice', 'bob']) {
    await cleanup(); const wish = await mutual(); const body = planBody(wish);
    const planned = await success('plan', body, actor); const replay = await success('plan', body, actor);
    assert.equal(planned.event_id, replay.event_id); assert.equal(planned.wish.event_id, planned.event_id);
    assert.equal(planned.wish.event_status, 'pending'); assert.equal(planned.wish.event_starts_at, body.starts_at);
    const event = await db.prepare('SELECT * FROM hamtdaa_calendar_events WHERE id=?').bind(planned.event_id).first<{ creator_id: string; pair_id: string; title: string; status: string; version: number; starts_at: number }>();
    assert.equal(event!.creator_id, actor); assert.equal(event!.pair_id, PAIR); assert.equal(event!.title, wish.title); assert.equal(event!.status, 'pending'); assert.equal(event!.version, 1); assert.equal(event!.starts_at, Date.parse(body.starts_at));
    assert.equal(await count('hamtdaa_calendar_events'), 1); assert.equal(await count('hamtdaa_together_receipts'), 1);
    assert.equal((await request('plan', planBody(planned.wish), actor)).status, 409);
    assert.equal((await request('complete', mutateBody(planned.wish), actor)).status, 409);
    await db.prepare("UPDATE hamtdaa_calendar_events SET status='accepted' WHERE id=?").bind(planned.event_id).run();
    const done = await success('complete', mutateBody(planned.wish), actor === 'alice' ? 'bob' : 'alice'); assert.equal(done.wish.status, 'done');
  }
});

test('single like cannot plan, stale versions cannot overwrite and only accepted past plans complete', async () => {
  await cleanup(); const wish = await newWish();
  assert.equal((await payload(await request('plan', planBody(wish)))).code, 'mutual_like_required');
  assert.equal((await request('complete', mutateBody(wish))).status, 409);
  const liked = (await success('like', mutateBody(wish, { liked: true }), 'bob')).wish;
  assert.equal((await request('like', mutateBody(wish, { liked: false }))).status, 409);
  assert.equal((await request('plan', planBody(wish))).status, 409);
  const planned = await success('plan', planBody(liked, { starts_at: '2099-10-01T08:00:00Z' }));
  await db.prepare("UPDATE hamtdaa_calendar_events SET status='accepted' WHERE id=?").bind(planned.event_id).run();
  assert.equal((await request('complete', mutateBody(planned.wish))).status, 409);
  await db.prepare("UPDATE hamtdaa_calendar_events SET status='declined',starts_at=1 WHERE id=?").bind(planned.event_id).run();
  assert.equal((await request('complete', mutateBody(planned.wish))).status, 409);
  assert.equal((await request('like', mutateBody(planned.wish, { liked: false }))).status, 409);
});

test('concurrent planning by both partners cannot create duplicate events or receipts', async () => {
  await cleanup(); const wish = await mutual();
  const responses = await Promise.all([request('plan', planBody(wish), 'alice'), request('plan', planBody(wish), 'bob')]);
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 409]);
  assert.equal(await count('hamtdaa_calendar_events'), 1); assert.equal(await count('hamtdaa_together_receipts'), 1);
  assert.equal((await db.prepare("SELECT count(*) n FROM hamtdaa_wish_receipts WHERE operation='plan'").first<{ n: number }>())!.n, 1);
});

test('simultaneous identical retries commit once, and lost replies replay safely', async () => {
  await cleanup(); const body = createBody(); const created = await Promise.all([request('create', body), request('create', body)]);
  assert.deepEqual(created.map(r => r.status), [200, 200]); assert.equal(await count('hamtdaa_wishes'), 1);
  const wish = (await payload(created[0])).wish; const like = mutateBody(wish, { liked: true });
  const likes = await Promise.all([request('like', like, 'bob'), request('like', like, 'bob')]); assert.deepEqual(likes.map(r => r.status), [200, 200]);
  const liked = (await payload(likes[0])).wish; const plan = planBody(liked);
  const plans = await Promise.all([request('plan', plan), request('plan', plan)]); assert.deepEqual(plans.map(r => r.status), [200, 200]); assert.equal(await count('hamtdaa_calendar_events'), 1);
  const planned = (await payload(plans[0])).wish; const deletion = mutateBody(planned);
  const deletes = await Promise.all([request('delete', deletion), request('delete', deletion)]); assert.deepEqual(deletes.map(r => r.status), [200, 200]);
  assert.equal(await count('hamtdaa_calendar_events'), 1); assert.equal((await request('plan', plan)).status, 410);
});

test('calendar deletion resets planned idea, bumps version and preserves mutual likes', async () => {
  await cleanup(); const wish = await mutual(); const body = planBody(wish); const planned = await success('plan', body);
  await db.prepare('DELETE FROM hamtdaa_calendar_events WHERE id=?').bind(planned.event_id).run();
  const restored = (await success('list', { expected_pair_id: PAIR })).wishes[0];
  assert.equal(restored.status, 'idea'); assert.equal(restored.version, planned.wish.version + 1); assert.equal(restored.event_id, null); assert.equal(restored.event_starts_at, null); assert.equal(restored.my_liked, true); assert.equal(restored.partner_liked, true);
  assert.equal((await request('complete', mutateBody(planned.wish))).status, 409);
  assert.equal((await request('plan', body)).status, 410);
  assert.notEqual((await success('plan', planBody(restored))).event_id, planned.event_id);
});

test('export contains only authored text and own likes, never partner text or partner like state', async () => {
  await cleanup(); const own = await newWish(); const other = await newWish({ title: 'Partner private text' }, 'bob');
  await success('like', mutateBody(other, { liked: true }));
  const exported = await success('export', { expected_pair_id: PAIR });
  assert.equal(exported.wishes.length, 1); assert.equal(exported.wishes[0].id, own.id);
  assert.equal(JSON.stringify(exported).includes('Partner private text'), false); assert.equal(JSON.stringify(exported).includes('partner_liked'), false);
  assert.equal(exported.likes.length, 2); assert.ok(exported.likes.some(l => l.wish_id === other.id));
});

test('live pair restrictions, unlink and account deletion revoke and erase wish data', async () => {
  const changes = ["INSERT INTO hamtdaa_blocks VALUES('bob','alice')", "UPDATE hamtdaa_pair_members SET revoked_at=1 WHERE user_id='bob'", "UPDATE \"user\" SET emailVerified=0 WHERE id='bob'", "UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id='bob'", "INSERT INTO hamtdaa_deleted_accounts VALUES('bob',1)"];
  for (const sql of changes) {
    await cleanup(); const wish = await mutual(); await db.prepare(sql).run();
    assert.equal((await request('list', { expected_pair_id: PAIR })).status, 409);
    assert.equal((await request('plan', planBody(wish))).status, 409);
    assert.equal((await request('export', { expected_pair_id: PAIR })).status, 409);
  }
  await cleanup(); await mutual(); await newWish({}, 'bob');
  await db.prepare("INSERT INTO hamtdaa_deleted_accounts VALUES('alice',1)").run();
  assert.equal((await db.prepare("SELECT count(*) n FROM hamtdaa_wishes WHERE creator_id='alice'").first<{ n: number }>())!.n, 0);
  assert.equal((await db.prepare("SELECT count(*) n FROM hamtdaa_wish_likes WHERE user_id='alice'").first<{ n: number }>())!.n, 0);
  assert.equal((await db.prepare("SELECT count(*) n FROM hamtdaa_wish_receipts WHERE user_id='alice'").first<{ n: number }>())!.n, 0);
  await db.prepare("UPDATE hamtdaa_pairs SET state='unlinked',unlinked_at=1 WHERE id=?").bind(PAIR).run();
  assert.equal(await count('hamtdaa_wishes'), 0); assert.equal(await count('hamtdaa_wish_likes'), 0); assert.equal(await count('hamtdaa_wish_receipts'), 0);
  assert.equal((await db.prepare('PRAGMA foreign_key_check').all()).results.length, 0);
});

test('unlink immediately before commit rolls back event creation and command quotas', async () => {
  await cleanup(); const wish = await mutual(); let intercepted = false;
  const racingDb = new Proxy(db, { get(target, key) {
    if (key === 'batch') return async (statements: D1PreparedStatement[]) => {
      intercepted = true; await db.prepare("UPDATE hamtdaa_pairs SET state='unlinked',unlinked_at=1 WHERE id=?").bind(PAIR).run(); return db.batch(statements);
    };
    const value = Reflect.get(target, key); return typeof value === 'function' ? value.bind(target) : value;
  } });
  const response = await handleWishesRequest('plan', racingDb, 'alice', planBody(wish));
  assert.equal(intercepted, true); assert.equal(response.status, 409); assert.equal(await count('hamtdaa_calendar_events'), 0); assert.equal(await count('hamtdaa_together_receipts'), 0);
});

test('strict validation rejects forged scope, malformed text, dates and like values', async () => {
  await cleanup();
  for (const override of [{ creator_id: 'bob' }, { category: 'bad' }, { budget: 'bad' }, { title: 'x'.repeat(81) }, { title: '  ' }, { note: 'x'.repeat(501) }, { location: 'x'.repeat(121) }, { note: '\u0000secret' }, { command_id: 'invalid' }]) assert.equal((await request('create', createBody(override))).status, 400);
  assert.equal((await request('create', createBody({ expected_pair_id: OTHER_PAIR }))).status, 409);
  const wish = await mutual();
  assert.equal((await request('like', mutateBody(wish, { liked: 'true' }))).status, 400);
  assert.equal((await request('plan', planBody(wish, { starts_at: '2026-02-30T00:00:00Z' }))).status, 400);
  assert.equal((await request('plan', planBody(wish, { ends_at: '2026-09-01T00:00:00Z' }))).status, 400);
  assert.equal((await request('plan', planBody(wish, { ends_at: '2026-12-01T00:00:00Z' }))).status, 400);
  assert.equal((await request('delete', mutateBody(wish, { expected_pair_id: OTHER_PAIR }), 'mallory')).status, 404);
});

test('wish daily quota and calendar create quota are enforced without partial writes', async () => {
  await cleanup(); const wish = await mutual(); const date = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
  await db.prepare("UPDATE hamtdaa_wish_quotas SET mutations=100 WHERE user_id='alice'").run();
  assert.equal((await request('create', createBody())).status, 429);
  await db.prepare("UPDATE hamtdaa_wish_quotas SET mutations=1 WHERE user_id='alice'").run();
  await db.prepare('INSERT INTO hamtdaa_together_quotas VALUES(?,?,100)').bind('alice', date).run();
  assert.equal((await request('plan', planBody(wish))).status, 429); assert.equal(await count('hamtdaa_calendar_events'), 0);
  await db.prepare('DELETE FROM hamtdaa_together_quotas').run();
  await db.batch(Array.from({ length: 30 }, () => db.prepare("INSERT INTO hamtdaa_together_receipts VALUES(?,?,?,?,?,?,?)").bind('alice', command(), PAIR, 'a'.repeat(64), 'calendar/create', date, Date.now())));
  assert.equal((await request('plan', planBody(wish))).status, 429); assert.equal(await count('hamtdaa_calendar_events'), 0);
});

test('calendar capacity and wish active capacity cannot be exceeded', async () => {
  await cleanup(); const wish = await mutual();
  await db.batch(Array.from({ length: 500 }, () => db.prepare("INSERT INTO hamtdaa_calendar_events(id,pair_id,creator_id,title,starts_at,created_at,updated_at) VALUES(?,?,?,'Test',1,1,1)").bind(command(), PAIR, 'alice')));
  assert.equal((await request('plan', planBody(wish))).status, 429); assert.equal(await count('hamtdaa_calendar_events'), 500);
  await db.batch(Array.from({ length: 199 }, () => db.prepare("INSERT INTO hamtdaa_wishes(id,pair_id,creator_id,title,category,budget,created_at,updated_at) VALUES(?,?,?,'Test','other','free',1,1)").bind(command(), PAIR, 'alice')));
  assert.equal((await request('create', createBody())).status, 429); assert.equal(await count('hamtdaa_wishes'), 200);
});

test('completed wishes survive independent calendar deletion with empty linked-event metadata', async () => {
  await cleanup(); const wish = await mutual(); const planned = await success('plan', planBody(wish));
  await db.prepare("UPDATE hamtdaa_calendar_events SET status='accepted' WHERE id=?").bind(planned.event_id).run();
  const completed = await success('complete', mutateBody(planned.wish));
  await db.prepare('DELETE FROM hamtdaa_calendar_events WHERE id=?').bind(planned.event_id).run();
  const saved = (await success('list', { expected_pair_id: PAIR })).wishes[0];
  assert.equal(saved.status, 'done'); assert.equal(saved.event_id, null); assert.equal(saved.event_status, null); assert.equal(saved.version, completed.wish.version + 1);
});

test('calendar response changing during completion fails the transactional event predicate', async () => {
  await cleanup(); const wish = await mutual(); const planned = await success('plan', planBody(wish));
  await db.prepare("UPDATE hamtdaa_calendar_events SET status='accepted' WHERE id=?").bind(planned.event_id).run();
  const racingDb = new Proxy(db, { get(target, key) {
    if (key === 'batch') return async (statements: D1PreparedStatement[]) => {
      await db.prepare("UPDATE hamtdaa_calendar_events SET status='declined' WHERE id=?").bind(planned.event_id).run(); return db.batch(statements);
    };
    const value = Reflect.get(target, key); return typeof value === 'function' ? value.bind(target) : value;
  } });
  const response = await handleWishesRequest('complete', racingDb, 'alice', mutateBody(planned.wish));
  assert.equal(response.status, 409);
  assert.equal((await success('list', { expected_pair_id: PAIR })).wishes[0].status, 'planned');
});

test('500 total wishes cap includes completed ideas and the bounded list remains complete', async () => {
  await cleanup();
  for (let i = 0; i < 5; i++) {
    await db.batch(Array.from({ length: 100 }, () => db.prepare("INSERT INTO hamtdaa_wishes(id,pair_id,creator_id,title,category,budget,created_at,updated_at) VALUES(?,?,?,'Test','other','free',1,1)").bind(command(), PAIR, 'alice')));
    await db.prepare("UPDATE hamtdaa_wishes SET status='done',version=version+1").run();
  }
  assert.equal((await request('create', createBody())).status, 429);
  assert.equal((await success('list', { expected_pair_id: PAIR })).wishes.length, 500);
});
