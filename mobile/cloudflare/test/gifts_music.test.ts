import { env } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { handleGiftRequest } from '../src/gifts';
import { handleMusicRequest } from '../src/music';
import { handleTogetherRequest } from '../src/together';
import { handleAccountRequest, type AccountActor } from '../src/account';
import { PairService, pairTokenHash } from '../src/pair';
type Json = Record<string, unknown>;
const id = () => crypto.randomUUID();
async function user(verified = true): Promise<AccountActor> {
  const actor = { id: id(), email: `${id()}@example.test`, sessionId: id(), sessionCreatedAt: new Date().toISOString() };
  const now = actor.sessionCreatedAt;
  await env.DB.prepare('INSERT INTO "user"(id,name,email,emailVerified,createdAt,updatedAt) VALUES(?,?,?,?,?,?)').bind(actor.id, 'Name', actor.email, Number(verified), now, now).run();
  await env.DB.prepare('INSERT INTO "session"(id,token,userId,createdAt,updatedAt,expiresAt) VALUES(?,?,?,?,?,?)')
    .bind(actor.sessionId, id(), actor.id, now, now, new Date(Date.now() + 3600000).toISOString()).run();
  await new PairService(env.DB).status(actor.id); return actor;
}
async function link(a: AccountActor, b: AccountActor) {
  const service = new PairService(env.DB); const token = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  const created = await service.execute(a.id, 'hamtdaa_create_pair_invite', { p_command_id: id(), p_token_hash: await pairTokenHash(token) });
  const invite = created.invitation as Json;
  const requested = await service.execute(b.id, 'hamtdaa_request_pair', { p_command_id: id(), p_token: token, p_expected_version: invite.version });
  const confirmed = await service.execute(a.id, 'hamtdaa_confirm_pair', { p_command_id: id(), p_invitation_id: invite.id, p_expected_version: (requested.invitation as Json).version });
  expect(confirmed.ok).toBe(true); return confirmed.pair_id as string;
}
async function fixture() { const a = await user(), b = await user(); return { a, b, pair: await link(a, b) }; }
async function unlink(actor: AccountActor, pair: string) {
  expect((await new PairService(env.DB).execute(actor.id, 'hamtdaa_unlink_pair', { p_command_id: id(), p_pair_id: pair, p_expected_version: 1 })).ok).toBe(true);
}
const request = (path: string) => new Request(`https://auth.test/v1/${path}`, { method: 'POST' });
async function gift(actor: AccountActor, operation: string, body: Json = {}, db = env.DB) {
  const response = await handleGiftRequest(request(`gifts/${operation}`), { DB: db }, actor.id, body); return { status: response.status, data: await response.json<Json>() };
}
const flower = (pair: string): Json => ({ command_id: id(), expected_pair_id: pair, template_id: 'garden', color_id: 'rose', occasion: 'Зүгээр л', message: 'Чамтай өдөр бүр илүү гоё.' });
const track = { video_id: 'F0B7HDiY-10', title: 'Love & coffee', channel_title: 'Example channel' };
const event = (pair: string): Json => ({ command_id: id(), expected_pair_id: pair, title: 'Кофе уух уу?', note: '', location: '', starts_at: '2026-10-20T10:00:00Z', ends_at: null });
async function together(actor: AccountActor, path: string, body: Json) {
  const response = await handleTogetherRequest(request(`together/${path}`), env, actor.id, body); return { status: response.status, data: await response.json<Json>() };
}
async function music(actor: AccountActor, body: Json = { query: 'love theory' }, config = { ...env, YOUTUBE_API_KEY: '' }) {
  const response = await handleMusicRequest(request('music/search'), config, actor.id, body); return { status: response.status, data: await response.json<Json>() };
}
function beforeBatch(work: () => Promise<void>): D1Database {
  let ran = false;
  return new Proxy(env.DB, { get(target, key) {
    if (key === 'batch') return async (statements: D1PreparedStatement[]) => { if (!ran) { ran = true; await work(); } return target.batch(statements); };
    const value = Reflect.get(target, key); return typeof value === 'function' ? value.bind(target) : value;
  } });
}
afterEach(() => vi.unstubAllGlobals());

