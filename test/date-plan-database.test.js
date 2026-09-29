'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { PGlite } = require('@electric-sql/pglite');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260909064508_date_plans.sql'), 'utf8');
let db;

test.before(async () => {
  db = new PGlite();
  // The non-bypass service role exercises the explicit service-only RLS policy.
  // Hosted Supabase also gives service_role BYPASSRLS; browser roles have none.
  await db.exec(`create role anon; create role authenticated; create role service_role;
    grant usage on schema public to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;`);
  const schema = fs.readFileSync(path.join(root, 'sql/schema.sql'), 'utf8');
  const invites = schema.match(/create table if not exists public\.invites \([\s\S]*?\n\);/);
  assert.ok(invites, 'load actual parent-table definition');
  await db.exec(invites[0]);
  await db.exec(migration);
});
test.after(async () => { if (db) await db.close(); });

async function asRole(role, work) {
  await db.exec('set role ' + role);
  try { return await work(); } finally { await db.exec('reset role'); }
}
async function invite() {
  const id = 'date-' + randomUUID();
  await db.query('insert into public.invites (id, config) values ($1, $2)', [id, '{}']);
  return id;
}
async function create(inviteId, document = { schema: 1, state: 'proposed' }, id = randomUUID()) {
  return (await db.query('select * from public.create_date_plan($1, $2, $3)', [id, inviteId, JSON.stringify(document)])).rows;
}
async function commit(id, version, document) {
  return (await db.query('select * from public.commit_date_plan($1, $2, $3)', [id, version, JSON.stringify(document)])).rows;
}
async function read(id) {
  return (await db.query('select * from public.date_plans where id = $1', [id])).rows[0];
}

test('SQL service role creates, reads and commits a private plan', async () => {
  const inviteId = await invite();
  await asRole('service_role', async () => {
    const [created] = await create(inviteId);
    assert.equal(created.invite_id, inviteId);
    assert.equal(created.version, 1);
    assert.deepEqual((await read(created.id)).document, { schema: 1, state: 'proposed' });
    const [saved] = await commit(created.id, 1, { schema: 1, state: 'agreed' });
    assert.equal(saved.version, 2);
    assert.equal(saved.document.state, 'agreed');
    assert.deepEqual(saved.created_at, created.created_at);
    assert.ok(new Date(saved.updated_at) >= new Date(created.updated_at));
  });
});

test('SQL retrying create returns the original plan without overwriting its current document', async () => {
  const inviteId = await invite();
  await asRole('service_role', async () => {
    const id = randomUUID();
    const [first] = await create(inviteId, { schema: 1 }, id);
    const [saved] = await commit(first.id, first.version, { schema: 1, steps: ['done'] });
    assert.deepEqual(await create(inviteId, { schema: 1 }, id), [saved]);
    assert.deepEqual(await create(inviteId, { schema: 1, replaced: true }), [saved]);
    const count = await db.query('select count(*)::int as n from public.date_plans where invite_id = $1', [inviteId]);
    assert.equal(count.rows[0].n, 1);
  });
});

test('SQL stale and missing writers return no rows and preserve the winner', async () => {
  const inviteId = await invite();
  await asRole('service_role', async () => {
    const [first] = await create(inviteId);
    const [winner] = await commit(first.id, first.version, { schema: 1, winner: 'creator' });
    // PGlite uses one session: this verifies stale-version behavior, not a
    // production two-session concurrency or lock scheduling guarantee.
    assert.deepEqual(await commit(first.id, first.version, { winner: 'partner' }), []);
    assert.deepEqual(await commit(randomUUID(), first.version, {}), []);
    assert.deepEqual(await commit(first.id, null, {}), []);
    assert.deepEqual(await read(first.id), winner);
  });
});

test('SQL browser roles cannot read private plans or invoke either mutation RPC', async () => {
  const inviteId = await invite();
  const [plan] = await create(inviteId);
  for (const role of ['anon', 'authenticated']) {
    await asRole(role, async () => {
      await assert.rejects(read(plan.id), /permission denied/);
      await assert.rejects(create(inviteId), /permission denied/);
      await assert.rejects(commit(plan.id, plan.version, { stolen: true }), /permission denied/);
      await assert.rejects(db.query('delete from public.date_plans where id = $1', [plan.id]), /permission denied/);
    });
  }
  assert.deepEqual(await read(plan.id), plan);
});

