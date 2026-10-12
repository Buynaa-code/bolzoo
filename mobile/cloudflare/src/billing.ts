import { createAuthRateStorage, type AuthEnvironment } from './auth';
import { verifyStorePurchase, refreshStorePurchase, STORE_PRODUCT_IDS, storeReadiness, storeAccountBinding, StoreVerificationError, type StoreVerificationEnv, type StorePurchaseInput, type VerifiedStorePurchase } from './store_verification';

export type BillingEnvironment = AuthEnvironment & StoreVerificationEnv & {
  BILLING_ENABLED?: string;
  BILLING_ALLOW_SANDBOX?: string;
  ENVIRONMENT?: string;
  BILLING_WEB_ENABLED?: string;
  BILLING_WIRE_MODE?: string;
  BILLING_WEB_ORIGIN?: string;
  BILLING_WEB_RETURN_URL?: string;
  WIRE_API_KEY?: string;
  WIRE_WEBHOOK_SECRET?: string;
  LEGAL_OPERATOR_NAME?: string;
  LEGAL_SUPPORT_EMAIL?: string;
};
type Json = Record<string, unknown>;
type Order = {
  id: string; user_id: string; command_id: string; plan: 'monthly' | 'yearly';
  duration_seconds: number; amount_minor: number; currency: string; livemode: number;
  return_url: string; description: string; provider_id: string | null; state: string;
  checkout_url: string | null; next_action: string | null; expires_at: number | null; created_at: number; updated_at: number;
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
    const origin = new URL(env.BILLING_WEB_ORIGIN ?? env.AUTH_BASE_URL);
    const returnURL = new URL(env.BILLING_WEB_RETURN_URL ?? '/plans', origin);
    const mode = env.BILLING_WIRE_MODE;
    if (origin.protocol !== 'https:' || origin.origin !== (env.BILLING_WEB_ORIGIN ?? env.AUTH_BASE_URL) ||
      returnURL.protocol !== 'https:' || returnURL.origin !== origin.origin || returnURL.username || returnURL.password ||
      (mode !== 'live' && mode !== 'test') || !env.WIRE_API_KEY?.startsWith(mode === 'live' ? 'sk_live_' : 'sk_test_') ||
      !env.WIRE_WEBHOOK_SECRET?.startsWith('whsec_')) return null;
    return { origin: origin.origin, returnURL: returnURL.href, live: mode === 'live' };
  } catch { return null; }
}
export function billingLegalReady(env: Pick<BillingEnvironment, 'LEGAL_OPERATOR_NAME' | 'LEGAL_SUPPORT_EMAIL'>): boolean {
  const name = env.LEGAL_OPERATOR_NAME?.trim() ?? '';
  const email = env.LEGAL_SUPPORT_EMAIL?.trim() ?? '';
  return name.length >= 2 && name.length <= 200 && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}
