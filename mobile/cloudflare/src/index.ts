import { createAuth } from './auth';
import { PairService } from './pair';
import { handleBillingRequest, type BillingEnvironment } from './billing';
import { handleBillingPage } from './billing_pages';
import { createPremiumCard } from './premium_cards';
import { handleTogetherRequest } from './together';
import { handleAccountRequest } from './account';
import { handleAccountPage } from './account_pages';

type Json = Record<string, unknown>;
const commands: Record<string, { rpc: string; fields: string[] }> = {
  create: { rpc: 'hamtdaa_create_pair_invite', fields: ['command_id', 'token_hash'] },
  request: { rpc: 'hamtdaa_request_pair', fields: ['command_id', 'token', 'expected_version'] },
  confirm: { rpc: 'hamtdaa_confirm_pair', fields: ['command_id', 'invitation_id', 'expected_version'] },
  close: { rpc: 'hamtdaa_close_pair_invite', fields: ['command_id', 'invitation_id', 'expected_version', 'action'] },
  unlink: { rpc: 'hamtdaa_unlink_pair', fields: ['command_id', 'pair_id', 'expected_version'] },
  'update-name': { rpc: 'hamtdaa_update_profile', fields: ['display_name', 'expected_version'] },
};

class RequestFailure extends Error {
  constructor(readonly code: string, readonly status: number, readonly retryAfter?: number) { super(code); }
}

function json(body: Json, status = 200, retryAfter = 60): Response {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store, private',
      'Pragma': 'no-cache',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      ...(status === 429 ? { 'Retry-After': String(retryAfter) } : {}),
    },
  });
}

function fail(code: string, status: number, retryAfter?: number): Response {
  return json({ ok: false, code, retryable: status === 429 || status >= 500 }, status, retryAfter);
}

function object(value: unknown): value is Json {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// Stream with a strict bound: Content-Length is optional and not trusted.
async function body(request: Request): Promise<Json> {
  if (request.headers.get('content-type')?.split(';')[0].trim() !== 'application/json') {
    throw new RequestFailure('unsupported_media_type', 415);
  }
  if (Number(request.headers.get('content-length')) > 8192) throw new RequestFailure('payload_too_large', 413);
  const reader = request.body?.getReader();
  if (!reader) throw new RequestFailure('validation', 400);
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    size += next.value.length;
    if (size > 8192) {
      await reader.cancel();
      throw new RequestFailure('payload_too_large', 413);
    }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const value: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes));
    if (object(value)) return value;
  } catch { /* Always return the same safe validation error. */ }
  throw new RequestFailure('validation', 400);
}

function fields(input: Json, allowed: string[]) {
  if (Object.keys(input).some((key) => !allowed.includes(key))) throw new RequestFailure('validation', 400);
}

function email(input: Json): string {
  if (typeof input.email !== 'string') throw new RequestFailure('invalid_email', 400);
  const value = input.email.trim().toLowerCase();
  if (value.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) throw new RequestFailure('invalid_email', 400);
  return value;
}

function bearer(request: Request): string {
  const value = request.headers.get('authorization');
  if (!value || !/^Bearer [^\s]{16,1024}$/.test(value)) throw new RequestFailure('unauthenticated', 401);
  return value;
}

function retryDelay(response: Response): number {
  const seconds = Number(response.headers.get('retry-after'));
  return Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 86400 ? seconds : 60;
}

function authError(response: Response, verification = false): Response {
  if (response.status === 429) return fail('rate_limited', 429, retryDelay(response));
  if (response.status >= 500) return fail('temporarily_unavailable', 503);
  return fail(verification ? 'invalid_code' : 'unauthenticated', verification ? 400 : 401);
}

function pairResult(result: Json): Response {
  if (result.ok !== false) return json(result);
  const status = ({ unauthenticated: 401, forbidden: 403, not_found: 404, rate_limited: 429,
    conflict: 409, already_paired: 409, invalid_state: 409, idempotency_mismatch: 409, expired: 410 } as Record<string, number>)[String(result.code)] ?? 400;
  return json(result, status);
}

/** Native app facade. Only the library handler creates/verifies/revokes sessions.
 * Never expose raw /api/auth, accept client actor IDs, or use cookie auth here. */
