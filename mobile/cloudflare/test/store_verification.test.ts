import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { STORE_PRODUCT_IDS, StoreVerificationError, refreshStorePurchase, storeAccountBinding, storeReadiness,
  verifyStorePurchase, type StoreVerificationEnv } from '../src/store_verification';

const [MONTHLY, YEARLY] = STORE_PRODUCT_IDS;
const APP = 'mn.moch.hamtdaa';
const OWNER = 'betterAuthRandomIdNotUUID';
const TOKEN = 'opaque-google-purchase-token';
const now = () => Date.now();
const iso = (time: number) => new Date(time).toISOString();
type Json = Record<string, unknown>;
let env: StoreVerificationEnv;
let binding: { apple: string; google: string };
let appleKey: CryptoKey;
let googleKey: CryptoKey;
const encode = (value: unknown) => btoa(JSON.stringify(value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const decode = (value: string) => JSON.parse(atob(value.replace(/-/g, '+').replace(/_/g, '/'))) as Json;
const jws = (value: Json) => `${encode({ alg: 'ES256' })}.${encode(value)}.${btoa('\0'.repeat(64)).replace(/=/g, '')}`;
async function pem(key: CryptoKey): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', key) as ArrayBuffer);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...bytes))}\n-----END PRIVATE KEY-----`;
}
beforeAll(async () => {
  const ec = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const rsa = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  appleKey = ec.publicKey;
  googleKey = rsa.publicKey;
  env = {
    APPLE_STORE_ENVIRONMENT: 'Production', APPLE_ISSUER_ID: '57246542-96fe-1a63-e053-0824d011072a',
    APPLE_KEY_ID: '2X9R4HXF34', APPLE_PRIVATE_KEY: await pem(ec.privateKey), APPLE_APP_ID: '1234567890',
    GOOGLE_STORE_ENVIRONMENT: 'Production', GOOGLE_SERVICE_ACCOUNT_EMAIL: 'billing@hamtdaa.iam.gserviceaccount.com',
    GOOGLE_PRIVATE_KEY: await pem(rsa.privateKey),
  };
  binding = await storeAccountBinding(env, OWNER);
});
afterEach(() => vi.unstubAllGlobals());
function transaction(overrides: Json = {}): Json {
  return { bundleId: APP, productId: MONTHLY, transactionId: '2000000001', originalTransactionId: '1000000001',
    appAccountToken: binding.apple, environment: 'Production', type: 'Auto-Renewable Subscription',
    inAppOwnershipType: 'PURCHASED', purchaseDate: now() - 100000, expiresDate: now() + 86400000, signedDate: now(), ...overrides };
}
function renewal(tx: Json, overrides: Json = {}): Json {
  return { productId: tx.productId, originalTransactionId: tx.originalTransactionId, environment: 'Production',
    autoRenewStatus: 1, signedDate: now(), ...overrides };
}
function appleMock(options: { seed?: Json; latest?: Json; status?: number; renewal?: Json; response?: Json } = {}) {
  const seed = options.seed ?? transaction();
  const latest = options.latest ?? seed;
  const data = { bundleId: APP, environment: 'Production', appAppleId: 1234567890, data: [{ subscriptionGroupIdentifier: '1', lastTransactions: [{
    originalTransactionId: latest.originalTransactionId, status: options.status ?? 1,
    signedTransactionInfo: jws(latest), signedRenewalInfo: jws(renewal(latest, options.renewal)),
  }] }], ...options.response };
  const fetcher = vi.fn(async (url: string, _init?: RequestInit) => {
    if (url.includes('/transactions/')) return Response.json({ signedTransactionInfo: jws(seed) });
    if (url.includes('/subscriptions/')) return Response.json(data);
    throw new Error('Unexpected URL');
  });
  vi.stubGlobal('fetch', fetcher);
  return fetcher;
}
function googleRecord(overrides: Json = {}): Json {
  return { kind: 'androidpublisher#subscriptionPurchaseV2', startTime: iso(now() - 100000),
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
    externalAccountIdentifiers: { obfuscatedExternalAccountId: binding.google },
    lineItems: [{ productId: MONTHLY, expiryTime: iso(now() + 86400000), latestSuccessfulOrderId: 'GPA.1234-5678-9012-34567..0', autoRenewingPlan: { autoRenewEnabled: true } }], ...overrides };
}
function googleMock(record: Json = googleRecord()) {
  const fetcher = vi.fn(async (url: string, _init?: RequestInit) => {
    if (url === 'https://oauth2.googleapis.com/token') return Response.json({ access_token: 'server-oauth-token', token_type: 'Bearer', expires_in: 300 });
    if (url.startsWith('https://androidpublisher.googleapis.com/')) return Response.json(record);
    throw new Error('Unexpected URL');
  });
  vi.stubGlobal('fetch', fetcher);
  return fetcher;
}
const appleInput = () => ({ provider: 'apple' as const, productId: MONTHLY, transactionId: '2000000001' });
const googleInput = () => ({ provider: 'google' as const, productId: MONTHLY, purchaseToken: TOKEN });
async function verifyJwt(value: string, algorithm: 'ES256' | 'RS256', key: CryptoKey): Promise<Json> {
  const parts = value.split('.');
  const signature = Uint8Array.from(atob(parts[2]!.replace(/-/g, '+').replace(/_/g, '/')), (x) => x.charCodeAt(0));
  expect(await crypto.subtle.verify(algorithm === 'ES256' ? { name: 'ECDSA', hash: 'SHA-256' } : 'RSASSA-PKCS1-v1_5', key,
    signature, new TextEncoder().encode(`${parts[0]}.${parts[1]}`))).toBe(true);
  return decode(parts[1]!);
}
describe('store account binding and configuration', () => {
  it('gives non-UUID auth users a stable UUID and SHA256 account binding', async () => {
    expect(binding.apple).toMatch(/^[\da-f]{8}-[\da-f]{4}-5[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/);
    expect(binding.google).toMatch(/^[\da-f]{64}$/);
    expect(binding).toEqual({ apple: 'c0c08806-61d0-586c-99db-3254ac6c91d9', google: 'd8904bf8adf1b32fbfed7414169a11ba48707aee0a73950046f752d9bea54844' });
    expect(await storeAccountBinding({}, OWNER)).toEqual(binding);
    expect(await storeAccountBinding(env, 'other-actor')).not.toEqual(binding);
    expect(binding.google).not.toContain(OWNER);
  });
  it('disables a provider without all required credentials and explicit mode', async () => {
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    expect(storeReadiness({})).toEqual({ apple: false, google: false });
    expect(storeReadiness(env)).toEqual({ apple: true, google: true });
    expect(storeReadiness({ ...env, APPLE_STORE_ENVIRONMENT: 'auto' }).apple).toBe(false);
    await expect(verifyStorePurchase({}, OWNER, appleInput())).rejects.toMatchObject({ status: 503, code: 'store_unavailable' });
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('rejects unapproved products and client receipt instead of transaction ID before network', async () => {
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    await expect(verifyStorePurchase(env, OWNER, { ...appleInput(), productId: 'lifetime-cheap' })).rejects.toMatchObject({ status: 400 });
    await expect(verifyStorePurchase(env, OWNER, { ...appleInput(), transactionId: jws(transaction()) })).rejects.toMatchObject({ status: 400 });
    await expect(verifyStorePurchase(env, OWNER, { ...googleInput(), purchaseToken: 'x'.repeat(4097) })).rejects.toMatchObject({ status: 400 });
    expect(fetcher).not.toHaveBeenCalled();
  });
});
describe('Apple authoritative subscription verification', () => {
  it('signs an ES256 server JWT and checks current renewal, not only the supplied old transaction', async () => {
    const newer = transaction({ transactionId: '2000000002', expiresDate: now() + 2 * 86400000 });
    const fetcher = appleMock({ latest: newer });
    const before = now();
    const result = await verifyStorePurchase(env, OWNER, appleInput());
    expect(result).toMatchObject({ provider: 'apple', environment: 'Production', productId: MONTHLY, active: true, revoked: false,
      autoRenew: true, purchaseId: '2000000002', originalPurchaseId: '1000000001', accountId: OWNER,
      refresh: { provider: 'apple', productId: MONTHLY, transactionId: '2000000002' } });
    expect(result.observedAt).toBeGreaterThanOrEqual(before);
    expect(fetcher.mock.calls.map(([url]) => url)).toEqual([
      'https://api.storekit.apple.com/inApps/v1/transactions/2000000001', 'https://api.storekit.apple.com/inApps/v1/subscriptions/2000000001']);
    for (const [, init] of fetcher.mock.calls) {
      expect(init?.redirect).toBe('error'); expect(init?.signal).toBeInstanceOf(AbortSignal);
      const token = new Headers(init?.headers).get('Authorization')!.slice(7);
      expect(decode(token.split('.')[0]!)).toEqual({ alg: 'ES256', kid: env.APPLE_KEY_ID, typ: 'JWT' });
      const payload = await verifyJwt(token, 'ES256', appleKey);
      expect(payload).toMatchObject({ iss: env.APPLE_ISSUER_ID, aud: 'appstoreconnect-v1', bid: APP });
      expect(Number(payload.exp) - Number(payload.iat)).toBe(300);
    }
  });
  it('rejects replay of another app account purchase', async () => {
    appleMock();
    await expect(verifyStorePurchase(env, 'other-actor', appleInput())).rejects.toMatchObject({ status: 403, code: 'purchase_account_mismatch' });
  });
  it.each([
    { bundleId: 'other.app' }, { productId: 'other.product' }, { environment: 'Sandbox' },
    { inAppOwnershipType: 'FAMILY_SHARED' }, { type: 'Consumable' }, { transactionId: '999999' },
  ])('rejects invalid app/product/environment/ownership proof %j', async (change) => {
    appleMock({ seed: transaction(change) });
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ status: 400, code: 'purchase_mismatch' });
  });
  it('rejects missing account binding, including legacy unbound receipts', async () => {
    const seed = transaction(); delete seed.appAccountToken;
    appleMock({ seed });
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ status: 403 });
  });
  it('does not grant a historically valid transaction after current refund', async () => {
    appleMock({ status: 5, latest: transaction({ revocationDate: now() - 100 }) });
    expect(await verifyStorePurchase(env, OWNER, appleInput())).toMatchObject({ active: false, revoked: true });
  });
  it('does not grant expired/current retry even if historical expiry is in future', async () => {
    appleMock({ status: 3 });
    expect(await verifyStorePurchase(env, OWNER, appleInput())).toMatchObject({ active: false, revoked: false });
    appleMock({ status: 2, latest: transaction({ expiresDate: now() - 1000 }) });
    expect(await verifyStorePurchase(env, OWNER, appleInput())).toMatchObject({ active: false });
  });
  it('uses authoritative grace-period expiry and keeps cancellation active until expiry', async () => {
    const grace = now() + 300000;
    appleMock({ status: 4, latest: transaction({ expiresDate: now() - 1000 }), renewal: { gracePeriodExpiresDate: grace } });
    expect(await verifyStorePurchase(env, OWNER, appleInput())).toMatchObject({ active: true, expiresAt: grace });
    appleMock({ renewal: { autoRenewStatus: 0 } });
    expect(await verifyStorePurchase(env, OWNER, appleInput())).toMatchObject({ active: true, autoRenew: false });
  });
  it('resolves an approved monthly-to-yearly change only along same bound subscription', async () => {
    appleMock({ latest: transaction({ productId: YEARLY, transactionId: '2000000002' }) });
    expect(await refreshStorePurchase(env, OWNER, appleInput())).toMatchObject({ productId: YEARLY,
      originalPurchaseId: '1000000001', refresh: { productId: YEARLY, transactionId: '2000000002' } });
    appleMock({ latest: transaction({ originalTransactionId: '999999' }) });
    await expect(refreshStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ code: 'invalid_store_response' });
  });
  it('requires account binding and app ID on current status as well as old proof', async () => {
    appleMock({ latest: transaction({ appAccountToken: (await storeAccountBinding(env, 'other-actor')).apple }) });
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ status: 403 });
    appleMock({ response: { appAppleId: 11111 } });
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ status: 400 });
  });
  it('uses only server-selected sandbox and never falls back after not-found', async () => {
    const seed = transaction({ environment: 'Sandbox' });
    const fetcher = appleMock({ seed, renewal: { environment: 'Sandbox' }, response: { environment: 'Sandbox' } });
    expect(await verifyStorePurchase({ ...env, APPLE_STORE_ENVIRONMENT: 'Sandbox' }, OWNER, appleInput())).toMatchObject({ environment: 'Sandbox' });
    expect(fetcher.mock.calls[0]![0]).toMatch(/^https:\/\/api\.storekit-sandbox\.apple\.com\//);
    const missing = vi.fn(async () => new Response('{}', { status: 404 })); vi.stubGlobal('fetch', missing);
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ code: 'purchase_not_found' });
    expect(missing).toHaveBeenCalledTimes(1);
  });
});
describe('Google authoritative subscription verification', () => {
  it('signs RS256 OAuth, reads fixed package and returns hashed token identity', async () => {
    const fetcher = googleMock();
    const result = await verifyStorePurchase(env, OWNER, googleInput());
    expect(result).toMatchObject({ provider: 'google', active: true, productId: MONTHLY, accountId: OWNER,
      purchaseId: 'GPA.1234-5678-9012-34567..0', autoRenew: true, environment: 'Production' });
    expect(result.originalPurchaseId).toMatch(/^[0-9a-f]{64}$/);
    expect(result.originalPurchaseId).not.toBe(TOKEN);
    expect(result.refresh).toEqual(googleInput());
    const authCall = fetcher.mock.calls[0]!;
    const body = new URLSearchParams(String(authCall[1]?.body));
    expect(body.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    expect(await verifyJwt(body.get('assertion')!, 'RS256', googleKey)).toMatchObject({
      iss: env.GOOGLE_SERVICE_ACCOUNT_EMAIL, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: 'https://oauth2.googleapis.com/token' });
    const read = fetcher.mock.calls[1]!;
    expect(read[0]).toBe(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP}/purchases/subscriptionsv2/tokens/${TOKEN}`);
    expect(new Headers(read[1]?.headers).get('Authorization')).toBe('Bearer server-oauth-token');
  });
  it('rejects purchase replay on another app account or absent account ID', async () => {
    googleMock();
    await expect(verifyStorePurchase(env, 'other-actor', googleInput())).rejects.toMatchObject({ status: 403 });
    googleMock(googleRecord({ externalAccountIdentifiers: {} }));
    await expect(verifyStorePurchase(env, OWNER, googleInput())).rejects.toMatchObject({ status: 403 });
  });
  it('rejects product substitution and test purchases on production', async () => {
    googleMock();
    await expect(verifyStorePurchase(env, OWNER, { ...googleInput(), productId: YEARLY })).rejects.toMatchObject({ code: 'purchase_mismatch' });
    googleMock(googleRecord({ testPurchase: {} }));
    await expect(verifyStorePurchase(env, OWNER, googleInput())).rejects.toMatchObject({ code: 'purchase_mismatch' });
    expect(await verifyStorePurchase({ ...env, GOOGLE_STORE_ENVIRONMENT: 'Sandbox' }, OWNER, googleInput())).toMatchObject({ environment: 'Sandbox' });
  });
  it.each(['ON_HOLD', 'PAUSED', 'EXPIRED'])('removes access for current %s status despite historical purchase', async (state) => {
    googleMock(googleRecord({ subscriptionState: `SUBSCRIPTION_STATE_${state}` }));
    expect(await verifyStorePurchase(env, OWNER, googleInput())).toMatchObject({ active: false, revoked: false });
  });
  it('reconciles a refund/expiration on refresh and permits recovery from hold', async () => {
    googleMock();
    const paid = await verifyStorePurchase(env, OWNER, googleInput());
    googleMock(googleRecord({ subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED', lineItems: [{ productId: MONTHLY,
      expiryTime: iso(now() - 1000), latestSuccessfulOrderId: paid.purchaseId, autoRenewingPlan: { autoRenewEnabled: false } }] }));
    expect(await refreshStorePurchase(env, OWNER, paid.refresh)).toMatchObject({ active: false, autoRenew: false, originalPurchaseId: paid.originalPurchaseId });
    googleMock();
    expect(await refreshStorePurchase(env, OWNER, paid.refresh)).toMatchObject({ active: true, revoked: false });
  });
  it('preserves canceled access until expiry and grace only to authoritative expiry', async () => {
    googleMock(googleRecord({ subscriptionState: 'SUBSCRIPTION_STATE_CANCELED', lineItems: [{ productId: MONTHLY,
      expiryTime: iso(now() + 50000), latestSuccessfulOrderId: 'GPA.12345', autoRenewingPlan: { autoRenewEnabled: false } }] }));
    expect(await verifyStorePurchase(env, OWNER, googleInput())).toMatchObject({ active: true, autoRenew: false });
    googleMock(googleRecord({ subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', lineItems: [{ productId: MONTHLY,
      expiryTime: iso(now() - 1), latestSuccessfulOrderId: 'GPA.12345', autoRenewingPlan: { autoRenewEnabled: true } }] }));
    expect(await verifyStorePurchase(env, OWNER, googleInput())).toMatchObject({ active: false });
  });
  it('rejects pending payment and unknown status without granting', async () => {
    googleMock(googleRecord({ subscriptionState: 'SUBSCRIPTION_STATE_PENDING' }));
    await expect(verifyStorePurchase(env, OWNER, googleInput())).rejects.toMatchObject({ status: 400, code: 'purchase_not_settled' });
    googleMock(googleRecord({ subscriptionState: 'NEW_UNDOCUMENTED_STATE' }));
    await expect(verifyStorePurchase(env, OWNER, googleInput())).rejects.toMatchObject({ status: 503 });
  });
  it('refreshes approved product transitions but ignores unpaid deferred replacement', async () => {
    googleMock(googleRecord({ lineItems: [{ productId: YEARLY, expiryTime: iso(now() + 86400000), latestSuccessfulOrderId: 'GPA.12345', autoRenewingPlan: { autoRenewEnabled: true } }] }));
    await expect(verifyStorePurchase(env, OWNER, googleInput())).rejects.toMatchObject({ status: 400 });
    expect(await refreshStorePurchase(env, OWNER, googleInput())).toMatchObject({ productId: YEARLY, refresh: { productId: YEARLY } });
    const record = googleRecord();
    (record.lineItems as Json[]).push({ productId: YEARLY, expiryTime: iso(now() + 8640000000), autoRenewingPlan: { autoRenewEnabled: true } });
    googleMock(record);
    expect(await refreshStorePurchase(env, OWNER, googleInput())).toMatchObject({ productId: MONTHLY });
  });
});
describe('bounded provider failures', () => {
  it('fails closed with sanitized error on network timeout and invalid credentials', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('secret-token-network-detail'); }));
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toEqual(new StoreVerificationError(503, 'store_unavailable'));
    await expect(verifyStorePurchase({ ...env, APPLE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\ninvalid\n-----END PRIVATE KEY-----' }, OWNER, appleInput()))
      .rejects.toMatchObject({ status: 503, code: 'store_unavailable' });
  });
  it('rejects oversized/malformed provider data and unsigned JWS headers', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('x'.repeat(256 * 1024 + 1))));
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ status: 503 });
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ signedTransactionInfo: `${encode({ alg: 'none' })}.${encode(transaction())}.AA` })));
    await expect(verifyStorePurchase(env, OWNER, appleInput())).rejects.toMatchObject({ status: 503, code: 'invalid_store_response' });
    vi.stubGlobal('fetch', vi.fn(async () => new Response('<html>failure</html>')));
    await expect(verifyStorePurchase(env, OWNER, googleInput())).rejects.toMatchObject({ status: 503 });
  });
});
