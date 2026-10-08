import { betterAuth, type BetterAuthOptions } from 'better-auth';
import { APIError, createAuthMiddleware } from 'better-auth/api';
import { bearer, emailOTP } from 'better-auth/plugins';

// Bindings come from Wrangler; string settings are widened for isolated tests
// and future named environments instead of copying platform binding types.
export type AuthEnvironment = Pick<Env, 'DB' | 'EMAIL' | 'BETTER_AUTH_SECRET'> & {
  AUTH_BASE_URL: string;
  EMAIL_FROM: string;
  SIGNUP_ENABLED: string;
};

export const AUTH_BASE_PATH = '/api/auth';
export const SESSION_SECONDS = 60 * 60 * 24 * 7;
export const OTP_SECONDS = 60 * 5;
export const OTP_ATTEMPTS = 5;
export const EMAIL_DAILY_LIMIT = 100;
const EMAIL_FAILURE_HEADER = 'x-hamtdaa-email-failure';

async function keyedHash(secret: string, purpose: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const bytes = new Uint8Array(await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`${purpose}\0${value}`),
  ));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** An atomic, shared rate bucket. No raw email or IP is stored in the key. */
export function createAuthRateStorage(env: Pick<AuthEnvironment, 'DB' | 'BETTER_AUTH_SECRET'>) {
  return {
    async consume(key: string, rule: { window: number; max: number }) {
      const digest = await keyedHash(env.BETTER_AUTH_SECRET, 'auth-rate-v1', key);
      const now = Date.now();
      const cutoff = now - rule.window * 1000;
      const row = await env.DB.prepare(`
        INSERT INTO "rateLimit" (id, "key", "count", "lastRequest") VALUES (?, ?, 1, ?)
        ON CONFLICT("key") DO UPDATE SET
          "count" = CASE WHEN "lastRequest" <= ? THEN 1 ELSE "count" + 1 END,
          "lastRequest" = CASE WHEN "lastRequest" <= ? THEN excluded."lastRequest" ELSE "lastRequest" END
        WHERE "lastRequest" <= ? OR "count" < ?
        RETURNING "count", "lastRequest"
      `).bind(digest, digest, now, cutoff, cutoff, cutoff, rule.max)
        .first<{ count: number; lastRequest: number }>();
      if (row) {
        // Bounded maintenance only on a newly opened bucket. All configured
        // windows are <= 1 day. Only already-expired buckets can be removed.
        if (row.count === 1) {
          await env.DB.prepare(`DELETE FROM "rateLimit" WHERE id IN (
            SELECT id FROM "rateLimit" WHERE "lastRequest" < ? LIMIT 100
          )`).bind(now - 86_400_000).run();
        }
        return { allowed: true, retryAfter: null };
      }
      const current = await env.DB.prepare('SELECT "lastRequest" FROM "rateLimit" WHERE "key" = ?')
        .bind(digest).first<{ lastRequest: number }>();
      // Another request removing a stale row must never turn a denied request
      // into an uncounted grant.
      return {
        allowed: false,
        retryAfter: Math.max(1, Math.ceil(((current?.lastRequest ?? now) + rule.window * 1000 - now) / 1000)),
      };
    },
  };
}

