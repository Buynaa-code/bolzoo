/** Authentication belongs to the router; pair identity is always resolved here. */
type Json = Record<string, unknown>;
type Value = string | number | null;
type Pair = { id: string; partner_id: string; display_name: string };
type Receipt = { pair_id: string; payload_hash: string };
type Event = { id: string; title: string; note: string; location: string; starts_at: number; ends_at: number | null; creator_id: string; status: string; version: number };
type Answer = { day: string; question_id: string; my_answer: string | null; partner_answer: string | null; both_answered: number };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DAY = /^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const OFFSET = 8 * 3600000;
const DAY_MS = 86400000;
// Version 1 is immutable: existing answers must always retain their question.
const QUESTIONS = [
  'Өнөөдөр чамайг инээлгэсэн жижигхэн зүйл юу байсан бэ?',
  'Хамтдаа өнгөрүүлсэн ямар мөчөө дахин нэг удаа мэдрэхийг хүсдэг вэ?',
  'Ядарсан үед чинь би чамд яаж тусалбал хамгийн тухтай санагдах вэ?',
  'Бид хоёрын хамт туршиж үзээсэй гэж хүсдэг шинэ зүйл юу вэ?',
  'Миний ямар жижиг үйлдэл чамд хайрлагдаж байгааг мэдрүүлдэг вэ?',
  'Чиний хувьд тайван, сайхан амралтын өдөр ямар байдаг вэ?',
  'Бага насны ямар дурсамжаа надад ярьж өгөхийг хүсэж байна вэ?',
  'Энэ долоо хоногт өөрөөрөө бахархсан нэг зүйлээ хуваалцаач.',
  'Бид хамтдаа ямар жижиг дадлыг эхлүүлбэл сайхан байх бол?',
  'Чамд яг одоо илүү их хэрэгтэй байгаа зүйл нь амралт, дэмжлэг, эсвэл ярилцах цагийн аль нь вэ?',
  'Бидний анхны уулзалтаас хамгийн тод санагддаг зүйл юу вэ?',
  'Чиний заавал очиж үзэхийг хүсдэг газар хаана вэ, яагаад?',
  'Миний талаар сүүлийн үед шинээр анзаарсан сайхан зүйл юу вэ?',
  'Санал зөрөх үедээ бид бие биенээ илүү сайн сонсохын тулд яаж болох вэ?',
  'Хамтдаа хийх энгийн боловч чамд онцгой санагддаг зүйл юу вэ?',
  'Чиний дуртай хоолтой холбоотой ямар дурсамж байдаг вэ?',
  'Энэ сард бид юунд зориулж цаг гаргавал чамд баяртай байх вэ?',
  'Чамайг урам зоригтой болгодог үг эсвэл үйлдэл юу вэ?',
  'Надад зааж өгөхийг хүсдэг чадвар, сонирхол чамд бий юу?',
  'Бид хоёрын ялгаатай зангаас чамд сонирхолтой санагддаг нь юу вэ?',
  'Утасгүй нэг оройг хамт өнгөрүүлбэл юу хиймээр байна вэ?',
  'Чиний хувьд итгэлцлийг өдөр тутамд бий болгодог зүйл юу вэ?',
  'Өнөөдөр надад талархаж байгаа нэг зүйлээ хэлээч.',
  'Ирэх жил хамтдаа бүтээсэн байгаасай гэж хүсдэг дурсамж юу вэ?',
  'Сэтгэл тавгүй үедээ чи ганцаараа байх уу, эсвэл хамт байхыг илүүд үздэг вэ?',
  'Бидний харилцаанд хадгалж үлдэхийг хүсдэг сайхан зуршил юу вэ?',
  'Хамтдаа сонсохыг хүсдэг дуу чинь ямар дурсамж төрүүлдэг вэ?',
  'Сүүлийн үед чиний бодлыг хамгийн их эзэлж байгаа зүйл юу вэ?',
  'Чамд зориулж гаргасан цагийг би яаж илүү утгатай болгож болох вэ?',
  'Маргааш бие биедээ баяр өгөхийн тулд хийж болох нэг жижиг зүйл юу вэ?',
] as const;
const activePair = `SELECT p.id,other.user_id partner_id,op.display_name
 FROM hamtdaa_pairs p
 JOIN hamtdaa_pair_members own ON own.pair_id=p.id AND own.user_id=? AND own.revoked_at IS NULL
 JOIN hamtdaa_pair_members other ON other.pair_id=p.id AND other.user_id<>own.user_id AND other.revoked_at IS NULL
 JOIN hamtdaa_profiles ap ON ap.user_id=own.user_id AND ap.account_state='active'
 JOIN hamtdaa_profiles op ON op.user_id=other.user_id AND op.account_state='active'
 JOIN "user" au ON au.id=own.user_id AND au.emailVerified=1
 JOIN "user" ou ON ou.id=other.user_id AND ou.emailVerified=1
 WHERE p.state='active' AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b
 WHERE (b.blocker_id=own.user_id AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=own.user_id))`;
