import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { Miniflare, convertV4MiniflareOptions, Response as MFResponse } from 'miniflare';
import jpeg from 'jpeg-js';
import worker, { collectGarbage, normalizeJpeg, readBounded } from '../src/index.js';

const PAIR = '10000000-0000-4000-8000-000000000001';
const OTHER_PAIR = '10000000-0000-4000-8000-000000000002';
let mf: Miniflare;
let db: D1Database;
let bucket: R2Bucket;
let authMode = 'valid';
let receivedAuthHeaders: Headers;
const image = jpeg.encode({ width: 8, height: 8, data: new Uint8Array(8 * 8 * 4).fill(150) }, 75).data.toString('base64');
const command = () => crypto.randomUUID();
const createBody = (overrides = {}) => ({ expected_pair_id: PAIR, command_id: command(), day: '2026-10-08', title: 'Хамтдаа', note: 'Нандин мөч', sticker: 'polaroid', photo_base64: image, thumbnail_base64: image, ...overrides });
async function request(path: string, body?: unknown, actor = 'alice', headers: Record<string, string> = {}) {
  const response = await mf.dispatchFetch(`https://memories.test/v1/memories/${path}`, { method: body === undefined ? 'GET' : 'POST', headers: { Authorization: `Bearer ${actor.padEnd(20, '_')}`, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
  return new MFResponse(await response.arrayBuffer(), { status: response.status, headers: response.headers });
}
async function payload(response: Response | Awaited<ReturnType<typeof mf.dispatchFetch>>) { return await response.json() as any; }
async function newMemory(overrides = {}, actor = 'alice') { const response = await request('create', createBody(overrides), actor); const body = await payload(response); assert.equal(response.status, 200, JSON.stringify(body)); return body.memory; }
async function cleanup() {
  authMode = 'valid';
  await db.batch(['DELETE FROM hamtdaa_memories', 'DELETE FROM hamtdaa_memory_gc', 'DELETE FROM hamtdaa_memory_receipts', 'DELETE FROM hamtdaa_memory_quotas', 'DELETE FROM hamtdaa_deleted_accounts', 'DELETE FROM hamtdaa_blocks', "UPDATE hamtdaa_profiles SET account_state='active'", 'UPDATE "user" SET emailVerified=1', "UPDATE hamtdaa_pairs SET state='active',unlinked_at=NULL", 'UPDATE hamtdaa_pair_members SET revoked_at=NULL'].map(sql => db.prepare(sql)));
}
before(async () => {
  mf = new Miniflare(convertV4MiniflareOptions({ modules: true, scriptPath: 'dist/index.js', compatibilityDate: '2026-10-08', compatibilityFlags: ['nodejs_compat'], d1Databases: ['DB'], r2Buckets: ['PHOTOS'], serviceBindings: {
    AUTH: async (req) => {
      receivedAuthHeaders = new Headers(req.headers);
      assert.equal(new URL(req.url).pathname, '/v1/auth/session');
      if (authMode === 'bad') return new MFResponse('{}', { status: 401 });
      if (authMode === 'oversize') return new MFResponse('x'.repeat(20000));
      const actor = req.headers.get('Authorization')!.slice(7).replace(/_+$/, '');
      return MFResponse.json({ ok: true, user: { id: actor, email: `${actor}@example.test` }, expires_at: authMode === 'expired' ? '2000-01-01T00:00:00Z' : '2099-01-01T00:00:00Z' });
    },
  }}));
  db = await mf.getD1Database('DB') as unknown as D1Database;
  bucket = await mf.getR2Bucket('PHOTOS') as unknown as R2Bucket;
  for (const file of ['test/base.sql', 'migrations/0001_memories.sql']) {
    const statements = JSON.parse(execFileSync('python3', ['-c', 'import sqlite3,json,sys\nbuf=""; out=[]\nfor line in sys.stdin:\n buf+=line\n if sqlite3.complete_statement(buf):\n  out.append(buf); buf=""\nprint(json.dumps(out))'], { input: readFileSync(file, 'utf8'), encoding: 'utf8' }));
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

test('creates normalized private photos; partner reads, outsider cannot; creator deletes idempotently', async () => {
  await cleanup(); const body = createBody();
  const first = await request('create', body); assert.equal(first.status, 200, JSON.stringify(await first.clone().json()));
  const memory = (await payload(first)).memory;
  const replay = await payload(await request('create', body)); assert.equal(replay.memory.id, memory.id);
  assert.equal((await request('create', { ...body, title: 'Changed' })).status, 409);
  const list = await payload(await request('list', { expected_pair_id: PAIR, month: '2026-10' }, 'bob')); assert.equal(list.memories.length, 1);
  const photo = await request(`${memory.id}/photo`, undefined, 'bob'); assert.equal(photo.status, 200); assert.equal(photo.headers.get('Cache-Control'), 'private, no-store'); assert.equal(photo.headers.get('Content-Type'), 'image/jpeg'); assert.ok((await photo.arrayBuffer()).byteLength > 0);
  assert.equal((await request(`${memory.id}/thumbnail`, undefined, 'mallory')).status, 404);
  assert.equal((await request('list', { expected_pair_id: PAIR, month: '2026-10' }, 'mallory')).status, 409);
  const deletion = { expected_pair_id: PAIR, id: memory.id, expected_version: 1, command_id: command() };
  assert.equal((await request('delete', deletion, 'bob')).status, 403);
  assert.equal((await request('delete', { ...deletion, expected_version: 2 })).status, 409);
  assert.deepEqual(await payload(await request('delete', deletion)), { ok: true, deleted: true });
  assert.deepEqual(await payload(await request('delete', deletion)), { ok: true, deleted: true });
  assert.equal((await request(`${memory.id}/photo`)).status, 404);
  assert.equal((await request('create', body)).status, 410);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memory_gc').first<any>()).n, 2);
});

test('authentication fails closed and forwards no cookies, origin or caller routing headers', async () => {
  await cleanup();
  authMode = 'bad'; assert.equal((await request('list', { expected_pair_id: PAIR, month: '2026-10' })).status, 401);
  authMode = 'expired'; assert.equal((await request('list', { expected_pair_id: PAIR, month: '2026-10' })).status, 401);
  authMode = 'oversize'; assert.notEqual((await request('list', { expected_pair_id: PAIR, month: '2026-10' })).status, 200);
  authMode = 'valid'; await request('list', { expected_pair_id: PAIR, month: '2026-10' }, 'alice', { Cookie: 'session=not-forwarded', 'X-Forwarded-For': '1.2.3.4' });
  assert.equal(receivedAuthHeaders.get('Cookie'), null); assert.equal(receivedAuthHeaders.get('Origin'), null); assert.equal(receivedAuthHeaders.get('X-Forwarded-For'), null);
  assert.equal((await request('list', { expected_pair_id: PAIR, month: '2026-10' }, 'alice', { Origin: 'https://evil.test' })).status, 403);
});

test('wrong pair, malformed image, oversized streams, invalid dates and unknown fields are rejected', async () => {
  await cleanup();
  assert.equal((await request('create', createBody({ expected_pair_id: OTHER_PAIR }))).status, 409);
  assert.equal((await request('create', createBody({ photo_base64: 'aGVsbG8=' }))).status, 400);
  assert.equal((await request('create', createBody({ day: '2026-02-30' }))).status, 400);
  assert.equal((await request('create', createBody({ actor: 'bob' }))).status, 400);
  // Invoke the handler directly for the deliberately canceled oversized stream:
  // Miniflare's shared HTTP proxy otherwise reuses its canceled upload socket for D1.
  assert.equal((await worker.fetch(localCreate(createBody({ photo_base64: 'A'.repeat(1300000) })), localEnv())).status, 413);
  let canceled = false;
  const stream = new ReadableStream<Uint8Array>({ pull(controller) { controller.enqueue(new Uint8Array(9)); }, cancel() { canceled = true; } });
  await assert.rejects(() => readBounded(stream, 10)); assert.equal(canceled, true);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memories').first<any>()).n, 0);
});

test('all current pair restrictions are enforced after a photo already exists', async () => {
  const changes = [
    ["INSERT INTO hamtdaa_blocks VALUES('bob','alice')", 'DELETE FROM hamtdaa_blocks'],
    ["UPDATE hamtdaa_pair_members SET revoked_at=1 WHERE user_id='bob'", "UPDATE hamtdaa_pair_members SET revoked_at=NULL WHERE user_id='bob'"],
    ["UPDATE \"user\" SET emailVerified=0 WHERE id='bob'", "UPDATE \"user\" SET emailVerified=1 WHERE id='bob'"],
    ["UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id='bob'", "UPDATE hamtdaa_profiles SET account_state='active' WHERE user_id='bob'"],
  ];
  await cleanup(); const memory = await newMemory();
  for (const [change, undo] of changes) { await db.prepare(change).run(); assert.equal((await request(`${memory.id}/photo`)).status, 404); assert.equal((await request('list', { expected_pair_id: PAIR, month: '2026-10' })).status, 409); await db.prepare(undo).run(); }
  await db.prepare("UPDATE hamtdaa_pairs SET state='unlinked',unlinked_at=1 WHERE id=?").bind(PAIR).run();
  assert.equal((await request(`${memory.id}/photo`)).status, 404);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memories').first<any>()).n, 0);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memory_gc').first<any>()).n, 2);
});

test('account deletion marker removes authored content and queues cleanup inside the transaction', async () => {
  await cleanup(); const memory = await newMemory();
  await db.prepare("INSERT INTO hamtdaa_deleted_accounts(user_id,deleted_at) VALUES('alice',?)").bind(Date.now()).run();
  assert.equal((await request(`${memory.id}/photo`, undefined, 'bob')).status, 404);
  for (const table of ['hamtdaa_memories', 'hamtdaa_memory_receipts', 'hamtdaa_memory_quotas']) assert.equal((await db.prepare(`SELECT count(*) n FROM ${table}`).first<any>()).n, 0);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memory_gc').first<any>()).n, 2);
});

test('calendar day and actor upload quotas are enforced transactionally', async () => {
  await cleanup();
  for (let i = 0; i < 10; i++) await newMemory();
  assert.equal((await request('create', createBody({ day: '2026-10-09' }))).status, 429);
  assert.equal((await request('create', createBody(), 'bob')).status, 429);
  assert.equal((await request('create', createBody({ day: '2026-10-09' }), 'bob')).status, 200);
});

test('export includes only creator records and complete photo data with a stable cursor', async () => {
  await cleanup(); await newMemory(); await newMemory({ day: '2026-10-09' }); await newMemory({}, 'bob');
  const first = await payload(await request('export', { expected_pair_id: PAIR })); assert.equal(first.memories.length, 1); assert.equal(first.memories[0].creator_id, 'alice'); assert.ok(first.memories[0].photo_base64); assert.ok(first.next_cursor);
  const second = await payload(await request('export', { expected_pair_id: PAIR, cursor: first.next_cursor })); assert.equal(second.memories.length, 1); assert.equal(second.next_cursor, null); assert.notEqual(first.memories[0].id, second.memories[0].id);
});

test('normalization strips metadata and bounds malformed JPEGs; 1280px encoding remains bounded', () => {
  const source = jpeg.encode({ width: 1280, height: 960, data: new Uint8Array(1280 * 960 * 4).fill(180), comments: ['PRIVATE GPS COMMENT'] }, 75).data;
  const start = performance.now(); const clean = normalizeJpeg(source); const elapsed = performance.now() - start;
  assert.ok(clean.length <= 768 * 1024); assert.equal(Buffer.from(clean).includes(Buffer.from('PRIVATE GPS COMMENT')), false);
  assert.ok(elapsed < 10000, `normalization took ${elapsed}ms`);
  assert.throws(() => normalizeJpeg(new Uint8Array([0xff, 0xd8, 0xff, 0xd9])));
});

test('concurrent identical delete commands return the same successful result', async () => {
  await cleanup(); const memory = await newMemory();
  const body = { expected_pair_id: PAIR, id: memory.id, expected_version: 1, command_id: command() };
  const responses = await Promise.all([request('delete', body), request('delete', body)]);
  assert.deepEqual(responses.map(r => r.status), [200, 200]);
});

function localEnv(photos: unknown = bucket): Env {
  return { DB: db, PHOTOS: photos, AUTH: { fetch: async () => Response.json({ ok: true, user: { id: 'alice', email: 'alice@example.test' }, expires_at: '2099-01-01T00:00:00Z' }) } } as unknown as Env;
}
function localCreate(body: unknown) { return new Request('https://test/v1/memories/create', { method: 'POST', headers: { Authorization: 'Bearer test_only_credential_12345', 'Content-Type': 'application/json' }, body: JSON.stringify(body) }); }

test('failed storage upload never publishes metadata and durably queues cleanup', async () => {
  await cleanup();
  const response = await worker.fetch(localCreate(createBody()), localEnv({ put: async () => { throw new Error('private storage error'); } }));
  assert.equal(response.status, 503); assert.equal(JSON.stringify(await response.json()).includes('private storage'), false);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memories').first<any>()).n, 0);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memory_gc').first<any>()).n, 2);
});

