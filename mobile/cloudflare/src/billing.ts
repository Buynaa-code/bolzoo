import { createAuthRateStorage, type AuthEnvironment } from './auth';

export type BillingEnvironment = AuthEnvironment & {
  BILLING_ENABLED?: string;
  BILLING_WEB_ENABLED?: string;
  BILLING_WIRE_MODE?: string;
  BILLING_WEB_ORIGIN?: string;
  BILLING_WEB_RETURN_URL?: string;
  WIRE_API_KEY?: string;
  WIRE_WEBHOOK_SECRET?: string;
};
type Json = Record<string, unknown>;
type Order = {
  id: string; user_id: string; command_id: string; plan: 'monthly' | 'yearly';
  duration_seconds: number; amount_minor: number; currency: string; livemode: number;
  return_url: string; description: string; provider_id: string | null; state: string;
  next_action: string | null; expires_at: number | null; created_at: number; updated_at: number;
};
const PLANS = {
  monthly: { amount_mnt: 9900, duration_days: 30 },
  yearly: { amount_mnt: 79900, duration_days: 365 },
} as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROVIDER_ID = /^[A-Za-z0-9_-]{1,200}$/;
const WIRE_STATES = new Set(['new', 'requires_payment_method', 'requires_action', 'requires_capture', 'processing', 'succeeded', 'canceled']);
const seconds = () => Math.floor(Date.now() / 1000);
const object = (value: unknown): Json | null => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Json : null;
const iso = (value: number | null) => value === null ? null : new Date(value * 1000).toISOString();
class BillingError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
function fail(status: number, code: string): never { throw new BillingError(status, code); }
function json(value: unknown, status = 200) {
  return Response.json(value, { status, headers: { 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' } });
}
function exact(body: Json | null, keys: string[]): Json {
  if (!body || Object.keys(body).some((key) => !keys.includes(key))) fail(400, 'invalid_request');
  return body;
}
async function requireActor(env: BillingEnvironment, actor: string | null): Promise<string> {
  if (!actor) fail(401, 'unauthenticated');
  const valid = await env.DB.prepare(`SELECT u.id FROM "user" u LEFT JOIN hamtdaa_profiles p ON p.user_id=u.id
    WHERE u.id=? AND u.emailVerified=1 AND (p.user_id IS NULL OR p.account_state='active')`).bind(actor).first();
  if (!valid) fail(401, 'unauthenticated');
  return actor;
}
function webConfig(env: BillingEnvironment) {
  try {
    const origin = new URL(env.BILLING_WEB_ORIGIN ?? '');
    const returnURL = new URL(env.BILLING_WEB_RETURN_URL ?? '');
    const mode = env.BILLING_WIRE_MODE;
    if (origin.protocol !== 'https:' || origin.origin !== env.BILLING_WEB_ORIGIN ||
      returnURL.protocol !== 'https:' || returnURL.origin !== origin.origin || returnURL.username || returnURL.password ||
      (mode !== 'live' && mode !== 'test') || !env.WIRE_API_KEY?.startsWith(mode === 'live' ? 'sk_live_' : 'sk_test_') ||
      !env.WIRE_WEBHOOK_SECRET?.startsWith('whsec_')) return null;
    return { origin: origin.origin, returnURL: returnURL.href, live: mode === 'live' };
  } catch { return null; }
}
function requireWire(env: BillingEnvironment, request?: Request) {
  const config = webConfig(env);
  if (env.BILLING_ENABLED !== 'true' || env.BILLING_WEB_ENABLED !== 'true' || !config) fail(503, 'billing_unavailable');
  // The separate web checkout only accepts its configured first-party origin.
  // Native screens contain no route/link to this checkout.
  if (request && request.headers.get('Origin') !== config.origin) fail(403, 'web_origin_required');
  return config;
}
async function rate(env: BillingEnvironment, actor: string, action: string, max: number) {
  const result = await createAuthRateStorage(env).consume(`billing|${action}|${actor}`, { window: 60, max });
  if (!result.allowed) fail(429, 'rate_limited');
}
async function boundedText(stream: ReadableStream<Uint8Array> | null, limit: number): Promise<string> {
  if (!stream) return '';
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > limit) { await reader.cancel(); fail(413, 'payload_too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const all = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { all.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder('utf-8', { fatal: true }).decode(all);
}
async function wire(env: BillingEnvironment, method: 'GET' | 'POST', path: string, body?: Json, idempotency?: string): Promise<Json> {
  const headers = new Headers({ Authorization: `Bearer ${env.WIRE_API_KEY}`, 'Content-Type': 'application/json' });
  if (idempotency) headers.set('Idempotency-Key', idempotency);
  try {
    const response = await fetch(`https://api.wire.mn${path}`, {
      method, headers, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000), redirect: 'error',
    });
    const text = await boundedText(response.body, 128 * 1024);
    if (!response.ok) fail(502, 'payment_provider_unavailable');
    const value = object(JSON.parse(text));
    if (!value) fail(502, 'invalid_provider_response');
    return value;
  } catch (error) {
    if (error instanceof BillingError) throw error;
    fail(502, 'payment_provider_unavailable');
  }
}
function checkIntent(order: Order, remote: Json, creating = false) {
  const metadata = object(remote.metadata);
  if (typeof remote.id !== 'string' || !PROVIDER_ID.test(remote.id) ||
    (!creating && remote.id !== order.provider_id) || remote.object !== 'payment_intent' ||
    remote.amount !== order.amount_minor || !Number.isSafeInteger(remote.amount) || remote.currency !== order.currency ||
    remote.livemode !== Boolean(order.livemode) || typeof remote.status !== 'string' || !WIRE_STATES.has(remote.status) ||
    metadata?.product !== 'hamtdaa_plus' || metadata.order_id !== order.id || metadata.plan !== order.plan ||
    (remote.selected_operator != null && remote.selected_operator !== (order.livemode ? 'qpay' : 'sandbox'))) {
    fail(502, 'payment_mismatch');
  }
}
async function readOrder(env: BillingEnvironment, id: string): Promise<Order> {
  const row = await env.DB.prepare('SELECT * FROM hamtdaa_billing_orders WHERE id=?').bind(id).first<Order>();
  if (!row) fail(404, 'order_not_found');
  return row;
}
function publicOrder(row: Order) {
  return { order_id: row.id, plan: row.plan, amount_mnt: row.amount_minor / 100, currency: row.currency,
    state: row.state, auto_renew: false, duration_days: row.duration_seconds / 86400,
    mode: row.livemode ? 'live' : 'test', expires_at: iso(row.expires_at),
    next_action: ['succeeded', 'canceled', 'refunded'].includes(row.state) ? null : row.next_action ? JSON.parse(row.next_action) as unknown : null };
}
async function chargeState(env: BillingEnvironment, row: Order): Promise<{ paid: boolean; refunded: boolean }> {
  const response = await wire(env, 'GET', `/v1/charges?payment_intent=${encodeURIComponent(row.provider_id!)}&limit=100`);
  if (!Array.isArray(response.data) || response.has_more !== false || response.data.length > 100) fail(502, 'invalid_charge_response');
  let paid = false;
  let refunded = false;
  for (const value of response.data) {
    const charge = object(value);
    if (!charge || typeof charge.id !== 'string' || !PROVIDER_ID.test(charge.id) || charge.object !== 'charge' ||
      charge.payment_intent !== row.provider_id || charge.livemode !== Boolean(row.livemode) ||
      charge.amount !== row.amount_minor || !Number.isSafeInteger(charge.amount_refunded) ||
      Number(charge.amount_refunded) < 0 || Number(charge.amount_refunded) > row.amount_minor ||
      !['pending', 'succeeded', 'failed'].includes(String(charge.status)) || charge.operator !== (row.livemode ? 'qpay' : 'sandbox')) {
      fail(502, 'payment_mismatch');
    }
    paid ||= charge.status === 'succeeded';
    refunded ||= Number(charge.amount_refunded) > 0;
  }
  return { paid, refunded };
}
async function reconcile(env: BillingEnvironment, row: Order, remote: Json, eventId?: string): Promise<Order> {
  checkIntent(row, remote);
  let state = String(remote.status);
  // Charges are authoritative for refunds; a callback never supplies the result.
  if (state === 'succeeded' || row.state === 'succeeded' || row.state === 'refunded') {
    const charges = await chargeState(env, row);
    if (charges.refunded) state = 'refunded';
    else if (state === 'succeeded' && !charges.paid) fail(502, 'payment_not_settled');
  }
  const now = seconds();
  const nextAction = object(remote.next_action);
  const expiry = remote.expires_at === null || remote.expires_at === undefined ? null : remote.expires_at;
  if (expiry !== null && (!Number.isSafeInteger(expiry) || Number(expiry) < 0)) fail(502, 'payment_mismatch');
  const statements = [env.DB.prepare(`UPDATE hamtdaa_billing_orders SET
    state=CASE WHEN state IN ('canceled','refunded') THEN state WHEN ? IN ('canceled','refunded') THEN ?
      WHEN state='succeeded' THEN state ELSE ? END,
    next_action=?, expires_at=?, updated_at=? WHERE id=?`).bind(state, state, state,
      nextAction ? JSON.stringify(nextAction) : null, expiry as number | null, now, row.id)];
  // One insert chooses a frozen period atomically. Replayed or concurrent polls
  // cannot add time. Only live, settled payments can create real access.
  if (state === 'succeeded' && row.livemode === 1) {
    statements.push(env.DB.prepare(`INSERT INTO hamtdaa_billing_grants
      (provider,source_id,user_id,transaction_id,product_id,starts_at,expires_at,observed_at)
      SELECT 'wire',o.provider_id,o.user_id,o.provider_id,o.plan,
        MAX(?,COALESCE((SELECT MAX(expires_at) FROM hamtdaa_billing_grants g
          WHERE g.user_id=o.user_id AND g.provider='wire' AND g.revoked_at IS NULL),0)),
        MAX(?,COALESCE((SELECT MAX(expires_at) FROM hamtdaa_billing_grants g
          WHERE g.user_id=o.user_id AND g.provider='wire' AND g.revoked_at IS NULL),0))+o.duration_seconds,?
      FROM hamtdaa_billing_orders o WHERE o.id=? AND o.state='succeeded'
      ON CONFLICT(provider,source_id) DO NOTHING`).bind(now, now, now, row.id));
  }
  if (state === 'canceled' || state === 'refunded') {
    statements.push(env.DB.prepare(`UPDATE hamtdaa_billing_grants SET revoked_at=COALESCE(revoked_at,?),observed_at=?
      WHERE provider='wire' AND source_id=?`).bind(now, now, row.provider_id));
  }
  if (eventId) statements.push(env.DB.prepare(`INSERT INTO hamtdaa_billing_events(provider,event_id,order_id,processed_at)
    VALUES('wire',?,?,?) ON CONFLICT(provider,event_id) DO NOTHING`).bind(eventId, row.id, now));
  await env.DB.batch(statements);
  return readOrder(env, row.id);
}
async function refresh(env: BillingEnvironment, row: Order, eventId?: string) {
  if (!row.provider_id) return row;
  const config = requireWire(env);
  if (Boolean(row.livemode) !== config.live) fail(503, 'billing_mode_changed');
  return reconcile(env, row, await wire(env, 'GET', `/v1/payment_intents/${encodeURIComponent(row.provider_id)}`), eventId);
}
async function checkout(request: Request, env: BillingEnvironment, actor: string, body: Json | null) {
  const config = requireWire(env, request);
  const input = exact(body, ['plan', 'command_id']);
  if ((input.plan !== 'monthly' && input.plan !== 'yearly') || typeof input.command_id !== 'string' || !UUID.test(input.command_id)) fail(400, 'invalid_request');
  await rate(env, actor, 'checkout', 10);
  const plan = PLANS[input.plan];
  const now = seconds();
  const id = crypto.randomUUID();
  const returnURL = new URL(config.returnURL);
  returnURL.searchParams.set('order_id', id);
  await env.DB.prepare(`INSERT INTO hamtdaa_billing_orders
    (id,user_id,command_id,plan,duration_seconds,amount_minor,livemode,return_url,description,created_at,updated_at)
    VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(user_id,command_id) DO NOTHING`).bind(id, actor, input.command_id,
      input.plan, plan.duration_days * 86400, plan.amount_mnt * 100, Number(config.live), returnURL.href,
      `Хамтдаа Plus — ${plan.duration_days} хоног`, now, now).run();
  let row = (await env.DB.prepare('SELECT * FROM hamtdaa_billing_orders WHERE user_id=? AND command_id=?')
    .bind(actor, input.command_id).first<Order>())!;
  if (row.plan !== input.plan) fail(409, 'command_conflict');
  if (Boolean(row.livemode) !== config.live) fail(503, 'billing_mode_changed');
  if (!row.provider_id) {
    // Wire forgets idempotency keys after 48h. Never recreate an uncertain order
    // after 47h, even if the process crashed before persisting its provider ID.
    if (now - row.created_at > 47 * 3600 || row.created_at > now + 60) fail(409, 'checkout_expired');
    const remote = await wire(env, 'POST', '/v1/payment_intents', {
      amount: row.amount_minor, currency: row.currency, automatic_operator: true,
      allowed_operators: [row.livemode ? 'qpay' : 'sandbox'], description: row.description,
      metadata: { product: 'hamtdaa_plus', order_id: row.id, plan: row.plan },
    }, `hamtdaa-plus-create-${row.id}`);
    checkIntent(row, remote, true);
    await env.DB.prepare('UPDATE hamtdaa_billing_orders SET provider_id=? WHERE id=? AND provider_id IS NULL')
      .bind(remote.id, row.id).run();
    row = await readOrder(env, row.id);
    if (row.provider_id !== remote.id) fail(502, 'payment_mismatch');
  }
  row = await refresh(env, row);
  if (row.state === 'new' || row.state === 'requires_payment_method') {
    if (now - row.created_at > 47 * 3600) fail(409, 'checkout_expired');
    await wire(env, 'POST', `/v1/payment_intents/${encodeURIComponent(row.provider_id!)}/confirm`,
      { operator: row.livemode ? 'qpay' : 'sandbox', return_url: row.return_url }, `hamtdaa-plus-confirm-${row.id}`);
    row = await refresh(env, row);
  }
  return json({ ok: true, order: publicOrder(row) });
}

/** Evaluates current pair membership every time; unlinking instantly stops sharing. */
export async function getBillingStatus(env: BillingEnvironment, actorId: string) {
  const actor = await requireActor(env, actorId);
  const now = seconds();
  const grant = await env.DB.prepare(`SELECT g.provider,g.user_id,g.expires_at,g.auto_renew FROM hamtdaa_billing_grants g
    JOIN "user" u ON u.id=g.user_id LEFT JOIN hamtdaa_profiles profile ON profile.user_id=g.user_id
    WHERE g.revoked_at IS NULL AND g.starts_at<=? AND g.expires_at>? AND u.emailVerified=1
      AND (profile.user_id IS NULL OR profile.account_state='active')
      AND (g.user_id=? OR EXISTS(SELECT 1 FROM hamtdaa_pair_members mine
        JOIN hamtdaa_pairs p ON p.id=mine.pair_id AND p.state='active'
        JOIN hamtdaa_pair_members partner ON partner.pair_id=p.id AND partner.user_id=g.user_id
        WHERE mine.user_id=? AND mine.revoked_at IS NULL AND partner.revoked_at IS NULL
          AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b WHERE
            (b.blocker_id=? AND b.blocked_id=g.user_id) OR (b.blocker_id=g.user_id AND b.blocked_id=?))))
    ORDER BY g.expires_at DESC LIMIT 1`).bind(now, now, actor, actor, actor, actor)
    .first<{ provider: string; user_id: string; expires_at: number; auto_renew: number }>();
  return { ok: true, tier: grant ? 'plus' : 'free', plus_active: Boolean(grant),
    source: grant ? grant.user_id === actor ? 'own' : 'partner' : null,
    expires_at: grant ? iso(grant.expires_at) : null,
    auto_renew: grant?.user_id === actor ? Boolean(grant.auto_renew) : null,
    features: { premium_cards: Boolean(grant) } };
}
async function validSignature(request: Request, raw: string, secret: string) {
  const header = request.headers.get('WirePayment-Signature');
  if (!header || header.length > 2048) return false;
  const timestamps: string[] = [];
  const signatures: string[] = [];
  for (const field of header.split(',')) {
    const [key, value] = field.trim().split('=');
    if (key === 't' && value) timestamps.push(value);
    if (key === 'v1' && value && /^[a-f0-9]{64}$/i.test(value)) signatures.push(value);
  }
  if (timestamps.length !== 1 || !/^\d{1,12}$/.test(timestamps[0]) || Math.abs(seconds() - Number(timestamps[0])) > 300 || signatures.length > 5) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  for (const signature of signatures) {
    const bytes = Uint8Array.from(signature.match(/../g)!, (byte) => parseInt(byte, 16));
    if (await crypto.subtle.verify('HMAC', key, bytes, new TextEncoder().encode(`${timestamps[0]}.${raw}`))) return true;
  }
  return false;
}
async function webhook(request: Request, env: BillingEnvironment) {
  requireWire(env);
  const raw = await boundedText(request.body, 64 * 1024);
  if (!await validSignature(request, raw, env.WIRE_WEBHOOK_SECRET!)) fail(400, 'invalid_signature');
  let event: Json | null;
  try { event = object(JSON.parse(raw)); } catch { fail(400, 'invalid_event'); }
  if (!event || typeof event.type !== 'string') fail(400, 'invalid_event');
  // Wire signs this handshake before enabling deliveries; it grants no access.
  if (event.type === 'endpoint.verification') return json({ ok: true });
  if (typeof event.id !== 'string' || !PROVIDER_ID.test(event.id)) fail(400, 'invalid_event');
  if (!/^(payment_intent\.|charge\.)/.test(event.type)) return json({ ok: true, ignored: true });
  const prior = await env.DB.prepare("SELECT 1 FROM hamtdaa_billing_events WHERE provider='wire' AND event_id=?").bind(event.id).first();
  if (prior) return json({ ok: true, already_processed: true });
  const data = object(event.data);
  const value = object(data?.object) ?? data;
  const id = event.type.startsWith('charge.') ? value?.payment_intent : value?.id;
  if (typeof id !== 'string' || !PROVIDER_ID.test(id)) fail(400, 'invalid_event');
  const row = await env.DB.prepare('SELECT * FROM hamtdaa_billing_orders WHERE provider_id=?').bind(id).first<Order>();
  // An early delivery can precede the durable bind; retry it instead of losing it.
  if (!row) fail(503, 'order_not_ready');
  await refresh(env, row, event.id);
  return json({ ok: true });
}

export async function handleBillingRequest(request: Request, env: BillingEnvironment, actorId: string | null, body: Json | null): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  if (!path.startsWith('/v1/billing/')) return null;
  try {
    if (path === '/v1/billing/wire/webhook' && request.method === 'POST') return await webhook(request, env);
    if (path === '/v1/billing/catalog' && request.method === 'GET') {
      return json({ ok: true, enabled: env.BILLING_ENABLED === 'true', plus: { shared_with_current_partner: true,
        features: ['premium_cards'], prices_mnt: { monthly: 9900, yearly: 79900 } },
        web: { ready: env.BILLING_ENABLED === 'true' && env.BILLING_WEB_ENABLED === 'true' && webConfig(env) !== null,
          auto_renew: false, monthly_days: 30, yearly_days: 365 } });
    }
    const actor = await requireActor(env, actorId);
    if (path === '/v1/billing/status' && request.method === 'GET') return json(await getBillingStatus(env, actor));
    if (path === '/v1/billing/web/checkout' && request.method === 'POST') return await checkout(request, env, actor, body);
    if (path === '/v1/billing/web/status' && request.method === 'POST') {
      requireWire(env, request);
      const input = exact(body, ['order_id']);
      if (typeof input.order_id !== 'string' || !UUID.test(input.order_id)) fail(400, 'invalid_request');
      await rate(env, actor, 'poll', 30);
      const row = await env.DB.prepare('SELECT * FROM hamtdaa_billing_orders WHERE id=? AND user_id=?').bind(input.order_id, actor).first<Order>();
      if (!row) fail(404, 'order_not_found');
      return json({ ok: true, order: publicOrder(await refresh(env, row)), billing: await getBillingStatus(env, actor) });
    }
    return json({ ok: false, code: 'not_found' }, 404);
  } catch (error) {
    if (error instanceof BillingError) return json({ ok: false, code: error.code }, error.status);
    // Never return/log provider errors, bearer credentials, receipts or tokens.
    return json({ ok: false, code: 'billing_unavailable' }, 503);
  }
}
