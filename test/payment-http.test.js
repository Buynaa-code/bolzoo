'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
const crypto=require('node:crypto');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawn}=require('node:child_process');
const campaign=require('../assets/campaign');
async function start(t,env={}){
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bolzoo-http-'));
  const child=spawn(process.execPath,['server.js'],{cwd:path.join(__dirname,'..'),env:{PATH:process.env.PATH,PORT:'0',HOST:'127.0.0.1',BOLZOO_DATA_DIR:dir,WIRE_API_KEY:'',ALLOW_MOCK_PAYMENT:'0',PRICE_MNT:'9900',...env},stdio:['ignore','pipe','pipe']});
  t.after(async()=>{child.kill();await new Promise(r=>child.exitCode!==null?r():child.once('exit',r));fs.rmSync(dir,{recursive:true,force:true});});
  const origin=await new Promise((resolve,reject)=>{
    let output='';const timer=setTimeout(()=>reject(new Error('Server startup timeout: '+output)),10000);
    child.stdout.on('data',chunk=>{output+=chunk;const match=output.match(/Create page\s+:\s+(http:\/\/[^/]+)/);if(match){clearTimeout(timer);resolve(match[1]);}});
    child.stderr.on('data',chunk=>{output+=chunk;});child.once('exit',code=>{clearTimeout(timer);reject(new Error('Server exited '+code+': '+output));});
  });
  return {origin,dir};
}
async function request(origin,route,body,token){
  const r=await fetch(origin+route,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  return {status:r.status,headers:r.headers,body:await r.json()};
}
const newToken=()=>Date.now()+'-'+crypto.randomBytes(32).toString('hex');
test('real local HTTP checkout → mock payment → publish → retry/recover uses one code',async t=>{
  const {origin}=await start(t,{ALLOW_MOCK_PAYMENT:'1'}),token=newToken();
  const payment=await request(origin,'/api/checkout',{checkout_token:token,from:'create'});
  assert.equal(payment.status,200);assert.equal(payment.body.amount,campaign.pricing(Date.now()).price);assert.equal(payment.headers.get('cache-control'),'no-store');
  const id=payment.body.intent_id;
  assert.equal((await request(origin,'/api/payment-status?id='+id)).status,403);
  assert.equal((await request(origin,'/api/dev-mark-paid',{intent_id:id},token)).status,200);
  const paid=(await request(origin,'/api/payment-status?id='+id,undefined,token)).body;
  assert.equal(paid.status,'succeeded');assert.match(paid.code,/^LOV-/);
  const publish={p_invite_id:'invite_test_1',p_config:{recipientName:'Номин'},p_access_code:paid.code,p_private_config:{}};
  const first=await request(origin,'/rest/v1/rpc/create_invite_with_code',publish);
  assert.equal(first.status,200);
  const retry=await request(origin,'/rest/v1/rpc/create_invite_with_code',publish);
  assert.deepEqual(retry.body,first.body);
  assert.equal((await request(origin,'/rest/v1/rpc/create_invite_with_code',{...publish,p_invite_id:'invite_test_2'})).status,400);
  const recovery=await request(origin,'/api/recover-invite',{code:paid.code});
  assert.equal(recovery.body.id,'invite_test_1');
  assert.equal((await request(origin,'/api/checkout',{checkout_token:token})).body.code,paid.code);
});
test('mock checkout is disabled by default and in production even when flag is set',async t=>{
  for(const env of [{},{ALLOW_MOCK_PAYMENT:'1',NODE_ENV:'production'}]){
    const {origin}=await start(t,env);
    assert.equal((await request(origin,'/api/checkout',{checkout_token:newToken()})).status,503);
    assert.equal((await request(origin,'/api/dev-mark-paid',{intent_id:'anything'})).status,403);
  }
});
test('real HTTP Wire callbacks verify raw bytes, reconcile provider status and reject stale signatures',async t=>{
  const intents=new Map();let confirmURL;
  const gateway=http.createServer(async(req,res)=>{
    const raw=[];for await(const chunk of req)raw.push(chunk);
    const body=JSON.parse(Buffer.concat(raw).toString()||'{}');let pi;
    if(req.url==='/v1/payment_intents'){
      assert.equal(body.amount,campaign.pricing(Date.now()).price*100);assert.deepEqual(body.allowed_operators,['sandbox']);
      pi={id:'pi_http',amount:body.amount,currency:'MNT',livemode:false,status:'requires_payment_method'};intents.set(pi.id,pi);
    }else{
      pi=intents.get('pi_http');
      if(req.url.endsWith('/confirm')){confirmURL=body.return_url;pi.status='requires_action';pi.next_action={qr:{image_url:'https://example.com/qr.png'}};}
    }
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(pi));
  });
  await new Promise(resolve=>gateway.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>gateway.close(resolve)));
  const secret='whsec_only_a_test';
  const {origin}=await start(t,{WIRE_API_KEY:'sk_test_only_a_test',WIRE_API_BASE:'http://127.0.0.1:'+gateway.address().port,WIRE_WEBHOOK_SECRET:secret});
  const token=newToken();const checkout=await request(origin,'/api/checkout',{checkout_token:token,from:'create'});
  assert.equal(checkout.status,200);assert.equal(checkout.body.mode,'test');
  assert.match(checkout.body.intent_id,/^checkout_/);
  assert.notEqual(checkout.body.intent_id,'pi_http');
  assert.equal(new URL(confirmURL).origin,origin);
  assert.equal((await request(origin,'/api/dev-mark-paid',{intent_id:checkout.body.intent_id},token)).status,403);
  const raw='{ "id": "evt_http", "type": "charge.succeeded", "data": {"object":{"id":"ch_http","payment_intent":"pi_http"}} }';
  async function event(timestamp){
    const digest=crypto.createHmac('sha256',secret).update(timestamp+'.'+raw).digest('hex');
    return fetch(origin+'/api/wire-webhook',{method:'POST',headers:{'Content-Type':'application/json','WirePayment-Signature':'t='+timestamp+',v1='+digest},body:raw});
  }
  assert.equal((await event(Math.floor(Date.now()/1000)-301)).status,403);
  intents.get('pi_http').status='succeeded';
  assert.equal((await event(Math.floor(Date.now()/1000))).status,200);
  const paid=(await request(origin,'/api/payment-status?id='+checkout.body.intent_id,undefined,token)).body;
  assert.match(paid.code,/^LOV-/);
  assert.equal((await event(Math.floor(Date.now()/1000))).status,200);
  assert.equal((await request(origin,'/api/payment-status?id='+checkout.body.intent_id,undefined,token)).body.code,paid.code);
});
