/** Native store proofs are lookups only. Entitlements come from authenticated,
 * fixed-origin store APIs; client receipts, prices and entitlement flags are never trusted. */
export const STORE_PRODUCT_IDS = [
  'mn.moch.hamtdaa.plus.monthly', 'mn.moch.hamtdaa.plus.yearly',
] as const;
const APP = 'mn.moch.hamtdaa';
type Mode = 'Production' | 'Sandbox';
type Json = Record<string, unknown>;
export type StoreVerificationEnv = {
  APPLE_STORE_ENVIRONMENT?: string;
  APPLE_ISSUER_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_APP_ID?: string;
  GOOGLE_SERVICE_ACCOUNT_EMAIL?: string;
  GOOGLE_PRIVATE_KEY?: string;
  GOOGLE_STORE_ENVIRONMENT?: string;
};
export type StorePurchaseInput =
  | { provider: 'apple'; productId: string; transactionId: string }
  | { provider: 'google'; productId: string; purchaseToken: string };
export type VerifiedStorePurchase = {
  provider: 'apple' | 'google'; environment: Mode; productId: string;
  purchaseId: string; originalPurchaseId: string; accountId: string;
  startedAt: number; expiresAt: number; observedAt: number;
  active: boolean; revoked: boolean; autoRenew: boolean;
  refresh: StorePurchaseInput;
};
export class StoreVerificationError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
function fail(status: number, code: string): never { throw new StoreVerificationError(status, code); }
const object = (v: unknown): Json | null => v !== null && typeof v === 'object' && !Array.isArray(v) ? v as Json : null;
const mode = (v: unknown): v is Mode => v === 'Production' || v === 'Sandbox';
const approved = (v: unknown): v is string => typeof v === 'string' && (STORE_PRODUCT_IDS as readonly string[]).includes(v);
const numericId = (v: unknown): v is string => typeof v === 'string' && /^\d{1,40}$/.test(v);
const epoch = (v: unknown): v is number => typeof v === 'number' && Number.isSafeInteger(v) && v > 0 && v < 8640000000000000;
const encoder = new TextEncoder();
function privateKey(value: string | undefined): boolean {
  return Boolean(value && value.length < 16384 && value.replace(/\\n/g, '\n').trim().startsWith('-----BEGIN PRIVATE KEY-----'));
}
export function storeReadiness(env: StoreVerificationEnv): { apple: boolean; google: boolean } {
  return {
    apple: mode(env.APPLE_STORE_ENVIRONMENT) && /^[0-9a-f-]{36}$/i.test(env.APPLE_ISSUER_ID ?? '') &&
      /^[A-Z0-9]{10}$/.test(env.APPLE_KEY_ID ?? '') && privateKey(env.APPLE_PRIVATE_KEY) &&
      (!env.APPLE_APP_ID || /^\d{1,20}$/.test(env.APPLE_APP_ID)),
    google: mode(env.GOOGLE_STORE_ENVIRONMENT) && /^[^\s@]+@[^\s@]+\.iam\.gserviceaccount\.com$/.test(env.GOOGLE_SERVICE_ACCOUNT_EMAIL ?? '') && privateKey(env.GOOGLE_PRIVATE_KEY),
  };
}
function base64url(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function unbase64(value: string): Uint8Array {
  const base = value.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(base + '='.repeat((4 - base.length % 4) % 4)), (x) => x.charCodeAt(0));
}
async function hash(value: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
}
const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
export async function storeAccountBinding(_env: StoreVerificationEnv, actorId: string): Promise<{ apple: string; google: string }> {
  if (!actorId || actorId.length > 256) fail(400, 'invalid_account');
  // RFC 9562 UUIDv5, using the DNS namespace and an application-specific name.
  // Better Auth IDs are not UUIDs. This binding must stay stable across secret
  // rotation and application upgrades; it is an identifier, never a credential.
  const namespace = Uint8Array.from('6ba7b8109dad11d180b400c04fd430c8'.match(/../g)!, (part) => parseInt(part, 16));
  const name = encoder.encode(`${APP}:app-account:v1:${actorId}`);
  const material = new Uint8Array(namespace.length + name.length);
  material.set(namespace); material.set(name, namespace.length);
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-1', material)).slice(0, 16);
  bytes[6] = (bytes[6]! & 15) | 0x50;
  bytes[8] = (bytes[8]! & 63) | 0x80;
  const value = hex(bytes);
  return { apple: `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`, google: hex(await hash(actorId)) };
}
async function jwt(header: Json, payload: Json, pem: string, algorithm: 'ES256' | 'RS256'): Promise<string> {
  try {
    const material = pem.replace(/\\n/g, '\n').trim();
    if (!/^-----BEGIN PRIVATE KEY-----\s+[A-Za-z0-9+/=\s]+\s+-----END PRIVATE KEY-----$/.test(material)) fail(503, 'store_unavailable');
    const keyData = unbase64(material.replace(/-----[^-]+-----/g, '').replace(/\s/g, ''));
    const importAlgorithm = algorithm === 'ES256' ? { name: 'ECDSA', namedCurve: 'P-256' } : { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };
    const key = await crypto.subtle.importKey('pkcs8', keyData, importAlgorithm, false, ['sign']);
    const data = `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(payload)))}`;
    const signature = await crypto.subtle.sign(algorithm === 'ES256' ? { name: 'ECDSA', hash: 'SHA-256' } : 'RSASSA-PKCS1-v1_5', key, encoder.encode(data));
    return `${data}.${base64url(new Uint8Array(signature))}`;
  } catch { fail(503, 'store_unavailable'); }
}
async function requestJSON(url: string, init: RequestInit, signal: AbortSignal): Promise<Json> {
  try {
    const response = await fetch(url, { ...init, signal, redirect: 'error' });
    if (!response.ok) {
      await response.body?.cancel();
      if (response.status === 404 || response.status === 410) fail(400, 'purchase_not_found');
      fail(503, 'store_unavailable');
    }
    if (!response.body || Number(response.headers.get('content-length') ?? 0) > 256 * 1024) {
      await response.body?.cancel();
      fail(503, 'invalid_store_response');
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    try {
      for (;;) {
        const part = await reader.read();
        if (part.done) break;
        length += part.value.byteLength;
        if (length > 256 * 1024) { await reader.cancel(); fail(503, 'invalid_store_response'); }
        chunks.push(part.value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const part of chunks) { bytes.set(part, offset); offset += part.length; }
    const parsed = object(JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes)));
    if (!parsed) fail(503, 'invalid_store_response');
    return parsed;
  } catch (error) {
    if (error instanceof StoreVerificationError) throw error;
    fail(503, 'store_unavailable');
  }
}
/** Only call on JWS values returned directly by the authenticated Apple HTTPS
 * client below. TLS authenticates these API responses; this is NOT a generic JWS
 * verifier and must never be used for client receipts or server notifications. */
function applePayload(value: unknown): Json {
  if (typeof value !== 'string' || value.length > 32768) fail(503, 'invalid_store_response');
  const parts = value.split('.');
  if (parts.length !== 3 || parts.some((p) => !/^[A-Za-z0-9_-]+$/.test(p))) fail(503, 'invalid_store_response');
  try {
    const header = object(JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(unbase64(parts[0]!))));
    const payload = object(JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(unbase64(parts[1]!))));
    if (header?.alg !== 'ES256' || unbase64(parts[2]!).length !== 64 || !payload) fail(503, 'invalid_store_response');
    return payload;
  } catch { fail(503, 'invalid_store_response'); }
}
function appleTransaction(value: unknown, account: string, environment: Mode): Json {
  const tx = applePayload(value);
  if (typeof tx.appAccountToken !== 'string' || tx.appAccountToken.toLowerCase() !== account) fail(403, 'purchase_account_mismatch');
  if (tx.bundleId !== APP || tx.environment !== environment || !approved(tx.productId) ||
    tx.type !== 'Auto-Renewable Subscription' || tx.inAppOwnershipType !== 'PURCHASED' ||
    !numericId(tx.transactionId) || !numericId(tx.originalTransactionId) ||
    !epoch(tx.purchaseDate) || !epoch(tx.expiresDate) || !epoch(tx.signedDate) ||
    (tx.revocationDate !== undefined && !epoch(tx.revocationDate))) fail(400, 'purchase_mismatch');
  return tx;
}
async function apple(env: StoreVerificationEnv, actor: string, input: Extract<StorePurchaseInput, { provider: 'apple' }>, observedAt: number, signal: AbortSignal): Promise<VerifiedStorePurchase> {
  const environment = env.APPLE_STORE_ENVIRONMENT as Mode;
  const account = (await storeAccountBinding(env, actor)).apple;
  const host = environment === 'Production' ? 'https://api.storekit.apple.com' : 'https://api.storekit-sandbox.apple.com';
  const read = async (path: string) => {
    const now = Math.floor(Date.now() / 1000);
    const token = await jwt({ alg: 'ES256', kid: env.APPLE_KEY_ID!, typ: 'JWT' },
      { iss: env.APPLE_ISSUER_ID!, iat: now, exp: now + 300, aud: 'appstoreconnect-v1', bid: APP }, env.APPLE_PRIVATE_KEY!, 'ES256');
    return requestJSON(host + path, { headers: { Authorization: `Bearer ${token}` } }, signal);
  };
  const proof = await read(`/inApps/v1/transactions/${input.transactionId}`);
  const seed = appleTransaction(proof.signedTransactionInfo, account, environment);
  if (seed.transactionId !== input.transactionId || seed.productId !== input.productId) fail(400, 'purchase_mismatch');
  const current = await read(`/inApps/v1/subscriptions/${input.transactionId}`);
  if (current.bundleId !== APP || current.environment !== environment ||
    (env.APPLE_APP_ID && String(current.appAppleId) !== env.APPLE_APP_ID) || !Array.isArray(current.data) || current.data.length > 100) fail(400, 'purchase_mismatch');
  const matches: Json[] = [];
  for (const item of current.data) {
    const group = object(item);
    if (!group || !Array.isArray(group.lastTransactions) || group.lastTransactions.length > 100) fail(503, 'invalid_store_response');
    for (const value of group.lastTransactions) {
      const last = object(value);
      if (last && last.originalTransactionId === seed.originalTransactionId) matches.push(last);
    }
  }
  if (matches.length !== 1) fail(503, 'invalid_store_response');
  const latest = matches[0]!;
  const tx = appleTransaction(latest.signedTransactionInfo, account, environment);
  const renewal = applePayload(latest.signedRenewalInfo);
  if (tx.originalTransactionId !== seed.originalTransactionId || renewal.originalTransactionId !== seed.originalTransactionId ||
    renewal.environment !== environment || renewal.productId !== tx.productId ||
    (renewal.autoRenewStatus !== 0 && renewal.autoRenewStatus !== 1) || !epoch(renewal.signedDate) ||
    ![1, 2, 3, 4, 5].includes(Number(latest.status)) || typeof latest.status !== 'number' ||
    (renewal.gracePeriodExpiresDate !== undefined && !epoch(renewal.gracePeriodExpiresDate))) fail(400, 'purchase_mismatch');
  const revoked = latest.status === 5 || tx.revocationDate !== undefined;
  const expiresAt = latest.status === 4 && epoch(renewal.gracePeriodExpiresDate) ? renewal.gracePeriodExpiresDate : tx.expiresDate as number;
  const active = !revoked && (latest.status === 1 || latest.status === 4) && expiresAt > Date.now() && tx.isUpgraded !== true;
  return { provider: 'apple', environment, productId: tx.productId as string, accountId: actor,
    purchaseId: tx.transactionId as string, originalPurchaseId: tx.originalTransactionId as string,
    startedAt: tx.purchaseDate as number, expiresAt, observedAt, active, revoked, autoRenew: renewal.autoRenewStatus === 1,
    refresh: { provider: 'apple', productId: tx.productId as string, transactionId: tx.transactionId as string } };
}
function timestamp(value: unknown): number {
  if (typeof value !== 'string' || value.length > 40 || !/^\d{4}-\d{2}-\d{2}T/.test(value)) fail(503, 'invalid_store_response');
  const parsed = Date.parse(value);
  if (!epoch(parsed)) fail(503, 'invalid_store_response');
  return parsed;
}
async function google(env: StoreVerificationEnv, actor: string, input: Extract<StorePurchaseInput, { provider: 'google' }>, observedAt: number, signal: AbortSignal, refreshing: boolean): Promise<VerifiedStorePurchase> {
  const now = Math.floor(Date.now() / 1000);
  const assertion = await jwt({ alg: 'RS256', typ: 'JWT' }, {
    iss: env.GOOGLE_SERVICE_ACCOUNT_EMAIL!, scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 300,
  }, env.GOOGLE_PRIVATE_KEY!, 'RS256');
  const auth = await requestJSON('https://oauth2.googleapis.com/token', { method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString() }, signal);
  if (typeof auth.access_token !== 'string' || !auth.access_token || auth.access_token.length > 16384 ||
    auth.token_type !== 'Bearer') fail(503, 'invalid_store_response');
  const result = await requestJSON(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP}/purchases/subscriptionsv2/tokens/${encodeURIComponent(input.purchaseToken)}`,
    { headers: { Authorization: `Bearer ${auth.access_token}` } }, signal);
  const account = (await storeAccountBinding(env, actor)).google;
  if (object(result.externalAccountIdentifiers)?.obfuscatedExternalAccountId !== account) fail(403, 'purchase_account_mismatch');
  const environment: Mode = result.testPurchase !== undefined ? 'Sandbox' : 'Production';
  if (environment !== env.GOOGLE_STORE_ENVIRONMENT || (result.testPurchase !== undefined && !object(result.testPurchase))) fail(400, 'purchase_mismatch');
  const states = ['PENDING', 'ACTIVE', 'PAUSED', 'IN_GRACE_PERIOD', 'ON_HOLD', 'CANCELED', 'EXPIRED', 'PENDING_PURCHASE_CANCELED'].map((s) => `SUBSCRIPTION_STATE_${s}`);
  if (typeof result.subscriptionState !== 'string' || !states.includes(result.subscriptionState) ||
    !Array.isArray(result.lineItems) || result.lineItems.length < 1 || result.lineItems.length > 20 ||
    !['ACKNOWLEDGEMENT_STATE_PENDING', 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'].includes(String(result.acknowledgementState))) fail(503, 'invalid_store_response');
  // Pending purchases have no settled order and must not grant even if a client
  // supplies a purchased flag. Native completion/acknowledgement follows durable grant.
  if (result.subscriptionState === 'SUBSCRIPTION_STATE_PENDING' || result.subscriptionState === 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED') fail(400, 'purchase_not_settled');
  const lines = result.lineItems.map(object);
  const owned = lines.filter((line): line is Json => Boolean(line && approved(line.productId) && typeof line.latestSuccessfulOrderId === 'string'));
  const candidates = owned.filter((line) => refreshing || line.productId === input.productId);
  if (!candidates.length) fail(400, 'purchase_mismatch');
  // Deferred replacement lines can exist without a successful order; they are
  // intentionally excluded. Choose the latest settled, approved entitlement.
  candidates.sort((a, b) => timestamp(b.expiryTime) - timestamp(a.expiryTime));
  const line = candidates[0]!;
  const plan = object(line.autoRenewingPlan);
  if (!plan || typeof plan.autoRenewEnabled !== 'boolean' || typeof line.latestSuccessfulOrderId !== 'string' ||
    !/^GPA\.[A-Za-z0-9.-]{1,180}$/.test(line.latestSuccessfulOrderId)) fail(400, 'purchase_mismatch');
  const expiresAt = timestamp(line.expiryTime);
  const startedAt = timestamp(result.startTime);
  const active = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'].includes(result.subscriptionState) && expiresAt > Date.now();
  // subscriptionsv2 reflects a refund/revocation as loss of entitlement. It does
  // not expose a reliable explicit revocation flag: ordinary cancellation still
  // grants until expiry, and hold/pause may recover, so neither is made sticky.
  return { provider: 'google', environment, productId: line.productId as string, accountId: actor,
    purchaseId: line.latestSuccessfulOrderId, originalPurchaseId: hex(await hash(input.purchaseToken)),
    startedAt, expiresAt, observedAt, active, revoked: false, autoRenew: plan.autoRenewEnabled,
    refresh: { provider: 'google', productId: line.productId as string, purchaseToken: input.purchaseToken } };
}
async function verify(env: StoreVerificationEnv, actor: string, input: StorePurchaseInput, refreshing: boolean): Promise<VerifiedStorePurchase> {
  const observedAt = Date.now();
  if (!object(input) || !approved(input.productId) || !['apple', 'google'].includes(input.provider)) fail(400, 'invalid_purchase');
  if (input.provider === 'apple' ? !numericId(input.transactionId) : typeof input.purchaseToken !== 'string' ||
    input.purchaseToken.length < 1 || input.purchaseToken.length > 4096 || /[\s\x00-\x1f]/.test(input.purchaseToken)) fail(400, 'invalid_purchase');
  if (!storeReadiness(env)[input.provider]) fail(503, 'store_unavailable');
  const signal = AbortSignal.timeout(15000); // one bound covers token + all store reads
  return input.provider === 'apple' ? apple(env, actor, input, observedAt, signal) : google(env, actor, input, observedAt, signal, refreshing);
}
export async function verifyStorePurchase(env: StoreVerificationEnv, actorId: string, input: StorePurchaseInput): Promise<VerifiedStorePurchase> {
  return verify(env, actorId, input, false);
}
export async function refreshStorePurchase(env: StoreVerificationEnv, actorId: string, input: StorePurchaseInput): Promise<VerifiedStorePurchase> {
  return verify(env, actorId, input, true);
}