/** Exported so migration generation uses exactly the configured auth models. */
export function createAuthOptions(env: AuthEnvironment) {
  if (env.BETTER_AUTH_SECRET.length < 32) throw new Error('Auth secret must contain at least 32 characters.');
  const base = new URL(env.AUTH_BASE_URL);
  if (base.username || base.password || base.pathname !== '/' || base.search || base.hash ||
      (base.protocol !== 'https:' && !(base.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)))) {
    throw new Error('Auth base URL must be an HTTPS origin or a local development origin.');
  }
  if (env.EMAIL_FROM !== 'noreply@auth.moch.mn') throw new Error('Unexpected auth email sender.');
  const rateStorage = createAuthRateStorage(env);
  return {
    appName: 'Хамтдаа',
    baseURL: base.origin,
    basePath: AUTH_BASE_PATH,
    secret: env.BETTER_AUTH_SECRET,
    database: env.DB,
    trustedOrigins: [base.origin],
    emailAndPassword: { enabled: false, disableSignUp: true },
    session: {
      expiresIn: SESSION_SECONDS,
      disableSessionRefresh: true,
      cookieCache: { enabled: false },
    },
    verification: {
      storeIdentifier: { hash: (identifier: string) => keyedHash(env.BETTER_AUTH_SECRET, 'auth-identifier-v1', identifier) },
    },
    advanced: {
      // CF injects this header at the edge; forwarded-for headers from clients
      // must not create arbitrary rate-limit buckets.
      ipAddress: { ipAddressHeaders: ['cf-connecting-ip'] },
      useSecureCookies: base.protocol === 'https:',
    },
    logger: { disabled: true },
    rateLimit: {
      enabled: true,
      storage: 'database',
      window: 60,
      max: 60,
      customStorage: rateStorage,
      customRules: {
        '/email-otp/send-verification-otp': { window: 60, max: 3 },
        '/sign-in/email-otp': { window: 60, max: 10 },
      },
    },
    hooks: {
      before: createAuthMiddleware(async (ctx) => {
        const sending = ctx.path === '/email-otp/send-verification-otp';
        const verifying = ctx.path === '/sign-in/email-otp';
        if (!sending && !verifying) return;
        const email = typeof ctx.body?.email === 'string' ? ctx.body.email.trim().toLowerCase() : '';
        if (!email || email.length > 254) throw new APIError('BAD_REQUEST', { code: 'INVALID_EMAIL', message: 'Invalid email.' });
        // Applying limits before account lookup keeps unknown addresses and
        // existing accounts indistinguishable in the public response.
        const rules = sending
          ? [{ key: 'send-cooldown', window: 60, max: 1 }, { key: 'send-hour', window: 3600, max: 5 }]
          : [{ key: 'verify-email', window: 600, max: 10 }];
        for (const rule of rules) {
          const result = await rateStorage.consume(`${rule.key}|${email}`, rule);
          if (!result.allowed) {
            ctx.setHeader('Retry-After', String(result.retryAfter));
            throw new APIError('TOO_MANY_REQUESTS', { code: 'RATE_LIMITED', message: 'Please try again later.' });
          }
        }
        // The first release is deliberately capped at 100 send requests/day
        // across all Workers, protecting the transactional sender quota. Count
        // before user lookup so signup settings cannot expose account existence.
        if (sending) {
          const result = await rateStorage.consume('send-global-day', { window: 86400, max: EMAIL_DAILY_LIMIT });
          if (!result.allowed) {
            ctx.setHeader('Retry-After', String(result.retryAfter));
            throw new APIError('TOO_MANY_REQUESTS', { code: 'RATE_LIMITED', message: 'Please try again later.' });
          }
        }
      }),
      after: createAuthMiddleware(async (ctx) => {
        // Better Auth intentionally swallows background email errors, including
        // awaited callbacks. This request-local marker lets our facade report a
        // retryable failure without returning provider details or secret data.
        if (ctx.context.responseHeaders?.get(EMAIL_FAILURE_HEADER) === '1') {
          ctx.context.responseHeaders.delete(EMAIL_FAILURE_HEADER);
          throw new APIError('SERVICE_UNAVAILABLE', { code: 'EMAIL_UNAVAILABLE', message: 'Email delivery unavailable.' });
        }
      }),
    },
    databaseHooks: {
      session: {
        create: {
          before: async (session: { userId: string }) => {
            const profile = await env.DB.prepare('SELECT account_state FROM hamtdaa_profiles WHERE user_id = ?')
              .bind(session.userId).first<{ account_state: string }>();
            if (profile && profile.account_state !== 'active') {
              throw new APIError('FORBIDDEN', { code: 'ACCOUNT_UNAVAILABLE', message: 'Account unavailable.' });
            }
          },
        },
      },
    },
    plugins: [
      {
        id: 'hamtdaa-auth-schema',
        // Only one outstanding challenge per purpose/address. Without this,
        // equal createdAt timestamps can make resend select an older challenge.
        schema: { verification: { fields: { identifier: { type: 'string', required: true, unique: true } } } },
      },
      bearer({ requireSignature: true }),
      emailOTP({
        otpLength: 6,
        expiresIn: OTP_SECONDS,
        allowedAttempts: OTP_ATTEMPTS,
        disableSignUp: env.SIGNUP_ENABLED !== 'true',
        // A keyed digest protects the small six-digit space against offline
        // guessing from a database-only leak. Better Auth compares safely.
        storeOTP: { hash: (otp) => keyedHash(env.BETTER_AUTH_SECRET, 'auth-otp-v1', otp) },
        resendStrategy: 'rotate',
        sendVerificationOnSignUp: false,
        sendVerificationOTP: async ({ email, otp, type }, ctx) => {
          if (type !== 'sign-in') throw new APIError('BAD_REQUEST', { code: 'UNSUPPORTED_OTP_TYPE', message: 'Unsupported request.' });
          try {
            await env.EMAIL.send({
              to: email,
              from: { email: env.EMAIL_FROM, name: 'Хамтдаа' },
              subject: 'Хамтдаа — нэвтрэх код',
              text: `Таны Хамтдаа аппд нэвтрэх код: ${otp}\nКод 5 минутын хугацаанд хүчинтэй. Кодоо бусдад бүү дамжуулаарай.\nХэрэв та хүсэлт гаргаагүй бол энэ имэйлийг үл тооно уу.`,
              html: `<div lang="mn"><h1>Хамтдаа</h1><p>Таны нэвтрэх код:</p><p style="font-size:32px;letter-spacing:8px"><strong>${otp}</strong></p><p>Код 5 минутын хугацаанд хүчинтэй. Кодоо бусдад бүү дамжуулаарай.</p><p>Хэрэв та хүсэлт гаргаагүй бол энэ имэйлийг үл тооно уу.</p></div>`,
            });
          } catch {
            // Do not leave an undisclosed valid code after delivery failure and
            // never log recipient, OTP or provider error payloads.
            if (ctx) {
              ctx.setHeader(EMAIL_FAILURE_HEADER, '1');
              await ctx.context.internalAdapter.deleteVerificationByIdentifier(`sign-in-otp-${email}`);
            }
            throw new APIError('SERVICE_UNAVAILABLE', { code: 'EMAIL_UNAVAILABLE', message: 'Email delivery unavailable.' });
          }
        },
      }),
    ],
  } satisfies BetterAuthOptions;
}

export function createAuth(env: AuthEnvironment) {
  return betterAuth(createAuthOptions(env));
}

export type AppAuth = ReturnType<typeof createAuth>;
export type AuthSession = AppAuth['$Infer']['Session'];