const actorEligible = `EXISTS(SELECT 1 FROM hamtdaa_profiles p JOIN "user" u ON u.id=p.user_id WHERE p.user_id=? AND p.account_state='active' AND u.emailVerified=1)`;
class Problem extends Error { constructor(readonly code: string, readonly status: number) { super(code); } }
function fail(code: string, status = 400): never { throw new Problem(code, status); }
function json(value: Json, status = 200): Response {
  const encoded = JSON.stringify(value);
  if (new TextEncoder().encode(encoded).byteLength > 512 * 1024) fail('response_too_large', 503);
  return new Response(encoded, { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store, private', 'Pragma': 'no-cache', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' } });
}
type CalendarCursor = { pair: string; starts: number; id: string; revision: string };
function calendarCursor(value: unknown, month: string): CalendarCursor | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length > 512 || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) fail('validation');
  try {
    const decoded = atob(value);
    if (btoa(decoded) !== value) fail('validation');
    const parts: unknown = JSON.parse(decoded);
    if (!Array.isArray(parts) || parts.length !== 6 || parts[0] !== 'calendar-v1' ||
      typeof parts[1] !== 'string' || !UUID.test(parts[1]) || parts[2] !== month ||
      !Number.isSafeInteger(parts[3]) || Number(parts[3]) < Date.parse('2000-01-01T00:00:00Z') || Number(parts[3]) >= Date.parse('2100-01-01T00:00:00Z') ||
      typeof parts[4] !== 'string' || !UUID.test(parts[4]) || typeof parts[5] !== 'string' || !/^[a-f0-9]{64}$/.test(parts[5])) fail('validation');
    return { pair: parts[1], starts: Number(parts[3]), id: parts[4], revision: parts[5] };
  } catch { fail('validation'); }
}
async function fingerprint(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(value)));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}
function fields(body: Json | null, required: string[], optional: string[] = []): Json {
  if (!body || Object.keys(body).some(k => !required.includes(k) && !optional.includes(k)) || required.some(k => !Object.hasOwn(body, k))) fail('validation');
  return body;
}
function text(value: unknown, max: number, required = false): string {
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(value)) fail('validation');
  const result = value.trim();
  if (required && !result) fail('validation');
  return result;
}
function id(value: unknown): string { if (typeof value !== 'string' || !UUID.test(value)) fail('validation'); return value.toLowerCase(); }
function day(value: unknown): string {
  if (typeof value !== 'string' || !DAY.test(value) || new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) !== value) fail('validation');
  return value;
}
function today(): string { return new Date(Date.now() + OFFSET).toISOString().slice(0, 10); }
function prompt(date: string) {
  const index = Math.floor(Date.parse(date + 'T00:00:00Z') / DAY_MS) % QUESTIONS.length;
  return { question_id: `dq-v1:${date}:${index + 1}`, question: QUESTIONS[index] };
}
function instant(value: unknown): number {
  if (typeof value !== 'string' || !/^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) fail('validation');
  const ms = Date.parse(value);
  const normalized = value.includes('.') ? value.replace(/\.(\d{1,3})Z$/, (_, fraction: string) => '.' + fraction.padEnd(3, '0') + 'Z') : value.replace('Z', '.000Z');
  if (!Number.isSafeInteger(ms) || new Date(ms).toISOString() !== normalized) fail('validation');
  return ms;
}
function eventInput(body: Json) {
  const starts = instant(body.starts_at);
  const ends = body.ends_at === null ? null : instant(body.ends_at);
  if (ends !== null && (ends <= starts || ends - starts > 31 * DAY_MS)) fail('validation');
  return { title: text(body.title, 120, true), note: text(body.note, 2000), location: text(body.location, 200), starts_at: starts, ends_at: ends };
}
const answerColumns = `a.day,MAX(a.question_id) question_id,
 MAX(CASE WHEN a.user_id=? THEN a.answer END) my_answer,
 CASE WHEN MAX(CASE WHEN a.user_id=? THEN 1 ELSE 0 END)=1 THEN MAX(CASE WHEN a.user_id<>? THEN a.answer END) ELSE NULL END partner_answer,
 CASE WHEN COUNT(*)=2 THEN 1 ELSE 0 END both_answered`;
