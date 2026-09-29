'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const root=path.join(__dirname,'..');
const schema=fs.readFileSync(path.join(root,'sql/schema.sql'),'utf8');
let db;
test.before(async () => {
  db=new PGlite();
  await db.exec('create role anon; create role authenticated; create role service_role;');
  for (const name of ['invites','access_codes','payments','webhook_events']) {
    const table=schema.match(new RegExp('create table if not exists public\\.'+name+' \\([\\s\\S]*?\\n\\);'));
    assert.ok(table,name+' fixture from real schema'); await db.exec(table[0]);
  }
  await db.exec(`alter table public.access_codes add column source text;
    alter table public.access_codes add column payment_id text references public.payments(id);
    create unique index codes_payment_unique on public.access_codes(payment_id) where payment_id is not null;
    create function public.process_wire_event(text,text,text,jsonb) returns void language sql as 'select';
    grant usage on schema public to service_role;
    grant select,insert,update on all tables in schema public to service_role;`);
  // A legacy pending invoice must not be silently accepted at the old 100x smaller amount.
  await db.exec("insert into payments(id,amount,provider_intent_id) values('pi_legacy',9900,'pi_legacy');");
  await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260907090000_payment_integrity.sql'),'utf8'));
  await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260907090001_retry_safe_redemption.sql'),'utf8'));
  await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20260922090728_payment_insert_compatibility.sql'),'utf8'));
});
test.after(async()=>{if(db)await db.close();});
async function add(id){
  await db.query("insert into payments(id,provider_intent_id,status,amount,amount_minor,currency,livemode) values($1,$1,'requires_action',9900,990000,'MNT',true)",[id]);
}
const remote=(id,patch={})=>({id,amount:990000,currency:'MNT',status:'succeeded',livemode:true,...patch});
async function reconcile(id,data){
  return (await db.query('select * from public.reconcile_wire_payment($1,$2)',[id,JSON.stringify(data)])).rows[0];
}
test('actual PostgreSQL migration rejects legacy underpayments and leaves code unissued', async()=>{
  await assert.rejects(reconcile('pi_legacy',remote('pi_legacy',{amount:9900})),/mismatch/);
  assert.equal((await db.query("select code from payments where id='pi_legacy'")).rows[0].code,null);
});
test('compatibility trigger accepts an old service-role insert and still quarantines its underpaid intent',async()=>{
  await db.exec('set role service_role');
  try{
    const result=await db.query("insert into payments(id,provider_intent_id,amount,status) values('pi_old_inflight','pi_old_inflight',9900,'requires_action') returning amount,amount_minor");
    assert.deepEqual(result.rows[0],{amount:9900,amount_minor:990000});
    await assert.rejects(reconcile('pi_old_inflight',remote('pi_old_inflight',{amount:9900})),/mismatch/);
    assert.equal((await db.query("select code from payments where id='pi_old_inflight'")).rows[0].code,null);
  }finally{await db.exec('reset role');}
});
test('compatibility trigger preserves explicit campaign and independently specified minor amounts',async()=>{
  await db.exec('set role service_role');
  try{
    for(const [id,amount] of [['pi_compat_campaign',9023],['pi_compat_explicit',9900]]){
      // The differing display amount proves the trigger only fills null, rather
      // than recomputing an explicit value supplied by the new API.
      const result=await db.query('insert into payments(id,amount,amount_minor) values($1,$2,902300) returning amount_minor',[id,amount]);
      assert.equal(result.rows[0].amount_minor,902300);
    }
  }finally{await db.exec('reset role');}
});
test('compatibility bridge keeps invalid amounts rejected and grants no callable RPC access',async()=>{
  await db.exec('set role service_role');
  try{
    await assert.rejects(db.query("insert into payments(id,amount) values('pi_compat_zero',0)"),/payments_positive_minor/);
    await assert.rejects(db.query("insert into payments(id,amount) values('pi_compat_overflow',21474837)"),/integer out of range/);
    await assert.rejects(db.query("insert into payments(id,amount,amount_minor) values('pi_compat_explicit_zero',9900,0)"),/payments_positive_minor/);
    await assert.rejects(db.query("update payments set amount_minor=null where id='pi_compat_campaign'"),/not-null constraint/);
  }finally{await db.exec('reset role');}
  for(const role of ['anon','authenticated','service_role']){
    const permissions=(await db.query("select has_function_privilege($1,'public._fill_payment_amount_minor()','EXECUTE') as allowed",[role])).rows[0];
    assert.equal(permissions.allowed,false);
  }
});
test('actual SQL allocates exactly one code and repeated/stale updates preserve success',async()=>{
  await add('pi_atomic');
  await db.exec('set role service_role');
  const result=await Promise.all(Array.from({length:8},()=>reconcile('pi_atomic',remote('pi_atomic'))));
  assert.equal(new Set(result.map(p=>p.code)).size,1); assert.match(result[0].code,/^LOV-[A-HJ-NP-Z2-9]{6}$/);
  const stale=await reconcile('pi_atomic',remote('pi_atomic',{status:'canceled'}));
  assert.equal(stale.status,'succeeded'); assert.equal(stale.code,result[0].code);
  assert.equal((await db.query("select count(*)::int as n from access_codes where payment_id='pi_atomic'")).rows[0].n,1);
  await db.exec('reset role');
});
test('SQL boundary independently rejects forged id, currency, amount and test-mode responses',async()=>{
  await add('pi_invalid');
  for(const patch of [{id:'pi_wrong'},{currency:'USD'},{amount:'990000'},{amount:990000.1},{livemode:false},{status:'failed'},{status:null}]){
    await assert.rejects(reconcile('pi_invalid',remote('pi_invalid',patch)),/mismatch/);
  }
  assert.equal((await db.query("select code from payments where id='pi_invalid'")).rows[0].code,null);
});
test('SQL rolls payment status back if fulfillment cannot finish',async()=>{
  await add('pi_rollback');
  await db.exec("create function public.reject_test_code() returns trigger language plpgsql as $$ begin if NEW.payment_id='pi_rollback' then raise exception 'storage failure'; end if; return NEW; end $$; create trigger fail_code before insert on access_codes for each row execute function public.reject_test_code();");
  await assert.rejects(reconcile('pi_rollback',remote('pi_rollback')),/storage failure/);
  assert.equal((await db.query("select status,code from payments where id='pi_rollback'")).rows[0].status,'requires_action');
  await db.exec('drop trigger fail_code on access_codes;');
  assert.ok((await reconcile('pi_rollback',remote('pi_rollback'))).code);
});
test('anon cannot reconcile payments or execute the obsolete webhook mutator',async()=>{
  for(const role of ['anon','authenticated']){
    await db.exec('set role '+role);
    await assert.rejects(reconcile('pi_atomic',remote('pi_atomic')),/permission denied/);
    await assert.rejects(db.query("select public.process_wire_event('evt','payment_intent.succeeded','pi_atomic','{}')"),/permission denied/);
    await db.exec('reset role');
  }
  await db.exec('set role service_role');
  await assert.rejects(db.query("select public.process_wire_event('evt','payment_intent.succeeded','pi_atomic','{}')"),/permission denied/);
  await db.exec('reset role');
});
test('lost publish response can be retried with same invite id; another invite cannot reuse code',async()=>{
  await add('pi_publish'); const paid=await reconcile('pi_publish',remote('pi_publish'));
  const publish=(id)=>db.query('select * from create_invite_with_code($1,$2,$3,$4)',[id,'{"recipientName":"Номин"}',paid.code,'{}']);
  await db.exec('set role anon');
  const first=(await publish('invite_one')).rows[0]; const retry=(await publish('invite_one')).rows[0];
  assert.deepEqual(retry,first);
  await assert.rejects(publish('invite_two'),/already used/);
  await db.exec('reset role');
  assert.equal((await db.query("select count(*)::int as n from invites where id in ('invite_one','invite_two')")).rows[0].n,1);
});

