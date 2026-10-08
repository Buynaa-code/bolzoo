/** Private pair wishes. Authentication is delegated to the existing router. */
type Json = Record<string, unknown>;
type Value = string | number | null;
type Operation = 'create' | 'like' | 'delete' | 'plan' | 'complete';
type Wish = { id: string; pair_id: string; creator_id: string; title: string; note: string; location: string; category: string; budget: string; status: 'idea' | 'planned' | 'done'; event_id: string | null; version: number; created_at: number; updated_at: number; my_liked: number; partner_liked: number; event_starts_at: number | null; event_status: string | null };
type Receipt = { pair_id: string; operation: string; payload_hash: string; wish_id: string; event_id: string | null };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
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
const wishColumns = `w.*,(SELECT e.starts_at FROM hamtdaa_calendar_events e WHERE e.id=w.event_id AND e.pair_id=w.pair_id) event_starts_at,(SELECT e.status FROM hamtdaa_calendar_events e WHERE e.id=w.event_id AND e.pair_id=w.pair_id) event_status,EXISTS(SELECT 1 FROM hamtdaa_wish_likes l WHERE l.wish_id=w.id AND l.user_id=?) my_liked,
 EXISTS(SELECT 1 FROM hamtdaa_wish_likes l WHERE l.wish_id=w.id AND l.user_id<>?) partner_liked`;
