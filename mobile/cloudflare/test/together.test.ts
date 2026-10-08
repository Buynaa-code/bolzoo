import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { PairService, pairTokenHash } from '../src/pair';
import { handleTogetherRequest } from '../src/together';
type Json = Record<string, unknown>;
type Event = { id: string; version: number; status: string; title: string };
type Daily = { day: string; question_id: string; question: string; my_answer: string | null; partner_answer: string | null; both_answered: boolean };
const command = () => crypto.randomUUID();
const month = '2026-10';
const event = { title: 'Хамт алхах', note: 'Цэцэрлэгт хүрээлэнд', location: 'Улаанбаатар', starts_at: '2026-10-15T10:00:00.000Z', ends_at: '2026-10-15T11:00:00.000Z' };
async function user(verified = true) {
  const id = command();
  await env.DB.prepare('INSERT INTO "user"(id,name,email,emailVerified,createdAt,updatedAt) VALUES(?,?,?,?,?,?)').bind(id, 'Нэр', `${id}@example.test`, Number(verified), Date.now(), Date.now()).run();
  await new PairService(env.DB).status(id);
  return id;
}
async function link(a: string, b: string) {
  const pair = new PairService(env.DB);
  const token = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
  const created = await pair.execute(a, 'hamtdaa_create_pair_invite', { p_command_id: command(), p_token_hash: await pairTokenHash(token) });
  const invite = created.invitation as {id:string;version:number};
  const requested = await pair.execute(b, 'hamtdaa_request_pair', {p_command_id: command(),p_token: token,p_expected_version: invite.version});
  const pending = requested.invitation as {id:string;version:number};
  const confirmed = await pair.execute(a,'hamtdaa_confirm_pair',{p_command_id:command(),p_invitation_id:pending.id,p_expected_version:pending.version});
  expect(confirmed.ok).toBe(true);
  return confirmed.pair_id as string;
}
async function fixture() { const a=await user(),b=await user();return {a,b,pair:await link(a,b)}; }
async function call(actor: string, path: string, body: Json, db=env.DB) {
  const response=await handleTogetherRequest(new Request('https://auth.test/v1/together/'+path,{method:'POST'}),{DB:db},actor,body);
  return {status:response.status,data:await response.json() as Json};
}
const state = (actor:string) => call(actor,'state',{month});
const create = (actor:string,pair:string,changes:Json={}) => call(actor,'calendar/create',{command_id:command(),expected_pair_id:pair,...event,...changes});
async function events(actor:string) { return (await state(actor)).data.events as Event[]; }
async function daily(actor:string) { return (await state(actor)).data.daily as Daily; }
const answer = (actor:string,pair:string,question:string,value='Миний хариулт',commandId=command()) => call(actor,'daily/answer',{command_id:commandId,expected_pair_id:pair,question_id:question,answer:value});
async function unlink(actor:string,pair:string) {
  const result=await new PairService(env.DB).execute(actor,'hamtdaa_unlink_pair',{p_command_id:command(),p_pair_id:pair,p_expected_version:1});
  expect(result.ok).toBe(true);
}
async function scalar(sql:string,...args:(string|number)[]) { return (await env.DB.prepare(sql).bind(...args).first<{n:number}>())!.n; }

