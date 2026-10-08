import jpeg from 'jpeg-js';
import { handleWishesRequest } from './wishes';

type Json = Record<string, unknown>;
type Value = string | number | null;
type Memory = { id: string; pair_id: string; creator_id: string; day: string; title: string; note: string; sticker: string; version: number; created_at: number; state: string; photo_key: string; thumbnail_key: string; payload_hash: string; upload_deadline: number };
type Receipt = { pair_id: string; operation: string; payload_hash: string; memory_id: string | null };
const MAX_BODY = 1200 * 1024;
const PHOTO_LIMIT = 768 * 1024;
const THUMB_LIMIT = 64 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HEADERS = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
const activePair = `SELECT p.id FROM hamtdaa_pairs p
 JOIN hamtdaa_pair_members own ON own.pair_id=p.id AND own.user_id=? AND own.revoked_at IS NULL
 JOIN hamtdaa_pair_members other ON other.pair_id=p.id AND other.user_id<>own.user_id AND other.revoked_at IS NULL
 JOIN hamtdaa_profiles ap ON ap.user_id=own.user_id AND ap.account_state='active'
 JOIN hamtdaa_profiles op ON op.user_id=other.user_id AND op.account_state='active'
 JOIN "user" au ON au.id=own.user_id AND au.emailVerified=1
 JOIN "user" ou ON ou.id=other.user_id AND ou.emailVerified=1
 WHERE p.state='active'
 AND NOT EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts d WHERE d.user_id IN(own.user_id,other.user_id))
 AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b WHERE
 (b.blocker_id=own.user_id AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=own.user_id))`;
