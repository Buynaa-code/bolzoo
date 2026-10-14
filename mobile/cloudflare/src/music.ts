import { giftActorEligible } from './gifts';

type Json = Record<string, unknown>;
export type MusicTrack = { video_id: string; title: string; channel_title: string };
export type MusicEnvironment = { DB: D1Database; YOUTUBE_API_KEY?: string };
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const LIMIT = 8;
function object(value: unknown): value is Json { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function label(value: unknown, required = true): value is string {
  return typeof value === 'string' && value.length <= 200 && (!required || !!value.trim()) && !/[\u0000-\u001F\u007F]/.test(value);
}
/** Accepted metadata is validated but only the user's chosen video reference is
 * persisted. Provider titles/channels are not retained beyond the picker. */
export function parseMusic(value: unknown): MusicTrack | null {
  if (value === null) return null;
  if (!object(value) || Object.keys(value).length !== 3 || !Object.hasOwn(value, 'video_id') || !Object.hasOwn(value, 'title') || !Object.hasOwn(value, 'channel_title') ||
    typeof value.video_id !== 'string' || value.video_id.length !== 11 || !VIDEO_ID.test(value.video_id) || !label(value.title) || !label(value.channel_title, false)) throw new Error('invalid_music');
  return { video_id: value.video_id, title: value.title.trim(), channel_title: value.channel_title.trim() };
}
export function storedMusic(value: MusicTrack | null): string | null {
  return value ? JSON.stringify({ video_id: value.video_id }) : null;
}
export function displayMusic(value: string | null): MusicTrack | null {
  if (value === null) return null;
  try {
    const data: unknown = JSON.parse(value);
    if (object(data) && typeof data.video_id === 'string' && data.video_id.length === 11 && VIDEO_ID.test(data.video_id)) {
      return { video_id: data.video_id, title: 'Сонгосон дуу', channel_title: '' };
    }
  } catch { /* Corrupt metadata must not become an external URL. */ }
  return null;
}
function json(value: Json, status = 200) {
  return Response.json(value, { status, headers: { 'Cache-Control': 'no-store, private', Pragma: 'no-cache', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff', ...(status === 429 ? { 'Retry-After': '60' } : {}) } });
}
async function boundedJson(response: Response): Promise<unknown> {
  if (Number(response.headers.get('content-length')) > 128 * 1024) { await response.body?.cancel(); throw new Error('provider_size'); }
  const reader = response.body?.getReader(); if (!reader) throw new Error('provider_body');
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const next = await reader.read(); if (next.done) break;
      size += next.value.length; if (size > 128 * 1024) { await reader.cancel(); throw new Error('provider_size'); }
      chunks.push(next.value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes));
}
function decodeTitle(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 1500) return null;
  const clean = value.replace(/&(?:amp|lt|gt|quot|apos|#39|#34);/g, match => ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&#39;': "'", '&#34;': '"' }[match] ?? match)).trim();
  return label(clean, false) ? clean : null;
}
function providerTracks(payload: unknown, direct: boolean): MusicTrack[] {
  if (!object(payload) || !Array.isArray(payload.items) || payload.items.length > 50) throw new Error('provider_shape');
  const tracks: MusicTrack[] = []; const seen = new Set<string>();
  for (const item of payload.items) {
    if (!object(item)) continue;
    const video = direct ? (object(item.id) ? item.id.videoId : null) : item.videoId;
    const snippet = direct && object(item.snippet) ? item.snippet : item;
    const title = decodeTitle(snippet.title), channel = decodeTitle(snippet.channelTitle);
    if (typeof video !== 'string' || video.length !== 11 || !VIDEO_ID.test(video) || !title || channel === null || seen.has(video)) continue;
    seen.add(video); tracks.push({ video_id: video, title, channel_title: channel });
    if (tracks.length === LIMIT) break;
  }
  return tracks;
}
async function consume(db: D1Database, actor: string): Promise<boolean> {
  const now = Date.now();
  const limits = [
    { key: `user:${actor}:minute`, window: Math.floor(now / 60000), max: 6 },
    { key: `user:${actor}:day`, window: Math.floor(now / 86400000), max: 30 },
    { key: 'global:day', window: Math.floor(now / 86400000), max: 80 },
  ];
  const key = crypto.randomUUID();
  // A denied narrow bucket must not consume a broader user's/app quota. D1
  // serializes the entire batch; this guard and all increments commit together.
  const allowed = limits.map(() => `NOT EXISTS(SELECT 1 FROM hamtdaa_music_limits WHERE scope=? AND window_start=? AND attempts>=?)`).join(' AND ');
  try {
    await db.batch([
      db.prepare(`INSERT INTO hamtdaa_gift_guards(id,allowed) SELECT ?,CASE WHEN ${giftActorEligible} AND ${allowed} THEN 1 ELSE 0 END`)
        .bind(key, actor, ...limits.flatMap(limit => [limit.key, limit.window, limit.max])),
      db.prepare('DELETE FROM hamtdaa_gift_guards WHERE id=?').bind(key),
      ...limits.map(limit => db.prepare(`INSERT INTO hamtdaa_music_limits(scope,window_start,attempts) VALUES(?,?,1)
        ON CONFLICT(scope) DO UPDATE SET window_start=excluded.window_start,
          attempts=CASE WHEN hamtdaa_music_limits.window_start=excluded.window_start THEN hamtdaa_music_limits.attempts+1 ELSE 1 END`)
        .bind(limit.key, limit.window)),
    ]);
    return true;
  } catch (error) {
    if (error instanceof Error && /constraint|gift_guards/i.test(error.message)) return false;
    throw error;
  }
}
export async function handleMusicRequest(request: Request, env: MusicEnvironment, actor: string, body: Json | null): Promise<Response> {
  if (request.method !== 'POST' || new URL(request.url).pathname !== '/v1/music/search') return json({ ok: false, code: 'not_found' }, 404);
  if (!body || Object.keys(body).length !== 1 || typeof body.query !== 'string' || body.query.length > 120 || body.query.trim().length < 2 || /[\u0000-\u001F\u007F]/.test(body.query)) return json({ ok: false, code: 'validation' }, 400);
  try {
    await env.DB.prepare('INSERT OR IGNORE INTO hamtdaa_profiles(user_id) SELECT id FROM "user" WHERE id=? AND emailVerified=1').bind(actor).run();
    const eligible = () => env.DB.prepare(`SELECT 1 WHERE ${giftActorEligible}`).bind(actor).first();
    if (!await eligible()) return json({ ok: false, code: 'unauthenticated' }, 401);
    if (!await consume(env.DB, actor)) return !await eligible()
      ? json({ ok: false, code: 'unauthenticated' }, 401)
      : json({ ok: false, code: 'rate_limited' }, 429);
    const direct = !!env.YOUTUBE_API_KEY;
    // Fixed origins only: the established Bolzoo service is the user's existing
    // YouTube Data API adapter. Neither client URLs nor redirects are accepted.
    const url = new URL(direct ? 'https://www.googleapis.com/youtube/v3/search' : 'https://bolzoodate.vercel.app/api/youtube-search');
    url.searchParams.set('q', body.query.trim()); url.searchParams.set('maxResults', String(LIMIT));
    if (direct) {
      url.searchParams.set('key', env.YOUTUBE_API_KEY!); url.searchParams.set('part', 'snippet');
      url.searchParams.set('type', 'video'); url.searchParams.set('safeSearch', 'moderate');
    }
    const abort = new AbortController(); const timer = setTimeout(() => abort.abort(), 7000);
    let tracks: MusicTrack[];
    try {
      const response = await fetch(url, { headers: { Accept: 'application/json' }, redirect: 'manual', signal: abort.signal });
      if (!response.ok) { await response.body?.cancel(); return json({ ok: false, code: 'music_unavailable' }, 503); }
      tracks = providerTracks(await boundedJson(response), direct);
    } finally { clearTimeout(timer); }
    if (!await eligible()) return json({ ok: false, code: 'unauthenticated' }, 401);
    return json({ ok: true, tracks });
  } catch {
    // Provider errors may contain credentials/query text. Never log or forward.
    return json({ ok: false, code: 'music_unavailable' }, 503);
  }
}
