import { env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { getMigrations } from 'better-auth/db/migration';
import { createAuth, createAuthOptions, createAuthRateStorage, EMAIL_DAILY_LIMIT, OTP_ATTEMPTS, SESSION_SECONDS, type AuthEnvironment } from '../src/auth';

let addressNumber = 1;
function fixture(signup = 'true', database: D1Database = env.DB) {
  const deliveries: EmailMessageBuilder[] = [];
  const email = `auth-${crypto.randomUUID()}@example.test`;
  const ip = `203.0.113.${addressNumber++}`;
  const testEnv: AuthEnvironment = {
    ...env,
    DB: database,
    SIGNUP_ENABLED: signup,
    EMAIL: { async send(message: EmailMessage | EmailMessageBuilder) {
      if (!('subject' in message)) throw new Error('Expected a composed email.');
      deliveries.push(message);
      return { messageId: crypto.randomUUID() };
    } },
  };
  const auth = createAuth(testEnv);
  const request = (path: string, body?: Record<string, unknown>, token?: string, clientIP = ip) => {
    const headers = new Headers({ 'cf-connecting-ip': clientIP });
    if (body) headers.set('content-type', 'application/json');
    if (token) headers.set('authorization', `Bearer ${token}`);
    return auth.handler(new Request(`https://auth.test/api/auth/${path}`, {
      method: body ? 'POST' : 'GET', headers,
      ...(body ? { body: JSON.stringify(body) } : {}),
    }));
  };
  const send = () => request('email-otp/send-verification-otp', { email, type: 'sign-in' });
  const code = () => {
    const value = deliveries.at(-1)?.text?.match(/\b\d{6}\b/)?.[0];
    if (!value) throw new Error('Expected a six-digit code in the captured email.');
    return value;
  };
  const verify = (otp = code()) => request('sign-in/email-otp', { email, otp });
  return { auth, testEnv, email, ip, deliveries, request, send, code, verify };
}

function latch() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}

