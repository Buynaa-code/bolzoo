'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const root = path.join(__dirname, '..');
const schema = fs.readFileSync(path.join(root, 'sql/schema.sql'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260929090000_learning_overview.sql'), 'utf8');
let db;
const range = (day, end = day + 1) => [`2024-09-${String(day).padStart(2, '0')}T00:00:00Z`, `2024-09-${String(end).padStart(2, '0')}T00:00:00Z`];
async function report(from, to) {
  return (await db.query('select public.moch_learning_overview($1, $2) as result', [from, to])).rows[0].result;
}
async function add(id, patch = {}) {
  const row = { status: 'succeeded', amount: 9900, currency: 'MNT', provider: 'wire', livemode: true, ...patch };
  await db.query('insert into public.payments(id,status,amount,currency,provider,livemode) values($1,$2,$3,$4,$5,$6)',
    [id, row.status, row.amount, row.currency, row.provider, row.livemode]);
}
// Test-only fixture clock edits. Production has no permission/RPC to alter facts.
async function fixtureTime(id, timestamp) {
  await db.query('update public.moch_learning_payment_facts set paid_at=$2 where payment_id=$1', [id, timestamp]);
}

test.before(async () => {
  db = new PGlite();
  await db.exec('create role anon; create role authenticated; create role service_role;');
  for (const name of ['invites', 'access_codes', 'payments']) {
    const table = schema.match(new RegExp('create table if not exists public\\.' + name + ' \\([\\s\\S]*?\\n\\);'));
    assert.ok(table, name + ' fixture comes from actual source schema');
    await db.exec(table[0]);
  }
  await db.exec('alter table public.payments add column livemode boolean; grant usage on schema public to anon,authenticated,service_role; grant select,insert,update on public.payments to service_role;');
  await add('legacy_success_before_coverage');
  await db.exec(migration);
});
test.after(async () => { if (db) await db.close(); });

test('new coverage never backfills old successes or fabricates historical success times', async () => {
  assert.equal((await db.query('select count(*)::int as count from public.moch_learning_payment_facts')).rows[0].count, 0);
  await db.exec("update public.payments set status='succeeded',updated_at=now() where id='legacy_success_before_coverage'");
  assert.equal((await db.query('select count(*)::int as count from public.moch_learning_payment_facts')).rows[0].count, 0);
  const old = await report(...range(1));
  assert.equal(old.measurement_available, false);
  assert.equal(old.recorded_count, null);
  assert.equal(old.recorded_amount_mnt, null);
  // Advance fixture coverage to a fixed historic instant; no production backfill.
  await db.exec("update public.moch_learning_coverage set started_at='2024-09-01T00:00:00Z'");
});

test('first observed success captures once; retries and status reversals cannot change the original amount or time', async () => {
  await add('first_success', { status: 'requires_action', amount: 9023 });
  assert.equal((await db.query("select count(*)::int as count from public.moch_learning_payment_facts where payment_id='first_success'")).rows[0].count, 0);
  await db.exec("update public.payments set status='succeeded' where id='first_success'");
  const read = async () => (await db.query("select payment_id,paid_at::text,amount_mnt::int,currency,provider,livemode from public.moch_learning_payment_facts where payment_id='first_success'")).rows[0];
  const first = await read();
  assert.equal(first.amount_mnt, 9023);
  assert.ok(Number.isFinite(Date.parse(first.paid_at)));
  await db.exec("update public.payments set status='succeeded',updated_at=now(),amount=12345 where id='first_success'; update public.payments set status='canceled' where id='first_success'; update public.payments set status='succeeded' where id='first_success';");
  assert.deepEqual(await read(), first);
  await fixtureTime('first_success', '2024-09-02T00:00:00Z');
});

test('half-open dates and stored prices count each live paid payment once without joining private tables', async () => {
  await add('before_range'); await fixtureTime('before_range', '2024-09-01T23:59:59.999Z');
  await add('inside_range'); await fixtureTime('inside_range', '2024-09-02T23:59:59.999Z');
  await add('at_end'); await fixtureTime('at_end', '2024-09-03T00:00:00Z');
  const result = await report(...range(2));
  assert.equal(result.measurement_available, true);
  assert.equal(result.recorded_count, 2);
  assert.equal(result.recorded_amount_mnt, 9023 + 9900);
  assert.deepEqual(Object.keys(result).sort(), ['measurement_available', 'read_at', 'recorded_amount_mnt', 'recorded_count']);
  assert.match(result.read_at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  const offset = await report('2024-09-02T08:00:00+08:00', '2024-09-03T08:00:00+08:00');
  assert.equal(offset.recorded_count, result.recorded_count);
  assert.equal(offset.recorded_amount_mnt, result.recorded_amount_mnt);
});

test('mock, manual, demo, test mode and pending rows do not enter commercial totals', async () => {
  for (const [id, patch] of [
    ['mock', { provider: 'mock' }], ['manual', { provider: 'manual', livemode: null }],
    ['demo', { provider: 'demo' }], ['test_mode', { livemode: false }], ['pending', { status: 'processing' }]
  ]) {
    await add(id, patch); await fixtureTime(id, '2024-09-04T12:00:00Z');
  }
  const result = await report(...range(4));
  assert.equal(result.measurement_available, true);
  assert.equal(result.recorded_count, 0);
  assert.equal(result.recorded_amount_mnt, 0);
});

test('unknown live mode, unsupported currency/provider and invalid commercial amounts fail closed', async () => {
  let day = 5;
  for (const [id, patch] of [
    ['unknown_mode', { livemode: null }], ['unsupported_currency', { currency: 'USD' }],
    ['unknown_provider', { provider: 'unclassified' }], ['invalid_amount', { amount: 0 }]
  ]) {
    await add(id, patch); await fixtureTime(id, range(day)[0]);
    const result = await report(...range(day));
    assert.equal(result.measurement_available, false, id);
    assert.equal(result.recorded_count, null);
    assert.equal(result.recorded_amount_mnt, null);
    day++;
  }
});

test('SQL independently rejects invalid or over-31-day windows', async () => {
  for (const args of [[null, range(2)[1]], [range(2)[0], null], ['infinity', 'infinity'],
    [range(2)[1], range(2)[0]], [range(2)[0], range(2)[0]],
    ['2024-09-01T00:00:00Z', '2024-10-02T00:00:00.001Z'],
    ['9998-01-01T00:00:00Z', '9998-01-02T00:00:00Z']]) {
    await assert.rejects(report(...args), /Invalid reporting period/);
  }
  assert.equal((await report('2024-10-01T00:00:00Z', '2024-11-01T00:00:00Z')).measurement_available, true);
});

test('only service role can read the RPC; it cannot call the trigger or mutate the facts/coverage', async () => {
  for (const role of ['anon', 'authenticated']) {
    await db.exec('set role ' + role);
    try {
      await assert.rejects(report(...range(2)), /permission denied/);
      await assert.rejects(db.query('select * from public.moch_learning_payment_facts'), /permission denied/);
      await assert.rejects(db.query('select * from public.moch_learning_coverage'), /permission denied/);
    } finally { await db.exec('reset role'); }
  }
  await db.exec('set role service_role');
  try {
    await db.exec('begin read only');
    assert.equal((await report(...range(2))).recorded_count, 2);
    await db.exec('commit');
    await assert.rejects(db.exec("update public.moch_learning_coverage set capture_complete=true"), /permission denied/);
    await assert.rejects(db.exec("update public.moch_learning_payment_facts set amount_mnt=1"), /permission denied/);
    await assert.rejects(db.exec("delete from public.moch_learning_payment_facts"), /permission denied/);
    assert.equal((await db.query("select has_function_privilege(current_user, 'public._capture_moch_learning_success()', 'EXECUTE') as allowed")).rows[0].allowed, false);
  } finally { await db.exec('reset role'); }
});

test('capture errors do not fail payment writes and permanently mark the source incomplete, including on migration rerun', async () => {
  await db.exec("create function public.learning_fixture_failure() returns trigger language plpgsql as $$ begin if new.payment_id='capture_failure' then raise exception 'fixture secret must not be stored'; end if; return new; end $$; create trigger learning_fixture_failure before insert on public.moch_learning_payment_facts for each row execute function public.learning_fixture_failure();");
  await add('capture_failure');
  assert.equal((await db.query("select status from public.payments where id='capture_failure'")).rows[0].status, 'succeeded');
  assert.equal((await db.query('select capture_complete from public.moch_learning_coverage')).rows[0].capture_complete, false);
  const unavailable = await report(...range(2));
  assert.equal(unavailable.measurement_available, false);
  assert.equal(unavailable.recorded_count, null);
  assert.doesNotMatch(JSON.stringify(unavailable), /fixture|secret|capture_failure/);
  const start = (await db.query('select started_at::text as start from public.moch_learning_coverage')).rows[0].start;
  await db.exec(migration);
  assert.equal((await report(...range(2))).measurement_available, false);
  assert.equal((await db.query('select started_at::text as start from public.moch_learning_coverage')).rows[0].start, start);
  await db.exec('drop trigger learning_fixture_failure on public.moch_learning_payment_facts; drop function public.learning_fixture_failure(); update public.moch_learning_coverage set capture_complete=true;');
});

test('disabled capture or missing coverage never claims complete zero accounting', async () => {
  await db.exec('alter table public.payments disable trigger moch_learning_capture_success');
  assert.equal((await report(...range(12))).measurement_available, false);
  await db.exec('alter table public.payments enable trigger moch_learning_capture_success');
  await db.exec('delete from public.moch_learning_coverage');
  assert.equal((await report(...range(12))).measurement_available, false);
});
