import { env } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { handleRequest } from '../src/index';
import { type AuthEnvironment } from '../src/auth';
import * as authModule from '../src/auth';
import { pairTokenHash } from '../src/pair';

type Json = Record<string, unknown>;
let ipNumber = 1;
afterEach(() => vi.restoreAllMocks());
function client() {
  const messages: EmailMessageBuilder[] = [];
  const ip = `198.51.100.${ipNumber++}`;
  const config: AuthEnvironment = { ...env, SIGNUP_ENABLED: 'true', EMAIL: {
    async send(message: EmailMessage | EmailMessageBuilder) {
      if (!('subject' in message)) throw new Error('Expected builder');
      messages.push(message);
      return { messageId: crypto.randomUUID() };
    },
  } };
  let token: string | undefined;
  const call = (path: string, input?: Json, custom?: HeadersInit) => {
    const headers = new Headers(custom);
    headers.set('cf-connecting-ip', ip);
    if (token && !headers.has('authorization')) headers.set('authorization', `Bearer ${token}`);
    if (input) headers.set('content-type', 'application/json');
    return handleRequest(new Request(`https://auth.test${path}`, {
      method: input ? 'POST' : 'GET', headers,
      ...(input ? { body: JSON.stringify(input) } : {}),
    }), config);
  };
  const data = async (path: string, input?: Json) => {
    const response = await call(path, input);
    const value = await response.json<Json>();
    expect(response.status, JSON.stringify(value)).toBe(200);
    expect(response.headers.get('cache-control')).toContain('no-store');
    expect(response.headers.get('set-cookie')).toBeNull();
    return value;
  };
  const login = async () => {
    const email = `${crypto.randomUUID()}@example.test`;
    await data('/v1/auth/request-code', { email });
    const code = messages.at(-1)?.text?.match(/\b\d{6}\b/)?.[0];
    const result = await data('/v1/auth/verify-code', { email, code });
    token = result.token as string;
    expect(token).toBeTruthy();
    expect((result.user as Json).email).toBe(email);
    expect(result.session).toBeUndefined();
    return result.user as { id: string; email: string };
  };
  return { config, call, data, login, messages, get token() { return token; } };
}