class Problem extends Error { constructor(readonly code: string, readonly status: number) { super(code); } }
function fail(code: string, status = 400): never { throw new Problem(code, status); }
function json(value: Json, status = 200) { return Response.json(value, { status, headers: HEADERS }); }
function object(value: unknown): Json { if (!value || typeof value !== 'object' || Array.isArray(value)) fail('validation'); return value as Json; }
function fields(value: Json, required: string[], optional: string[] = []) {
  if (Object.keys(value).some(k => !required.includes(k) && !optional.includes(k)) || required.some(k => !Object.hasOwn(value, k))) fail('validation');
}
function id(value: unknown): string { if (typeof value !== 'string' || !UUID.test(value)) fail('validation'); return value.toLowerCase(); }
function text(value: unknown, max: number, required = false): string {
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(value)) fail('validation');
  const result = value.trim(); if (required && !result) fail('validation'); return result;
}
function day(value: unknown): string {
  if (typeof value !== 'string' || !/^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/.test(value) || new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) !== value) fail('validation');
  return value;
}
export async function readBounded(stream: ReadableStream<Uint8Array> | null, limit: number): Promise<Uint8Array> {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader(); const chunks: Uint8Array[] = []; let size = 0;
  try {
    for (;;) { const chunk = await reader.read(); if (chunk.done) break; size += chunk.value.byteLength; if (size > limit) { await reader.cancel(); fail('payload_too_large', 413); } chunks.push(chunk.value); }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(size); let offset = 0; for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; } return result;
}
async function hash(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest('SHA-256', bytes as BufferSource);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}
function decodeBase64(value: unknown, limit: number): Uint8Array {
  if (typeof value !== 'string' || !value || value.length > 4 * Math.ceil(limit / 3) || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) fail('invalid_photo');
  let raw: string; try { raw = atob(value); } catch { fail('invalid_photo'); }
  if (raw.length > limit) fail('photo_too_large', 413);
  const result = Uint8Array.from(raw, c => c.charCodeAt(0)); if (btoa(raw) !== value) fail('invalid_photo'); return result;
}
export function normalizeJpeg(bytes: Uint8Array, thumbnail = false): Uint8Array {
  const limit = thumbnail ? THUMB_LIMIT : PHOTO_LIMIT;
  if (bytes.length > limit) fail('photo_too_large', 413);
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) fail('invalid_photo');
  try {
    // jpeg-js bounds allocation before decoding; encoding fresh pixels discards EXIF/GPS and comments.
    const decoded = jpeg.decode(bytes, { useTArray: true, formatAsRGBA: true, tolerantDecoding: false, maxResolutionInMP: thumbnail ? 0.25 : 4, maxMemoryUsageInMB: 48 });
    if (!decoded.width || !decoded.height || decoded.width > (thumbnail ? 512 : 4096) || decoded.height > (thumbnail ? 512 : 4096)) fail('invalid_photo');
    const normalized = jpeg.encode({ width: decoded.width, height: decoded.height, data: decoded.data }, 80).data;
    if (normalized.length > limit) fail('photo_too_large', 413);
    return new Uint8Array(normalized);
  } catch (error) { if (error instanceof Problem) throw error; fail('invalid_photo'); }
}
function metadata(memory: Memory) {
  return { id: memory.id, pair_id: memory.pair_id, creator_id: memory.creator_id, day: memory.day, title: memory.title, note: memory.note, sticker: memory.sticker, version: memory.version, created_at: new Date(memory.created_at).toISOString() };
}
async function authenticate(request: Request, env: Env): Promise<string> {
  const authorization = request.headers.get('Authorization');
  if (!authorization || !/^Bearer [^\s]{16,1024}$/.test(authorization)) fail('unauthenticated', 401);
  const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 8000);
  try {
    // Preserve the edge-provided IP so Better Auth does not put every service
    // caller in its single fallback rate bucket. Never forward caller routing
    // headers such as X-Forwarded-For, cookies, or browser Origin.
    const authHeaders = new Headers({ Authorization: authorization, Accept: 'application/json' });
    const edgeIp = request.headers.get('CF-Connecting-IP');
    if (edgeIp) authHeaders.set('CF-Connecting-IP', edgeIp);
    const response = await env.AUTH.fetch(new Request('https://auth.internal/v1/auth/session', { headers: authHeaders, redirect: 'manual', signal: controller.signal }));
    if (response.status === 401 || response.status === 403) fail('unauthenticated', 401);
    if (response.status !== 200) fail('temporarily_unavailable', 503);
    const raw = await readBounded(response.body, 16 * 1024);
    const data = object(JSON.parse(new TextDecoder().decode(raw))); const user = object(data.user);
    if (data.ok !== true || typeof user.id !== 'string' || !user.id || user.id.length > 256 || typeof user.email !== 'string' || typeof data.expires_at !== 'string' || !Number.isFinite(Date.parse(data.expires_at)) || Date.parse(data.expires_at) <= Date.now()) fail('unauthenticated', 401);
    return user.id;
  } catch (error) { if (error instanceof Problem) throw error; fail('temporarily_unavailable', 503); }
  finally { clearTimeout(timer); }
}
class Memories {
  constructor(private env: Env, private actor: string) {}
  q(sql: string, ...values: Value[]) { return this.env.DB.prepare(sql).bind(...values); }
  guard(predicate: string, ...values: Value[]) {
    const key = crypto.randomUUID(); return [this.q(`INSERT INTO hamtdaa_memory_guards(id,allowed) SELECT ?,CASE WHEN ${predicate} THEN 1 ELSE 0 END`, key, ...values), this.q('DELETE FROM hamtdaa_memory_guards WHERE id=?', key)];
  }
  pairGuard(pair: string) { return this.guard(`EXISTS(${activePair} AND p.id=?)`, this.actor, pair); }
  async checkPair(pair: string) { if (!await this.q(`${activePair} AND p.id=?`, this.actor, pair).first()) fail('pair_required', 409); }
  async receipt(command: string) { return this.q('SELECT pair_id,operation,payload_hash,memory_id FROM hamtdaa_memory_receipts WHERE user_id=? AND command_id=?', this.actor, command).first<Receipt>(); }
  async replay(receipt: Receipt, operation: string, payloadHash: string): Promise<Response> {
    if (receipt.operation !== operation || receipt.payload_hash !== payloadHash) fail('idempotency_mismatch', 409);
    await this.checkPair(receipt.pair_id);
    if (operation === 'delete') return json({ ok: true, deleted: true });
    const row = await this.q(`SELECT m.* FROM hamtdaa_memories m WHERE m.id=? AND m.state='ready' AND EXISTS(${activePair} AND p.id=m.pair_id)`, receipt.memory_id, this.actor).first<Memory>();
    if (!row) fail('memory_deleted', 410); return json({ ok: true, memory: metadata(row) });
  }
  async list(body: Json) {
    fields(body, ['expected_pair_id', 'month']); const pair = id(body.expected_pair_id);
    if (typeof body.month !== 'string' || !/^20\d{2}-(0[1-9]|1[0-2])$/.test(body.month)) fail('validation');
    let results: D1Result[];
    try {
      results = await this.env.DB.batch([...this.pairGuard(pair), this.q(`SELECT m.* FROM hamtdaa_memories m WHERE m.pair_id=? AND m.state='ready' AND m.day LIKE ? ORDER BY m.day,m.created_at,m.id LIMIT 310`, pair, `${body.month}-%`)]);
    } catch (error) { await this.checkPair(pair); throw error; }
    await this.checkPair(pair);
    return json({ ok: true, pair_id: pair, memories: (results[2].results as Memory[]).map(metadata) });
  }
  async create(body: Json) {
    fields(body, ['expected_pair_id', 'command_id', 'day', 'title', 'note', 'sticker', 'photo_base64', 'thumbnail_base64']);
    const pair = id(body.expected_pair_id); const command = id(body.command_id); const date = day(body.day); const title = text(body.title, 80, true); const note = text(body.note, 2000);
    if (body.sticker !== 'rounded' && body.sticker !== 'polaroid') fail('validation');
    const original = decodeBase64(body.photo_base64, PHOTO_LIMIT); const thumb = decodeBase64(body.thumbnail_base64, THUMB_LIMIT);
    const payloadHash = await hash(JSON.stringify({ operation: 'create', pair, date, title, note, sticker: body.sticker, photo: await hash(original), thumbnail: await hash(thumb) }));
    const previous = await this.receipt(command); if (previous) return this.replay(previous, 'create', payloadHash);
    await this.checkPair(pair);
    const pending = await this.q('SELECT payload_hash FROM hamtdaa_memories WHERE creator_id=? AND command_id=?', this.actor, command).first<{ payload_hash: string }>();
    if (pending) fail(pending.payload_hash === payloadHash ? 'upload_in_progress' : 'idempotency_mismatch', 409);
    const uploadDay = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
    const usage = await this.q(`SELECT (SELECT count(*) FROM hamtdaa_memories WHERE pair_id=?) total, (SELECT count(*) FROM hamtdaa_memories WHERE pair_id=? AND day=?) day_total, COALESCE((SELECT creates FROM hamtdaa_memory_quotas WHERE user_id=? AND day=?),0) creates`, pair, pair, date, this.actor, uploadDay).first<{ total: number; day_total: number; creates: number }>();
    if (usage!.total >= 1000 || usage!.day_total >= 10 || usage!.creates >= 10) fail('quota_exceeded', 429);
    const photo = normalizeJpeg(original); const thumbnail = normalizeJpeg(thumb, true);
    const memoryId = crypto.randomUUID(); const now = Date.now(); const deadline = now + 120000;
    const key = `memories/${crypto.randomUUID()}`; const photoKey = `${key}/photo.jpg`; const thumbKey = `${key}/thumbnail.jpg`;
    try {
      await this.env.DB.batch([
        ...this.pairGuard(pair),
        ...this.guard("date('now','+8 hours')=?", uploadDay),
        ...this.guard(`(SELECT count(*) FROM hamtdaa_memories WHERE pair_id=?)<1000 AND (SELECT count(*) FROM hamtdaa_memories WHERE pair_id=? AND day=?)<10 AND COALESCE((SELECT creates FROM hamtdaa_memory_quotas WHERE user_id=? AND day=?),0)<10`, pair, pair, date, this.actor, uploadDay),
        this.q(`INSERT INTO hamtdaa_memory_quotas(user_id,day,creates) VALUES(?,?,1) ON CONFLICT(user_id) DO UPDATE SET day=excluded.day,creates=CASE WHEN hamtdaa_memory_quotas.day=excluded.day THEN hamtdaa_memory_quotas.creates+1 ELSE 1 END`, this.actor, uploadDay),
        this.q(`INSERT INTO hamtdaa_memories(id,pair_id,creator_id,day,title,note,sticker,state,photo_key,thumbnail_key,photo_bytes,thumb_bytes,payload_hash,command_id,version,created_at,upload_deadline) VALUES(?,?,?,?,?,?,?,'pending',?,?,?,?,?,?,1,?,?)`, memoryId, pair, this.actor, date, title, note, body.sticker, photoKey, thumbKey, photo.length, thumbnail.length, payloadHash, command, now, deadline),
      ]);
    } catch {
      const duplicate = await this.receipt(command); if (duplicate) return this.replay(duplicate, 'create', payloadHash);
      await this.checkPair(pair); fail('conflict', 409);
    }
    try {
      const options: R2PutOptions = { httpMetadata: { contentType: 'image/jpeg', cacheControl: 'private, no-store' }, onlyIf: { etagDoesNotMatch: '*' } };
      const uploaded = await Promise.all([this.env.PHOTOS.put(photoKey, photo, options), this.env.PHOTOS.put(thumbKey, thumbnail, options)]);
      if (uploaded.some(v => !v)) fail('temporarily_unavailable', 503);
      await this.env.DB.batch([
        ...this.pairGuard(pair),
        this.q(`UPDATE hamtdaa_memories SET state='ready' WHERE id=? AND state='pending' AND upload_deadline>?`, memoryId, Date.now()),
        ...this.guard('changes()=1'),
        this.q(`INSERT INTO hamtdaa_memory_receipts(user_id,command_id,pair_id,operation,payload_hash,memory_id,created_at) VALUES(?,?,?,'create',?,?,?)`, this.actor, command, pair, payloadHash, memoryId, now),
      ]);
    } catch (error) {
      // A committed finalization may have lost its reply. Never delete a ready record.
      const committed = await this.receipt(command); if (committed) return this.replay(committed, 'create', payloadHash);
      await this.q(`DELETE FROM hamtdaa_memories WHERE id=? AND state='pending'`, memoryId).run();
      await this.checkPair(pair); if (error instanceof Problem) throw error; fail('temporarily_unavailable', 503);
    }
    const saved = await this.q(`SELECT m.* FROM hamtdaa_memories m WHERE m.id=? AND m.state='ready' AND EXISTS(${activePair} AND p.id=m.pair_id)`, memoryId, this.actor).first<Memory>();
    if (!saved) fail('pair_required', 409); return json({ ok: true, memory: metadata(saved) });
  }
  async delete(body: Json) {
    fields(body, ['expected_pair_id', 'command_id', 'id', 'expected_version']);
    const pair = id(body.expected_pair_id); const command = id(body.command_id); const memoryId = id(body.id);
    if (!Number.isSafeInteger(body.expected_version) || Number(body.expected_version) < 1) fail('validation');
    const version = Number(body.expected_version); const payloadHash = await hash(JSON.stringify({ operation: 'delete', pair, memoryId, version }));
    const previous = await this.receipt(command); if (previous) return this.replay(previous, 'delete', payloadHash);
    await this.checkPair(pair);
    const row = await this.q('SELECT * FROM hamtdaa_memories WHERE id=? AND pair_id=?', memoryId, pair).first<Memory>();
    if (!row) {
      const concurrent = await this.receipt(command); if (concurrent) return this.replay(concurrent, 'delete', payloadHash);
      fail('not_found', 404);
    }
    if (row.creator_id !== this.actor) fail('forbidden', 403); if (row.version !== version) fail('conflict', 409);
    try {
      await this.env.DB.batch([
        ...this.pairGuard(pair),
        this.q('DELETE FROM hamtdaa_memories WHERE id=? AND pair_id=? AND creator_id=? AND version=?', memoryId, pair, this.actor, version),
        ...this.guard('changes()=1'),
        this.q(`INSERT INTO hamtdaa_memory_receipts(user_id,command_id,pair_id,operation,payload_hash,memory_id,created_at) VALUES(?,?,?,'delete',?,?,?)`, this.actor, command, pair, payloadHash, memoryId, Date.now()),
      ]);
    } catch (error) {
      const duplicate = await this.receipt(command); if (duplicate) return this.replay(duplicate, 'delete', payloadHash);
      await this.checkPair(pair); throw error;
    }
    return json({ ok: true, deleted: true });
  }
  async photo(memoryId: string, thumbnail: boolean) {
    const row = await this.q(`SELECT m.* FROM hamtdaa_memories m WHERE m.id=? AND m.state='ready' AND EXISTS(${activePair} AND p.id=m.pair_id)`, memoryId, this.actor).first<Memory>();
    if (!row) fail('not_found', 404);
    const photo = await this.env.PHOTOS.get(thumbnail ? row.thumbnail_key : row.photo_key); if (!photo) fail('not_found', 404);
    // Resolve again after the storage read; an unlink or account deletion must not expose a stale object.
    if (!await this.q(`SELECT 1 FROM hamtdaa_memories m WHERE m.id=? AND m.state='ready' AND EXISTS(${activePair} AND p.id=m.pair_id)`, memoryId, this.actor).first()) { await photo.body.cancel(); fail('not_found', 404); }
    return new Response(photo.body, { headers: { ...HEADERS, 'Content-Type': 'image/jpeg', 'Content-Length': String(photo.size) } });
  }
  async export(body: Json) {
    fields(body, ['expected_pair_id'], ['cursor']); const pair = id(body.expected_pair_id); await this.checkPair(pair); const cursor = body.cursor === undefined || body.cursor === null ? '' : id(body.cursor);
    const result = await this.q(`SELECT m.* FROM hamtdaa_memories m WHERE m.creator_id=? AND m.pair_id=? AND m.id>? AND m.state='ready' AND EXISTS(${activePair} AND p.id=m.pair_id) ORDER BY m.id LIMIT 2`, this.actor, pair, cursor, this.actor).all<Memory>();
    const row = result.results[0]; if (!row) { await this.checkPair(pair); return json({ ok: true, memories: [], next_cursor: null }); }
    const responses = await Promise.all([this.photo(row.id, false), this.photo(row.id, true)]);
    const bytes = await Promise.all(responses.map(r => readBounded(r.body, PHOTO_LIMIT)));
    if (!await this.q(`SELECT 1 FROM hamtdaa_memories m WHERE m.id=? AND m.state='ready' AND EXISTS(${activePair} AND p.id=m.pair_id)`, row.id, this.actor).first()) fail('pair_required', 409);
    function base64(value: Uint8Array) { let text = ''; for (let i = 0; i < value.length; i += 8192) text += String.fromCharCode(...value.subarray(i, i + 8192)); return btoa(text); }
    return json({ ok: true, memories: [{ ...metadata(row), photo_base64: base64(bytes[0]), thumbnail_base64: base64(bytes[1]) }], next_cursor: result.results.length > 1 ? row.id : null });
  }
}

