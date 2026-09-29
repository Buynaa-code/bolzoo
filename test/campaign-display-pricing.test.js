'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {JSDOM}=require('jsdom');
const campaign=require('../assets/campaign');
const read=file=>fs.readFileSync(path.join(__dirname,'..',file),'utf8');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const end=Date.parse(campaign.PROMOTION_END_AT);
const health=at=>({...campaign.pricing(at),server_time:new Date(at).toISOString()});
const response=data=>({ok:true,json:async()=>data});
async function watch(t,fetch){
  const dom=new JSDOM('',{runScripts:'outside-only',url:'https://bolzoo.test',pretendToBeVisual:true});
  const w=dom.window;await tick();let now=0,sequence=0;const tasks=new Map(),seen=[];
  Object.defineProperty(w.performance,'now',{value:()=>now});w.Date.now=()=>Date.parse('2040-01-01T00:00:00Z');
  w.setTimeout=(fn,delay)=>{const id=++sequence;tasks.set(id,{fn,at:now+delay});return id;};w.clearTimeout=id=>tasks.delete(id);
  w.fetch=fetch;w.eval(read('assets/campaign-pricing.js'));const stop=w.BolzooPricing.watch(data=>seen.push(data));
  t.after(()=>{stop();w.close();});await tick();
  return {w,seen,stop,advance:async ms=>{now+=ms;for(const [id,task]of[...tasks])if(task.at<=now){tasks.delete(id);task.fn();}await tick();}};
}
test('active price expires offline at the server boundary, independently of the device clock',async t=>{
  const b=await watch(t,async()=>response(health(end-1000)));
  assert.equal(b.seen.at(-1).price,9023);b.w.fetch=async()=>{throw Error('offline');};
  await b.advance(999);assert.equal(b.seen.at(-1).price,9023);
  await b.advance(1);assert.equal(b.seen.at(-1).price,9900);assert.equal(b.seen.at(-1).promotion.active,false);
});
test('a hung revalidation never delays expiry or restores a discounted price after expiry',async t=>{
  const b=await watch(t,async()=>response(health(end-2000)));
  let finish;b.w.fetch=()=>new Promise(resolve=>{finish=()=>resolve(response(health(end-2000)));});
  b.w.dispatchEvent(new b.w.Event('pageshow'));await tick();
  await b.advance(2000);assert.equal(b.seen.at(-1).price,9900);
  finish();await tick();assert.equal(b.seen.at(-1).price,9900);assert.ok(!b.seen.slice(1).some(x=>x.price===9023));
});
test('an initially slow health response cannot first display an already expired promotional price',async t=>{
  let finish;const b=await watch(t,()=>new Promise(resolve=>{finish=()=>resolve(response(health(end-1000)));}));
  await b.advance(1500);finish();await tick();
  assert.deepEqual(b.seen.map(x=>x.price),[9900]);
});
test('invalid promotion timing cannot introduce a price that has no enforceable expiry',async t=>{
  const b=await watch(t,async()=>response({...health(end-1000),server_time:'invalid'}));
  assert.equal(b.seen.length,0);
});
test('an existing invoice retains its 9900 amount during a 9023 promotion',async t=>{
  const html=read('pay.html'),dom=new JSDOM(html,{url:'http://localhost/pay.html?intent=pi_existing#payment_token='+('a'.repeat(64)),runScripts:'outside-only'}),w=dom.window;
  t.after(()=>w.close());let update;
  w.BolzooPricing={watch:fn=>{update=fn;fn(health(end-1000));}};
  const invoice={intent_id:'pi_existing',amount:9900,status:'requires_action',mode:'mock',next_action:null,expires_at:'2041-01-01T00:00:00Z'};
  w.fetch=async url=>{assert.match(url,/payment-status/);return {ok:true,status:200,text:async()=>JSON.stringify(invoice)};};
  w.eval([...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1]);await tick();await tick();
  assert.match(w.document.getElementById('priceAmt').textContent,/9.?900/);
  update(health(end-500));assert.match(w.document.getElementById('priceAmt').textContent,/9.?900/);
  assert.equal(w.document.getElementById('regularPriceBlock').hidden,true);assert.equal(w.document.getElementById('promotionNote').hidden,true);
});