test('SQL RLS still protects documents if a browser role is accidentally granted table access', async () => {
  const inviteId = await invite();
  const [plan] = await create(inviteId);
  await db.exec('grant select, insert, update on public.date_plans to authenticated');
  try {
    await asRole('authenticated', async () => {
      assert.equal(await read(plan.id), undefined);
      const update = await db.query('update public.date_plans set document = $1 where id = $2 returning *', ['{}', plan.id]);
      assert.equal(update.rows.length, 0);
      await assert.rejects(db.query('insert into public.date_plans (id, invite_id, document) values ($1, $2, $3)', [randomUUID(), inviteId, '{}']), /row-level security/);
    });
  } finally {
    await db.exec('revoke select, insert, update on public.date_plans from authenticated');
  }
  assert.deepEqual(await read(plan.id), plan);
});

test('SQL structural constraints reject invalid documents and roll back the version increment', async () => {
  const inviteId = await invite();
  const [plan] = await create(inviteId);
  await asRole('service_role', async () => {
    for (const document of [null, [], 'wrong', { large: 'x'.repeat(131072) }]) {
      await assert.rejects(commit(plan.id, 1, document), /check constraint/);
      assert.deepEqual(await read(plan.id), plan);
    }
    await assert.rejects(db.query('update public.date_plans set version = 0 where id = $1', [plan.id]), /positive_version/);
    await assert.rejects(db.query('update public.date_plans set document = null where id = $1', [plan.id]), /not-null constraint/);
    assert.deepEqual(await read(plan.id), plan);
  });
});

test('SQL rejects orphan plans, duplicate ids and changing aggregate identity', async () => {
  const inviteId = await invite();
  const otherInviteId = await invite();
  await asRole('service_role', async () => {
    await assert.rejects(create('missing-invite'), /foreign key constraint/);
    const [plan] = await create(inviteId);
    await assert.rejects(create(otherInviteId, {}, plan.id), /unique constraint/);
    await assert.rejects(db.query('update public.date_plans set invite_id = $1 where id = $2', [otherInviteId, plan.id]), /permission denied/);
    await assert.rejects(db.query('delete from public.date_plans where id = $1', [plan.id]), /permission denied/);
    assert.deepEqual(await read(plan.id), plan);
  });
});

test('SQL failed storage writes roll back the aggregate and optimistic version together', async () => {
  const inviteId = await invite();
  const [plan] = await create(inviteId);
  await db.exec(`create function public.reject_date_plan_test_write() returns trigger language plpgsql as $$
    begin if new.document ? 'storage_failure' then raise exception 'test storage failure'; end if; return new; end $$;
    create trigger date_plan_test_failure before update on public.date_plans
      for each row execute function public.reject_date_plan_test_write();`);
  try {
    await asRole('service_role', async () => {
      await assert.rejects(commit(plan.id, plan.version, { storage_failure: true }), /test storage failure/);
      assert.deepEqual(await read(plan.id), plan);
    });
  } finally {
    await db.exec('drop trigger date_plan_test_failure on public.date_plans; drop function public.reject_date_plan_test_write();');
  }
});

test('SQL deleting an invite cascades private plan data and migration reruns preserve existing plans', async () => {
  const inviteId = await invite();
  const [plan] = await create(inviteId);
  await db.exec(migration);
  assert.deepEqual(await read(plan.id), plan);
  await db.query('delete from public.invites where id = $1', [inviteId]);
  assert.equal(await read(plan.id), undefined);
  const functions = await db.query(`select proname, prosecdef, proconfig from pg_proc
    where pronamespace = 'public'::regnamespace and proname in ('create_date_plan', 'commit_date_plan')`);
  assert.equal(functions.rows.length, 2);
  for (const fn of functions.rows) {
    assert.equal(fn.prosecdef, false, fn.proname + ' uses caller privileges');
    assert.deepEqual(fn.proconfig, ['search_path=""']);
  }
});