export async function collectGarbage(env: Env) {
  const now = Date.now();
  await env.DB.prepare(`DELETE FROM hamtdaa_memories WHERE state='pending' AND upload_deadline<?`).bind(now).run();
  const queue = await env.DB.prepare('SELECT object_key,retain_until FROM hamtdaa_memory_gc WHERE due_at<=? ORDER BY due_at LIMIT 100').bind(now).all<{ object_key: string; retain_until: number }>();
  for (const row of queue.results) {
    try {
      await env.PHOTOS.delete(row.object_key);
      if (row.retain_until <= now) await env.DB.prepare('DELETE FROM hamtdaa_memory_gc WHERE object_key=?').bind(row.object_key).run();
      else await env.DB.prepare('UPDATE hamtdaa_memory_gc SET attempts=attempts+1,due_at=? WHERE object_key=?').bind(Math.min(now + 900000, row.retain_until), row.object_key).run();
    } catch { /* Retain the durable queue row for the next scheduled attempt. */ }
  }
  // Persist a paginated sweep so a late-finishing PUT can never remain an untracked orphan.
  const state = await env.DB.prepare("SELECT value FROM hamtdaa_memory_gc_state WHERE name='cursor'").first<{ value: string }>();
  const page = await env.PHOTOS.list({ prefix: 'memories/', limit: 100, ...(state?.value ? { cursor: state.value } : {}) });
  for (const item of page.objects) {
    if (item.uploaded.getTime() > now - 86400000) continue;
    const referenced = await env.DB.prepare('SELECT 1 FROM hamtdaa_memories WHERE photo_key=? OR thumbnail_key=?').bind(item.key, item.key).first();
    if (!referenced) await env.PHOTOS.delete(item.key);
  }
  await env.DB.prepare("INSERT INTO hamtdaa_memory_gc_state(name,value) VALUES('cursor',?) ON CONFLICT(name) DO UPDATE SET value=excluded.value").bind(page.truncated ? page.cursor : '').run();
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url); if (url.search || url.hash) fail('validation');
      if (url.pathname === '/v1/health' && request.method === 'GET') return json({ ok: true, service: 'nandin-moch-memories' });
      // Native app only. Never reflect an arbitrary browser Origin.
      if (request.headers.has('Origin')) fail('forbidden', 403);
      const match = /^\/v1\/memories\/([0-9a-f-]+)\/(photo|thumbnail)$/.exec(url.pathname);
      if (match && request.method === 'GET') return await new Memories(env, await authenticate(request, env)).photo(id(match[1]), match[2] === 'thumbnail');
      const wishRoute = /^\/v1\/wishes\/(list|create|like|delete|plan|complete|export)$/.exec(url.pathname);
      if (!wishRoute && !['/v1/memories/list', '/v1/memories/create', '/v1/memories/delete', '/v1/memories/export'].includes(url.pathname)) fail('not_found', 404);
      if (request.method !== 'POST') fail('method_not_allowed', 405);
      const actor = await authenticate(request, env);
      if (!/^application\/json(?:;|$)/i.test(request.headers.get('Content-Type') ?? '')) fail('validation');
      const bytes = await readBounded(request.body, url.pathname === '/v1/memories/create' ? MAX_BODY : 8192);
      let body: Json; try { body = object(JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes))); } catch { fail('validation'); }
      if (wishRoute) return await handleWishesRequest(wishRoute[1], env.DB, actor, body);
      const service = new Memories(env, actor);
      if (url.pathname.endsWith('/list')) return await service.list(body);
      if (url.pathname.endsWith('/create')) return await service.create(body);
      if (url.pathname.endsWith('/delete')) return await service.delete(body);
      return await service.export(body);
    } catch (error) {
      if (error instanceof Problem) return json({ ok: false, code: error.code }, error.status);
      // No raw SQL, credential, photo or upstream failure text is returned or logged.
      if (error instanceof Error && /constraint|memory_guards/i.test(error.message)) return json({ ok: false, code: 'conflict' }, 409);
      return json({ ok: false, code: 'temporarily_unavailable' }, 503);
    }
  },
  async scheduled(_controller: ScheduledController, env: Env) { await collectGarbage(env); },
} satisfies ExportedHandler<Env>;