class Problem extends Error { constructor(readonly code: string, readonly status: number) { super(code); } }
function fail(code: string, status = 400): never { throw new Problem(code, status); }
function json(value: Json, status = 200) { return Response.json(value, { status, headers: { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' } }); }
function fields(body: Json, required: string[]) { if (Object.keys(body).some(k => !required.includes(k)) || required.some(k => !Object.hasOwn(body, k))) fail('validation'); }
function id(value: unknown) { if (typeof value !== 'string' || !UUID.test(value)) fail('validation'); return value.toLowerCase(); }
function text(value: unknown, max: number, required = false) {
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(value)) fail('validation');
  const result = value.trim(); if (required && !result) fail('validation'); return result;
}
function choice(value: unknown, choices: string[]) { if (typeof value !== 'string' || !choices.includes(value)) fail('validation'); return value; }
function instant(value: unknown): number {
  if (typeof value !== 'string' || !/^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) fail('validation');
  const ms = Date.parse(value);
  const normalized = value.includes('.') ? value.replace(/\.(\d{1,3})Z$/, (_, fraction: string) => '.' + fraction.padEnd(3, '0') + 'Z') : value.replace('Z', '.000Z');
  if (!Number.isSafeInteger(ms) || new Date(ms).toISOString() !== normalized) fail('validation'); return ms;
}
function metadata(w: Wish) {
  return { id: w.id, pair_id: w.pair_id, creator_id: w.creator_id, title: w.title, note: w.note, location: w.location, category: w.category, budget: w.budget, status: w.status, event_id: w.event_id, event_starts_at: w.event_starts_at === null ? null : new Date(w.event_starts_at).toISOString(), event_status: w.event_status, version: w.version, my_liked: w.my_liked === 1, partner_liked: w.partner_liked === 1, created_at: new Date(w.created_at).toISOString(), updated_at: new Date(w.updated_at).toISOString() };
}
class Wishes {
  constructor(private db: D1Database, private actor: string) {}
  q(sql: string, ...values: Value[]) { return this.db.prepare(sql).bind(...values); }
  guard(predicate: string, ...values: Value[]) {
    const key = crypto.randomUUID(); return [this.q(`INSERT INTO hamtdaa_wish_guards(id,allowed) SELECT ?,CASE WHEN ${predicate} THEN 1 ELSE 0 END`, key, ...values), this.q('DELETE FROM hamtdaa_wish_guards WHERE id=?', key)];
  }
  pairGuard(pair: string) { return this.guard(`EXISTS(${activePair} AND p.id=?)`, this.actor, pair); }
  async checkPair(pair: string) { if (!await this.q(`${activePair} AND p.id=?`, this.actor, pair).first()) fail('pair_required', 409); }
  async receipt(command: string) { return this.q('SELECT pair_id,operation,payload_hash,wish_id,event_id FROM hamtdaa_wish_receipts WHERE user_id=? AND command_id=?', this.actor, command).first<Receipt>(); }
  async wish(pair: string, wishId: string) {
    return this.q(`SELECT ${wishColumns} FROM hamtdaa_wishes w WHERE w.id=? AND w.pair_id=? AND EXISTS(${activePair} AND p.id=w.pair_id)`, this.actor, this.actor, wishId, pair, this.actor).first<Wish>();
  }
  async replay(receipt: Receipt, operation: Operation, payloadHash: string): Promise<Response> {
    if (receipt.operation !== operation || receipt.payload_hash !== payloadHash) fail('idempotency_mismatch', 409);
    await this.checkPair(receipt.pair_id);
    if (operation === 'delete') return json({ ok: true, deleted: true });
    const row = await this.wish(receipt.pair_id, receipt.wish_id); if (!row) fail('wish_deleted', 410);
    if (operation === 'plan' && !await this.q('SELECT 1 FROM hamtdaa_calendar_events WHERE id=? AND pair_id=?', receipt.event_id, receipt.pair_id).first()) fail('event_deleted', 410);
    await this.checkPair(receipt.pair_id);
    return json({ ok: true, wish: metadata(row), ...(operation === 'plan' ? { event_id: receipt.event_id } : {}) });
  }
  async list(body: Json, exporting = false) {
    fields(body, ['expected_pair_id']); const pair = id(body.expected_pair_id);
    let results: D1Result[];
    try {
      results = await this.db.batch([...this.pairGuard(pair),
        this.q(`SELECT ${wishColumns} FROM hamtdaa_wishes w WHERE w.pair_id=? ${exporting ? 'AND w.creator_id=?' : ''} ORDER BY w.created_at DESC,w.id LIMIT 500`, this.actor, this.actor, pair, ...(exporting ? [this.actor] : [])),
        ...(exporting ? [this.q('SELECT l.wish_id FROM hamtdaa_wish_likes l JOIN hamtdaa_wishes w ON w.id=l.wish_id WHERE w.pair_id=? AND l.user_id=? ORDER BY l.wish_id LIMIT 500', pair, this.actor)] : []),
      ]);
    } catch (error) { await this.checkPair(pair); throw error; }
    await this.checkPair(pair);
    const rows = (results[2].results as Wish[]).map(metadata);
    if (exporting) return json({ ok: true, pair_id: pair, wishes: rows.map(({ partner_liked: _partner, ...own }) => own), likes: results[3].results.map(r => ({ wish_id: (r as { wish_id: string }).wish_id, liked: true })) });
    return json({ ok: true, pair_id: pair, wishes: rows });
  }
  async quota(pair: string, date: string, operation: Operation) {
    const row = await this.q(`SELECT
      COALESCE((SELECT mutations FROM hamtdaa_wish_quotas WHERE user_id=? AND day=?),0) mutations,
      (SELECT count(*) FROM hamtdaa_wishes WHERE pair_id=?) total,
      (SELECT count(*) FROM hamtdaa_wishes WHERE pair_id=? AND status<>'done') active,
      (SELECT count(*) FROM hamtdaa_calendar_events WHERE pair_id=?) events,
      COALESCE((SELECT mutations FROM hamtdaa_together_quotas WHERE user_id=? AND day=?),0) together_mutations,
      (SELECT count(*) FROM hamtdaa_together_receipts WHERE user_id=? AND day=? AND operation='calendar/create') event_creates`, this.actor, date, pair, pair, pair, this.actor, date, this.actor, date).first<{ mutations: number; total: number; active: number; events: number; together_mutations: number; event_creates: number }>();
    if (!row || row.mutations >= 100 || (operation === 'create' && (row.total >= 500 || row.active >= 200)) || (operation === 'plan' && (row.events >= 500 || row.together_mutations >= 100 || row.event_creates >= 30))) fail('quota_exceeded', 429);
  }
  async mutate(operation: Operation, body: Json) {
    const required = ['expected_pair_id', 'command_id', ...(operation === 'create' ? ['title', 'note', 'location', 'category', 'budget'] : ['id', 'expected_version']), ...(operation === 'like' ? ['liked'] : []), ...(operation === 'plan' ? ['starts_at', 'ends_at'] : [])];
    fields(body, required); const pair = id(body.expected_pair_id); const command = id(body.command_id);
    const wishId = operation === 'create' ? crypto.randomUUID() : id(body.id);
    let version = 1;
    if (operation !== 'create') { if (!Number.isSafeInteger(body.expected_version) || Number(body.expected_version) < 1) fail('validation'); version = Number(body.expected_version); }
    if (operation === 'like' && typeof body.liked !== 'boolean') fail('validation');
    const input = operation === 'create' ? { title: text(body.title, 80, true), note: text(body.note, 500), location: text(body.location, 120), category: choice(body.category, ['home', 'outdoor', 'food', 'travel', 'other']), budget: choice(body.budget, ['free', 'low', 'medium', 'high']) } : null;
    const starts = operation === 'plan' ? instant(body.starts_at) : null;
    const ends = operation === 'plan' && body.ends_at !== null ? instant(body.ends_at) : null;
    if (starts !== null && ends !== null && (ends <= starts || ends - starts > 2678400000)) fail('validation');
    const canonical: Json = { operation }; for (const key of required.filter(k => k !== 'command_id').sort()) canonical[key] = body[key];
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(canonical)));
    const payloadHash = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
    const prior = await this.receipt(command); if (prior) return this.replay(prior, operation, payloadHash);
    await this.checkPair(pair);
    const date = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10); const now = Date.now();
    try { await this.quota(pair, date, operation); }
    catch (error) {
      const concurrent = await this.receipt(command); if (concurrent) return this.replay(concurrent, operation, payloadHash);
      throw error;
    }
    const row = operation === 'create' ? null : await this.wish(pair, wishId);
    if (operation !== 'create') {
      // A concurrent retry may have deleted the row or changed its version already.
      const concurrent = await this.receipt(command); if (concurrent) return this.replay(concurrent, operation, payloadHash);
      if (!row) fail('not_found', 404);
      if (operation === 'delete' && row.creator_id !== this.actor) fail('forbidden', 403);
      if (row.version !== version) fail('conflict', 409);
      if ((operation === 'plan' || operation === 'like') && row.status !== 'idea') fail('conflict', 409);
      if (operation === 'complete' && (row.status !== 'planned' || row.event_status !== 'accepted' || row.event_starts_at === null || row.event_starts_at > now)) fail('conflict', 409);
      if (operation === 'plan' && (!row.my_liked || !row.partner_liked)) fail('mutual_like_required', 409);
    }
    const eventId = operation === 'plan' ? crypto.randomUUID() : null;
    const statements: D1PreparedStatement[] = [
      ...this.pairGuard(pair), ...this.guard("date('now','+8 hours')=?", date),
      this.q(`INSERT INTO hamtdaa_wish_quotas(user_id,day,mutations) VALUES(?,?,1) ON CONFLICT(user_id) DO UPDATE SET day=excluded.day,mutations=CASE WHEN hamtdaa_wish_quotas.day=excluded.day THEN hamtdaa_wish_quotas.mutations+1 ELSE 1 END`, this.actor, date),
      this.q('INSERT INTO hamtdaa_wish_receipts(user_id,command_id,pair_id,operation,payload_hash,wish_id,event_id,created_at) VALUES(?,?,?,?,?,?,?,?)', this.actor, command, pair, operation, payloadHash, wishId, eventId, now),
    ];
    if (operation === 'create' && input) {
      statements.push(...this.guard("(SELECT count(*) FROM hamtdaa_wishes WHERE pair_id=?)<500 AND (SELECT count(*) FROM hamtdaa_wishes WHERE pair_id=? AND status<>'done')<200", pair, pair),
        this.q("INSERT INTO hamtdaa_wishes(id,pair_id,creator_id,title,note,location,category,budget,status,version,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'idea',1,?,?)", wishId, pair, this.actor, input.title, input.note, input.location, input.category, input.budget, now, now),
        this.q('INSERT INTO hamtdaa_wish_likes(wish_id,user_id,created_at) VALUES(?,?,?)', wishId, this.actor, now));
    } else if (operation === 'like') {
      statements.push(this.q("UPDATE hamtdaa_wishes SET version=version+1,updated_at=? WHERE id=? AND pair_id=? AND version=? AND status='idea'", now, wishId, pair, version), ...this.guard('changes()=1'),
        body.liked ? this.q('INSERT INTO hamtdaa_wish_likes(wish_id,user_id,created_at) VALUES(?,?,?) ON CONFLICT(wish_id,user_id) DO NOTHING', wishId, this.actor, now) : this.q('DELETE FROM hamtdaa_wish_likes WHERE wish_id=? AND user_id=?', wishId, this.actor));
    } else if (operation === 'delete') {
      statements.push(this.q('DELETE FROM hamtdaa_wishes WHERE id=? AND pair_id=? AND version=? AND creator_id=?', wishId, pair, version, this.actor), ...this.guard('changes()=1'));
    } else if (operation === 'complete') {
      statements.push(this.q("UPDATE hamtdaa_wishes SET status='done',version=version+1,updated_at=? WHERE id=? AND pair_id=? AND version=? AND status='planned' AND EXISTS(SELECT 1 FROM hamtdaa_calendar_events e WHERE e.id=hamtdaa_wishes.event_id AND e.pair_id=hamtdaa_wishes.pair_id AND e.status='accepted' AND e.starts_at<=?)", now, wishId, pair, version, now), ...this.guard('changes()=1'));
    } else if (operation === 'plan' && row) {
      statements.push(
        ...this.guard("(SELECT count(*) FROM hamtdaa_calendar_events WHERE pair_id=?)<500 AND (SELECT count(*) FROM hamtdaa_together_receipts WHERE user_id=? AND day=? AND operation='calendar/create')<30", pair, this.actor, date),
        ...this.guard('EXISTS(SELECT 1 FROM hamtdaa_wish_likes WHERE wish_id=? AND user_id=?) AND EXISTS(SELECT 1 FROM hamtdaa_wish_likes l JOIN hamtdaa_pair_members m ON m.user_id=l.user_id AND m.pair_id=? AND m.revoked_at IS NULL WHERE l.wish_id=? AND l.user_id<>?)', wishId, this.actor, pair, wishId, this.actor),
        this.q(`INSERT INTO hamtdaa_together_quotas(user_id,day,mutations) VALUES(?,?,1) ON CONFLICT(user_id) DO UPDATE SET day=excluded.day,mutations=CASE WHEN hamtdaa_together_quotas.day=excluded.day THEN hamtdaa_together_quotas.mutations+1 ELSE 1 END`, this.actor, date),
        this.q("INSERT INTO hamtdaa_together_receipts(user_id,command_id,pair_id,payload_hash,operation,day,created_at) VALUES(?,?,?,?,'calendar/create',?,?)", this.actor, command, pair, payloadHash, date, now),
        this.q("INSERT INTO hamtdaa_calendar_events(id,pair_id,creator_id,title,note,location,starts_at,ends_at,status,version,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'pending',1,?,?)", eventId, pair, this.actor, row.title, row.note, row.location, starts, ends, now, now),
        this.q("UPDATE hamtdaa_wishes SET status='planned',event_id=?,version=version+1,updated_at=? WHERE id=? AND pair_id=? AND version=? AND status='idea' AND event_id IS NULL", eventId, now, wishId, pair, version), ...this.guard('changes()=1'));
    }
    try { await this.db.batch(statements); }
    catch (error) {
      const duplicate = await this.receipt(command); if (duplicate) return this.replay(duplicate, operation, payloadHash);
      await this.checkPair(pair); await this.quota(pair, date, operation);
      if (error instanceof Error && /constraint|wish_guards|wish_/i.test(error.message)) fail('conflict', 409); throw error;
    }
    const saved = await this.receipt(command); if (!saved) { await this.checkPair(pair); fail('temporarily_unavailable', 503); }
    return this.replay(saved, operation, payloadHash);
  }
}
export async function handleWishesRequest(operation: string, db: D1Database, actor: string, body: Json): Promise<Response> {
  try {
    const service = new Wishes(db, actor);
    if (operation === 'list' || operation === 'export') return await service.list(body, operation === 'export');
    if (operation === 'create' || operation === 'like' || operation === 'delete' || operation === 'plan' || operation === 'complete') return await service.mutate(operation, body);
    fail('not_found', 404);
  } catch (error) {
    if (error instanceof Problem) return json({ ok: false, code: error.code }, error.status);
    if (error instanceof Error && /constraint|wish_guards/i.test(error.message)) return json({ ok: false, code: 'conflict' }, 409);
    return json({ ok: false, code: 'temporarily_unavailable' }, 503);
  }
}
