import { env } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { getBillingStatus, handleBillingRequest, type BillingEnvironment } from '../src/billing';
import { PairService, pairTokenHash } from '../src/pair';
type Json = Record<string, unknown>;
const command = () => crypto.randomUUID();
const settings = (): BillingEnvironment => ({ ...env, BILLING_ENABLED: 'true', BILLING_WEB_ENABLED: 'true', BILLING_WIRE_MODE: 'live', WIRE_API_KEY: 'sk_live_local_fixture', WIRE_WEBHOOK_SECRET: 'whsec_local_fixture' });
async function user(verified = true) {
  const id = command();
  await env.DB.prepare('INSERT INTO "user"(id,name,email,emailVerified,createdAt,updatedAt) VALUES(?,?,?,?,?,?)').bind(id,'Ану',`${id}@test.example`,Number(verified),Date.now(),Date.now()).run();
  await new PairService(env.DB).status(id);
  return id;
}
async function call(path: string, actor: string|null, body: Json|null=null, config=settings(), origin='https://auth.test') {
  const response = (await handleBillingRequest(new Request(`https://auth.test/v1/billing/${path}`, {method:body ? 'POST':'GET', headers:{Origin:origin}, ...(body ? {body:JSON.stringify(body)}:{})}),config,actor,body))!;
  return {status:response.status,data:await response.json() as Json};
}
async function event(value: Json, age=0, secret=settings().WIRE_WEBHOOK_SECRET!) {
  const raw=JSON.stringify(value); const t=Math.floor(Date.now()/1000)-age;
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const sig=Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(`${t}.${raw}`))),(v)=>v.toString(16).padStart(2,'0')).join('');
  const response=(await handleBillingRequest(new Request('https://auth.test/v1/billing/wire/webhook',{method:'POST',body:raw,headers:{'WirePayment-Signature':`t=${t},v1=${sig}`}}),settings(),null,null))!;
  return {status:response.status,data:await response.json() as Json};
}
function provider() {
  const intents=new Map<string,Json>();const keys=new Map<string,string>();const calls:Json[]=[];
  let refund=0;let lose=false;
  vi.spyOn(globalThis,'fetch').mockImplementation(async (input,init)=>{
    const url=new URL(String(input));expect(url.origin).toBe('https://api.wire.mn');
    const body=init?.body ? JSON.parse(String(init.body)) as Json:null;const key=new Headers(init?.headers).get('Idempotency-Key');
    calls.push({path:url.pathname,body,key});
    if(url.pathname==='/v1/payment_intents') {
      let id=keys.get(key!);if(!id){id=`pi_${command()}`;keys.set(key!,id);intents.set(id,{...body,id,object:'payment_intent',status:'requires_payment_method',livemode:(body!.allowed_operators as string[])[0]!=='sandbox',expires_at:Math.floor(Date.now()/1000)+600});}
      if(lose){lose=false;throw new TypeError('lost response');}return Response.json(intents.get(id)!);
    }
    if(url.pathname==='/v1/charges') {
      const id=url.searchParams.get('payment_intent')!;const row=intents.get(id)!;
      return Response.json({has_more:false,data:[{id:`ch_${id}`,object:'charge',payment_intent:id,status:'succeeded',amount:row.amount,amount_refunded:refund,livemode:row.livemode,operator:row.livemode?'qpay':'sandbox'}]});
    }
    const row=intents.get(url.pathname.split('/')[3]);if(!row)return new Response(null,{status:404});
    if(url.pathname.endsWith('/confirm')){row.status='requires_action';row.next_action={qr:{image_url:'https://wire.mn/fixture.png'}};}
    return Response.json(row);
  });
  return {intents,calls,setRefund(v:number){refund=v;},lose(){lose=true;},settle(){for(const row of intents.values())row.status='succeeded';}};
}
async function purchase(a:string) {const result=await call('web/checkout',a,{plan:'monthly',command_id:command()});expect(result.status,JSON.stringify(result.data)).toBe(200);return result.data.order as Json;}
afterEach(()=>vi.restoreAllMocks());
describe('billing with real migrated D1',()=>{
  it('stays disabled by default and validates authentication, origin and request fields',async()=>{
    const a=await user();expect((await call('catalog',null,null,{...env})).data).toMatchObject({enabled:false,web:{ready:false}});
    expect((await call('web/checkout',a,{plan:'monthly',command_id:command()},{...env})).status).toBe(503);
    expect((await call('status',null)).status).toBe(401);expect((await call('status',await user(false))).status).toBe(401);
    expect((await call('web/checkout',a,{plan:'monthly',command_id:command()},settings(),'https://evil.test')).status).toBe(403);
    expect((await call('web/checkout',a,{plan:'monthly',command_id:command(),amount:1})).status).toBe(400);
  });
  it('freezes prices before lost responses and safely replays without another invoice',async()=>{
    const api=provider();const a=await user();const cmd=command();api.lose();
    expect((await call('web/checkout',a,{plan:'monthly',command_id:cmd})).status).toBe(502);
    expect(await env.DB.prepare('SELECT amount_minor,provider_id FROM hamtdaa_billing_orders WHERE user_id=?').bind(a).first()).toEqual({amount_minor:990000,provider_id:null});
    expect((await call('web/checkout',a,{plan:'monthly',command_id:cmd})).status).toBe(200);expect(api.intents.size).toBe(1);
    const creates=api.calls.filter(v=>v.path==='/v1/payment_intents');expect(creates[1]).toEqual(creates[0]);
    expect((await call('web/checkout',a,{plan:'yearly',command_id:cmd})).status).toBe(409);
    expect((await call('web/checkout',a,{plan:'yearly',command_id:command()})).data.order).toMatchObject({amount_mnt:79900,duration_days:365,auto_renew:false});
  });
  it('rejects uncertain retries after provider idempotency retention',async()=>{
    const api=provider();const a=await user();const cmd=command();const now=Math.floor(Date.now()/1000)-48*3600;
    await env.DB.prepare(`INSERT INTO hamtdaa_billing_orders(id,user_id,command_id,plan,duration_seconds,amount_minor,livemode,return_url,description,created_at,updated_at) VALUES(?,?,?,'monthly',2592000,990000,1,'https://auth.test/plans','Plus',?,?)`).bind(command(),a,cmd,now,now).run();
    expect((await call('web/checkout',a,{plan:'monthly',command_id:cmd})).status).toBe(409);expect(api.calls).toHaveLength(0);
  });
  it('grants once through concurrent checks and hides orders from outsiders',async()=>{
    const api=provider();const a=await user();const outsider=await user();const order=await purchase(a);
    expect((await call('web/status',outsider,{order_id:order.order_id})).status).toBe(404);api.settle();
    const results=await Promise.all(Array.from({length:4},()=>call('web/status',a,{order_id:order.order_id})));expect(results.every(v=>v.status===200)).toBe(true);
    const grants=await env.DB.prepare('SELECT starts_at,expires_at FROM hamtdaa_billing_grants WHERE user_id=?').bind(a).all<{starts_at:number;expires_at:number}>();expect(grants.results).toHaveLength(1);expect(grants.results[0].expires_at-grants.results[0].starts_at).toBe(30*86400);
    await call('web/status',a,{order_id:order.order_id});expect(await env.DB.prepare('SELECT expires_at FROM hamtdaa_billing_grants WHERE user_id=?').bind(a).first()).toEqual({expires_at:grants.results[0].expires_at});
    expect(await getBillingStatus(settings(),outsider)).toMatchObject({plus_active:false});
  });
  it('rejects amount, mode, metadata and provider identity mismatches',async()=>{
    const api=provider();const a=await user();const order=await purchase(a);api.settle();const row=Array.from(api.intents.values())[0];
    for(const [field,value] of Object.entries({amount:1,livemode:false,metadata:{product:'wrong'},id:'pi_other'})) {const old=row[field];row[field]=value;expect((await call('web/status',a,{order_id:order.order_id})).status).toBe(502);expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:false});row[field]=old;}
  });
  it('checks raw HMAC freshness, refetches provider facts and deduplicates events',async()=>{
    const api=provider();const a=await user();await purchase(a);const id=Array.from(api.intents.keys())[0];
    const value={id:`evt_${command()}`,type:'payment_intent.succeeded',data:{object:{id,status:'succeeded'}}};
    expect((await event(value,301)).status).toBe(400);expect((await event(value,0,'wrong')).status).toBe(400);
    expect((await event(value)).status).toBe(200);expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:false});
    api.settle();const paid={...value,id:`evt_${command()}`};expect((await event(paid)).status).toBe(200);const before=api.calls.length;
    expect((await event(paid)).data).toMatchObject({already_processed:true});expect(api.calls.length).toBe(before);expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:true});
  });
  it('revokes refunds permanently even when a late success arrives',async()=>{
    const api=provider();const a=await user();const order=await purchase(a);api.settle();await call('web/status',a,{order_id:order.order_id});expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:true});
    api.setRefund(990000);expect((await call('web/status',a,{order_id:order.order_id})).data.order).toMatchObject({state:'refunded'});expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:false});
    api.setRefund(0);await call('web/status',a,{order_id:order.order_id});expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:false});
  });
  it('never grants real access for sandbox payments',async()=>{
    const api=provider();const a=await user();const config={...settings(),BILLING_WIRE_MODE:'test',WIRE_API_KEY:'sk_test_local_fixture'};
    const checkout=await call('web/checkout',a,{plan:'monthly',command_id:command()},config);expect(checkout.status).toBe(200);api.settle();const order=checkout.data.order as Json;
    expect((await call('web/status',a,{order_id:order.order_id},config)).status).toBe(200);expect(await getBillingStatus(config,a)).toMatchObject({plus_active:false});
  });
  it('shares with only the active partner and ends sharing immediately after unlink',async()=>{
    const api=provider();const a=await user();const b=await user();const outsider=await user();const service=new PairService(env.DB);
    const token=btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
    const created=await service.execute(a,'hamtdaa_create_pair_invite',{p_command_id:command(),p_token_hash:await pairTokenHash(token)});const invitation=created.invitation as Json;
    const pending=await service.execute(b,'hamtdaa_request_pair',{p_command_id:command(),p_token:token,p_expected_version:invitation.version});const invite=pending.invitation as Json;
    const pair=await service.execute(a,'hamtdaa_confirm_pair',{p_command_id:command(),p_invitation_id:invite.id,p_expected_version:invite.version});expect(pair.ok).toBe(true);
    const order=await purchase(a);api.settle();await call('web/status',a,{order_id:order.order_id});
    expect(await getBillingStatus(settings(),b)).toMatchObject({plus_active:true,source:'partner'});expect(await getBillingStatus(settings(),outsider)).toMatchObject({plus_active:false});
    const result=await service.execute(a,'hamtdaa_unlink_pair',{p_command_id:command(),p_pair_id:pair.pair_id,p_expected_version:pair.version});expect(result.ok,JSON.stringify(result)).toBe(true);
    expect(await getBillingStatus(settings(),b)).toMatchObject({plus_active:false});expect(await getBillingStatus(settings(),a)).toMatchObject({plus_active:true});
  });
});
