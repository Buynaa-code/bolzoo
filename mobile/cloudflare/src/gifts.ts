/** Actor identity belongs to the native auth router, never the request body. */
type Json = Record<string, unknown>;
type Value = string | number | null;
type Pair = { id: string; partner_id: string; display_name: string };
type Receipt = { pair_id: string; gift_id: string; payload_hash: string };
type Gift = { id: string; pair_id: string; sender_id: string; recipient_id: string; sender_name: string; recipient_name: string; template_id: string; color_id: string; occasion: string; message: string; created_at: number };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const giftActorEligible = `EXISTS(SELECT 1 FROM hamtdaa_profiles p JOIN "user" u ON u.id=p.user_id WHERE p.user_id=? AND p.account_state='active' AND u.emailVerified=1)`;
const activePair = `SELECT p.id,other.user_id partner_id,op.display_name
 FROM hamtdaa_pairs p
 JOIN hamtdaa_pair_members own ON own.pair_id=p.id AND own.user_id=? AND own.revoked_at IS NULL
 JOIN hamtdaa_pair_members other ON other.pair_id=p.id AND other.user_id<>own.user_id AND other.revoked_at IS NULL
 JOIN hamtdaa_profiles ap ON ap.user_id=own.user_id AND ap.account_state='active'
 JOIN hamtdaa_profiles op ON op.user_id=other.user_id AND op.account_state='active'
 JOIN "user" au ON au.id=own.user_id AND au.emailVerified=1
 JOIN "user" ou ON ou.id=other.user_id AND ou.emailVerified=1
 WHERE p.state='active' AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b
 WHERE (b.blocker_id=own.user_id AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=own.user_id))`;