function afterVerificationConsume(database: D1Database, pause: () => Promise<void>): D1Database {
  const wrapStatement = (statement: D1PreparedStatement, sql: string): D1PreparedStatement => new Proxy(statement, {
    get(target, key) {
      if (key === 'bind') return (...values: unknown[]) => wrapStatement(target.bind(...values), sql);
      if (key === 'all') return async () => {
        const result = await target.all();
        if (/delete from "verification"/i.test(sql) && /returning/i.test(sql)) await pause();
        return result;
      };
      const value = Reflect.get(target, key);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  return new Proxy(database, {
    get(target, key) {
      if (key === 'prepare') return (sql: string) => wrapStatement(target.prepare(sql), sql);
      const value = Reflect.get(target, key);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
}

beforeEach(async () => {
  await env.DB.prepare('DELETE FROM "rateLimit"').run();
  await env.DB.prepare('DELETE FROM "verification"').run();
});

describe('Cloudflare OTP authentication with real D1 storage', () => {
  it('matches the generated migration to the configured Better Auth schema', async () => {
    const f = fixture();
    const plan = await getMigrations(createAuthOptions(f.testEnv));
    expect(plan.toBeCreated).toEqual([]);
    expect(plan.toBeAdded).toEqual([]);
    expect(plan.toBeAddedIndexes).toEqual([]);
    expect(plan.schemaProblems).toEqual([]);
    expect(plan.unsafeChanges).toEqual([]);
  });

  it('sends six digits and stores keyed hashes instead of OTP/email/IP in auth challenge and rate keys', async () => {
    const f = fixture();
    expect((await f.send()).status).toBe(200);
    expect(f.code()).toMatch(/^\d{6}$/);
    expect(f.deliveries).toHaveLength(1);
    expect(f.deliveries[0].from).toEqual({ email: 'noreply@auth.moch.mn', name: 'Хамтдаа' });
    expect(f.deliveries[0].html).toContain(f.code());
    const challenge = await env.DB.prepare('SELECT * FROM verification').first<{ identifier: string; value: string }>();
    expect(challenge?.identifier).toMatch(/^[0-9a-f]{64}$/);
    expect(challenge?.value).toMatch(/^[0-9a-f]{64}:0$/);
    expect(challenge?.value.split(':')[0]).not.toBe(f.code());
    const buckets = await env.DB.prepare('SELECT "key" FROM "rateLimit"').all<{ key: string }>();
    expect(buckets.results.length).toBeGreaterThan(0);
    for (const bucket of buckets.results) expect(bucket.key).toMatch(/^[0-9a-f]{64}$/);
  });

  it('creates a verified fixed-expiry session, rejects unsigned/altered bearer and revokes on sign-out', async () => {
    const f = fixture();
    await f.send();
    const response = await f.verify();
    expect(response.status).toBe(200);
    const signed = response.headers.get('set-auth-token')!;
    const body = await response.json<{ token: string; user: { id: string; emailVerified: boolean } }>();
    expect(body.user.emailVerified).toBe(true);
    expect(signed).toBeTruthy();
    expect(signed).not.toBe(body.token);
    const sessionResponse = await f.request('get-session', undefined, signed);
    const session = await sessionResponse.json<{ session: { expiresAt: string }; user: { id: string } }>();
    expect(session.user.id).toBe(body.user.id);
    const remaining = Date.parse(session.session.expiresAt) - Date.now();
    expect(remaining).toBeGreaterThan((SESSION_SECONDS - 10) * 1000);
    expect(remaining).toBeLessThanOrEqual(SESSION_SECONDS * 1000);
    expect(await (await f.request('get-session', undefined, body.token)).json()).toBeNull();
    expect(await (await f.request('get-session', undefined, `${signed}tampered`)).json()).toBeNull();
    expect((await f.request('sign-out', {}, signed)).status).toBe(200);
    expect(await (await f.request('get-session', undefined, signed)).json()).toBeNull();
  });

  it('allows at most one session when the same valid OTP is submitted concurrently', async () => {
    const f = fixture();
    await f.send();
    const otp = f.code();
    const results = await Promise.all([f.verify(otp), f.verify(otp), f.verify(otp)]);
    expect(results.filter((response) => response.status === 200)).toHaveLength(1);
    expect(results.filter((response) => response.status === 400)).toHaveLength(2);
    expect((await f.verify(otp)).status).toBe(400);
  });

  it('rejects an expired OTP even when its value is correct', async () => {
    const f = fixture();
    await f.send();
    await env.DB.prepare('UPDATE verification SET "expiresAt" = ?').bind(new Date(0).toISOString()).run();
    expect((await f.verify()).status).toBe(400);
  });

  it('locks a code after the configured wrong-attempt budget', async () => {
    const f = fixture();
    await f.send();
    const wrong = f.code() === '000000' ? '111111' : '000000';
    for (let i = 0; i < OTP_ATTEMPTS; i++) expect((await f.verify(wrong)).status).toBe(400);
    expect((await f.verify()).status).toBe(403);
    expect((await f.verify()).status).toBe(400);
  });

  it('enforces an email resend cooldown across different client IPs and auth instances', async () => {
    const f = fixture();
    const second = createAuth(f.testEnv);
    const request = new Request('https://auth.test/api/auth/email-otp/send-verification-otp', {
      method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': '198.51.100.201' },
      body: JSON.stringify({ email: f.email, type: 'sign-in' }),
    });
    const results = await Promise.all([f.send(), second.handler(request)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 429]);
    expect(f.deliveries).toHaveLength(1);
  });

  it('rotates a code when resend is allowed and invalidates the previous code', async () => {
    const f = fixture();
    await f.send();
    const oldCode = f.code();
    await env.DB.prepare('DELETE FROM "rateLimit"').run();
    await f.send();
    const nextCode = f.code();
    // A random six-digit generator can rarely produce the same digits; assert
    // old challenge removal unconditionally and differing-code rejection when distinct.
    expect(f.deliveries).toHaveLength(2);
    expect((await env.DB.prepare('SELECT count(*) AS total FROM verification').first<{ total: number }>())?.total).toBe(1);
    if (oldCode !== nextCode) expect((await f.verify(oldCode)).status).toBe(400);
    expect((await f.verify(nextCode)).status).toBe(200);
  });

  it('preserves a newly resent code while an older verification finishes consuming its code', async () => {
    const consumed = latch();
    const finishConsume = latch();
    let paused = false;
    const database = afterVerificationConsume(env.DB, async () => {
      if (paused) return;
      paused = true;
      consumed.resolve();
      await finishConsume.promise;
    });
    const f = fixture('true', database);
    expect((await f.send()).status).toBe(200);
    const verifying = f.verify(f.code());
    await Promise.race([consumed.promise, verifying.then(async (response) => { throw new Error(`Verification finished before pause: ${response.status} ${await response.text()}`); })]);
    try {
      await env.DB.prepare('UPDATE "rateLimit" SET "lastRequest" = "lastRequest" - 61_000').run();
      // The router creates an auth instance per HTTP request. Reusing f.auth
      // would queue the resend behind its deliberately paused Kysely connection
      // and deadlock the fixture instead of exercising a concurrent request.
      const resend = createAuth({ ...f.testEnv, DB: env.DB });
      const response = await resend.handler(new Request('https://auth.test/api/auth/email-otp/send-verification-otp', {
        method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': f.ip },
        body: JSON.stringify({ email: f.email, type: 'sign-in' }),
      }));
      expect(response.status).toBe(200);
    } finally {
      finishConsume.resolve();
    }
    expect((await verifying).status).toBe(200);
    expect(f.deliveries).toHaveLength(2);
    expect((await f.verify(f.code())).status).toBe(200);
  });

  it('limits email resends within an hour even after each one-minute cooldown', async () => {
    const f = fixture();
    for (let i = 0; i < 5; i++) {
      expect((await f.send()).status).toBe(200);
      await env.DB.prepare('UPDATE "rateLimit" SET "lastRequest" = "lastRequest" - 61_000').run();
    }
    expect((await f.send()).status).toBe(429);
    expect(f.deliveries).toHaveLength(5);
  });

  it('does not send or create users with public signup disabled', async () => {
    const f = fixture('false');
    expect((await f.send()).status).toBe(200);
    expect(f.deliveries).toHaveLength(0);
    expect((await f.verify('000000')).status).toBe(400);
    expect(await env.DB.prepare('SELECT id FROM "user" WHERE email = ?').bind(f.email).first()).toBeNull();
  });

  it('continues to authenticate an existing user when public signup is disabled', async () => {
    const f = fixture();
    await f.send();
    expect((await f.verify()).status).toBe(200);
    await env.DB.prepare('DELETE FROM "rateLimit"').run();
    const closed = createAuth({ ...f.testEnv, SIGNUP_ENABLED: 'false' });
    const request = (path: string, body: Record<string, unknown>) => closed.handler(new Request(`https://auth.test/api/auth/${path}`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': f.ip }, body: JSON.stringify(body),
    }));
    expect((await request('email-otp/send-verification-otp', { email: f.email, type: 'sign-in' })).status).toBe(200);
    expect((await request('sign-in/email-otp', { email: f.email, otp: f.code() })).status).toBe(200);
  });

  it('blocks new sessions for a disabled account', async () => {
    const f = fixture();
    await f.send();
    const user = (await (await f.verify()).json<{ user: { id: string } }>()).user;
    await env.DB.prepare("INSERT INTO hamtdaa_profiles (user_id, account_state) VALUES (?, 'disabled')").bind(user.id).run();
    await env.DB.prepare('DELETE FROM "rateLimit"').run();
    await f.send();
    expect((await f.verify()).status).toBe(403);
  });

  it('returns a safe delivery error and invalidates the challenge if the sender fails', async () => {
    const f = fixture();
    const failing = createAuth({ ...f.testEnv, EMAIL: { async send() { throw new Error('provider payload must stay private'); } } });
    const response = await failing.handler(new Request('https://auth.test/api/auth/email-otp/send-verification-otp', {
      method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': f.ip },
      body: JSON.stringify({ email: f.email, type: 'sign-in' }),
    }));
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain('provider payload');
    expect(await env.DB.prepare('SELECT id FROM verification').first()).toBeNull();
  });
});

describe('atomic authentication limits', () => {
  it('stops sender traffic at the global daily cap and resets only after that window', async () => {
    const storage = createAuthRateStorage(env);
    await Promise.all(Array.from({ length: EMAIL_DAILY_LIMIT }, () => storage.consume('send-global-day', { window: 86400, max: EMAIL_DAILY_LIMIT })));
    const f = fixture();
    expect((await f.send()).status).toBe(429);
    expect(f.deliveries).toHaveLength(0);
    await env.DB.prepare('UPDATE "rateLimit" SET "lastRequest" = "lastRequest" - 86_401_000').run();
    expect((await f.send()).status).toBe(200);
    expect(f.deliveries).toHaveLength(1);
  });

  it('enforces the exact budget across many simultaneous independent storage clients', async () => {
    const key = `race|${crypto.randomUUID()}`;
    const results = await Promise.all(Array.from({ length: 24 }, () => createAuthRateStorage(env).consume(key, { window: 60, max: 5 })));
    expect(results.filter((result) => result.allowed)).toHaveLength(5);
    expect(results.filter((result) => !result.allowed)).toHaveLength(19);
    for (const result of results.filter((result) => !result.allowed)) expect(result.retryAfter).toBeGreaterThan(0);
  });

  it('opens a new bucket after its fixed window expires', async () => {
    const storage = createAuthRateStorage(env);
    const key = `expiry|${crypto.randomUUID()}`;
    expect((await storage.consume(key, { window: 60, max: 1 })).allowed).toBe(true);
    expect((await storage.consume(key, { window: 60, max: 1 })).allowed).toBe(false);
    await env.DB.prepare('UPDATE "rateLimit" SET "lastRequest" = ?').bind(Date.now() - 61_000).run();
    expect((await storage.consume(key, { window: 60, max: 1 })).allowed).toBe(true);
  });
});