export async function handleRequest(request: Request, env: BillingEnvironment & { LEGAL_OPERATOR_NAME?: string; LEGAL_SUPPORT_EMAIL?: string }): Promise<Response> {
  try {
    const url = new URL(request.url);
    const page = handleAccountPage(request) ?? handleBillingPage(request, env);
    if (page) return page;
    if (url.search || url.hash) return fail('validation', 400);
    const origin = request.headers.get('origin');
    if (origin && origin !== new URL(env.AUTH_BASE_URL).origin) return fail('forbidden', 403);
    if (url.pathname === '/v1/health' && request.method === 'GET') {
      await env.DB.prepare('SELECT id FROM hamtdaa_calendar_events LIMIT 1').first();
      return json({ ok: true, service: 'hamtdaa', stage: 'auth-pair-together-billing-account' });
    }
    if ((url.pathname === '/v1/billing/catalog' && request.method === 'GET') ||
      (url.pathname === '/v1/billing/wire/webhook' && request.method === 'POST')) {
      // Webhooks verify the unmodified byte stream using the provider signature.
      return (await handleBillingRequest(request, env, null, null)) ?? fail('not_found', 404);
    }

    const auth = createAuth(env);
    const invoke = (path: string, payload?: Json, authorization?: string) => {
      const headers = new Headers({ accept: 'application/json' });
      // Cloudflare overwrites this header at the edge; never trust forwarded-for.
      const ip = request.headers.get('cf-connecting-ip');
      if (ip) headers.set('cf-connecting-ip', ip);
      if (authorization) headers.set('authorization', authorization);
      if (payload) headers.set('content-type', 'application/json');
      return auth.handler(new Request(new URL(`/api/auth/${path}`, env.AUTH_BASE_URL), {
        method: payload ? 'POST' : 'GET', headers,
        ...(payload ? { body: JSON.stringify(payload) } : {}),
      }));
    };
    const session = async (authorization: string) => {
      const response = await invoke('get-session', undefined, authorization);
      if (response.status === 429) throw new RequestFailure('rate_limited', 429, retryDelay(response));
      if (response.status >= 500) throw new RequestFailure('temporarily_unavailable', 503);
      if (!response.ok) throw new RequestFailure('unauthenticated', 401);
      const data: unknown = await response.json();
      if (!object(data) || !object(data.user) || !object(data.session) ||
        typeof data.user.id !== 'string' || typeof data.user.email !== 'string' ||
        data.user.emailVerified !== true || typeof data.session.expiresAt !== 'string' ||
        !(Date.parse(data.session.expiresAt) > Date.now())) throw new RequestFailure('unauthenticated', 401);
      const profile = await env.DB.prepare('SELECT account_state FROM hamtdaa_profiles WHERE user_id=?')
        .bind(data.user.id).first<{ account_state: string }>();
      if (profile && profile.account_state !== 'active') throw new RequestFailure('unauthenticated', 401);
      return { user: { id: data.user.id, email: data.user.email }, expires_at: data.session.expiresAt,
        session_created_at: typeof data.session.createdAt === 'string' ? data.session.createdAt : '',
        session_id: typeof data.session.id === 'string' ? data.session.id : '' };
    };

    if (url.pathname === '/v1/auth/request-code' && request.method === 'POST') {
      const input = await body(request); fields(input, ['email']);
      const response = await invoke('email-otp/send-verification-otp', { email: email(input), type: 'sign-in' });
      if (!response.ok) return authError(response);
      return json({ ok: true });
    }
    if (url.pathname === '/v1/auth/verify-code' && request.method === 'POST') {
      const input = await body(request); fields(input, ['email', 'code']);
      if (typeof input.code !== 'string' || !/^\d{6}$/.test(input.code.trim())) return fail('invalid_code', 400);
      const response = await invoke('sign-in/email-otp', { email: email(input), otp: input.code.trim() });
      if (!response.ok) return authError(response, true);
      const token = response.headers.get('set-auth-token');
      if (!token) return fail('temporarily_unavailable', 503);
      const verified = await session(`Bearer ${token}`);
      return json({ ok: true, token, ...verified });
    }
    if (url.pathname === '/v1/auth/sign-out' && request.method === 'POST') {
      const response = await invoke('sign-out', {}, bearer(request));
      return response.ok ? json({ ok: true }) : authError(response);
    }
    if (url.pathname === '/v1/auth/session' && request.method === 'GET') {
      return json({ ok: true, ...await session(bearer(request)) });
    }
    if (url.pathname.startsWith('/v1/together/')) {
      const verified = await session(bearer(request));
      return handleTogetherRequest(request, env, verified.user.id, request.method === 'POST' ? await body(request) : null);
    }
    if (url.pathname.startsWith('/v1/account/')) {
      const verified = await session(bearer(request));
      return handleAccountRequest(request, env,
        { ...verified.user, sessionCreatedAt: verified.session_created_at, sessionId: verified.session_id },
        request.method === 'POST' ? await body(request) : null);
    }
    if (url.pathname.startsWith('/v1/billing/')) {
      const actor = (await session(bearer(request))).user.id;
      const input = request.method === 'POST' ? await body(request) : null;
      return (await handleBillingRequest(request, env, actor, input)) ?? fail('not_found', 404);
    }
    if (url.pathname === '/v1/premium/cards' && request.method === 'POST') {
      const actor = (await session(bearer(request))).user.id;
      return await createPremiumCard(env, actor, await body(request));
    }
    if (url.pathname === '/v1/pair/status' && request.method === 'GET') {
      const actor = (await session(bearer(request))).user.id;
      return pairResult(await new PairService(env.DB).status(actor));
    }
    if (url.pathname === '/v1/pair/preview' && request.method === 'POST') {
      const actor = (await session(bearer(request))).user.id;
      const input = await body(request); fields(input, ['token']);
      if (typeof input.token !== 'string') return fail('not_found', 404);
      return pairResult(await new PairService(env.DB).preview(actor, input.token));
    }
    const match = /^\/v1\/pair\/commands\/([a-z-]+)$/.exec(url.pathname);
    const command = match && Object.hasOwn(commands, match[1]) ? commands[match[1]] : undefined;
    if (command && request.method === 'POST') {
      const actor = (await session(bearer(request))).user.id;
      const input = await body(request); fields(input, command.fields);
      const params = Object.fromEntries(Object.entries(input).map(([key, value]) => [`p_${key}`, value]));
      return pairResult(await new PairService(env.DB).execute(actor, command.rpc, params));
    }
    return fail('not_found', 404);
  } catch (error) {
    if (error instanceof RequestFailure) return fail(error.code, error.status, error.retryAfter);
    // Error objects can carry SQL, email addresses, tokens and request bodies.
    console.error(JSON.stringify({ event: 'api_failure', request_id: crypto.randomUUID() }));
    return fail('temporarily_unavailable', 503);
  }
}

export default {
  fetch(request, env) { return handleRequest(request, env); },
} satisfies ExportedHandler<Env>;