class Together {
  constructor(private db: D1Database, private actor: string) {}
  q(sql: string, ...values: Value[]) { return this.db.prepare(sql).bind(...values); }
  guard(predicate: string, ...values: Value[]) {
    const key = crypto.randomUUID();
    return [this.q(`INSERT INTO hamtdaa_together_guards(id,allowed) SELECT ?,CASE WHEN ${predicate} THEN 1 ELSE 0 END`, key, ...values), this.q('DELETE FROM hamtdaa_together_guards WHERE id=?', key)];
  }
  pairGuard(pair: string) { return this.guard(`EXISTS(${activePair} AND p.id=?)`, this.actor, pair); }
  async eligible() {
    await this.q('INSERT OR IGNORE INTO hamtdaa_profiles(user_id) SELECT id FROM "user" WHERE id=? AND emailVerified=1', this.actor).run();
    if (!await this.q(`SELECT 1 WHERE ${actorEligible}`, this.actor).first()) fail('unauthenticated', 401);
  }
  async pair() { return this.q(activePair, this.actor).first<Pair>(); }
  async receipt(command: string) { return this.q('SELECT pair_id,payload_hash FROM hamtdaa_together_receipts WHERE user_id=? AND command_id=?', this.actor, command).first<Receipt>(); }
  async replay(record: Receipt, hash: string): Promise<Response> {
    if (record.payload_hash !== hash) fail('idempotency_mismatch', 409);
    try { await this.db.batch(this.pairGuard(record.pair_id)); }
    catch (error) {
      if (error instanceof Error && /constraint|together_guards/i.test(error.message)) fail('pair_required', 409);
      throw error;
    }
    return json({ ok: true });
  }
  async state(body: Json | null) {
    const value = fields(body, ['month'], ['cursor']);
    if (typeof value.month !== 'string' || !/^20\d{2}-(0[1-9]|1[0-2])$/.test(value.month)) fail('validation');
    const cursor = calendarCursor(value.cursor, value.month);
    const start = Date.parse(value.month + '-01T00:00:00Z') - OFFSET;
    const endDate = new Date(start + OFFSET); endDate.setUTCMonth(endDate.getUTCMonth() + 1);
    const end = endDate.getTime() - OFFSET;
    const date = today();
    const monthRange = 'e.starts_at<? AND (e.ends_at>? OR (e.ends_at IS NULL AND e.starts_at>=?))';
    const result = await this.db.batch([
      ...this.guard(actorEligible, this.actor), this.q(activePair, this.actor),
      this.q(`WITH current_pair AS (${activePair}) SELECT e.id,e.title,e.note,e.location,e.starts_at,e.ends_at,e.creator_id,e.status,e.version
        FROM hamtdaa_calendar_events e JOIN current_pair p ON p.id=e.pair_id
        WHERE ${monthRange} AND (? IS NULL OR p.id=?) AND (? IS NULL OR (e.starts_at,e.id)>(?,?))
        ORDER BY e.starts_at,e.id LIMIT 51`, this.actor, end, start, start, cursor?.pair ?? null, cursor?.pair ?? null, cursor?.id ?? null, cursor?.starts ?? null, cursor?.id ?? null),
      this.q(`WITH current_pair AS (${activePair}) SELECT ${answerColumns} FROM hamtdaa_daily_answers a JOIN current_pair p ON p.id=a.pair_id WHERE a.day=? GROUP BY a.day`, this.actor, this.actor, this.actor, this.actor, date),
      // Small version-only snapshot (at most 500 rows) detects edits, deletions
      // and moves across page boundaries without copying notes or storing tokens.
      this.q(`WITH current_pair AS (${activePair}) SELECT e.id,e.version FROM hamtdaa_calendar_events e JOIN current_pair p ON p.id=e.pair_id
        WHERE ${monthRange} ORDER BY e.id LIMIT 500`, this.actor, end, start, start),
    ]);
    const pair = result[2].results[0] as Pair | undefined;
    if (cursor && cursor.pair !== pair?.id) fail('pair_changed', 409);
    const revisionRows = result[5].results as { id: string; version: number }[];
    const revision = await fingerprint(revisionRows.map(row => [row.id, row.version]));
    if (cursor && cursor.revision !== revision) fail('calendar_changed', 409);
    const answer = result[4].results[0] as Answer | undefined;
    const rows = result[3].results as Event[];
    const page = rows.slice(0, 50);
    const last = page.at(-1);
    const next = rows.length > 50 && last && pair ? btoa(JSON.stringify(['calendar-v1', pair.id, value.month, last.starts_at, last.id, revision])) : null;
    return json({ ok: true, paired: !!pair, pair_id: pair?.id ?? null,
      partner: pair ? { id: pair.partner_id, display_name: pair.display_name } : null,
      events: page.map(e => ({ ...e, starts_at: new Date(e.starts_at).toISOString(), ends_at: e.ends_at === null ? null : new Date(e.ends_at).toISOString() })),
      next_cursor: next,
      daily: pair ? { day: date, ...prompt(date), my_answer: answer?.my_answer ?? null, partner_answer: answer?.partner_answer ?? null, both_answered: answer?.both_answered === 1 } : null });
  }
  async history(body: Json | null) {
    const value = fields(body, [], ['before_day']);
    const before = value.before_day === undefined ? new Date(Date.now() + OFFSET + DAY_MS).toISOString().slice(0, 10) : day(value.before_day);
    const result = await this.db.batch([
      ...this.guard(actorEligible, this.actor),
      this.q(`WITH current_pair AS (${activePair}) SELECT ${answerColumns} FROM hamtdaa_daily_answers a JOIN current_pair p ON p.id=a.pair_id
        WHERE a.day<? GROUP BY a.day ORDER BY a.day DESC LIMIT 31`, this.actor, this.actor, this.actor, this.actor, before),
    ]);
    const rows = result[2].results as Answer[];
    return json({ ok: true, entries: rows.slice(0, 30).map(a => ({ ...a, ...prompt(a.day), both_answered: a.both_answered === 1 })), next_before_day: rows.length > 30 ? rows[29].day : null });
  }
  async mutate(operation: string, body: Json | null) {
    const common = ['command_id', 'expected_pair_id'];
    const eventFields = ['title', 'note', 'location', 'starts_at', 'ends_at'];
    const required = operation === 'calendar/create' ? [...common, ...eventFields] : operation === 'calendar/update' ? [...common, 'id', 'expected_version', ...eventFields] : operation === 'daily/answer' ? [...common, 'question_id', 'answer'] : [...common, 'id', 'expected_version', ...(operation === 'calendar/respond' ? ['response'] : [])];
    const value = fields(body, required);
    const command = id(value.command_id);
    const expectedPair = id(value.expected_pair_id);
    const canonical: Json = { operation };
    // Hash every accepted field in stable order, including the operation itself.
    for (const key of required.filter(k => k !== 'command_id').sort()) canonical[key] = value[key];
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(canonical)));
    const hash = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
    const previous = await this.receipt(command);
    if (previous) return this.replay(previous, hash);
    const pair = await this.pair();
    if (!pair) fail('pair_required', 409);
    if (pair.id !== expectedPair) fail('pair_changed', 409);
    const date = today();
    const now = Date.now();
    const quota = await this.q('SELECT mutations FROM hamtdaa_together_quotas WHERE user_id=? AND day=?', this.actor, date).first<{ mutations: number }>();
    if (quota && quota.mutations >= 100) fail('quota_exceeded', 429);
    const mutations: D1PreparedStatement[] = [];
    if (operation === 'calendar/create') {
      const event = eventInput(value);
      const used = await this.q(`SELECT (SELECT count(*) FROM hamtdaa_calendar_events WHERE pair_id=?) events,
        (SELECT count(*) FROM hamtdaa_together_receipts WHERE user_id=? AND day=? AND operation='calendar/create') creates`, pair.id, this.actor, date).first<{ events: number; creates: number }>();
      if (used!.events >= 500 || used!.creates >= 30) fail('quota_exceeded', 429);
      mutations.push(...this.guard(`(SELECT count(*) FROM hamtdaa_calendar_events WHERE pair_id=?)<500 AND
        (SELECT count(*) FROM hamtdaa_together_receipts WHERE user_id=? AND day=? AND operation='calendar/create')<=30`, pair.id, this.actor, date));
      mutations.push(this.q('INSERT INTO hamtdaa_calendar_events(id,pair_id,creator_id,title,note,location,starts_at,ends_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
        crypto.randomUUID(), pair.id, this.actor, event.title, event.note, event.location, event.starts_at, event.ends_at, now, now));
    } else if (operation === 'daily/answer') {
      const question = prompt(date);
      if (value.question_id !== question.question_id) fail('question_expired', 409);
      const answer = text(value.answer, 2000, true);
      if (await this.q('SELECT 1 FROM hamtdaa_daily_answers WHERE pair_id=? AND day=? AND user_id=?', pair.id, date, this.actor).first()) fail('answer_locked', 409);
      mutations.push(this.q('INSERT INTO hamtdaa_daily_answers(pair_id,day,user_id,question_id,answer,created_at) VALUES(?,?,?,?,?,?)', pair.id, date, this.actor, question.question_id, answer, now));
    } else {
      const eventId = id(value.id);
      if (!Number.isSafeInteger(value.expected_version) || Number(value.expected_version) < 1) fail('validation');
      const version = Number(value.expected_version);
      const event = await this.q('SELECT creator_id,version FROM hamtdaa_calendar_events WHERE pair_id=? AND id=?', pair.id, eventId).first<{ creator_id: string; version: number }>();
      if (!event) fail('not_found', 404);
      if ((operation === 'calendar/respond') === (event.creator_id === this.actor)) fail('forbidden', 403);
      if (event.version !== version) fail('conflict', 409);
      if (operation === 'calendar/update') {
        const updated = eventInput(value);
        mutations.push(this.q("UPDATE hamtdaa_calendar_events SET title=?,note=?,location=?,starts_at=?,ends_at=?,status='pending',version=version+1,updated_at=? WHERE pair_id=? AND id=? AND version=? AND creator_id=?", updated.title, updated.note, updated.location, updated.starts_at, updated.ends_at, now, pair.id, eventId, version, this.actor));
      } else if (operation === 'calendar/delete') {
        mutations.push(this.q('DELETE FROM hamtdaa_calendar_events WHERE pair_id=? AND id=? AND version=? AND creator_id=?', pair.id, eventId, version, this.actor));
      } else {
        if (value.response !== 'accepted' && value.response !== 'declined') fail('validation');
        mutations.push(this.q('UPDATE hamtdaa_calendar_events SET status=?,version=version+1,updated_at=? WHERE pair_id=? AND id=? AND version=? AND creator_id<>?', value.response, now, pair.id, eventId, version, this.actor));
      }
      mutations.push(...this.guard('changes()=1'));
    }
    try {
      await this.db.batch([
        ...this.pairGuard(pair.id),
        // A midnight rollover may not commit a yesterday command as today's answer.
        ...this.guard("date('now','+8 hours')=?", date),
        this.q('INSERT INTO hamtdaa_together_receipts(user_id,command_id,pair_id,payload_hash,operation,day,created_at) VALUES(?,?,?,?,?,?,?)', this.actor, command, pair.id, hash, operation, date, now),
        this.q(`INSERT INTO hamtdaa_together_quotas(user_id,day,mutations) VALUES(?,?,1) ON CONFLICT(user_id) DO UPDATE SET day=excluded.day,
          mutations=CASE WHEN hamtdaa_together_quotas.day=excluded.day THEN hamtdaa_together_quotas.mutations+1 ELSE 1 END`, this.actor, date),
        ...mutations,
      ]);
    } catch (error) {
      const duplicate = await this.receipt(command);
      if (duplicate) return this.replay(duplicate, hash);
      if (error instanceof Error && /constraint|together_guards|daily_answer_immutable/i.test(error.message)) fail('conflict', 409);
      throw error;
    }
    return json({ ok: true });
  }
}
export async function handleTogetherRequest(request: Request, env: { DB: D1Database }, actorId: string, body: Json | null): Promise<Response> {
  try {
    if (request.method !== 'POST') return json({ ok: false, code: 'method_not_allowed' }, 405);
    const operation = new URL(request.url).pathname.replace(/^\/v1\/together\//, '');
    if (!['state', 'calendar/create', 'calendar/update', 'calendar/delete', 'calendar/respond', 'daily/answer', 'daily/history'].includes(operation)) fail('not_found', 404);
    const service = new Together(env.DB, actorId);
    await service.eligible();
    if (operation === 'state') return await service.state(body);
    if (operation === 'daily/history') return await service.history(body);
    return await service.mutate(operation, body);
  } catch (error) {
    if (error instanceof Problem) return json({ ok: false, code: error.code }, error.status);
    return json({ ok: false, code: 'temporarily_unavailable' }, 503);
  }
}