describe('private digital flower gifts', () => {
  it('derives recipient, shares only within the current pair, retries exactly once', async () => {
    const { a, b, pair } = await fixture(); const outsider = await user(); const body = flower(pair);
    const sent = await gift(a, 'send', body); expect(sent.status).toBe(200); expect(sent.data.id).toBeTypeOf('string');
    expect((await gift(a, 'send', body)).data).toEqual(sent.data);
    const own = await gift(a, 'state'); const received = await gift(b, 'state'); expect(received.data.gifts).toEqual(own.data.gifts);
    expect(received.data.gifts).toHaveLength(1);
    expect((received.data.gifts as Json[])[0]).toMatchObject({ id: sent.data.id, pair_id: pair, sender_id: a.id, recipient_id: b.id, message: body.message });
    expect((await gift(outsider, 'state')).data.gifts).toEqual([]);
    expect((await gift(outsider, 'send', flower(pair))).data.code).toBe('pair_required');
    expect((await gift(a, 'send', { ...body, message: 'Different' })).data.code).toBe('idempotency_mismatch');
    expect((await gift(a, 'send', { ...flower(pair), recipient_id: outsider.id })).data.code).toBe('validation');
    const deletion = { command_id: id(), expected_pair_id: pair, id: sent.data.id };
    expect((await gift(b, 'delete', deletion)).data.code).toBe('forbidden');
    expect((await gift(a, 'delete', deletion)).status).toBe(200); expect((await gift(a, 'delete', deletion)).status).toBe(200);
    expect((await gift(b, 'state')).data.gifts).toEqual([]);
  });
  it('blocks unverified/disabled access and validates every field', async () => {
    const { a, pair } = await fixture();
    for (const change of [{ template_id: 'file:///secret' }, { color_id: 'pink' }, { occasion: 'arbitrary' }, { message: '' }, { message: 'a'.repeat(501) }, { message: '\u0000bad' }, { command_id: 'no' }, { expected_pair_id: 'no' }]) {
      expect((await gift(a, 'send', { ...flower(pair), ...change })).status).toBe(400);
    }
    expect((await gift(await user(false), 'state')).status).toBe(401);
    await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(a.id).run();
    expect((await gift(a, 'state')).status).toBe(401);
  });
  it('paginates equal-time gifts and rejects the old pair cursor after unlink/re-pair', async () => {
    const { a, b, pair } = await fixture(); const ids = Array.from({ length: 33 }, id).sort().reverse();
    await env.DB.batch(ids.map(key => env.DB.prepare("INSERT INTO hamtdaa_flower_gifts(id,pair_id,sender_id,recipient_id,template_id,color_id,occasion,message,created_at) VALUES(?,?,?,?,'letter','rose','Зүгээр л','Hi',100)").bind(key, pair, a.id, b.id)));
    const first = (await gift(b, 'state')).data; const second = (await gift(b, 'state', { cursor: first.next_cursor })).data;
    expect([...(first.gifts as Json[]), ...(second.gifts as Json[])].map(g => g.id)).toEqual(ids); expect(second.next_cursor).toBeNull();
    await unlink(a, pair); expect((await gift(b, 'state')).data.gifts).toEqual([]);
    const c = await user(); const newPair = await link(a, c);
    expect((await gift(a, 'state', { cursor: first.next_cursor })).data.code).toBe('pair_changed');
    expect((await gift(a, 'send', flower(pair))).data.code).toBe('pair_changed');
    expect((await gift(a, 'send', flower(newPair))).status).toBe(200);
  });
  it('fences unlink/block races inside the D1 transaction without receipts', async () => {
    const { a, b, pair } = await fixture(); const body = flower(pair);
    const raced = beforeBatch(async () => { await unlink(a, pair); });
    expect((await gift(a, 'send', body, raced)).data.code).toBe('pair_required');
    expect(await env.DB.prepare('SELECT 1 FROM hamtdaa_gift_receipts WHERE command_id=?').bind(body.command_id).first()).toBeNull();
    const nextPair = await link(a, b); const sent = flower(nextPair); expect((await gift(a, 'send', sent)).status).toBe(200);
    await env.DB.prepare('INSERT INTO hamtdaa_blocks(blocker_id,blocked_id) VALUES(?,?)').bind(a.id, b.id).run();
    expect((await gift(a, 'send', sent)).data.code).toBe('pair_required'); expect((await gift(b, 'state')).data.gifts).toEqual([]);
  });
  it('rejects pagination when a previously read card is deleted or a new gift arrives', async () => {
    const { a, b, pair } = await fixture(); const ids = Array.from({ length: 33 }, id).sort().reverse();
    await env.DB.batch(ids.map(key => env.DB.prepare("INSERT INTO hamtdaa_flower_gifts(id,pair_id,sender_id,recipient_id,template_id,color_id,occasion,message,created_at) VALUES(?,?,?,?,'letter','rose','Зүгээр л','Hi',100)").bind(key, pair, a.id, b.id)));
    const first = (await gift(b, 'state')).data;
    const removed = (first.gifts as Json[])[0].id;
    expect((await gift(a, 'delete', { command_id: id(), expected_pair_id: pair, id: removed })).status).toBe(200);
    expect((await gift(b, 'state', { cursor: first.next_cursor })).data.code).toBe('gifts_changed');
    const fresh = (await gift(b, 'state')).data;
    const rest = (await gift(b, 'state', { cursor: fresh.next_cursor })).data;
    expect([...(fresh.gifts as Json[]), ...(rest.gifts as Json[])].map(row => row.id)).toEqual(ids.filter(key => key !== removed));
    expect((await gift(a, 'send', flower(pair))).status).toBe(200);
    expect((await gift(b, 'state', { cursor: fresh.next_cursor })).data.code).toBe('gifts_changed');
  });
  it('caps sends without charging a retry or allowing create-delete quota bypass', async () => {
    const { a, pair } = await fixture(); const first = flower(pair); expect((await gift(a, 'send', first)).status).toBe(200);
    for (let i = 1; i < 20; i++) expect((await gift(a, 'send', flower(pair))).status).toBe(200);
    expect((await gift(a, 'send', first)).status).toBe(200); expect((await gift(a, 'send', flower(pair))).data.code).toBe('quota_exceeded');
    const rows = (await gift(a, 'state')).data.gifts as Json[];
    expect((await gift(a, 'delete', { command_id: id(), expected_pair_id: pair, id: rows[0].id })).status).toBe(200);
    expect((await gift(a, 'send', flower(pair))).status).toBe(429);
  });
  it('exports received gifts only while linked, and erases both directions on account deletion', async () => {
    const { a, b, pair } = await fixture(); await gift(a, 'send', flower(pair)); await gift(b, 'send', flower(pair));
    const exportCall = () => handleAccountRequest(request('account/export'), env, a, { section: 'flower_gifts' });
    const data = await (await exportCall()).json<{ export: { data: Json[] } }>(); expect(data.export.data).toHaveLength(2);
    await unlink(a, pair); expect((await (await exportCall()).json<{ export: { data: Json[] } }>()).export.data).toHaveLength(1);
    expect((await handleAccountRequest(request('account/delete'), env, a, { confirmation: 'УСТГАХ' })).status).toBe(200);
    expect(await env.DB.prepare('SELECT 1 FROM hamtdaa_flower_gifts WHERE sender_id=? OR recipient_id=?').bind(a.id, a.id).first()).toBeNull();
    expect((await gift(a, 'state')).status).toBe(401);
  });
});