test('unlink during storage upload fails publication and retains cleanup tombstones', async () => {
  await cleanup();
  const response = await worker.fetch(localCreate(createBody()), localEnv({ put: async (key: string, value: Uint8Array, options: R2PutOptions) => {
    const stored = await bucket.put(key, value, options);
    await db.prepare("UPDATE hamtdaa_pairs SET state='unlinked',unlinked_at=1 WHERE id=?").bind(PAIR).run(); return stored;
  } }));
  assert.equal(response.status, 409);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memories').first<any>()).n, 0);
  assert.equal((await db.prepare('SELECT count(*) n FROM hamtdaa_memory_gc').first<any>()).n, 2);
});

test('GC retries late writes and clamps retry time to tombstone expiry', async () => {
  await cleanup(); const memory = await newMemory();
  const row = await db.prepare('SELECT photo_key FROM hamtdaa_memories WHERE id=?').bind(memory.id).first<{ photo_key: string }>();
  await request('delete', { expected_pair_id: PAIR, id: memory.id, expected_version: 1, command_id: command() });
  const expiry = Date.now() + 300000;
  await db.prepare('UPDATE hamtdaa_memory_gc SET due_at=1,retain_until=?').bind(expiry).run();
  await collectGarbage(localEnv()); assert.equal(await bucket.get(row!.photo_key), null);
  const tombstone = await db.prepare('SELECT due_at,attempts FROM hamtdaa_memory_gc WHERE object_key=?').bind(row!.photo_key).first<any>();
  assert.equal(tombstone.due_at, expiry); assert.equal(tombstone.attempts, 1);
  await bucket.put(row!.photo_key, 'late upload');
  await db.prepare('UPDATE hamtdaa_memory_gc SET due_at=1').run();
  await collectGarbage(localEnv()); assert.equal(await bucket.get(row!.photo_key), null);
});


test('auth binding preserves only the edge client IP to avoid a shared all-user rate bucket', async () => {
  await cleanup();
  for (const edgeIp of ['203.0.113.5', '2001:db8::8']) {
    await request('list', { expected_pair_id: PAIR, month: '2026-10' }, 'alice', {
      'CF-Connecting-IP': edgeIp, 'X-Forwarded-For': '198.51.100.99',
      'X-Real-IP': '198.51.100.98', Cookie: 'private-cookie',
    });
    assert.equal(receivedAuthHeaders.get('CF-Connecting-IP'), edgeIp);
    for (const name of ['X-Forwarded-For', 'X-Real-IP', 'Cookie', 'Origin']) assert.equal(receivedAuthHeaders.get(name), null);
  }
});
