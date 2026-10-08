/** Pair operations accept ONLY an identity obtained by the authenticated router. */
type Json = Record<string, unknown>;
type Operation = 'create' | 'request' | 'confirm' | 'close' | 'unlink';
type InvitationRow = {
  id: string; creator_id: string; requester_id: string | null; token_hash: string;
  state: string; version: number; expires_at: number; requested_at: number | null;
  creator_name?: string; requester_name?: string;
};
type Receipt = { payload_hash: string; outcome: string };
const operations: Record<string, Operation> = {
  hamtdaa_create_pair_invite: 'create', hamtdaa_request_pair: 'request',
  hamtdaa_confirm_pair: 'confirm', hamtdaa_close_pair_invite: 'close', hamtdaa_unlink_pair: 'unlink',
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const tokenPattern = /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/;
const failure = (code: string, retryable = false): Json => ({ ok: false, code, retryable });
const now = () => Math.floor(Date.now() / 1000);
const iso = (seconds: number) => new Date(seconds * 1000).toISOString();
const validVersion = (value: unknown): value is number => Number.isSafeInteger(value) && Number(value) > 0;
const eligible = (expression: string) => `EXISTS (SELECT 1 FROM hamtdaa_profiles ep JOIN "user" eu ON eu.id=ep.user_id WHERE ep.user_id=${expression} AND ep.account_state='active' AND eu.emailVerified=1)`;
const unpaired = (expression: string) => `NOT EXISTS (SELECT 1 FROM hamtdaa_pair_members em WHERE em.user_id=${expression} AND em.revoked_at IS NULL)`;
const unblocked = (a: string, b: string) => `NOT EXISTS (SELECT 1 FROM hamtdaa_blocks eb WHERE (eb.blocker_id=${a} AND eb.blocked_id=${b}) OR (eb.blocker_id=${b} AND eb.blocked_id=${a}))`;
const liveInvitation = `i.state IN ('open','awaiting_creator') AND i.expires_at>CAST(strftime('%s','now') AS INTEGER)
  AND ${eligible('i.creator_id')} AND (i.requester_id IS NULL OR ${eligible('i.requester_id')})
  AND ${unpaired('i.creator_id')} AND (i.requester_id IS NULL OR ${unpaired('i.requester_id')})
  AND ${unblocked('i.creator_id', 'i.requester_id')}`;
const invitationProjection = `SELECT i.*,c.display_name creator_name,r.display_name requester_name
  FROM hamtdaa_pair_invitations i JOIN hamtdaa_profiles c ON c.user_id=i.creator_id
  LEFT JOIN hamtdaa_profiles r ON r.user_id=i.requester_id`;
const pairProjection = `SELECT p.id,p.version,p.state,pm.user_id partner_id,pr.display_name partner_name
  FROM hamtdaa_pairs p JOIN hamtdaa_pair_members own ON own.pair_id=p.id
  JOIN hamtdaa_pair_members pm ON pm.pair_id=p.id AND pm.user_id<>own.user_id
  JOIN hamtdaa_profiles pr ON pr.user_id=pm.user_id
  WHERE own.user_id=? AND own.revoked_at IS NULL AND pm.revoked_at IS NULL AND p.state='active'
  AND ${eligible('own.user_id')} AND ${eligible('pm.user_id')} AND ${unblocked('own.user_id', 'pm.user_id')}`;

export async function pairTokenHash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export class PairService {
  constructor(private readonly db: D1Database) {}

  private statement(sql: string, ...values: (string | number | null)[]) {
    return this.db.prepare(sql).bind(...values);
  }

  private guard(predicate: string, ...values: (string | number | null)[]): D1PreparedStatement[] {
    const id = crypto.randomUUID();
    return [
      this.statement(`INSERT INTO hamtdaa_pair_transition_guards(id,allowed) SELECT ?,CASE WHEN ${predicate} THEN 1 ELSE 0 END`, id, ...values),
      this.statement('DELETE FROM hamtdaa_pair_transition_guards WHERE id=?', id),
    ];
  }

  private alive(users: string[]): D1PreparedStatement[] {
    const distinct = [...new Set(users)];
    return this.guard(`(SELECT count(*) FROM hamtdaa_profiles p JOIN "user" u ON u.id=p.user_id
      WHERE p.account_state='active' AND u.emailVerified=1 AND p.user_id IN (${distinct.map(() => '?').join(',')}))=?`, ...distinct, distinct.length);
  }

  private free(users: string[]) {
    return this.guard(`NOT EXISTS(SELECT 1 FROM hamtdaa_pair_members WHERE revoked_at IS NULL AND user_id IN (${users.map(() => '?').join(',')}))`, ...users);
  }

  private notBlocked(a: string, b: string) {
    return this.guard('NOT EXISTS(SELECT 1 FROM hamtdaa_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?))', a, b, b, a);
  }

  private invitationGuard(row: InvitationRow) {
    return this.guard(`EXISTS(SELECT 1 FROM hamtdaa_pair_invitations WHERE id=? AND version=? AND state=?
      AND creator_id=? AND requester_id IS ? AND expires_at>CAST(strftime('%s','now') AS INTEGER))`,
      row.id, row.version, row.state, row.creator_id, row.requester_id);
  }

  /** An unverified, deleted, or disabled identity never gains a profile/access. */
  private async bootstrap(actor: string): Promise<boolean> {
    if (!actor) return false;
    await this.statement(`INSERT OR IGNORE INTO hamtdaa_profiles(user_id)
      SELECT id FROM "user" WHERE id=? AND emailVerified=1`, actor).run();
    const result = await this.statement(`SELECT 1 ok WHERE ${eligible('?')}`, actor).first();
    return result !== null;
  }

  private async rate(actor: string, action: 'preview' | 'create' | 'request' | 'mutation') {
    const window = Math.floor(now() / 60);
    const result = await this.statement(`INSERT INTO hamtdaa_pair_rate_limits(user_id,action,window_start,attempts)
      VALUES(?,?,?,1) ON CONFLICT(user_id,action) DO UPDATE SET window_start=excluded.window_start,
      attempts=CASE WHEN hamtdaa_pair_rate_limits.window_start=excluded.window_start
        THEN min(hamtdaa_pair_rate_limits.attempts+1,1000000) ELSE 1 END RETURNING attempts`, actor, action, window)
      .first<{ attempts: number }>();
    return (result?.attempts ?? Infinity) <= { preview: 20, create: 5, request: 10, mutation: 30 }[action];
  }

  private invitation(row: InvitationRow, actor: string, preview = false): Json {
    return { id: row.id, version: row.version, state: row.state,
      role: preview ? 'viewer' : row.creator_id === actor ? 'creator' : 'requester',
      creator: { user_id: row.creator_id, display_name: row.creator_name },
      requester: preview || !row.requester_id ? null : { user_id: row.requester_id, display_name: row.requester_name },
      expires_at: iso(row.expires_at) };
  }

  async status(actor: string): Promise<Json> {
    if (!await this.bootstrap(actor)) return failure('unauthenticated');
    try {
      const result = await this.db.batch([
        ...this.alive([actor]),
        this.statement('SELECT user_id,display_name,version FROM hamtdaa_profiles WHERE user_id=?', actor),
        this.statement(pairProjection, actor),
        this.statement(`${invitationProjection} WHERE (i.creator_id=? OR i.requester_id=?) AND ${liveInvitation} ORDER BY i.created_at,i.id`, actor, actor),
      ]);
      const profile = result[2].results[0];
      const pair = result[3].results[0] as Json | undefined;
      return { ok: true, server_time: iso(now()), profile,
        pair: pair ? { id: pair.id, version: pair.version, partner: { user_id: pair.partner_id, display_name: pair.partner_name } } : null,
        invitations: (result[4].results as InvitationRow[]).map((row) => this.invitation(row, actor)) };
    } catch { return failure('conflict', true); }
  }

  async preview(actor: string, token: string): Promise<Json> {
    if (!await this.bootstrap(actor)) return failure('unauthenticated');
    if (!await this.rate(actor, 'preview')) return failure('rate_limited', true);
    if (typeof token !== 'string' || !tokenPattern.test(token)) return failure('not_found');
    const hash = await pairTokenHash(token);
    const row = await this.statement(`${invitationProjection} WHERE i.token_hash=? AND i.state='open' AND i.creator_id<>?
      AND ${liveInvitation} AND ${eligible('?')} AND ${unpaired('?')}
      AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b WHERE (b.blocker_id=? AND b.blocked_id=i.creator_id) OR (b.blocker_id=i.creator_id AND b.blocked_id=?))`,
      hash, actor, actor, actor, actor, actor).first<InvitationRow>();
    return row ? { ok: true, invitation: this.invitation(row, actor, true) } : failure('not_found');
  }

  private async receipt(actor: string, command: string) {
    return this.statement('SELECT payload_hash,outcome FROM hamtdaa_pair_receipts WHERE user_id=? AND command_id=?', actor, command).first<Receipt>();
  }

  private async replay(actor: string, record: Receipt, hash: string): Promise<Json> {
    if (record.payload_hash !== hash) return failure('idempotency_mismatch');
    if (!await this.bootstrap(actor)) return failure('unauthenticated');
    const outcome = JSON.parse(record.outcome) as Json;
    if (outcome.ok === false) return outcome;
    const id = outcome.id as string;
    if (outcome.kind === 'invitation' || outcome.kind === 'close') {
      const row = await this.statement(`${invitationProjection} WHERE i.id=? AND (i.creator_id=? OR i.requester_id=?)
        AND ${eligible('?')} ${outcome.kind === 'invitation' ? `AND ${liveInvitation}` : ''}`, id, actor, actor, actor).first<InvitationRow>();
      if (!row) return failure('invalid_state');
      if (outcome.kind === 'close') return { ok: true, invitation_id: row.id, version: row.version, state: row.state };
      return { ok: true, invitation: this.invitation(row, actor) };
    }
    if (outcome.kind === 'pair') {
      const pair = await this.statement(`${pairProjection} AND p.id=?`, actor, id).first<{ id: string; version: number }>();
      return pair ? { ok: true, pair_id: pair.id, version: pair.version } : failure('invalid_state');
    }
    const pair = await this.statement(`SELECT p.id,p.version FROM hamtdaa_pairs p JOIN hamtdaa_pair_members m ON m.pair_id=p.id
      WHERE p.id=? AND m.user_id=? AND p.state='unlinked' AND ${eligible('?')}`, id, actor, actor).first<{ id: string; version: number }>();
    return pair ? { ok: true, pair_id: pair.id, version: pair.version } : failure('invalid_state');
  }

  private async commit(actor: string, command: string, hash: string, outcome: Json, mutations: D1PreparedStatement[] = []): Promise<Json> {
    const receipt: Receipt = { payload_hash: hash, outcome: JSON.stringify(outcome) };
    try {
      await this.db.batch([
        ...this.alive([actor]),
        this.statement('INSERT INTO hamtdaa_pair_receipts(user_id,command_id,payload_hash,outcome,created_at) VALUES(?,?,?,?,?)', actor, command, hash, receipt.outcome, now()),
        ...mutations,
      ]);
      return this.replay(actor, receipt, hash);
    } catch {
      // A duplicate receipt is the only success recoverable from a failed batch.
      // Domain changes and that receipt are otherwise rolled back together.
      const previous = await this.receipt(actor, command);
      return previous ? this.replay(actor, previous, hash) : failure('conflict', true);
    }
  }

  async execute(actor: string, rpc: string, params: Json): Promise<Json> {
    if (!await this.bootstrap(actor)) return failure('unauthenticated');
    if (rpc === 'hamtdaa_update_profile') return this.updateName(actor, params);
    const operation = operations[rpc];
    const command = params.p_command_id;
    if (!operation || typeof command !== 'string' || !uuid.test(command)) return failure('validation');
    const presented = typeof params.p_token === 'string' && params.p_token.length <= 256 ? await pairTokenHash(params.p_token) : null;
    const hash = await pairTokenHash(JSON.stringify({ operation,
      token_hash: params.p_token_hash ?? null, presented_token_hash: presented,
      expected_version: params.p_expected_version ?? null, invitation_id: params.p_invitation_id ?? null,
      action: params.p_action ?? null, pair_id: params.p_pair_id ?? null }));
    const previous = await this.receipt(actor, command);
    if (previous) return this.replay(actor, previous, hash);
    if (!await this.rate(actor, operation === 'create' || operation === 'request' ? operation : 'mutation')) return failure('rate_limited', true);
    const reject = (code: string) => this.commit(actor, command, hash, failure(code));

    if (operation === 'create') {
      if (typeof params.p_token_hash !== 'string' || !/^[0-9a-f]{64}$/.test(params.p_token_hash)) return reject('validation');
      if (!await this.isFree(actor)) return reject('already_paired');
      const id = crypto.randomUUID();
      return this.commit(actor, command, hash, { ok: true, kind: 'invitation', id }, [
        ...this.free([actor]),
        this.statement(`UPDATE hamtdaa_pair_invitations SET state=CASE WHEN expires_at<=? THEN 'expired' ELSE 'revoked' END,version=version+1
          WHERE creator_id=? AND state IN ('open','awaiting_creator')`, now(), actor),
        this.statement('INSERT INTO hamtdaa_pair_invitations(id,creator_id,token_hash,created_at,expires_at) VALUES(?,?,?,?,?)', id, actor, params.p_token_hash, now(), now() + 86400),
      ]);
    }

    if (!validVersion(params.p_expected_version)) return reject('validation');
    if (operation === 'unlink') {
      if (typeof params.p_pair_id !== 'string' || !uuid.test(params.p_pair_id)) return reject('validation');
      const pair = await this.statement('SELECT p.* FROM hamtdaa_pairs p JOIN hamtdaa_pair_members m ON m.pair_id=p.id WHERE p.id=? AND m.user_id=?', params.p_pair_id, actor).first<Json>();
      if (!pair) return reject('not_found');
      if (pair.state !== 'active') return reject('invalid_state');
      if (pair.version !== params.p_expected_version) return reject('conflict');
      return this.commit(actor, command, hash, { ok: true, kind: 'unlink', id: pair.id }, [
        ...this.guard(`EXISTS(SELECT 1 FROM hamtdaa_pairs p JOIN hamtdaa_pair_members m ON m.pair_id=p.id
          WHERE p.id=? AND p.state='active' AND p.version=? AND m.user_id=? AND m.revoked_at IS NULL)`, params.p_pair_id, params.p_expected_version, actor),
        this.statement("UPDATE hamtdaa_pairs SET state='unlinked',version=version+1,unlinked_at=? WHERE id=?", now(), params.p_pair_id),
        this.statement('UPDATE hamtdaa_pair_members SET revoked_at=? WHERE pair_id=? AND revoked_at IS NULL', now(), params.p_pair_id),
      ]);
    }

    let row: InvitationRow | null;
    if (operation === 'request') {
      if (typeof params.p_token !== 'string' || !tokenPattern.test(params.p_token)) return reject('not_found');
      row = await this.statement('SELECT * FROM hamtdaa_pair_invitations WHERE token_hash=?', presented).first<InvitationRow>();
      if (!row || row.state !== 'open' || row.creator_id === actor || !await this.available([actor, row.creator_id])) return reject('not_found');
    } else {
      if (typeof params.p_invitation_id !== 'string' || !uuid.test(params.p_invitation_id)) return reject('validation');
      row = await this.statement('SELECT * FROM hamtdaa_pair_invitations WHERE id=? AND (creator_id=? OR requester_id=?)', params.p_invitation_id, actor, actor).first<InvitationRow>();
      if (!row) return reject('not_found');
    }
    if (row.expires_at <= now()) return reject(operation === 'request' ? 'not_found' : 'expired');
    if (row.version !== params.p_expected_version) return reject('conflict');
    if (operation === 'request') {
      const pending = await this.statement("SELECT 1 FROM hamtdaa_pair_invitations WHERE requester_id=? AND state='awaiting_creator' AND expires_at>?", actor, now()).first();
      if (pending) return reject('invalid_state');
      return this.commit(actor, command, hash, { ok: true, kind: 'invitation', id: row.id }, [
        ...this.invitationGuard(row), ...this.alive([actor, row.creator_id]), ...this.free([actor, row.creator_id]), ...this.notBlocked(actor, row.creator_id),
        this.statement("UPDATE hamtdaa_pair_invitations SET state='expired',version=version+1 WHERE requester_id=? AND state='awaiting_creator' AND expires_at<=?", actor, now()),
        this.statement("UPDATE hamtdaa_pair_invitations SET requester_id=?,state='awaiting_creator',requested_at=?,version=version+1 WHERE id=?", actor, now(), row.id),
      ]);
    }
    if (operation === 'confirm') {
      if (row.creator_id !== actor) return reject('forbidden');
      if (row.state !== 'awaiting_creator' || !row.requester_id || !row.requested_at) return reject('invalid_state');
      const other = row.requester_id;
      if (!await this.available([actor, other])) return reject('already_paired');
      const id = crypto.randomUUID();
      return this.commit(actor, command, hash, { ok: true, kind: 'pair', id }, [
        ...this.invitationGuard(row), ...this.alive([actor, other]), ...this.free([actor, other]), ...this.notBlocked(actor, other),
        this.statement('INSERT INTO hamtdaa_pairs(id,invitation_id,created_at) VALUES(?,?,?)', id, row.id, now()),
        this.statement('INSERT INTO hamtdaa_pair_members(pair_id,user_id,slot) VALUES(?,?,1),(?,?,2)', id, actor, id, other),
        this.statement("UPDATE hamtdaa_pairs SET state='active' WHERE id=?", id),
        this.statement("UPDATE hamtdaa_pair_invitations SET state='linked',version=version+1,confirmed_at=?,pair_id=? WHERE id=?", now(), id, row.id),
        this.statement("UPDATE hamtdaa_pair_invitations SET state='revoked',version=version+1 WHERE state IN ('open','awaiting_creator') AND (creator_id IN (?,?) OR requester_id IN (?,?))", actor, other, actor, other),
      ]);
    }
    const action = params.p_action;
    if (action !== 'revoke' && action !== 'decline' && action !== 'cancel') return reject('validation');
    if ((action === 'cancel' && row.requester_id !== actor) || (action !== 'cancel' && row.creator_id !== actor)) return reject('forbidden');
    if (action === 'revoke' ? !['open', 'awaiting_creator'].includes(row.state) : row.state !== 'awaiting_creator') return reject('invalid_state');
    const state = { revoke: 'revoked', decline: 'declined', cancel: 'cancelled' }[action];
    return this.commit(actor, command, hash, { ok: true, kind: 'close', id: row.id }, [
      ...this.invitationGuard(row), this.statement('UPDATE hamtdaa_pair_invitations SET state=?,version=version+1 WHERE id=?', state, row.id),
    ]);
  }

  private async isFree(actor: string) {
    return await this.statement(`SELECT 1 WHERE ${unpaired('?')}`, actor).first() !== null;
  }

  private async available([a, b]: [string, string] | string[]) {
    return await this.statement(`SELECT 1 WHERE ${eligible('?')} AND ${eligible('?')} AND ${unpaired('?')} AND ${unpaired('?')}
      AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?))`, a, b, a, b, a, b, b, a).first() !== null;
  }

  private async updateName(actor: string, params: Json): Promise<Json> {
    const name = typeof params.p_display_name === 'string' ? params.p_display_name.trim() : '';
    if ([...name].length < 1 || [...name].length > 40 || /[\u0000-\u001f\u007f]/.test(name) || !validVersion(params.p_expected_version)) return failure('validation');
    if (!await this.rate(actor, 'mutation')) return failure('rate_limited', true);
    try {
      const results = await this.db.batch([
        ...this.alive([actor]),
        ...this.guard('EXISTS(SELECT 1 FROM hamtdaa_profiles WHERE user_id=? AND version=?)', actor, params.p_expected_version),
        this.statement('UPDATE hamtdaa_profiles SET display_name=?,version=version+1 WHERE user_id=? RETURNING user_id,display_name,version', name, actor),
      ]);
      return { ok: true, profile: results[4].results[0], server_time: iso(now()) };
    } catch { return failure('conflict'); }
  }
}
