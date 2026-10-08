import { createAuthRateStorage } from './auth';
import { getBillingStatus, type BillingEnvironment } from './billing';

const palettes = {
  rose: ['#FFF0F6', '#FFD3E5', '#D62078'],
  sage: ['#F3F6EC', '#D9E4C7', '#49633D'],
  peach: ['#FFF6ED', '#FFDBC1', '#A34E32'],
} as const;

/** Every render/export is authorized against current server entitlement. No
 * client-provided tier, partner ID, asset URL or storage path is accepted. */
export async function createPremiumCard(env: BillingEnvironment, actor: string, input: Record<string, unknown>) {
  const headers = { 'Cache-Control': 'no-store, private', 'X-Content-Type-Options': 'nosniff' };
  const fail = (code: string, status: number) => Response.json({ ok: false, code }, { status, headers });
  if (Object.keys(input).some(k => !['names', 'message', 'date', 'theme'].includes(k)) ||
    typeof input.names !== 'string' || !input.names.trim() || input.names.length > 50 ||
    typeof input.message !== 'string' || !input.message.trim() || input.message.length > 160 ||
    typeof input.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input.date) ||
    !Number.isFinite(Date.parse(input.date)) || new Date(input.date).toISOString().slice(0, 10) !== input.date ||
    typeof input.theme !== 'string' || !Object.hasOwn(palettes, input.theme) ||
    /[\u0000-\u001f\u007f]/.test(input.names + input.message)) return fail('validation', 400);
  const rate = await createAuthRateStorage(env).consume(`premium-card|${actor}`, { window: 60, max: 12 });
  if (!rate.allowed) return fail('rate_limited', 429);
  const status = await getBillingStatus(env, actor);
  if (!status.entitlement.premium_cards) return fail('plus_required', 403);
  // Returning text as JSON keeps generated content inert on all clients. The
  // mobile renderer handles typography; no personal card content is stored.
  return Response.json({ ok: true, card: { names: input.names.trim(), message: input.message.trim(),
    date: input.date, theme: input.theme, colors: palettes[input.theme as keyof typeof palettes],
    width: 1080, height: 1920 } }, { headers });
}
