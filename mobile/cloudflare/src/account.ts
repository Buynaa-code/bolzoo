/** Account identity and session creation time come only from the auth router. */
export type AccountEnvironment = { DB: D1Database; BETTER_AUTH_SECRET: string };
export type AccountActor = { id: string; email: string; sessionId: string; sessionCreatedAt: string };
type Json = Record<string, unknown>;
type Value = string | number | null;
const PAGE_SIZE = 50;
const SECTIONS = ['profile', 'calendar', 'daily_answers', 'flower_gifts', 'billing_orders', 'billing_subscriptions'] as const;
type Section = typeof SECTIONS[number];
const activeActor = `EXISTS(SELECT 1 FROM "user" u LEFT JOIN hamtdaa_profiles p ON p.user_id=u.id
 WHERE u.id=? AND u.email=? AND u.emailVerified=1 AND (p.user_id IS NULL OR p.account_state='active')
 AND NOT EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts d WHERE d.user_id=u.id))`;
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

function json(value: Json, status = 200): Response {
  return Response.json(value, { status, headers: {
    'Cache-Control': 'no-store, private', Pragma: 'no-cache',
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    ...(status === 429 ? { 'Retry-After': '60' } : {}),
  } });
}
const error = (code: string, status: number) => json({ ok: false, code, retryable: status >= 500 || status === 429 }, status);
function exact(body: unknown, allowed: string[]): body is Json {
  return body !== null && typeof body === 'object' && !Array.isArray(body)
    && Object.keys(body).every(key => allowed.includes(key));
}
function q(db: D1Database, sql: string, ...values: Value[]) { return db.prepare(sql).bind(...values); }
function guard(db: D1Database, predicate: string, ...values: Value[]) {
  const id = crypto.randomUUID();
  return [q(db, `INSERT INTO hamtdaa_account_guards(id,allowed) SELECT ?,CASE WHEN ${predicate} THEN 1 ELSE 0 END`, id, ...values),
    q(db, 'DELETE FROM hamtdaa_account_guards WHERE id=?', id)];
}
async function keyedHash(secret: string, purpose: string, value: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${purpose}\0${value}`));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

/** Cursor is merely a bounded keyset position, never an authorization token. */
function readCursor(value: unknown, section: Section): string[] | null {
  if (value === undefined || value === null) return [];
  if (typeof value !== 'string' || value.length > 1200 || !/^[A-Za-z0-9+/=]+$/.test(value)) return null;
  try {
    const parsed: unknown = JSON.parse(atob(value));
    if (!Array.isArray(parsed) || parsed[0] !== section || parsed.length !== (section === 'daily_answers' ? 4 : section === 'billing_subscriptions' ? 3 : 2)) return null;
    const keys = parsed.slice(1);
    return keys.every(key => typeof key === 'string' && key.length > 0 && key.length <= 400 && !/[\u0000-\u001f\u007f]/.test(key)) ? keys as string[] : null;
  } catch { return null; }
}
const cursor = (section: Section, keys: unknown[]) => btoa(JSON.stringify([section, ...keys]));

async function exportData(env: AccountEnvironment, actor: AccountActor, body: Json): Promise<Response> {
  const section = (body.section ?? 'profile') as Section;
  if (!SECTIONS.includes(section)) return error('validation', 400);
  const after = readCursor(body.cursor, section);
  if (after === null || (section === 'profile' && after.length)) return error('validation', 400);
  const db = env.DB;
  const minute = Math.floor(Date.now() / 60000);
  // 60 bounded pages/minute permits large exports without an unbounded query.
  const rate = await q(db, `INSERT INTO hamtdaa_account_export_limits(user_id,window_start,attempts)
    SELECT id,?,1 FROM "user" WHERE id=? AND emailVerified=1
    ON CONFLICT(user_id) DO UPDATE SET window_start=excluded.window_start,
      attempts=CASE WHEN hamtdaa_account_export_limits.window_start=excluded.window_start
      THEN min(hamtdaa_account_export_limits.attempts+1,1000000) ELSE 1 END RETURNING attempts`, minute, actor.id).first<{ attempts: number }>();
  if (!rate) return error('unauthenticated', 401);
  if (rate.attempts > 60) return error('rate_limited', 429);
  let statement: D1PreparedStatement;
  if (section === 'profile') {
    statement = q(db, `SELECT u.id,u.email,u.name,u.image,u.createdAt created_at,p.display_name
      FROM "user" u LEFT JOIN hamtdaa_profiles p ON p.user_id=u.id WHERE u.id=?`, actor.id);
  } else if (section === 'calendar') {
    statement = q(db, `WITH current_pair AS (${activePair})
      SELECT e.id,e.pair_id,e.creator_id,e.title,e.note,e.location,e.starts_at,e.ends_at,e.status,e.version,e.created_at,e.updated_at,e.music_json
      FROM hamtdaa_calendar_events e WHERE (e.creator_id=? OR e.pair_id IN(SELECT id FROM current_pair))
      AND e.id>? ORDER BY e.id LIMIT 51`, actor.id, actor.id, after[0] ?? '');
  } else if (section === 'daily_answers') {
    statement = q(db, `WITH current_pair AS (${activePair})
      SELECT a.pair_id,a.day,a.user_id,a.question_id,a.answer,a.created_at FROM hamtdaa_daily_answers a
      WHERE (a.user_id=? OR (a.pair_id IN(SELECT id FROM current_pair) AND EXISTS(
        SELECT 1 FROM hamtdaa_daily_answers own WHERE own.pair_id=a.pair_id AND own.day=a.day
        AND own.question_id=a.question_id AND own.user_id=?)))
      AND (a.pair_id,a.day,a.user_id)>(?,?,?) ORDER BY a.pair_id,a.day,a.user_id LIMIT 51`,
      actor.id, actor.id, actor.id, after[0] ?? '', after[1] ?? '', after[2] ?? '');
  } else if (section === 'flower_gifts') {
    statement = q(db, `WITH current_pair AS (${activePair})
      SELECT g.id,g.pair_id,g.sender_id,g.recipient_id,g.template_id,g.color_id,g.occasion,g.message,g.created_at
      FROM hamtdaa_flower_gifts g WHERE (g.sender_id=? OR g.pair_id IN(SELECT id FROM current_pair))
      AND g.id>? ORDER BY g.id LIMIT 51`, actor.id, actor.id, after[0] ?? '');
  } else if (section === 'billing_orders') {
    statement = q(db, `SELECT id,plan,duration_seconds,amount_minor,currency,livemode,provider_id,state,created_at,updated_at
      FROM hamtdaa_billing_orders WHERE user_id=? AND id>? ORDER BY id LIMIT 51`, actor.id, after[0] ?? '');
  } else {
    statement = q(db, `SELECT provider,source_id,environment,transaction_id,product_id,starts_at,expires_at,revoked_at,auto_renew,is_active
      FROM hamtdaa_billing_grants WHERE user_id=? AND (provider,source_id)>(?,?) ORDER BY provider,source_id LIMIT 51`, actor.id, after[0] ?? '', after[1] ?? '');
  }
  try {
    // Read actor access and all projections in one D1 snapshot transaction.
    const result = await db.batch([...guard(db, activeActor, actor.id, actor.email), statement,
      ...(section === 'profile' ? [q(db, activePair, actor.id)] : [])]);
    const rows = result[2].results as Json[];
    const data = rows.slice(0, PAGE_SIZE);
    const last = data.at(-1);
    const next = rows.length > PAGE_SIZE && last ? cursor(section, section === 'daily_answers'
      ? [last.pair_id, last.day, last.user_id] : section === 'billing_subscriptions'
      ? [last.provider, last.source_id] : [last.id]) : null;
    const exported: Json = { schema_version: 1, section, generated_at: new Date().toISOString(),
      timestamp_units: 'calendar/daily/flower_gifts milliseconds; billing seconds', data, next_cursor: next };
    if (section === 'profile') {
      exported.account = rows[0];
      exported.pair = result[3].results[0] ?? null;
      exported.sections = SECTIONS;
      delete exported.data;
    }
    const value = { ok: true, export: exported };
    if (new TextEncoder().encode(JSON.stringify(value)).byteLength > 512 * 1024) return error('export_too_large', 503);
    return json(value);
  } catch {
    if (!await q(db, `SELECT 1 WHERE ${activeActor}`, actor.id, actor.email).first()) return error('unauthenticated', 401);
    return error('temporarily_unavailable', 503);
  }
}

async function deleteAccount(env: AccountEnvironment, actor: AccountActor): Promise<Response> {
  const created = Date.parse(actor.sessionCreatedAt);
  const now = Date.now();
  if (!Number.isFinite(created) || created < now - 600000 || created > now + 30000) return error('reauthentication_required', 409);
  if (!env.BETTER_AUTH_SECRET || env.BETTER_AUTH_SECRET.length < 32) return error('temporarily_unavailable', 503);
  const db = env.DB;
  const seconds = Math.floor(now / 1000);
  // Better Auth's SQLite adapter has supportsDates=false: it stores canonical
  // ISO strings, not Unix milliseconds. Keep comparisons in that native format.
  const nowIso = new Date(now).toISOString();
  const createdIso = new Date(created).toISOString();
  const freshSince = new Date(now - 600000).toISOString();
  const tombstoneEmail = `deleted-${crypto.randomUUID()}@deleted.invalid`;
  const otpHash = await keyedHash(env.BETTER_AUTH_SECRET, 'auth-identifier-v1', `sign-in-otp-${actor.email}`);
  const rateHashes = await Promise.all(['send-cooldown', 'send-hour', 'verify-email'].map(key =>
    keyedHash(env.BETTER_AUTH_SECRET, 'auth-rate-v1', `${key}|${actor.email}`)));
  try {
    await db.batch([
      ...guard(db, activeActor, actor.id, actor.email),
      // A revoked login cannot delete by racing after the router's auth check.
      ...guard(db, `EXISTS(SELECT 1 FROM "session" WHERE id=? AND userId=? AND createdAt=?
        AND expiresAt>? AND createdAt>=?)`, actor.sessionId, actor.id, createdIso, nowIso, freshSince),
      q(db, 'INSERT INTO hamtdaa_deleted_accounts(user_id,deleted_at) VALUES(?,?)', actor.id, now),
      q(db, `INSERT INTO hamtdaa_profiles(user_id,display_name,account_state) VALUES(?,'Устгасан бүртгэл','disabled')
        ON CONFLICT(user_id) DO UPDATE SET display_name=excluded.display_name,account_state='disabled',version=hamtdaa_profiles.version+1`, actor.id),
      q(db, `UPDATE "user" SET name='Deleted account',email=?,emailVerified=0,image=NULL,createdAt=?,updatedAt=? WHERE id=?`, tombstoneEmail, nowIso, nowIso, actor.id),
      q(db, `UPDATE hamtdaa_pairs SET state='unlinked',unlinked_at=COALESCE(unlinked_at,?),version=version+1
        WHERE id IN(SELECT pair_id FROM hamtdaa_pair_members WHERE user_id=?) AND state<>'unlinked'`, seconds, actor.id),
      q(db, `UPDATE hamtdaa_pair_members SET revoked_at=COALESCE(revoked_at,?)
        WHERE pair_id IN(SELECT pair_id FROM hamtdaa_pair_members WHERE user_id=?)`, seconds, actor.id),
      q(db, `UPDATE hamtdaa_pair_invitations SET state='revoked',requester_id=NULL,requested_at=NULL,confirmed_at=NULL,
        token_hash=lower(hex(randomblob(32))),version=version+1 WHERE creator_id=? OR requester_id=?`, actor.id, actor.id),
      q(db, 'DELETE FROM hamtdaa_calendar_events WHERE creator_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_flower_gifts WHERE sender_id=? OR recipient_id=?', actor.id, actor.id),
      q(db, 'DELETE FROM hamtdaa_gift_receipts WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_gift_quotas WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_music_limits WHERE scope IN(?,?)', `user:${actor.id}:minute`, `user:${actor.id}:day`),
      q(db, 'DELETE FROM hamtdaa_daily_answers WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_together_receipts WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_together_quotas WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_pair_receipts WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_pair_rate_limits WHERE user_id=?', actor.id),
      q(db, 'DELETE FROM hamtdaa_blocks WHERE blocker_id=? OR blocked_id=?', actor.id, actor.id),
      q(db, 'DELETE FROM hamtdaa_pair_members WHERE user_id=?', actor.id),
      q(db, `DELETE FROM hamtdaa_pair_invitations WHERE creator_id=?
        AND NOT EXISTS(SELECT 1 FROM hamtdaa_pairs WHERE invitation_id=hamtdaa_pair_invitations.id)`, actor.id),
      q(db, 'DELETE FROM "session" WHERE userId=?', actor.id),
      q(db, 'DELETE FROM "account" WHERE userId=?', actor.id),
      q(db, 'DELETE FROM "verification" WHERE identifier=?', otpHash),
      q(db, 'DELETE FROM "rateLimit" WHERE "key" IN(?,?,?)', ...rateHashes),
      q(db, 'DELETE FROM hamtdaa_account_export_limits WHERE user_id=?', actor.id),
      q(db, 'UPDATE hamtdaa_billing_grants SET refresh_cipher=NULL,is_active=0 WHERE user_id=?', actor.id),
      q(db, 'UPDATE hamtdaa_billing_orders SET checkout_url=NULL,next_action=NULL WHERE user_id=?', actor.id),
    ]);
    return json({ ok: true, deleted: true, deleted_at: new Date(now).toISOString(),
      retained: ['opaque_payment_ownership_and_transaction_audit'],
      subscriptions: 'Store subscriptions are not canceled by account deletion. Manage them in App Store or Google Play.' });
  } catch {
    if (!await q(db, `SELECT 1 WHERE ${activeActor}`, actor.id, actor.email).first()) return error('unauthenticated', 401);
    const live = await q(db, `SELECT 1 FROM "session" WHERE id=? AND userId=? AND createdAt=? AND expiresAt>?`, actor.sessionId, actor.id, createdIso, nowIso).first();
    if (!live) return error('reauthentication_required', 409);
    return error('temporarily_unavailable', 503);
  }
}

export async function handleAccountRequest(request: Request, env: AccountEnvironment, actor: AccountActor, body: unknown): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (request.method !== 'POST' || !['/v1/account/export', '/v1/account/delete'].includes(path)) return error('not_found', 404);
  if (!actor.id || !actor.email) return error('unauthenticated', 401);
  if (!exact(body, path.endsWith('/delete') ? ['confirmation'] : ['section', 'cursor'])) return error('validation', 400);
  if (!await q(env.DB, `SELECT 1 WHERE ${activeActor}`, actor.id, actor.email).first()) return error('unauthenticated', 401);
  if (path.endsWith('/export')) return exportData(env, actor, body);
  if (body.confirmation !== 'УСТГАХ') return error('validation', 400);
  return deleteAccount(env, actor);
}
