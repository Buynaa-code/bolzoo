'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('jsdom');
const campaign = require('../assets/campaign');
const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
const pause = () => new Promise(resolve => setImmediate(resolve));
const end = Date.parse(campaign.PROMOTION_END_AT);
const activeAt = Date.parse('2026-09-22T04:00:00Z');
function health(at=activeAt, extra={}) { return {...campaign.pricing(at), server_time:new Date(at).toISOString(), ...extra}; }

async function banner(t, opts={}) {
  const dom = new JSDOM(read('ideas.html'), {url:'https://bolzoo.test/ideas.html', runScripts:'outside-only'});
  const w=dom.window, d=w.document;
  await pause();
  let monotonic=0, timerId=0;
  const timers=new Map(), calls=[];
  Object.defineProperty(w.performance,'now',{value:()=>monotonic});
  w.Date.now=()=>Date.parse(opts.deviceTime||'2040-01-01T00:00:00Z');
  w.setTimeout=(callback,delay)=>{const id=++timerId;timers.set(id,{callback,due:monotonic+delay});return id;};
  w.clearTimeout=id=>timers.delete(id);
  w.fetch=async(url,config)=>{
    calls.push({url,config});
    if(opts.fetch)return opts.fetch(url,config,calls);
    return {ok:true,json:async()=>opts.health||health()};
  };
  if(opts.link)d.querySelector('[data-campaign-banner]').setAttribute('data-campaign-link',opts.link);
  w.eval(read('assets/campaign.js'));w.eval(read('assets/campaign-marketing.js'));
  t.after(()=>{w.BolzooCampaignMarketing.destroy();w.close();});
  if(!opts.pending)await w.BolzooCampaignMarketing.refresh();
  return {w,d,calls,host:d.querySelector('[data-campaign-banner]'),advance:async ms=>{
    monotonic+=ms;
    for(const [id,timer] of [...timers])if(timer.due<=monotonic){timers.delete(id);timer.callback();}
    await pause();
  }};
}

test('ideas campaign banner is initially hidden and appears only for the server-confirmed offer', async t=>{
  const document=new JSDOM(read('ideas.html')).window.document;
  assert.equal(document.querySelector('[data-campaign-banner]').hidden,true);
  assert.match(read('ideas.html'),/assets\/campaign\.js/);
  assert.match(read('ideas.html'),/assets\/campaign-marketing\.js/);
  const {host,calls}=await banner(t);
  assert.equal(host.hidden,false);
  assert.match(host.textContent,/100 хоногийн дараа шинэ он/);
  assert.match(host.textContent,/9\/23-ААС ТООЛОХОД/);
  assert.match(host.textContent,/9\/22–9\/23/);
  assert.equal(host.querySelector('.campaign-current').textContent,'9,023₮');
  assert.equal(host.querySelector('.campaign-previous').textContent,'9,900₮');
  assert.equal(host.querySelector('.campaign-cta').getAttribute('href'),'#catalog-heading');
  assert.equal(calls[0].url,'/api/health');assert.equal(calls[0].config.cache,'no-store');
});

test('server time governs the active offer despite a device clock years ahead or behind', async t=>{
  const ahead=await banner(t,{deviceTime:'2040-01-01T00:00:00Z'});
  assert.equal(ahead.host.hidden,false);
  const behind=await banner(t,{deviceTime:'2020-01-01T00:00:00Z',health:health(end)});
  assert.equal(behind.host.hidden,true);assert.equal(behind.host.childElementCount,0);
});

test('offer and price are removed exactly at the exclusive Ulaanbaatar midnight boundary', async t=>{
  const b=await banner(t,{health:health(end-1000)});
  assert.equal(b.host.hidden,false);
  await b.advance(999);assert.equal(b.host.hidden,false);
  await b.advance(1);assert.equal(b.host.hidden,true);assert.equal(b.host.textContent,'');
});

test('an in-flight response cannot show an offer that ended while the request was pending', async t=>{
  let finish;
  const b=await banner(t,{pending:true,fetch:()=>new Promise(resolve=>{finish=()=>resolve({ok:true,json:async()=>health(end-1000)});})});
  await pause();assert.equal(b.host.hidden,true);
  await b.advance(1500);finish();await b.w.BolzooCampaignMarketing.refresh();
  assert.equal(b.host.hidden,true);assert.equal(b.host.childElementCount,0);
});

test('failed or untrusted health data leaves no stale promotional claim', async t=>{
  const b=await banner(t);
  b.w.fetch=async()=>{throw new Error('offline');};
  await b.w.BolzooCampaignMarketing.refresh();assert.equal(b.host.hidden,true);assert.equal(b.host.textContent,'');
  const bad=[
    {...health(),server_time:undefined},
    {...health(),price:9900},
    {...health(),regular_price:0},
    {...health(),promotion:{...health().promotion,active:false}},
    {...health(),promotion:{...health().promotion,id:'another-offer'}},
    {...health(),promotion:{...health().promotion,ends_at:'invalid'}},
    {...health(end),promotion:{...health().promotion,active:true}}
  ];
  for(const data of bad){b.w.fetch=async()=>({ok:true,json:async()=>data});await b.w.BolzooCampaignMarketing.refresh();assert.equal(b.host.hidden,true);}
});

test('restored pages revalidate before showing the campaign and reject unsafe CTA overrides', async t=>{
  const b=await banner(t,{link:'javascript:alert(1)'});
  assert.equal(b.host.querySelector('.campaign-cta').getAttribute('href'),'/ideas.html');
  let finish;
  b.w.fetch=()=>new Promise(resolve=>{finish=()=>resolve({ok:true,json:async()=>health(end)});});
  b.w.dispatchEvent(new b.w.Event('pageshow'));
  assert.equal(b.host.hidden,true);
  await pause();finish();await b.w.BolzooCampaignMarketing.refresh();assert.equal(b.host.hidden,true);
  assert.match(read('assets/campaign-marketing.css'),/body\[data-experience="apology"\] \[data-campaign-banner\]/);
});