test('existing PostgreSQL schema supports durable quote reservations and provider ids distinct from internal payment ids',async()=>{
  const internal='checkout_reserved_sql',provider='pi_reserved_sql';
  await db.exec('set role service_role');
  try{
    await db.query("insert into payments(id,provider_intent_id,status,amount,amount_minor,currency,livemode,checkout_token_hash) values($1,null,'new',9023,902300,'MNT',true,$2)",[internal,'c'.repeat(64)]);
    const bound=await db.query('update payments set provider_intent_id=$2 where id=$1 and provider_intent_id is null returning id',[internal,provider]);
    assert.equal(bound.rows.length,1);
    const conflict=await db.query('update payments set provider_intent_id=$2 where id=$1 and provider_intent_id is null returning id',[internal,'pi_different']);
    assert.equal(conflict.rows.length,0,'provider binding cannot overwrite an established linkage');
    const saved=await reconcile(internal,remote(provider,{amount:902300}));
    assert.equal(saved.id,internal);assert.equal(saved.provider_intent_id,provider);assert.equal(saved.amount,9023);assert.equal(saved.status,'succeeded');
    const code=(await db.query('select payment_id from access_codes where code=$1',[saved.code])).rows[0];
    assert.equal(code.payment_id,internal);
    await assert.rejects(reconcile(internal,remote(internal,{amount:902300})),/mismatch/);
    const replay=await reconcile(internal,remote(provider,{amount:902300,status:'requires_action'}));
    assert.equal(replay.status,'succeeded');assert.equal(replay.code,saved.code);
  }finally{await db.exec('reset role');}
});