describe('native HTTP API with real auth and D1', () => {
  it('keeps transient session failures retryable and preserves long upstream rate-limit delays', async () => {
    const a = client();
    const auth = authModule.createAuth(a.config);
    const handler = vi.spyOn(auth, 'handler');
    vi.spyOn(authModule, 'createAuth').mockReturnValue(auth);
    handler.mockResolvedValue(Response.json({ message: 'private database error' }, { status: 500 }));
    const failed = await a.call('/v1/auth/session', undefined, { authorization: 'Bearer '.concat('x'.repeat(40)) });
    expect(failed.status).toBe(503);
    expect(await failed.json()).toEqual({ ok: false, code: 'temporarily_unavailable', retryable: true });
    handler.mockResolvedValue(Response.json({}, { status: 429, headers: { 'Retry-After': '86000' } }));
    const limited = await a.call('/v1/auth/request-code', { email: 'limited@example.test' });
    expect(limited.status).toBe(429);
    expect(limited.headers.get('retry-after')).toBe('86000');
  });

  it('supports two authenticated users: profile → invite → preview → request → confirm → unlink → logout', async () => {
    const a = client(); const b = client(); const c = client();
    const userA = await a.login(); const userB = await b.login(); await c.login();
    const initial = await a.data('/v1/pair/status');
    expect((initial.profile as Json).user_id).toBe(userA.id);
    await a.data('/v1/pair/commands/update-name', { display_name: 'Ану', expected_version: 1 });
    await b.data('/v1/pair/status');
    await b.data('/v1/pair/commands/update-name', { display_name: 'Тэмүүлэн', expected_version: 1 });
    const secret = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
      .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    const created = await a.data('/v1/pair/commands/create', { command_id: crypto.randomUUID(), token_hash: await pairTokenHash(secret) });
    const invite = created.invitation as Json;
    expect(JSON.stringify(created)).not.toContain(secret);
    const preview = await b.data('/v1/pair/preview', { token: secret });
    expect(((preview.invitation as Json).creator as Json).display_name).toBe('Ану');
    const requested = await b.data('/v1/pair/commands/request', { command_id: crypto.randomUUID(), token: secret, expected_version: invite.version });
    const pending = requested.invitation as Json;
    expect((await a.data('/v1/pair/status')).pair).toBeNull();
    expect((await b.call('/v1/pair/commands/confirm', { command_id: crypto.randomUUID(), invitation_id: invite.id, expected_version: pending.version })).status).toBe(403);
    const confirmed = await a.data('/v1/pair/commands/confirm', { command_id: crypto.randomUUID(), invitation_id: invite.id, expected_version: pending.version });
    const pairedA = (await a.data('/v1/pair/status')).pair as Json;
    const pairedB = (await b.data('/v1/pair/status')).pair as Json;
    expect(pairedA.id).toBe(pairedB.id);
    expect((pairedA.partner as Json).user_id).toBe(userB.id);
    expect((pairedB.partner as Json).user_id).toBe(userA.id);
    expect((await c.data('/v1/pair/status')).pair).toBeNull();
    expect((await c.call('/v1/pair/commands/unlink', { command_id: crypto.randomUUID(), pair_id: pairedA.id, expected_version: confirmed.version })).status).toBe(404);
    await b.data('/v1/pair/commands/unlink', { command_id: crypto.randomUUID(), pair_id: pairedB.id, expected_version: confirmed.version });
    expect((await a.data('/v1/pair/status')).pair).toBeNull();
    expect((await b.data('/v1/pair/status')).pair).toBeNull();
    await a.data('/v1/auth/sign-out', {});
    expect((await a.call('/v1/auth/session')).status).toBe(401);
    expect((await a.call('/v1/pair/status')).status).toBe(401);
  });

  it('rejects cookie identity, forged actor fields and disables all access after profile suspension', async () => {
    const a = client(); const user = await a.login();
    await a.data('/v1/pair/status');
    const stranger = client();
    expect((await stranger.call('/v1/pair/status', undefined, { cookie: `better-auth.session_token=${a.token}` })).status).toBe(401);
    expect((await a.call('/v1/pair/commands/update-name', { display_name: 'Other', expected_version: 1, user_id: 'other-user' })).status).toBe(400);
    await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(user.id).run();
    expect((await a.call('/v1/auth/session')).status).toBe(401);
    expect((await a.call('/v1/pair/status')).status).toBe(401);
    expect((await a.call('/v1/pair/commands/create', { command_id: crypto.randomUUID(), token_hash: 'a'.repeat(64) })).status).toBe(401);
    // Users must still be able to revoke a suspended account's exact session.
    await a.data('/v1/auth/sign-out', {});
  });

  it('deletes an account using its exact freshly authenticated session and revokes that token', async () => {
    const a = client(); const user = await a.login();
    await a.data('/v1/pair/status');
    const session = await a.data('/v1/auth/session');
    expect(typeof session.session_id).toBe('string');
    expect(Number.isFinite(Date.parse(session.session_created_at as string))).toBe(true);
    const stored = await env.DB.prepare('SELECT createdAt FROM "session" WHERE id=? AND userId=?')
      .bind(session.session_id, user.id).first<{ createdAt: string }>();
    expect(stored?.createdAt).toBe(session.session_created_at);
    expect((await a.data('/v1/account/delete', { confirmation: 'УСТГАХ' })).deleted).toBe(true);
    expect(await env.DB.prepare('SELECT 1 FROM "session" WHERE userId=?').bind(user.id).first()).toBeNull();
    expect((await a.call('/v1/auth/session')).status).toBe(401);
    expect((await a.call('/v1/pair/status')).status).toBe(401);
  });

  it('exposes only the native facade and rejects foreign origins, query tokens, oversized and non-JSON bodies', async () => {
    const a = client();
    expect((await a.call('/api/auth/get-session')).status).toBe(404);
    expect((await a.call('/v1/auth/session?token=secret')).status).toBe(400);
    expect((await a.call('/v1/health', undefined, { origin: 'https://evil.test' })).status).toBe(403);
    const plain = await handleRequest(new Request('https://auth.test/v1/auth/request-code', { method: 'POST', body: 'email=someone' }), a.config);
    expect(plain.status).toBe(415);
    expect((await a.call('/v1/auth/request-code', { email: 'a'.repeat(9000) })).status).toBe(413);
    expect((await a.call('/v1/auth/request-code', { email: 'not-an-email' })).status).toBe(400);
    const malformed = await handleRequest(new Request('https://auth.test/v1/auth/request-code', { method: 'POST', body: '{', headers: { 'content-type': 'application/json' } }), a.config);
    expect(malformed.status).toBe(400);
    expect(a.messages).toHaveLength(0);
    expect(await (await a.call('/v1/health')).json()).toMatchObject({ ok: true });
  });
});