class Problem extends Error { constructor(readonly code: string, readonly status: number) { super(code); } }
function fail(code: string, status = 400): never { throw new Problem(code, status); }
function json(value: Json, status = 200) {
  return Response.json(value, { status, headers: { 'Cache-Control': 'no-store, private', Pragma: 'no-cache', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff', ...(status === 429 ? { 'Retry-After': '60' } : {}) } });
}
function fields(body: Json | null, required: string[], optional: string[] = []): Json {
  if (!body || Object.keys(body).some(k => !required.includes(k) && !optional.includes(k)) || required.some(k => !Object.hasOwn(body, k))) fail('validation');
  return body;
}
function id(value: unknown): string { if (typeof value !== 'string' || !UUID.test(value)) fail('validation'); return value.toLowerCase(); }
function text(value: unknown): string {
  if (typeof value !== 'string' || value.length > 500 || !value.trim() || /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(value)) fail('validation');
  return value.trim();
}
function pick(value: unknown, options: string[]): string { if (typeof value !== 'string' || !options.includes(value)) fail('validation'); return value; }
function readCursor(value: unknown): { pair: string; created: number; id: string; revision: string } | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length > 400 || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) fail('validation');
  try {
    const decoded = atob(value); if (btoa(decoded) !== value) fail('validation');
    const parts: unknown = JSON.parse(decoded);
    if (!Array.isArray(parts) || parts.length !== 5 || parts[0] !== 'flowers-v1' || !Number.isSafeInteger(parts[2]) || parts[2] < 0 ||
      typeof parts[4] !== 'string' || !/^[a-f0-9]{64}$/.test(parts[4])) fail('validation');
    return { pair: id(parts[1]), created: Number(parts[2]), id: id(parts[3]), revision: parts[4] };
  } catch { fail('validation'); }
}
async function hash(value: Json) {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(value))));
  return [...bytes].map(v => v.toString(16).padStart(2, '0')).join('');
}
class Gifts {
  constructor(private db: D1Database, private actor: string) {}
  q(sql: string, ...values: Value[]) { return this.db.prepare(sql).bind(...values); }
  guard(predicate: string, ...values: Value[]) {
    const key = crypto.randomUUID();
    return [this.q(`INSERT INTO hamtdaa_gift_guards(id,allowed) SELECT ?,CASE WHEN ${predicate} THEN 1 ELSE 0 END`, key, ...values), this.q('DELETE FROM hamtdaa_gift_guards WHERE id=?', key)];
  }
  pairGuard(pair: string) { return this.guard(`EXISTS(${activePair} AND p.id=?)`, this.actor, pair); }
  async eligible() {
    await this.q('INSERT OR IGNORE INTO hamtdaa_profiles(user_id) SELECT id FROM "user" WHERE id=? AND emailVerified=1', this.actor).run();
    if (!await this.q(`SELECT 1 WHERE ${giftActorEligible}`, this.actor).first()) fail('unauthenticated', 401);
  }
  async pair() { return this.q(activePair, this.actor).first<Pair>(); }
  async receipt(command: string) { return this.q('SELECT pair_id,gift_id,payload_hash FROM hamtdaa_gift_receipts WHERE user_id=? AND command_id=?', this.actor, command).first<Receipt>(); }
  async replay(receipt: Receipt, digest: string) {
    if (receipt.payload_hash !== digest) fail('idempotency_mismatch', 409);
    try { await this.db.batch(this.pairGuard(receipt.pair_id)); }
    catch (error) { if (error instanceof Error && /constraint|gift_guards/i.test(error.message)) fail('pair_required', 409); throw error; }
    return json({ ok: true, id: receipt.gift_id });
  }
  async state(body: Json | null) {
    const value = fields(body, [], ['cursor']); const cursor = readCursor(value.cursor);
    const result = await this.db.batch([
      ...this.guard(giftActorEligible, this.actor), this.q(activePair, this.actor),
      this.q(`WITH current_pair AS (${activePair}) SELECT g.*,sp.display_name sender_name,rp.display_name recipient_name
        FROM hamtdaa_flower_gifts g JOIN current_pair p ON p.id=g.pair_id
        JOIN hamtdaa_profiles sp ON sp.user_id=g.sender_id JOIN hamtdaa_profiles rp ON rp.user_id=g.recipient_id
        WHERE g.sender_id IN(?,p.partner_id) AND g.recipient_id IN(?,p.partner_id)
        AND (? IS NULL OR p.id=?) AND (? IS NULL OR (g.created_at,g.id)<(?,?))
        ORDER BY g.created_at DESC,g.id DESC LIMIT 31`, this.actor, this.actor, this.actor, cursor?.pair ?? null, cursor?.pair ?? null, cursor?.id ?? null, cursor?.created ?? null, cursor?.id ?? null),
      // Gifts are immutable after creation. A bounded ID snapshot detects sends
      // and deletions between pages, including a deleted card from an earlier page.
      this.q(`WITH current_pair AS (${activePair}) SELECT g.id,g.created_at
        FROM hamtdaa_flower_gifts g JOIN current_pair p ON p.id=g.pair_id
        WHERE g.sender_id IN(?,p.partner_id) AND g.recipient_id IN(?,p.partner_id)
        ORDER BY g.id LIMIT 500`, this.actor, this.actor, this.actor),
    ]);
    const pair = result[2].results[0] as Pair | undefined;
    if (cursor && cursor.pair !== pair?.id) fail('pair_changed', 409);
    const revision = await hash({ gifts: (result[4].results as { id: string; created_at: number }[])
      .map(row => [row.id, row.created_at]) });
    if (cursor && cursor.revision !== revision) fail('gifts_changed', 409);
    const rows = result[3].results as Gift[]; const page = rows.slice(0, 30); const last = page.at(-1);
    return json({ ok: true, paired: !!pair, pair_id: pair?.id ?? null, partner: pair ? { id: pair.partner_id, display_name: pair.display_name } : null,
      gifts: page.map(g => ({ ...g, created_at: new Date(g.created_at).toISOString() })),
      next_cursor: rows.length > 30 && last && pair ? btoa(JSON.stringify(['flowers-v1', pair.id, last.created_at, last.id, revision])) : null });
  }
  async mutate(operation: string, body: Json | null) {
    const value = fields(body, ['command_id', 'expected_pair_id', ...(operation === 'send' ? ['template_id', 'color_id', 'occasion', 'message'] : ['id'])]);
    const command = id(value.command_id), expected = id(value.expected_pair_id);
    const content = operation === 'send' ? { template_id: pick(value.template_id, ['letter', 'garden', 'bloom']), color_id: pick(value.color_id, ['rose', 'sage', 'peach']),
      occasion: pick(value.occasion, ['Зүгээр л', 'Төрсөн өдөр', 'Баярлалаа']), message: text(value.message) } : null;
    const selected = operation === 'delete' ? id(value.id) : null;
    const digest = await hash({ operation, expected_pair_id: expected, ...(content ?? { id: selected }) });
    const previous = await this.receipt(command); if (previous) return this.replay(previous, digest);
    const pair = await this.pair(); if (!pair) fail('pair_required', 409); if (pair.id !== expected) fail('pair_changed', 409);
    const now = Date.now(), day = new Date(now + 8 * 3600000).toISOString().slice(0, 10);
    const used = await this.q(`SELECT (SELECT mutations FROM hamtdaa_gift_quotas WHERE user_id=? AND day=?) mutations,
      (SELECT count(*) FROM hamtdaa_gift_receipts WHERE user_id=? AND day=? AND operation='send') sends,
      (SELECT count(*) FROM hamtdaa_flower_gifts WHERE pair_id=?) gifts`, this.actor, day, this.actor, day, pair.id).first<{ mutations: number | null; sends: number; gifts: number }>();
    if ((used?.mutations ?? 0) >= 60 || (content && (used!.sends >= 20 || used!.gifts >= 500))) fail('quota_exceeded', 429);
    const giftId = selected ?? crypto.randomUUID();
    const mutations: D1PreparedStatement[] = [];
    if (content) {
      mutations.push(...this.guard(`(SELECT count(*) FROM hamtdaa_flower_gifts WHERE pair_id=?)<500 AND
        (SELECT count(*) FROM hamtdaa_gift_receipts WHERE user_id=? AND day=? AND operation='send')<=20`, pair.id, this.actor, day));
      mutations.push(this.q('INSERT INTO hamtdaa_flower_gifts(id,pair_id,sender_id,recipient_id,template_id,color_id,occasion,message,created_at) VALUES(?,?,?,?,?,?,?,?,?)',
        giftId, pair.id, this.actor, pair.partner_id, content.template_id, content.color_id, content.occasion, content.message, now));
    } else {
      const gift = await this.q('SELECT sender_id FROM hamtdaa_flower_gifts WHERE id=? AND pair_id=?', giftId, pair.id).first<{ sender_id: string }>();
      if (!gift) fail('not_found', 404); if (gift.sender_id !== this.actor) fail('forbidden', 403);
      mutations.push(this.q('DELETE FROM hamtdaa_flower_gifts WHERE id=? AND pair_id=? AND sender_id=?', giftId, pair.id, this.actor), ...this.guard('changes()=1'));
    }
    try {
      await this.db.batch([
        ...this.pairGuard(pair.id), ...this.guard("date('now','+8 hours')=?", day),
        this.q('INSERT INTO hamtdaa_gift_receipts(user_id,command_id,pair_id,gift_id,payload_hash,operation,day,created_at) VALUES(?,?,?,?,?,?,?,?)', this.actor, command, pair.id, giftId, digest, operation, day, now),
        this.q(`INSERT INTO hamtdaa_gift_quotas(user_id,day,mutations) VALUES(?,?,1) ON CONFLICT(user_id) DO UPDATE SET day=excluded.day,
          mutations=CASE WHEN hamtdaa_gift_quotas.day=excluded.day THEN hamtdaa_gift_quotas.mutations+1 ELSE 1 END`, this.actor, day), ...mutations,
      ]);
    } catch (error) {
      const duplicate = await this.receipt(command); if (duplicate) return this.replay(duplicate, digest);
      if (error instanceof Error && /constraint|gift_guards/i.test(error.message)) {
        const live = await this.pair(); if (live?.id !== expected) fail(live ? 'pair_changed' : 'pair_required', 409);
        fail('conflict', 409);
      }
      throw error;
    }
    return json({ ok: true, id: giftId });
  }
}
export async function handleGiftRequest(request: Request, env: { DB: D1Database }, actor: string, body: Json | null): Promise<Response> {
  try {
    if (request.method !== 'POST') return json({ ok: false, code: 'method_not_allowed' }, 405);
    const operation = new URL(request.url).pathname.replace(/^\/v1\/gifts\//, '');
    if (!['state', 'send', 'delete'].includes(operation)) fail('not_found', 404);
    const service = new Gifts(env.DB, actor); await service.eligible();
    return operation === 'state' ? await service.state(body) : await service.mutate(operation, body);
  } catch (error) {
    if (error instanceof Problem) return json({ ok: false, code: error.code }, error.status);
    return json({ ok: false, code: 'temporarily_unavailable' }, 503);
  }
}