describe('invitation music', () => {
  it('shares a chosen video reference, preserves omission by old clients, explicitly clears it', async () => {
    const { a, b, pair } = await fixture(); const body = { ...event(pair), music: track };
    expect((await together(a, 'calendar/create', body)).status).toBe(200);
    expect((await together(a, 'calendar/create', body)).status).toBe(200);
    let row = ((await together(b, 'state', { month: '2026-10' })).data.events as Json[])[0];
    expect(row.music).toEqual({ video_id: track.video_id, title: 'Сонгосон дуу', channel_title: '' });
    const storage = await env.DB.prepare('SELECT music_json FROM hamtdaa_calendar_events WHERE id=?').bind(row.id).first<{ music_json: string }>();
    expect(storage?.music_json).toBe(JSON.stringify({ video_id: track.video_id }));
    expect((await together(a, 'calendar/update', { ...event(pair), id: row.id, expected_version: row.version })).status).toBe(200);
    row = ((await together(b, 'state', { month: '2026-10' })).data.events as Json[])[0]; expect(row.music).not.toBeNull();
    expect((await together(a, 'calendar/update', { ...event(pair), id: row.id, expected_version: row.version, music: null })).status).toBe(200);
    row = ((await together(b, 'state', { month: '2026-10' })).data.events as Json[])[0]; expect(row.music).toBeNull();
    expect((await together(a, 'calendar/create', { ...body, music: null })).data.code).toBe('idempotency_mismatch');
  });
  it('rejects arbitrary URLs, unknown fields, oversized titles, malformed music', async () => {
    const { a, pair } = await fixture();
    for (const bad of ['', [], {}, { ...track, video_id: 'https://evil.test/' }, { ...track, video_id: track.video_id + '\n' }, { ...track, url: 'https://evil.test/' }, { ...track, title: 'x'.repeat(201) }, { ...track, channel_title: '\n' }]) {
      expect((await together(a, 'calendar/create', { ...event(pair), music: bad })).status).toBe(400);
    }
  });
  it('uses fixed existing provider, filters its results and never trusts its URLs', async () => {
    const a = await user(); const fetcher = vi.fn(async (_url: RequestInfo | URL, _init?: RequestInit) => Response.json({ items: [
      { videoId: track.video_id, title: 'Love &amp; coffee', channelTitle: 'Example channel', url: 'https://evil.test/' },
      { videoId: track.video_id, title: 'duplicate', channelTitle: '' },
      { videoId: '../malicious', title: 'bad', channelTitle: '' },
      { videoId: track.video_id + '\n', title: 'newline', channelTitle: '' },
    ] })); vi.stubGlobal('fetch', fetcher);
    expect((await music(a)).data).toEqual({ ok: true, tracks: [track] });
    const url = new URL(String(fetcher.mock.calls[0][0])); expect(url.origin).toBe('https://bolzoodate.vercel.app'); expect(url.pathname).toBe('/api/youtube-search');
    expect(url.searchParams.get('q')).toBe('love theory'); expect(fetcher.mock.calls[0][1]).toMatchObject({ redirect: 'manual' });
    expect((await music(a, { query: 'x', url: 'https://evil.test' })).status).toBe(400);
  });
  it('uses workerd-supported Request options and rejects redirects without following them', async () => {
    const a = await user();
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      // Unlike a plain fetch stub, the real workerd Request constructor rejects
      // unsupported redirect modes before the mocked transport can succeed.
      const outbound = new Request(String(input), init);
      expect(outbound.redirect).toBe('manual');
      return new URL(outbound.url).searchParams.get('q') === 'redirect song'
        ? new Response('', { status: 302, headers: { Location: 'https://unexpected-provider.test/private' } })
        : Response.json({ items: [{ videoId: track.video_id, title: track.title, channelTitle: track.channel_title }] });
    });
    vi.stubGlobal('fetch', fetcher);
    expect((await music(a, { query: 'runtime song' })).data.tracks).toEqual([track]);
    expect((await music(a, { query: 'redirect song' })).data.code).toBe('music_unavailable');
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
  it('supports official provider without exposing the secret, bounds bodies, rechecks deletion', async () => {
    const a = await user(); const config = { ...env, YOUTUBE_API_KEY: 'unit-test-key-not-real' };
    const fetcher = vi.fn(async (_url: RequestInfo | URL, _init?: RequestInit) => Response.json({ items: [{ id: { videoId: track.video_id }, snippet: { title: track.title, channelTitle: track.channel_title } }] })); vi.stubGlobal('fetch', fetcher);
    const result = await music(a, { query: 'coffee' }, config); expect(result.data.tracks).toEqual([track]); expect(JSON.stringify(result.data)).not.toContain(config.YOUTUBE_API_KEY);
    expect(new URL(String(fetcher.mock.calls[0][0])).origin).toBe('https://www.googleapis.com');
    vi.stubGlobal('fetch', vi.fn(async () => new Response('x'.repeat(128 * 1024 + 1)))); expect((await music(a)).data.code).toBe('music_unavailable');
    vi.stubGlobal('fetch', vi.fn(async () => { await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(a.id).run(); return Response.json({ items: [] }); }));
    expect((await music(a)).status).toBe(401);
  });
  it('rolls back every bucket when the day limit rejects, including a transaction-time race', async () => {
    const a = await user(); const fetcher = vi.fn(async () => Response.json({ items: [] })); vi.stubGlobal('fetch', fetcher);
    await music(a);
    const userDay = `user:${a.id}:day`;
    await env.DB.prepare('UPDATE hamtdaa_music_limits SET attempts=30 WHERE scope=?').bind(userDay).run();
    const before = (await env.DB.prepare('SELECT scope,window_start,attempts FROM hamtdaa_music_limits ORDER BY scope').all()).results;
    expect((await music(a)).status).toBe(429);
    expect((await env.DB.prepare('SELECT scope,window_start,attempts FROM hamtdaa_music_limits ORDER BY scope').all()).results).toEqual(before);
    await env.DB.prepare('UPDATE hamtdaa_music_limits SET attempts=29 WHERE scope=?').bind(userDay).run();
    const raced = beforeBatch(async () => { await env.DB.prepare('UPDATE hamtdaa_music_limits SET attempts=30 WHERE scope=?').bind(userDay).run(); });
    expect((await music(a, { query: 'love' }, { ...env, DB: raced, YOUTUBE_API_KEY: '' })).status).toBe(429);
    expect((await env.DB.prepare('SELECT scope,window_start,attempts FROM hamtdaa_music_limits ORDER BY scope').all()).results).toEqual(before);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it('admits only the remaining minute capacity for simultaneous searches', async () => {
    const a = await user(); const fetcher = vi.fn(async () => Response.json({ items: [] })); vi.stubGlobal('fetch', fetcher);
    expect((await music(a)).status).toBe(200);
    await env.DB.prepare('UPDATE hamtdaa_music_limits SET attempts=5 WHERE scope=?').bind(`user:${a.id}:minute`).run();
    const globalBefore = (await env.DB.prepare("SELECT attempts FROM hamtdaa_music_limits WHERE scope='global:day'").first<{ attempts: number }>())!.attempts;
    const results = await Promise.all([music(a), music(a)]);
    expect(results.map(result => result.status).sort()).toEqual([200, 429]);
    expect(await env.DB.prepare('SELECT attempts FROM hamtdaa_music_limits WHERE scope=?').bind(`user:${a.id}:day`).first()).toEqual({ attempts: 2 });
    expect(await env.DB.prepare("SELECT attempts FROM hamtdaa_music_limits WHERE scope='global:day'").first()).toEqual({ attempts: globalBefore + 1 });
  });
  it('enforces authenticated per-user search limits before provider requests', async () => {
    const a = await user(); const fetcher = vi.fn(async (_url: RequestInfo | URL, _init?: RequestInit) => Response.json({ items: [] })); vi.stubGlobal('fetch', fetcher);
    for (let i = 0; i < 6; i++) expect((await music(a)).status).toBe(200);
    const before = await env.DB.prepare('SELECT scope,window_start,attempts FROM hamtdaa_music_limits ORDER BY scope').all();
    for (let i = 0; i < 10; i++) expect((await music(a)).data.code).toBe('rate_limited');
    expect((await env.DB.prepare('SELECT scope,window_start,attempts FROM hamtdaa_music_limits ORDER BY scope').all()).results).toEqual(before.results);
    expect(fetcher).toHaveBeenCalledTimes(6);
    expect((await music(await user(false))).status).toBe(401); expect(fetcher).toHaveBeenCalledTimes(6);
  });
});