describe('Together on migrated D1',()=>{
 it('returns honest empty unpaired state and requires verified active profiles',async()=>{
  const a=await user();
  expect((await state(a)).data).toMatchObject({ok:true,paired:false,pair_id:null,partner:null,events:[],daily:null});
  expect((await call(a,'daily/history',{})).data).toEqual({ok:true,entries:[],next_before_day:null});
  for(const actor of [command(),await user(false)]) expect((await state(actor)).status).toBe(401);
  await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(a).run();
  expect((await state(a)).status).toBe(401);
 });
 it('shares created events, restricts author edits, lets partner respond and resets consent after edits',async()=>{
  const {a,b,pair}=await fixture();
  expect((await create(a,pair)).data).toEqual({ok:true});
  const first=(await events(b))[0];
  expect(first).toMatchObject({title:event.title,status:'pending',version:1,creator_id:a});
  const response={command_id:command(),expected_pair_id:pair,id:first.id,expected_version:1,response:'accepted'};
  expect((await call(a,'calendar/respond',response)).status).toBe(403);
  expect((await call(b,'calendar/respond',response)).status).toBe(200);
  expect((await call(b,'calendar/update',{command_id:command(),expected_pair_id:pair,id:first.id,expected_version:2,...event})).status).toBe(403);
  expect((await call(a,'calendar/update',{command_id:command(),expected_pair_id:pair,id:first.id,expected_version:2,...event,title:'Шинэ газар'})).status).toBe(200);
  expect((await events(b))[0]).toMatchObject({status:'pending',version:3,title:'Шинэ газар'});
  expect((await call(b,'calendar/respond',{...response,command_id:command(),expected_version:2})).data.code).toBe('conflict');
  expect((await call(b,'calendar/delete',{command_id:command(),expected_pair_id:pair,id:first.id,expected_version:3})).status).toBe(403);
  const deletion={command_id:command(),expected_pair_id:pair,id:first.id,expected_version:3};
  expect((await call(a,'calendar/delete',deletion)).status).toBe(200);
  expect((await call(a,'calendar/delete',deletion)).status).toBe(200);
  expect(await events(a)).toEqual([]);
 });
 it('resolves month boundaries in Ulaanbaatar and includes overlapping events',async()=>{
  const {a,pair}=await fixture();
  await create(a,pair,{title:'October starts',starts_at:'2026-09-30T16:00:00Z',ends_at:null});
  await create(a,pair,{title:'Before October',starts_at:'2026-09-30T15:59:59Z',ends_at:null});
  await create(a,pair,{title:'Overlap',starts_at:'2026-09-30T15:00:00Z',ends_at:'2026-09-30T17:00:00Z'});
  await create(a,pair,{title:'November starts',starts_at:'2026-10-31T16:00:00Z',ends_at:null});
  expect((await events(a)).map(e=>e.title)).toEqual(['Overlap','October starts']);
 });
 it('rejects invalid, oversized and unknown fields and invalid calendar dates',async()=>{
  const {a,pair}=await fixture();
  for(const changes of [{title:''},{title:'x'.repeat(121)},{note:'x'.repeat(2001)},{location:'x'.repeat(201)},{title:'bad\0title'},
   {starts_at:'2026-02-30T10:00:00Z'},{starts_at:'2026-10-15T10:00:00+08:00'},{ends_at:event.starts_at},{ends_at:'2027-01-01T10:00:00Z'},
   {pair_id:pair},{command_id:'invalid'},{expected_pair_id:'invalid'}]) expect((await create(a,pair,changes)).status).toBe(400);
  expect((await call(a,'state',{month:'2026-13'})).status).toBe(400);
  expect((await call(a,'daily/history',{before_day:'2026-02-30'})).status).toBe(400);
  expect((await call(a,'state',{month,pair_id:pair})).status).toBe(400);
  expect(await events(a)).toEqual([]);
 });
 it('binds idempotency to actor, pair, operation and complete payload; concurrent duplicates save once',async()=>{
  const {a,b,pair}=await fixture();
  const payload={command_id:command(),expected_pair_id:pair,...event};
  const results=await Promise.all([call(a,'calendar/create',payload),call(a,'calendar/create',payload)]);
  expect(results.map(r=>r.status)).toEqual([200,200]);
  expect((await events(a)).length).toBe(1);
  expect((await call(a,'calendar/create',{...payload,title:'Different'})).data.code).toBe('idempotency_mismatch');
  expect((await call(b,'calendar/create',payload)).status).toBe(200);
  expect((await events(a)).length).toBe(2);
  expect(await scalar('SELECT mutations n FROM hamtdaa_together_quotas WHERE user_id=?',a)).toBe(1);
 });
 it('competing versions atomically save one change and roll back loser receipt and quota',async()=>{
  const {a,b,pair}=await fixture();await create(a,pair);const e=(await events(a))[0];
  const results=await Promise.all(['accepted','declined'].map(response=>call(b,'calendar/respond',{command_id:command(),expected_pair_id:pair,id:e.id,expected_version:1,response})));
  expect(results.map(r=>r.status).sort()).toEqual([200,409]);
  expect((await events(a))[0].version).toBe(2);
  expect(await scalar('SELECT count(*) n FROM hamtdaa_together_receipts WHERE user_id=?',b)).toBe(1);
  expect(await scalar('SELECT mutations n FROM hamtdaa_together_quotas WHERE user_id=?',b)).toBe(1);
  expect(await scalar('SELECT count(*) n FROM hamtdaa_together_guards')).toBe(0);
 });
 it('keeps partner answers hidden in state/history until both answer, then permanently locks submitted answers',async()=>{
  const {a,b,pair}=await fixture();const question=await daily(a);
  expect(question.day).toBe(new Date(Date.now()+8*3600000).toISOString().slice(0,10));
  expect(question.question.length).toBeGreaterThan(10);
  const cmd=command();expect((await answer(a,pair,question.question_id,'Нууц хариулт',cmd)).status).toBe(200);
  expect(await daily(a)).toMatchObject({my_answer:'Нууц хариулт',partner_answer:null,both_answered:false});
  expect(await daily(b)).toMatchObject({my_answer:null,partner_answer:null,both_answered:false});
  expect(JSON.stringify((await call(b,'daily/history',{})).data)).not.toContain('Нууц хариулт');
  expect((await answer(b,pair,question.question_id,'Хамтдаа ярилцъя')).status).toBe(200);
  expect(await daily(b)).toMatchObject({my_answer:'Хамтдаа ярилцъя',partner_answer:'Нууц хариулт',both_answered:true});
  expect((await answer(a,pair,question.question_id,'Нууц хариулт',cmd)).status).toBe(200);
  expect((await answer(a,pair,question.question_id,'Өөр хариулт')).data.code).toBe('answer_locked');
  expect((await call(a,'daily/history',{})).data.entries).toMatchObject([{my_answer:'Нууц хариулт',partner_answer:'Хамтдаа ярилцъя',both_answered:true}]);
  await expect(env.DB.prepare('UPDATE hamtdaa_daily_answers SET answer=? WHERE pair_id=?').bind('rewrite',pair).run()).rejects.toThrow(/immutable/);
 });
 it('prevents simultaneous conflicting answers and rejects expired or invalid answers',async()=>{
  const {a,pair}=await fixture();const q=await daily(a);
  expect((await answer(a,pair,'dq-v1:2000-01-01:1')).data.code).toBe('question_expired');
  expect((await answer(a,pair,q.question_id,' ')).status).toBe(400);
  expect((await answer(a,pair,q.question_id,'x'.repeat(2001))).status).toBe(400);
  const results=await Promise.all([answer(a,pair,q.question_id,'Нэг'),answer(a,pair,q.question_id,'Хоёр')]);
  expect(results.map(r=>r.status).sort()).toEqual([200,409]);
  expect(await scalar('SELECT count(*) n FROM hamtdaa_daily_answers WHERE pair_id=?',pair)).toBe(1);
 });
 it('never exposes records to outsiders, inactive partners or blocked pairs',async()=>{
  const {a,b,pair}=await fixture();const other=await fixture();await create(a,pair);
  const e=(await events(a))[0];await answer(a,pair,(await daily(a)).question_id,'Private');
  expect((await call(other.a,'calendar/respond',{command_id:command(),expected_pair_id:other.pair,id:e.id,expected_version:1,response:'accepted'})).status).toBe(404);
  expect(JSON.stringify((await state(other.a)).data)).not.toContain(e.id);
  await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id=?").bind(b).run();
  expect((await state(a)).data).toMatchObject({paired:false,events:[],daily:null});
  expect((await call(a,'daily/history',{})).data.entries).toEqual([]);
  expect((await create(a,pair)).data.code).toBe('pair_required');
  await env.DB.prepare("UPDATE hamtdaa_profiles SET account_state='active' WHERE user_id=?").bind(b).run();
  await env.DB.prepare('INSERT INTO hamtdaa_blocks(blocker_id,blocked_id) VALUES(?,?)').bind(a,b).run();
  expect((await state(a)).data.paired).toBe(false);
 });
 it('isolates prior pair records and retries after unlink and after linking another partner',async()=>{
  const {a,b,pair}=await fixture();const payload={command_id:command(),expected_pair_id:pair,...event};
  await call(a,'calendar/create',payload);const q=await daily(a);await answer(a,pair,q.question_id,'Old pair');
  await unlink(a,pair);
  expect((await state(b)).data).toMatchObject({paired:false,events:[],daily:null});
  expect((await call(a,'calendar/create',payload)).data.code).toBe('pair_required');
  const c=await user(),next=await link(a,c);
  expect((await call(a,'calendar/create',payload)).data.code).toBe('pair_required');
  expect((await create(a,pair)).data.code).toBe('pair_changed');
  expect(await events(a)).toEqual([]);
  expect((await call(a,'daily/history',{})).data.entries).toEqual([]);
  expect((await answer(a,next,(await daily(a)).question_id,'New pair')).status).toBe(200);
  expect((await daily(c)).partner_answer).toBeNull();
 });
 it('rechecks membership inside the mutation transaction when unlink wins the race',async()=>{
  const {a,pair}=await fixture();let intercepted=false;
  const db=new Proxy(env.DB,{get(target,key){
   if(key==='batch')return async (statements:D1PreparedStatement[])=>{
    if(!intercepted){intercepted=true;await unlink(a,pair);}
    return target.batch(statements);
   };
   const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;
  }});
  const result=await call(a,'calendar/create',{command_id:command(),expected_pair_id:pair,...event},db);
  expect(result.status).toBe(409);
  expect(await scalar('SELECT count(*) n FROM hamtdaa_calendar_events WHERE pair_id=?',pair)).toBe(0);
  expect(await scalar('SELECT count(*) n FROM hamtdaa_together_receipts WHERE user_id=?',a)).toBe(0);
 });
 it('paginates 30 daily history entries without leaking an unanswered partner response',async()=>{
  const {a,b,pair}=await fixture();
  await env.DB.prepare(`WITH RECURSIVE days(n) AS(SELECT 1 UNION ALL SELECT n+1 FROM days WHERE n<35)
   INSERT INTO hamtdaa_daily_answers(pair_id,day,user_id,question_id,answer,created_at)
   SELECT ?,date('now','+8 hours','-'||n||' days'),?,'seed','Partner secret',0 FROM days`).bind(pair,b).run();
  const first=(await call(a,'daily/history',{})).data;
  expect((first.entries as Daily[]).length).toBe(30);
  expect(JSON.stringify(first)).not.toContain('Partner secret');
  const next=(await call(a,'daily/history',{before_day:first.next_before_day})).data;
  expect((next.entries as Daily[]).length).toBe(5);expect(next.next_before_day).toBeNull();
  expect((first.entries as Daily[]).at(-1)!.day).toBe(first.next_before_day);
 });
 it('enforces daily write/create quotas and pair event capacity without consuming rejected command receipts',async()=>{
  const {a,pair}=await fixture();const date=(await daily(a)).day;
  await env.DB.prepare('INSERT INTO hamtdaa_together_quotas(user_id,day,mutations) VALUES(?,?,100)').bind(a,date).run();
  expect((await create(a,pair)).status).toBe(429);
  await env.DB.prepare('DELETE FROM hamtdaa_together_quotas WHERE user_id=?').bind(a).run();
  await env.DB.prepare(`WITH RECURSIVE n(x) AS(SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<30)
   INSERT INTO hamtdaa_together_receipts(user_id,command_id,pair_id,payload_hash,operation,day,created_at)
   SELECT ?,'seed-'||x,?,printf('%064d',0),'calendar/create',?,0 FROM n`).bind(a,pair,date).run();
  expect((await create(a,pair)).status).toBe(429);
  await env.DB.prepare('DELETE FROM hamtdaa_together_receipts WHERE user_id=?').bind(a).run();
  await env.DB.prepare(`WITH RECURSIVE n(x) AS(SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<500)
   INSERT INTO hamtdaa_calendar_events(id,pair_id,creator_id,title,starts_at,created_at,updated_at)
   SELECT ?||x,?,?,'seed',0,0,0 FROM n`).bind(command(),pair,a).run();
  expect((await create(a,pair)).status).toBe(429);
  expect(await scalar('SELECT count(*) n FROM hamtdaa_together_receipts WHERE user_id=?',a)).toBe(0);
 });
});
