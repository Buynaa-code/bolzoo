import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { PairService, pairTokenHash } from '../src/pair';

type Json = Record<string, unknown>;
type Invitation = { id: string; version: number; state: string; role: string };
const service = () => new PairService(env.DB);
const command = () => crypto.randomUUID();
const token = () => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
  .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
const invitation = (result: Json) => {
  expect(result.ok, JSON.stringify(result)).toBe(true);
  return result.invitation as Invitation;
};
async function user(name = 'Ану', verified = true) {
  const id = crypto.randomUUID();
  await env.DB.prepare(`INSERT INTO "user" (id,name,email,emailVerified,createdAt,updatedAt)
    VALUES(?,?,?,?,?,?)`).bind(id, name, `${id}@example.test`, verified ? 1 : 0, Date.now(), Date.now()).run();
  if (verified) {
    expect((await service().status(id)).ok).toBe(true);
    expect((await service().execute(id, 'hamtdaa_update_profile', {
      p_display_name: name, p_expected_version: 1,
    })).ok).toBe(true);
  }
  return id;
}
async function create(actor: string, secret = token(), id = command()) {
  const params = { p_command_id: id, p_token_hash: await pairTokenHash(secret) };
  const result = await service().execute(actor, 'hamtdaa_create_pair_invite', params);
  return { secret, params, invitation: invitation(result), result };
}
async function request(actor: string, created: Awaited<ReturnType<typeof create>>) {
  const params = { p_command_id: command(), p_token: created.secret, p_expected_version: created.invitation.version };
  const result = await service().execute(actor, 'hamtdaa_request_pair', params);
  return { params, invitation: invitation(result), result };
}
async function confirm(actor: string, pending: Invitation) {
  const params = { p_command_id: command(), p_invitation_id: pending.id, p_expected_version: pending.version };
  const result = await service().execute(actor, 'hamtdaa_confirm_pair', params);
  expect(result.ok, JSON.stringify(result)).toBe(true);
  return { params, result, id: result.pair_id as string, version: result.version as number };
}
async function linked(a: string, b: string) {
  const created = await create(a);
  const pending = await request(b, created);
  const pair = await confirm(a, pending.invitation);
  return { created, pending, pair };
}
async function expire(id: string) {
  await env.DB.prepare(`UPDATE hamtdaa_pair_invitations
    SET created_at=CAST(strftime('%s','now') AS INTEGER)-100,
        expires_at=CAST(strftime('%s','now') AS INTEGER)-1 WHERE id=?`).bind(id).run();
}
async function receiptCount(actor: string, id: string) {
  return (await env.DB.prepare(`SELECT count(*) AS count FROM hamtdaa_pair_receipts
    WHERE user_id=? AND command_id=?`).bind(actor, id).first<{ count: number }>())!.count;
}

