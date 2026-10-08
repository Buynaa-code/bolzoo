import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { createPremiumCard } from '../src/premium_cards';
import { handleRequest } from '../src/index';
import { PairService, pairTokenHash } from '../src/pair';
import type { BillingEnvironment } from '../src/billing';

type Json = Record<string, unknown>;
const now = () => Math.floor(Date.now() / 1000);
const card = () => ({ names: 'Ану ♡ Тэмүүлэн', message: 'Чамтай өдөр бүр илүү гоё.', date: '2026-10-06', theme: 'rose' });
async function user(): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO "user"(id,name,email,emailVerified,createdAt,updatedAt) VALUES(?,?,?,?,?,?)')
    .bind(id, 'Туршилт', `${id}@example.test`, 1, Date.now(), Date.now()).run();
  await new PairService(env.DB).status(id);
  return id;
}
/** Fixtures represent authoritative grants already reconciled by the billing
 * layer. Billing tests separately prove provider verification and settlement. */
async function grant(actor: string, patch: { expires?: number; revoked?: number; starts?: number; active?: number; provider?: string; observed?: number } = {}) {
  const id = crypto.randomUUID();
  await env.DB.prepare(`INSERT INTO hamtdaa_billing_grants
    (provider,source_id,user_id,transaction_id,product_id,starts_at,expires_at,revoked_at,is_active,observed_at)
    VALUES(?,?,?,?,?,?,?,?,?,?)`).bind(patch.provider ?? 'wire', id, actor, id, 'mn.moch.hamtdaa.plus.monthly',
    patch.starts ?? now() - 3600, patch.expires ?? now() + 3600, patch.revoked ?? null, patch.active ?? 1, patch.observed ?? Date.now()).run();
  return id;
}
async function render(actor: string, input: Json = card()) {
  const response = await createPremiumCard(env, actor, input);
  return { response, status: response.status, data: await response.json<Json>() };
}
async function pair(a: string, b: string) {
  const service = new PairService(env.DB);
  const token = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  const created = await service.execute(a, 'hamtdaa_create_pair_invite', { p_command_id: crypto.randomUUID(), p_token_hash: await pairTokenHash(token) });
  expect(created.ok).not.toBe(false);
  const invitation = created.invitation as Json;
  const requested = await service.execute(b, 'hamtdaa_request_pair', { p_command_id: crypto.randomUUID(), p_token: token, p_expected_version: invitation.version });
  expect(requested.ok, JSON.stringify(requested)).not.toBe(false);
  const confirmed = await service.execute(a, 'hamtdaa_confirm_pair', { p_command_id: crypto.randomUUID(), p_invitation_id: invitation.id,
    p_expected_version: (requested.invitation as Json).version });
  expect(confirmed.ok).not.toBe(false);
  return { service, id: ((await service.status(a)).pair as Json).id, version: confirmed.version };
}

describe('premium card authorization against real D1 entitlements', () => {
  it('denies a free user and rejects forged tier/actor/asset fields', async () => {
    const a = await user();
    expect(await render(a)).toMatchObject({ status: 403, data: { ok: false, code: 'plus_required' } });
    for (const field of ['tier', 'plus_active', 'premium_cards', 'user_id', 'partner_id', 'asset_url', 'storage_path']) {
      expect(await render(a, { ...card(), [field]: 'forged' })).toMatchObject({ status: 400, data: { code: 'validation' } });
    }
  });
  it('returns the authorized card as inert JSON with private no-store headers', async () => {
    const a = await user(); await grant(a);
    const input = { ...card(), names: '  Ану ♡ Тэмүүлэн  ', message: '<img src=x onerror=alert(1)>', theme: 'sage' };
    const result = await render(a, input);
    expect(result.status).toBe(200);
    expect(result.data).toEqual({ ok: true, card: { ...input, names: input.names.trim(), colors: ['#F3F6EC', '#D9E4C7', '#49633D'], width: 1080, height: 1920 } });
    expect(result.response.headers.get('content-type')).toContain('application/json');
    expect(result.response.headers.get('cache-control')).toBe('no-store, private');
    expect(result.response.headers.get('x-content-type-options')).toBe('nosniff');
    expect(result.response.headers.get('set-cookie')).toBeNull();
  });
  it.each([
    { expires: now() - 1 }, { revoked: now() }, { starts: now() + 600 }, { active: 0 },
    { provider: 'apple', observed: Date.now() - 301000 },
    { provider: 'wire', observed: Date.now() - 301000 },
  ])('denies expired, refunded, not-started, inactive or stale entitlement %j', async (patch) => {
    const a = await user(); await grant(a, patch);
    expect(await render(a)).toMatchObject({ status: 403, data: { code: 'plus_required' } });
  });
  it('checks entitlement again on every render after refund', async () => {
    const a = await user(); const source = await grant(a);
    expect((await render(a)).status).toBe(200);
    await env.DB.prepare('UPDATE hamtdaa_billing_grants SET revoked_at=? WHERE source_id=?').bind(now(), source).run();
    expect((await render(a)).status).toBe(403);
  });
  it('allows only the current partner and removes shared card access immediately on unlink', async () => {
    const a = await user(); const b = await user(); const stranger = await user(); await grant(a);
    const linked = await pair(a, b);
    expect((await render(b)).status).toBe(200);
    expect((await render(stranger)).status).toBe(403);
    const unlinked = await linked.service.execute(b, 'hamtdaa_unlink_pair', { p_command_id: crypto.randomUUID(), p_pair_id: linked.id, p_expected_version: linked.version });
    expect(unlinked.ok).not.toBe(false);
    expect((await render(b)).status).toBe(403);
    expect((await render(a)).status).toBe(200);
  });
  it.each([
    { date: '2026-02-30' }, { date: '2026-2-01' }, { date: '2026-13-01' }, { date: 'NaN' },
    { date: '2026-10-06T00:00:00Z' }, { names: '' }, { names: ' '.repeat(4) }, { names: 'x'.repeat(51) },
    { message: 'x'.repeat(161) }, { message: '\tcontrol' }, { names: '\u0000invalid' }, { message: 'a\u007fb' },
    { theme: '__proto__' }, { theme: 'constructor' }, { theme: 'unknown' }, { message: 42 },
  ])('rejects malformed input before export %j', async (patch) => {
    const a = await user(); await grant(a);
    expect(await render(a, { ...card(), ...patch })).toMatchObject({ status: 400, data: { code: 'validation' } });
  });
  it('bounds card creation per actor and accepts a valid leap day', async () => {
    const a = await user(); await grant(a);
    for (let i = 0; i < 12; i++) expect((await render(a, { ...card(), date: '2028-02-29' })).status).toBe(200);
    expect(await render(a)).toMatchObject({ status: 429, data: { code: 'rate_limited' } });
  });
});