function requireWire(env: BillingEnvironment, request?: Request, purchase = false) {
  const config = webConfig(env);
  if (!config || (purchase && (env.BILLING_ENABLED !== 'true' || env.BILLING_WEB_ENABLED !== 'true'))) fail(503, 'billing_unavailable');
  if (purchase && !billingLegalReady(env)) fail(503, 'legal_not_ready');
  if (purchase && config.live && nativeEnvironment(env) === 'Sandbox') fail(503, 'billing_mode_changed');
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
  return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(all);
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
    checkout_url: ['succeeded', 'canceled', 'refunded'].includes(row.state) ? null : row.checkout_url,
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
    else if ((state === 'succeeded' || row.state === 'succeeded') && state !== 'canceled' && !charges.paid) fail(502, 'payment_not_settled');
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
      ON CONFLICT(provider,source_id) DO NOTHING`).bind(now, now, Date.now(), row.id));
  }
  if (state === 'canceled' || state === 'refunded') {
    statements.push(env.DB.prepare(`UPDATE hamtdaa_billing_grants SET revoked_at=COALESCE(revoked_at,?),observed_at=?
      WHERE provider='wire' AND source_id=?`).bind(now, Date.now(), row.provider_id));
  }
  // Refresh only the observation time after authoritative intent + charge checks.
  // Never recompute a prepaid grant's start or expiry on a replay.
  statements.push(env.DB.prepare(`UPDATE hamtdaa_billing_grants SET observed_at=?
    WHERE provider='wire' AND source_id=? AND revoked_at IS NULL
      AND EXISTS(SELECT 1 FROM hamtdaa_billing_orders WHERE id=? AND state='succeeded')`)
    .bind(Date.now(), row.provider_id, row.id));
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
  const config = requireWire(env, request, true);
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
  if (!row.checkout_url && (row.state === 'new' || row.state === 'requires_payment_method')) {
    if (now - row.created_at > 47 * 3600) fail(409, 'checkout_expired');
    // Hosted checkout performs confirm itself. Never also dispatch /confirm:
    // Wire only accepts a session for an unconfirmed PaymentIntent.
    const session = await wire(env, 'POST', '/v1/checkout/sessions',
      { payment_intent: row.provider_id, success_url: row.return_url, cancel_url: row.return_url }, `hamtdaa-plus-session-${row.id}`);
    if (session.object !== 'checkout.session' || session.payment_intent !== row.provider_id || typeof session.url !== 'string') fail(502, 'payment_mismatch');
    let checkoutURL: URL;
    try { checkoutURL = new URL(session.url); } catch { fail(502, 'payment_mismatch'); }
    if (checkoutURL.origin !== 'https://pay.wire.mn' || checkoutURL.username || checkoutURL.password ||
      !/^\/c\/[A-Za-z0-9_-]{1,300}$/.test(checkoutURL.pathname) || checkoutURL.search || checkoutURL.hash) fail(502, 'payment_mismatch');
    await env.DB.prepare('UPDATE hamtdaa_billing_orders SET checkout_url=? WHERE id=? AND checkout_url IS NULL')
      .bind(checkoutURL.href, row.id).run();
    row = await readOrder(env, row.id);
    if (row.checkout_url !== checkoutURL.href) fail(502, 'payment_mismatch');
  }
  return json({ ok: true, order: publicOrder(row) });
}

const eligibleGrantOwner = `(g.user_id=? OR EXISTS(SELECT 1 FROM hamtdaa_pair_members mine
  JOIN hamtdaa_pairs p ON p.id=mine.pair_id AND p.state='active'
  JOIN hamtdaa_pair_members partner ON partner.pair_id=p.id AND partner.user_id=g.user_id
  WHERE mine.user_id=? AND mine.revoked_at IS NULL AND partner.revoked_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b WHERE
      (b.blocker_id=? AND b.blocked_id=g.user_id) OR (b.blocker_id=g.user_id AND b.blocked_id=?))))`;
async function refreshKey(env: BillingEnvironment) {
  const material = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`hamtdaa-store-refresh-v1\0${env.BETTER_AUTH_SECRET}`));
  return crypto.subtle.importKey('raw', material, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
async function encryptRefresh(env: BillingEnvironment, actor: string, input: StorePurchaseInput) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv,
    additionalData: new TextEncoder().encode(actor) }, await refreshKey(env), new TextEncoder().encode(JSON.stringify(input)));
  return `${btoa(String.fromCharCode(...iv))}.${btoa(String.fromCharCode(...new Uint8Array(encrypted)))}`;
}
async function decryptRefresh(env: BillingEnvironment, actor: string, value: string): Promise<StorePurchaseInput> {
  const [nonce, cipher] = value.split('.');
  const decode = (text: string) => Uint8Array.from(atob(text), (char) => char.charCodeAt(0));
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: decode(nonce),
    additionalData: new TextEncoder().encode(actor) }, await refreshKey(env), decode(cipher));
  return JSON.parse(new TextDecoder().decode(plain)) as StorePurchaseInput;
}
function nativeEnvironment(env: BillingEnvironment): 'Production' | 'Sandbox' {
  return env.BILLING_ALLOW_SANDBOX === 'true' && env.ENVIRONMENT === 'staging' &&
    env.AUTH_BASE_URL === 'https://hamtdaa-api-staging.mendmedey.workers.dev' ? 'Sandbox' : 'Production';
}
async function persistStore(env: BillingEnvironment, actor: string, value: VerifiedStorePurchase) {
  if (value.accountId !== actor) fail(403, 'purchase_owner_mismatch');
  const now = seconds();
  const start = Math.floor(value.startedAt / 1000);
  const expiry = Math.floor(value.expiresAt / 1000);
  const observed = value.observedAt;
  if (![start, expiry, observed].every(Number.isSafeInteger) || expiry <= start || observed > Date.now() + 60000 ||
      typeof value.purchaseId !== 'string' || !value.purchaseId || typeof value.originalPurchaseId !== 'string' || !value.originalPurchaseId) fail(502, 'invalid_store_response');
  // Sandbox access exists only in the explicitly opted-in, fixed staging realm.
  // Persisting its realm prevents an accidental shared DB from granting prod access.
  if (value.environment !== nativeEnvironment(env)) fail(400, 'purchase_environment_mismatch');
  const source = `${value.environment}:${value.originalPurchaseId}`;
  const revoked = value.revoked ? now : null;
  const cipher = await encryptRefresh(env, actor, value.refresh);
  const guard = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO hamtdaa_billing_guards(id,allowed) SELECT ?, CASE WHEN
      NOT EXISTS(SELECT 1 FROM hamtdaa_billing_grants WHERE provider=? AND source_id=? AND user_id<>?)
      AND NOT EXISTS(SELECT 1 FROM hamtdaa_billing_transactions WHERE provider=? AND environment=? AND transaction_id=?
        AND (user_id<>? OR source_id<>?)) THEN 1 ELSE 0 END`).bind(guard, value.provider, source,
      actor, value.provider, value.environment, value.purchaseId, actor, source),
    env.DB.prepare(`INSERT INTO hamtdaa_billing_transactions(provider,environment,transaction_id,source_id,user_id)
      VALUES(?,?,?,?,?) ON CONFLICT(provider,environment,transaction_id) DO NOTHING`).bind(value.provider, value.environment, value.purchaseId, source, actor),
    env.DB.prepare(`INSERT INTO hamtdaa_billing_grants
      (provider,source_id,environment,user_id,transaction_id,product_id,starts_at,expires_at,revoked_at,auto_renew,observed_at,refresh_cipher,is_active)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(provider,source_id) DO UPDATE SET
      transaction_id=excluded.transaction_id, product_id=excluded.product_id,
      starts_at=excluded.starts_at, expires_at=excluded.expires_at,
      revoked_at=CASE WHEN hamtdaa_billing_grants.transaction_id=excluded.transaction_id
        AND hamtdaa_billing_grants.revoked_at IS NOT NULL THEN hamtdaa_billing_grants.revoked_at ELSE excluded.revoked_at END,
      auto_renew=excluded.auto_renew,observed_at=excluded.observed_at,refresh_cipher=excluded.refresh_cipher,is_active=excluded.is_active
      WHERE hamtdaa_billing_grants.user_id=excluded.user_id
        AND excluded.observed_at>=hamtdaa_billing_grants.observed_at
        AND (excluded.expires_at>=hamtdaa_billing_grants.expires_at OR excluded.transaction_id=hamtdaa_billing_grants.transaction_id)`)
      .bind(value.provider, source, value.environment, actor, value.purchaseId, value.productId, start, expiry,
        revoked, Number(value.autoRenew), observed, cipher, Number(value.active)),
    env.DB.prepare('DELETE FROM hamtdaa_billing_guards WHERE id=?').bind(guard),
  ]);
}
async function refreshEntitlements(env: BillingEnvironment, actor: string) {
  const now = seconds();
  // Include expired/revoked subscriptions: an authoritative renewal can restore
  // access. Tokens remain encrypted and are never sent back to either partner.
  const stale = await env.DB.prepare(`SELECT g.provider,g.source_id,g.user_id,g.refresh_cipher FROM hamtdaa_billing_grants g
    JOIN "user" u ON u.id=g.user_id LEFT JOIN hamtdaa_profiles profile ON profile.user_id=g.user_id
    WHERE g.environment=? AND g.observed_at<?
      AND ((g.provider IN ('apple','google') AND g.refresh_cipher IS NOT NULL)
        OR (g.provider='wire' AND g.revoked_at IS NULL AND g.starts_at<=? AND g.expires_at>?))
      AND u.emailVerified=1 AND (profile.user_id IS NULL OR profile.account_state='active')
      AND ${eligibleGrantOwner} ORDER BY g.expires_at DESC LIMIT 8`).bind(nativeEnvironment(env), (now - 240) * 1000, now, now, actor, actor, actor, actor)
    .all<{ provider: string; source_id: string; user_id: string; refresh_cipher: string | null }>();
  await Promise.all(stale.results.map(async (row) => {
    try {
      if (row.provider === 'wire') {
        const order = await env.DB.prepare('SELECT * FROM hamtdaa_billing_orders WHERE provider_id=? AND user_id=?')
          .bind(row.source_id, row.user_id).first<Order>();
        if (order) await refresh(env, order);
      } else if (row.refresh_cipher) {
        const input = await decryptRefresh(env, row.user_id, row.refresh_cipher);
        await persistStore(env, row.user_id, await refreshStorePurchase(env, row.user_id, input));
      }
    } catch {
      // A provider outage cannot extend freshness. The access query below
      // excludes stale grants after the bounded five-minute window.
    }
  }));
}
/** Evaluates current pair membership every time; unlinking instantly stops sharing. */
export async function getBillingStatus(env: BillingEnvironment, actorId: string) {
  const actor = await requireActor(env, actorId);
  await refreshEntitlements(env, actor);
  const now = seconds();
  const grant = await env.DB.prepare(`SELECT g.provider,g.environment,g.user_id,g.expires_at,g.auto_renew FROM hamtdaa_billing_grants g
    JOIN "user" u ON u.id=g.user_id LEFT JOIN hamtdaa_profiles profile ON profile.user_id=g.user_id
    WHERE g.environment=? AND g.revoked_at IS NULL AND g.is_active=1 AND g.starts_at<=? AND g.expires_at>? AND u.emailVerified=1
      AND g.observed_at>=?
      AND (profile.user_id IS NULL OR profile.account_state='active') AND ${eligibleGrantOwner}
      AND EXISTS(SELECT 1 FROM \"user\" actor_user LEFT JOIN hamtdaa_profiles actor_profile ON actor_profile.user_id=actor_user.id
        WHERE actor_user.id=? AND actor_user.emailVerified=1 AND (actor_profile.user_id IS NULL OR actor_profile.account_state='active'))
    ORDER BY g.expires_at DESC LIMIT 1`).bind(nativeEnvironment(env), now, now, (now - 300) * 1000, actor, actor, actor, actor, actor)
    .first<{ provider: string; environment: string; user_id: string; expires_at: number; auto_renew: number }>();
  const source = grant ? grant.user_id === actor ? 'self' : 'partner' : null;
  return { ok: true, tier: grant ? 'plus' : 'free', plus_active: Boolean(grant),
    source: source === 'self' ? 'own' : source, expires_at: grant ? iso(grant.expires_at) : null,
    auto_renew: grant?.user_id === actor ? Boolean(grant.auto_renew) : null,
    features: { premium_cards: Boolean(grant) },
    entitlement: { tier: grant ? 'plus' : 'free', premium_cards: Boolean(grant), source, environment: grant?.environment ?? null,
      expires_at: grant ? iso(grant.expires_at) : null, provider: grant ? grant.provider === 'wire' ? 'qpay' : grant.provider : null },
    store_account: await storeAccountBinding(env, actor) };
}
async function verifyNative(env: BillingEnvironment, actor: string, body: Json | null) {
  if (env.BILLING_ENABLED !== 'true') fail(503, 'billing_unavailable');
  if (!billingLegalReady(env)) fail(503, 'legal_not_ready');
  const value = exact(body, ['provider', 'product_id', 'transaction_id', 'purchase_token']);
  if (typeof value.product_id !== 'string' || value.product_id.length > 160) fail(400, 'invalid_request');
  let input: StorePurchaseInput;
  if (value.provider === 'apple' && typeof value.transaction_id === 'string' && value.transaction_id.length <= 200 && value.purchase_token === undefined) {
    input = { provider: 'apple', productId: value.product_id, transactionId: value.transaction_id };
  } else if (value.provider === 'google' && typeof value.purchase_token === 'string' && value.purchase_token.length <= 4096 && value.transaction_id === undefined) {
    input = { provider: 'google', productId: value.product_id, purchaseToken: value.purchase_token };
  } else fail(400, 'invalid_request');
  await rate(env, actor, 'store-verify', 15);
  const verified = await verifyStorePurchase(env, actor, input);
  try { await persistStore(env, actor, verified); }
  catch (error) {
    if (error instanceof Error && error.message.includes('CHECK constraint failed')) fail(409, 'purchase_already_linked');
    throw error;
  }
  return json(await getBillingStatus(env, actor));
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
      const ready = storeReadiness(env);
      return json({ ok: true, enabled: env.BILLING_ENABLED === 'true',
        native_enabled: { apple: env.BILLING_ENABLED === 'true' && billingLegalReady(env) && ready.apple && env.APPLE_STORE_ENVIRONMENT === nativeEnvironment(env),
          google: env.BILLING_ENABLED === 'true' && billingLegalReady(env) && ready.google && env.GOOGLE_STORE_ENVIRONMENT === nativeEnvironment(env) },
        products: (['apple', 'google'] as const).flatMap((provider) => STORE_PRODUCT_IDS.map((id) => ({
          id, provider, period: id.endsWith('.monthly') ? 'month' : 'year', amount_mnt: id.endsWith('.monthly') ? 9900 : 79900,
        }))), prices_mnt: { monthly: 9900, yearly: 79900 }, plus: { shared_with_current_partner: true,
        features: ['premium_cards'], prices_mnt: { monthly: 9900, yearly: 79900 } },
        web: { ready: env.BILLING_ENABLED === 'true' && env.BILLING_WEB_ENABLED === 'true' && webConfig(env) !== null && billingLegalReady(env) && !(webConfig(env)?.live && nativeEnvironment(env) === 'Sandbox'),
          auto_renew: false, monthly_days: 30, yearly_days: 365 } });
    }
    const actor = await requireActor(env, actorId);
    if (path === '/v1/billing/status' && request.method === 'GET') {
      await rate(env, actor, 'status', 30);
      return json(await getBillingStatus(env, actor));
    }
    if (path === '/v1/billing/store/verify' && request.method === 'POST') return await verifyNative(env, actor, body);
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
    if (error instanceof BillingError || error instanceof StoreVerificationError) return json({ ok: false, code: error.code }, error.status);
    // Never return/log provider errors, bearer credentials, receipts or tokens.
    return json({ ok: false, code: 'billing_unavailable' }, 503);
  }
}