describe('PairService using migrated D1', () => {
  it('admits only verified, active identities and never creates a profile for an unknown/unverified user', async () => {
    const missing = crypto.randomUUID();
    const unverified = await user('Үл баталсан', false);
    for (const id of [missing, unverified]) {
      expect(await service().status(id)).toMatchObject({ ok: false, code: 'unauthenticated' });
      expect(await service().preview(id, token())).toMatchObject({ ok: false, code: 'unauthenticated' });
      expect(await env.DB.prepare('SELECT * FROM hamtdaa_profiles WHERE user_id=?').bind(id).first()).toBeNull();
    }
    const disabled = await user();
    await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(disabled).run();
    expect(await service().status(disabled)).toMatchObject({ ok: false, code: 'unauthenticated' });
    expect(await service().execute(disabled, 'hamtdaa_create_pair_invite', {
      p_command_id: command(), p_token_hash: await pairTokenHash(token()),
    })).toMatchObject({ ok: false, code: 'unauthenticated' });
  });

  it('requires request plus creator confirmation; previews never create consent or expose raw secrets', async () => {
    const a = await user('Ану'); const b = await user('Тэмүүлэн'); const outsider = await user('Өөр хүн');
    const created = await create(a);
    const preview = await service().preview(b, created.secret);
    expect(preview).toMatchObject({ ok: true, invitation: {
      id: created.invitation.id, role: 'viewer', state: 'open', version: 1,
      creator: { user_id: a, display_name: 'Ану' }, requester: null,
    } });
    expect(await service().preview(a, created.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().status(outsider)).toMatchObject({ pair: null, invitations: [] });
    expect(await service().status(b)).toMatchObject({ pair: null, invitations: [] });
    expect(JSON.stringify(preview)).not.toContain(created.secret);
    expect(JSON.stringify(preview)).not.toContain(created.params.p_token_hash);
    const pending = await request(b, created);
    expect(pending.invitation).toMatchObject({ state: 'awaiting_creator', role: 'requester', version: 2 });
    expect(await service().status(a)).toMatchObject({ pair: null, invitations: [{ role: 'creator', requester: { user_id: b } }] });
    expect(await service().preview(outsider, created.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().execute(b, 'hamtdaa_confirm_pair', {
      p_command_id: command(), p_invitation_id: pending.invitation.id, p_expected_version: 2,
    })).toMatchObject({ ok: false, code: 'forbidden' });
    const pair = await confirm(a, pending.invitation);
    expect(await service().status(a)).toMatchObject({ pair: { id: pair.id, partner: { user_id: b, display_name: 'Тэмүүлэн' } }, invitations: [] });
    expect(await service().status(b)).toMatchObject({ pair: { id: pair.id, partner: { user_id: a, display_name: 'Ану' } }, invitations: [] });
    expect(await service().status(outsider)).toMatchObject({ pair: null, invitations: [] });
    const members = await env.DB.prepare('SELECT user_id,slot FROM hamtdaa_pair_members WHERE pair_id=? ORDER BY slot').bind(pair.id).all();
    expect(members.results).toEqual([{ user_id: a, slot: 1 }, { user_id: b, slot: 2 }]);
  });

  it('retries create/request/confirm exactly once and rejects changed payloads for the same command', async () => {
    const a = await user(); const b = await user('Болд');
    const created = await create(a);
    expect(await service().execute(a, 'hamtdaa_create_pair_invite', created.params)).toEqual(created.result);
    expect(await receiptCount(a, created.params.p_command_id)).toBe(1);
    expect(await service().execute(a, 'hamtdaa_create_pair_invite', {
      ...created.params, p_token_hash: await pairTokenHash(token()),
    })).toMatchObject({ ok: false, code: 'idempotency_mismatch' });
    const pending = await request(b, created);
    expect(await service().execute(b, 'hamtdaa_request_pair', pending.params)).toEqual(pending.result);
    const pair = await confirm(a, pending.invitation);
    expect(await service().execute(a, 'hamtdaa_confirm_pair', pair.params)).toEqual(pair.result);
    expect(await receiptCount(a, pair.params.p_command_id)).toBe(1);
    const receipts = await env.DB.prepare('SELECT * FROM hamtdaa_pair_receipts WHERE user_id IN (?,?)').bind(a, b).all();
    expect(JSON.stringify(receipts.results)).not.toContain(created.secret);
    expect(JSON.stringify(receipts.results)).not.toContain('Болд');
  });

  it('scopes receipts to an actor even when two users supply the same command UUID', async () => {
    const a = await user(); const b = await user(); const id = command();
    const first = await create(a, token(), id); const second = await create(b, token(), id);
    expect(first.invitation.id).not.toBe(second.invitation.id);
    expect(await receiptCount(a, id)).toBe(1);
    expect(await receiptCount(b, id)).toBe(1);
  });

  it('rejects stale versions without mutation, and requires a fresh command after a recorded rejection', async () => {
    const a = await user(); const b = await user(); const created = await create(a);
    const pending = await request(b, created);
    const params = { p_command_id: command(), p_invitation_id: created.invitation.id, p_expected_version: 1 };
    expect(await service().execute(a, 'hamtdaa_confirm_pair', params)).toMatchObject({ ok: false, code: 'conflict' });
    expect(await service().execute(a, 'hamtdaa_confirm_pair', { ...params, p_expected_version: 2 }))
      .toMatchObject({ ok: false, code: 'idempotency_mismatch' });
    expect(await service().status(a)).toMatchObject({ pair: null, invitations: [{ version: 2 }] });
    await confirm(a, pending.invitation);
  });

  it.each(['revoke', 'decline', 'cancel'] as const)('%s revokes consent and cannot be replayed into a connection', async (action) => {
    const a = await user(); const b = await user(); const outsider = await user();
    const created = await create(a); const pending = await request(b, created);
    const actor = action === 'cancel' ? b : a;
    const params = { p_command_id: command(), p_invitation_id: pending.invitation.id, p_expected_version: 2, p_action: action };
    expect(await service().execute(outsider, 'hamtdaa_close_pair_invite', params)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().execute(action === 'cancel' ? a : b, 'hamtdaa_close_pair_invite', { ...params, p_command_id: command() }))
      .toMatchObject({ ok: false, code: 'forbidden' });
    const closed = await service().execute(actor, 'hamtdaa_close_pair_invite', params);
    expect(closed).toMatchObject({ ok: true, version: 3, state: { revoke: 'revoked', decline: 'declined', cancel: 'cancelled' }[action] });
    expect(await service().execute(actor, 'hamtdaa_close_pair_invite', params)).toEqual(closed);
    expect(await service().execute(b, 'hamtdaa_request_pair', pending.params)).toMatchObject({ ok: false, code: 'invalid_state' });
    expect(await service().preview(b, created.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().status(a)).toMatchObject({ pair: null, invitations: [] });
    expect(await service().status(b)).toMatchObject({ pair: null, invitations: [] });
  });

  it('expires invitations, hides them, and permits a new request when the old request expires', async () => {
    const a = await user(); const b = await user(); const c = await user();
    const created = await create(a); const pending = await request(b, created);
    await expire(created.invitation.id);
    expect(await service().status(a)).toMatchObject({ pair: null, invitations: [] });
    expect(await service().preview(c, created.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().execute(a, 'hamtdaa_confirm_pair', {
      p_command_id: command(), p_invitation_id: pending.invitation.id, p_expected_version: 2,
    })).toMatchObject({ ok: false, code: 'expired' });
    const replacement = await create(c);
    expect((await request(b, replacement)).invitation.state).toBe('awaiting_creator');
    expect(await env.DB.prepare('SELECT state FROM hamtdaa_pair_invitations WHERE id=?').bind(created.invitation.id).first())
      .toEqual({ state: 'expired' });
  });

  it('issuing a replacement invite invalidates the old token and any pending consent', async () => {
    const a = await user(); const b = await user();
    const first = await create(a); const pending = await request(b, first);
    const second = await create(a);
    expect(await service().preview(b, first.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().execute(b, 'hamtdaa_request_pair', pending.params)).toMatchObject({ ok: false, code: 'invalid_state' });
    expect(await service().execute(a, 'hamtdaa_create_pair_invite', first.params)).toMatchObject({ ok: false, code: 'invalid_state' });
    expect(await service().status(b)).toMatchObject({ pair: null, invitations: [] });
    expect((await request(b, second)).invitation.id).toBe(second.invitation.id);
  });

  it('unlink immediately removes both members access; replay never resurrects the old pair', async () => {
    const a = await user(); const b = await user(); const c = await user();
    const { pair } = await linked(a, b);
    const params = { p_command_id: command(), p_pair_id: pair.id, p_expected_version: pair.version };
    expect(await service().execute(c, 'hamtdaa_unlink_pair', params)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().execute(b, 'hamtdaa_unlink_pair', { ...params, p_command_id: command(), p_expected_version: 2 }))
      .toMatchObject({ ok: false, code: 'conflict' });
    const result = await service().execute(b, 'hamtdaa_unlink_pair', params);
    expect(result).toMatchObject({ ok: true, pair_id: pair.id, version: 2 });
    expect(await service().execute(b, 'hamtdaa_unlink_pair', params)).toEqual(result);
    expect(await service().execute(a, 'hamtdaa_confirm_pair', pair.params)).toMatchObject({ ok: false, code: 'invalid_state' });
    expect(await service().status(a)).toMatchObject({ pair: null, invitations: [] });
    expect(await service().status(b)).toMatchObject({ pair: null, invitations: [] });
    const next = await linked(a, c);
    expect(next.pair.id).not.toBe(pair.id);
    expect(await service().execute(b, 'hamtdaa_unlink_pair', {
      p_command_id: command(), p_pair_id: next.pair.id, p_expected_version: 1,
    })).toMatchObject({ ok: false, code: 'not_found' });
    await expect(env.DB.prepare('UPDATE hamtdaa_pair_members SET revoked_at=NULL WHERE pair_id=?').bind(pair.id).run()).rejects.toThrow();
    await expect(env.DB.prepare("UPDATE hamtdaa_pairs SET state='active' WHERE id=?").bind(pair.id).run()).rejects.toThrow();
  });

  it.each(['disabled', 'deleting'] as const)('withdraws access when either member account is %s, including cached command replay', async (state) => {
    const a = await user(); const b = await user(); const { pair } = await linked(a, b);
    await env.DB.prepare('UPDATE hamtdaa_profiles SET account_state=? WHERE user_id=?').bind(state, b).run();
    expect(await service().status(a)).toMatchObject({ pair: null, invitations: [] });
    expect(await service().execute(a, 'hamtdaa_confirm_pair', pair.params)).toMatchObject({ ok: false, code: 'invalid_state' });
    expect(await service().status(b)).toMatchObject({ ok: false, code: 'unauthenticated' });
    // The eligible remaining member may still unlink, even when the partner is disabled.
    expect(await service().execute(a, 'hamtdaa_unlink_pair', {
      p_command_id: command(), p_pair_id: pair.id, p_expected_version: pair.version,
    })).toMatchObject({ ok: true });
  });

  it('blocks discovery and confirmation in both directions; blocks also invalidate an active pair projection', async () => {
    const a = await user(); const b = await user();
    const created = await create(a); const pending = await request(b, created);
    await env.DB.prepare('INSERT INTO hamtdaa_blocks(blocker_id,blocked_id) VALUES(?,?)').bind(b, a).run();
    expect(await service().status(a)).toMatchObject({ invitations: [], pair: null });
    expect(await service().preview(b, created.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(await service().execute(a, 'hamtdaa_confirm_pair', {
      p_command_id: command(), p_invitation_id: pending.invitation.id, p_expected_version: 2,
    })).toMatchObject({ ok: false });
    await env.DB.prepare('DELETE FROM hamtdaa_blocks WHERE blocker_id=? AND blocked_id=?').bind(b, a).run();
    const pair = await confirm(a, pending.invitation);
    await env.DB.prepare('INSERT INTO hamtdaa_blocks(blocker_id,blocked_id) VALUES(?,?)').bind(a, b).run();
    expect(await service().status(a)).toMatchObject({ pair: null });
    expect(await service().status(b)).toMatchObject({ pair: null });
    expect(await service().execute(a, 'hamtdaa_confirm_pair', pair.params)).toMatchObject({ ok: false, code: 'invalid_state' });
  });

  it('only one simultaneous requester can claim an invite and the loser cannot read that requester', async () => {
    const a = await user(); const b = await user(); const c = await user(); const created = await create(a);
    const results = await Promise.all([b, c].map(actor => service().execute(actor, 'hamtdaa_request_pair', {
      p_command_id: command(), p_token: created.secret, p_expected_version: 1,
    })));
    expect(results.filter(result => result.ok === true)).toHaveLength(1);
    const loser = results[0].ok ? c : b;
    expect(await service().status(loser)).toMatchObject({ pair: null, invitations: [] });
    expect(await service().preview(loser, created.secret)).toMatchObject({ ok: false, code: 'not_found' });
    expect(JSON.stringify(results.find(result => !result.ok))).not.toContain('requester');
  });

  it('atomic confirmation admits at most one pair when one member has two competing consent paths', async () => {
    const a = await user(); const b = await user(); const c = await user();
    // A receives B's request and also asks C to connect. Both creators race to confirm.
    const ab = await create(a); const requestedAB = await request(b, ab);
    const ca = await create(c); const requestedCA = await request(a, ca);
    const commands = [[a, requestedAB.invitation], [c, requestedCA.invitation]] as const;
    const results = await Promise.all(commands.map(([actor, pending]) => service().execute(actor, 'hamtdaa_confirm_pair', {
      p_command_id: command(), p_invitation_id: pending.id, p_expected_version: pending.version,
    })));
    expect(results.filter(result => result.ok === true)).toHaveLength(1);
    const rows = await env.DB.prepare('SELECT pair_id FROM hamtdaa_pair_members WHERE user_id=? AND revoked_at IS NULL').bind(a).all();
    expect(rows.results).toHaveLength(1);
    const pairId = rows.results[0].pair_id;
    const members = await env.DB.prepare('SELECT user_id FROM hamtdaa_pair_members WHERE pair_id=? AND revoked_at IS NULL').bind(pairId).all();
    expect(members.results).toHaveLength(2);
    const forming = await env.DB.prepare("SELECT id FROM hamtdaa_pairs WHERE state='forming' AND invitation_id IN (?,?)").bind(ab.invitation.id, ca.invitation.id).all();
    expect(forming.results).toHaveLength(0);
  });

  it('confirm racing revoke cannot leave a partial pair or a successful revoke with live membership', async () => {
    const a = await user(); const b = await user(); const created = await create(a); const pending = await request(b, created);
    const base = { p_invitation_id: pending.invitation.id, p_expected_version: 2 };
    const results = await Promise.all([
      service().execute(a, 'hamtdaa_confirm_pair', { ...base, p_command_id: command() }),
      service().execute(a, 'hamtdaa_close_pair_invite', { ...base, p_command_id: command(), p_action: 'revoke' }),
    ]);
    expect(results.filter(result => result.ok === true)).toHaveLength(1);
    const status = await service().status(a);
    if (results[1].ok) expect(status.pair).toBeNull();
    else expect(status.pair).toMatchObject({ partner: { user_id: b } });
    const forming = await env.DB.prepare("SELECT id FROM hamtdaa_pairs WHERE state='forming' AND invitation_id=?").bind(pending.invitation.id).all();
    expect(forming.results).toHaveLength(0);
  });

  it('simultaneous exact retries share one receipt and one invitation', async () => {
    const a = await user(); const params = { p_command_id: command(), p_token_hash: await pairTokenHash(token()) };
    const results = await Promise.all([1, 2].map(() => service().execute(a, 'hamtdaa_create_pair_invite', params)));
    expect(results[0].ok).toBe(true);
    expect(results[0]).toEqual(results[1]);
    expect(await receiptCount(a, params.p_command_id)).toBe(1);
    expect((await env.DB.prepare('SELECT id FROM hamtdaa_pair_invitations WHERE creator_id=?').bind(a).all()).results).toHaveLength(1);
  });

  it('duplicate token collision rolls back replacement revocation and its receipt together', async () => {
    const a = await user(); const b = await user(); const first = await create(a); const occupied = await create(b);
    const params = { p_command_id: command(), p_token_hash: occupied.params.p_token_hash };
    expect(await service().execute(a, 'hamtdaa_create_pair_invite', params)).toMatchObject({ ok: false, code: 'conflict', retryable: true });
    expect(await receiptCount(a, params.p_command_id)).toBe(0);
    expect(await service().status(a)).toMatchObject({ invitations: [{ id: first.invitation.id, state: 'open', version: 1 }] });
    expect((await env.DB.prepare('SELECT id FROM hamtdaa_pair_transition_guards').all()).results).toHaveLength(0);
  });

  it('validates names and optimistic profile updates without modifying another profile', async () => {
    const a = await user('Эхний'); const b = await user('Хоёр дахь');
    for (const name of ['', ' ', 'a'.repeat(41), 'name\nsecret']) {
      expect(await service().execute(a, 'hamtdaa_update_profile', { p_display_name: name, p_expected_version: 2 }))
        .toMatchObject({ ok: false, code: 'validation' });
    }
    const changed = await service().execute(a, 'hamtdaa_update_profile', { p_display_name: '  Өөрчилсөн  ', p_expected_version: 2, p_user_id: b });
    expect(changed).toMatchObject({ ok: true, profile: { user_id: a, display_name: 'Өөрчилсөн', version: 3 } });
    expect(await service().execute(a, 'hamtdaa_update_profile', { p_display_name: 'Хуучин', p_expected_version: 2 }))
      .toMatchObject({ ok: false, code: 'conflict' });
    expect(await service().status(b)).toMatchObject({ profile: { display_name: 'Хоёр дахь', version: 2 } });
  });

  it('rejects malformed tokens/versions and limits token probes per authenticated user', async () => {
    const a = await user(); const b = await user(); const created = await create(a);
    for (const secret of ['', 'x'.repeat(44), 'x'.repeat(42) + 'B']) {
      expect(await service().preview(b, secret)).toMatchObject({ ok: false, code: 'not_found' });
    }
    for (const version of [0, -1, 1.2, '1', Number.MAX_SAFE_INTEGER + 1]) {
      expect(await service().execute(b, 'hamtdaa_request_pair', { p_command_id: command(), p_token: created.secret, p_expected_version: version }))
        .toMatchObject({ ok: false, code: 'validation' });
    }
    // Pin the current minute instead of waiting across a real clock boundary.
    await env.DB.prepare(`INSERT OR REPLACE INTO hamtdaa_pair_rate_limits(user_id,action,window_start,attempts)
      VALUES(?,'preview',?,20)`).bind(b, Math.floor(Date.now() / 60000)).run();
    expect(await service().preview(b, created.secret)).toMatchObject({ ok: false, code: 'rate_limited', retryable: true });
    expect((await service().preview(await user(), created.secret)).ok).toBe(true);
  });
});