let nextIp = 90;
function httpClient() {
  let token: string | undefined;
  const messages: EmailMessageBuilder[] = [];
  const config: BillingEnvironment = { ...env, SIGNUP_ENABLED: 'true', EMAIL: {
    async send(message: EmailMessage | EmailMessageBuilder) {
      if (!('subject' in message)) throw new Error('Expected builder');
      messages.push(message); return { messageId: crypto.randomUUID() };
    },
  } };
  const ip = `203.0.113.${nextIp++}`;
  const request = (path: string, input: Json, headersInit?: HeadersInit) => {
    const headers = new Headers(headersInit);
    headers.set('Content-Type', 'application/json'); headers.set('cf-connecting-ip', ip);
    if (token && !headers.has('authorization')) headers.set('authorization', `Bearer ${token}`);
    return handleRequest(new Request(`https://auth.test${path}`, { method: 'POST', headers, body: JSON.stringify(input) }), config);
  };
  return { request, config, get token() { return token; }, async login() {
    const email = `${crypto.randomUUID()}@example.test`;
    expect((await request('/v1/auth/request-code', { email })).status).toBe(200);
    const code = messages.at(-1)?.text?.match(/\b\d{6}\b/)?.[0];
    const response = await request('/v1/auth/verify-code', { email, code });
    expect(response.status).toBe(200);
    const data = await response.json<Json>(); token = data.token as string;
    return (data.user as Json).id as string;
  } };
}
describe('premium card HTTP flow with real signed auth sessions', () => {
  it('requires a valid signed bearer even when a paying actor or cookie is supplied', async () => {
    const a = httpClient(); const id = await a.login(); await grant(id);
    const anonymous = httpClient();
    expect((await anonymous.request('/v1/premium/cards', card())).status).toBe(401);
    expect((await anonymous.request('/v1/premium/cards', { ...card(), user_id: id, tier: 'plus' })).status).toBe(401);
    expect((await anonymous.request('/v1/premium/cards', card(), { cookie: `better-auth.session_token=${a.token}` })).status).toBe(401);
    expect((await anonymous.request('/v1/premium/cards', card(), { authorization: `Bearer ${'x'.repeat(80)}` })).status).toBe(401);
    expect((await a.request('/v1/premium/cards', card())).status).toBe(200);
  });
  it('moves free→paid→refunded→logged-out with no stale UI tier accepted', async () => {
    const a = httpClient(); const id = await a.login();
    expect((await a.request('/v1/premium/cards', card())).status).toBe(403);
    expect((await a.request('/v1/premium/cards', { ...card(), tier: 'plus' })).status).toBe(400);
    const source = await grant(id);
    expect((await a.request('/v1/premium/cards', card())).status).toBe(200);
    await env.DB.prepare('UPDATE hamtdaa_billing_grants SET revoked_at=? WHERE source_id=?').bind(now(), source).run();
    expect((await a.request('/v1/premium/cards', card())).status).toBe(403);
    expect((await a.request('/v1/auth/sign-out', {})).status).toBe(200);
    expect((await a.request('/v1/premium/cards', card())).status).toBe(401);
  });
  it('revokes paid access when the account is disabled and rejects cross-origin export', async () => {
    const a = httpClient(); const id = await a.login(); await grant(id);
    await new PairService(env.DB).status(id);
    expect((await a.request('/v1/premium/cards', card(), { origin: 'https://evil.example' })).status).toBe(403);
    await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(id).run();
    expect((await a.request('/v1/premium/cards', card())).status).toBe(401);
  });
  it('enforces HTTP JSON and size bounds before rendering', async () => {
    const a = httpClient(); const id = await a.login(); await grant(id);
    expect((await a.request('/v1/premium/cards', { ...card(), message: 'x'.repeat(9000) })).status).toBe(413);
    const response = await handleRequest(new Request('https://auth.test/v1/premium/cards', { method: 'POST', body: '{',
      headers: { authorization: `Bearer ${a.token}`, 'Content-Type': 'application/json' } }), a.config);
    expect(response.status).toBe(400);
    const plain = await handleRequest(new Request('https://auth.test/v1/premium/cards', { method: 'POST', body: 'names=someone',
      headers: { authorization: `Bearer ${a.token}` } }), a.config);
    expect(plain.status).toBe(415);
  });
});
