'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('jsdom');
const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const response = (data, status=200) => ({ok:status>=200&&status<300,status,json:async()=>structuredClone(data)});
const pause = () => new Promise(resolve=>setImmediate(resolve));
const base = () => ({id:'plan-123456',invite_id:'invite123',role:'creator',version:1,revision:1,state:'proposed',template_id:'coffee-questions',title:'Кофе ба гурван асуулт',scheduled_at:'2026-10-10T10:30:00Z',location:'Тохирсон кафе',budget:'Хоёр хүн 40,000₮',steps:[{id:'before',text:'Кофегоо сонгоё',outcomes:{}},{id:'together',text:'Хамт ярилцъя',outcomes:{}},{id:'after',text:'Дараагийн санаа',outcomes:{}}],accepted:{creator:null,partner:null},partner_claimed:false,my_memory:'',senderName:'А',recipientName:'Б',claim_expires_at:'2027-10-10T00:00:00Z'});

async function browser(t, opts={}) {
  const page=opts.page||'date-plan';
  const dom=new JSDOM(read(page+'.html'),{url:opts.url||'https://bolzoo.test/date-plan.html?invite=invite123&idea=coffee-questions',runScripts:'outside-only'});
  t.after(()=>dom.window.close());
  const w=dom.window,d=w.document,calls=[];
  w.BolzooAPI={getOwnerToken:()=>opts.owner===false?null:'11111111-1111-4111-8111-111111111111'};
  Object.entries(opts.storage||{}).forEach(([key,value])=>w.localStorage.setItem(key,JSON.stringify(value)));
  w.fetch=async(url,config)=>{const body=config.body?JSON.parse(config.body):null;calls.push({url,config,body});return opts.fetch?opts.fetch(url,config,body,calls):response(base());};
  w.eval(read('assets/mission-catalog.js'));
  if(page==='date-plan')w.eval(read('assets/date-plan-api.js'));
  if(opts.before)opts.before(w);
  w.eval(read('assets/date-plan.js'));
  await pause();await pause();
  return {w,d,calls,click:async id=>{d.getElementById(id).click();await pause();await pause();},submit:async id=>{d.getElementById(id).dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));await pause();await pause();}};
}

test('ideas start with three distinct editorial suggestions and direct quick invitation links', async t=>{
  const {d,calls}=await browser(t,{page:'ideas',url:'https://bolzoo.test/ideas.html'});
  assert.deepEqual([...d.querySelectorAll('.idea-card')].map(x=>x.dataset.ideaId),['coffee-questions','coffee-walk','movie-and-talk']);
  assert.deepEqual([...d.querySelectorAll('[data-idea-preset]')].map(x=>x.textContent),['Богино болзоо','Бүтэн орой','Бага зардлаар','Дотор','Гадаа']);
  assert.equal(d.querySelectorAll('[data-idea-preset][aria-pressed="true"]').length,0);
  assert.equal(d.getElementById('advanced-filters').open,false);
  assert.match(d.querySelector('.site-header a[href="/dashboard.html"]').textContent,/Хариу харах/);
  assert.equal(d.getElementById('idea-detail').hidden,true);
  for(const card of d.querySelectorAll('.idea-card')){
    assert.equal(card.querySelector('.idea-use').textContent,'Энэ загварыг ашиглах');
    assert.equal(card.querySelector('.idea-use').getAttribute('href'),'/create.html?idea='+card.dataset.ideaId+'&quick=1');
  }
  d.querySelector('[data-idea-id="movie-and-talk"] .idea-details-button').click();
  assert.equal(d.querySelector('#idea-detail .button').getAttribute('href'),'/create.html?idea=movie-and-talk&quick=1');
  assert.match(d.querySelector('#idea-detail').textContent,/тасалбараа тусад нь/);
  assert.equal(calls.length,0);
});

test('each quick preset replaces the previous preset with three matching suggestions', async t=>{
  const {w,d}=await browser(t,{page:'ideas',url:'https://bolzoo.test/ideas.html'});
  for(const preset of w.BolzooMissionCatalog.quickPresets){
    d.querySelector('[data-idea-preset="'+preset.id+'"]').click();
    const selected=d.querySelectorAll('[data-idea-preset][aria-pressed="true"]');
    assert.equal(selected.length,1);assert.equal(selected[0].dataset.ideaPreset,preset.id);
    assert.deepEqual([...d.querySelectorAll('.idea-card')].map(x=>x.dataset.ideaId),Array.from(w.BolzooMissionCatalog.getSuggestions(preset.id).slice(0,3),x=>x.id));
  }
  d.querySelector('[data-idea-preset="outdoor"]').click();
  assert.equal(d.querySelectorAll('[data-idea-preset][aria-pressed="true"]').length,0);
  assert.deepEqual([...d.querySelectorAll('.idea-card')].map(x=>x.dataset.ideaId),['coffee-questions','coffee-walk','movie-and-talk']);
});

test('more ideas only adds unseen matching suggestions and stops when exhausted', async t=>{
  const {w,d,click}=await browser(t,{page:'ideas',url:'https://bolzoo.test/ideas.html'});
  for(const preset of ['',...Array.from(w.BolzooMissionCatalog.quickPresets,x=>x.id)]){
    await click('clear-idea-filters');
    if(preset)d.querySelector('[data-idea-preset="'+preset+'"]').click();
    let ids=[...d.querySelectorAll('.idea-card')].map(x=>x.dataset.ideaId);
    let iterations=0;
    while(!d.getElementById('show-more').hidden){
      assert.ok(iterations++<10,'more results must reach an end');
      await click('show-more');
      const next=[...d.querySelectorAll('.idea-card')].map(x=>x.dataset.ideaId);
      assert.ok(next.length>ids.length);assert.deepEqual(next.slice(0,ids.length),ids);
      assert.equal(new Set(next).size,next.length);ids=next;
    }
    assert.equal(ids.length,w.BolzooMissionCatalog.getSuggestions(preset).length);
  }
});

test('advanced constraints can return an honest empty state and a quick preset clears stale filters', async t=>{
  const {w,d,click}=await browser(t,{page:'ideas',url:'https://bolzoo.test/ideas.html'});
  d.querySelector('[data-idea-preset="evening"]').click();
  const form=d.getElementById('idea-filters');form.elements.environment.value='outdoor';form.dispatchEvent(new w.Event('change',{bubbles:true}));
  assert.equal(d.querySelectorAll('.idea-card').length,0);assert.equal(d.getElementById('ideas-empty').hidden,false);assert.equal(d.getElementById('show-more').hidden,true);
  d.querySelector('[data-idea-preset="short"]').click();
  assert.equal(form.elements.environment.value,'');assert.equal(d.querySelectorAll('.idea-card').length,3);assert.equal(d.getElementById('ideas-empty').hidden,true);
  d.querySelector('.idea-details-button').click();assert.equal(d.getElementById('idea-detail').hidden,false);
  await click('clear-idea-filters');assert.equal(d.getElementById('idea-detail').hidden,true);assert.equal(d.querySelectorAll('[data-idea-preset][aria-pressed="true"]').length,0);
});

test('existing invitation context and optional idea deep links retain the plan editor route', async t=>{
  const {d,calls}=await browser(t,{page:'ideas',url:'https://bolzoo.test/ideas.html?invite=invite123&idea=movie-and-talk'});
  assert.equal(d.getElementById('idea-detail').hidden,false);
  assert.match(d.querySelector('.journey-strip').textContent,/Хоёулаа тохирох/);
  assert.equal(d.querySelector('#idea-detail .button').getAttribute('href'),'/date-plan.html?invite=invite123&idea=movie-and-talk');
  for(const card of d.querySelectorAll('.idea-card'))assert.equal(card.querySelector('.idea-use').getAttribute('href'),'/date-plan.html?invite=invite123&idea='+card.dataset.ideaId);
  assert.equal(calls.length,0);
});

test('owner creation errors preserve edits and retry the same operation without an optimistic ticket',async t=>{
  let fail=true;
  const b=await browser(t,{fetch:async(url,config,body)=>{
    if(!body)return response({code:'plan_not_found'},404);
    if(fail)throw new Error('offline');
    return response({...base(),title:body.title,location:body.location});
  }});
  assert.equal(b.d.getElementById('plan-editor').hidden,false);
  b.d.getElementById('plan-title').value='Өөрсдийн кофе';b.d.getElementById('plan-location').value='Миний бичсэн газар';
  await b.submit('plan-form');
  assert.equal(b.d.getElementById('plan-content').hidden,true);
  assert.equal(b.d.getElementById('plan-title').value,'Өөрсдийн кофе');
  assert.match(b.d.getElementById('plan-error').textContent,/Холболт тасарлаа/);
  fail=false;await b.submit('plan-form');
  const posts=b.calls.filter(c=>c.body);
  assert.equal(posts.length,2);assert.equal(posts[0].body.request_id,posts[1].body.request_id);
  assert.equal(posts[0].body.claim_token.length,64);assert.equal(posts[0].body.claim_token,posts[1].body.claim_token);
  assert.equal(b.d.getElementById('plan-content').hidden,false);
  assert.equal(b.d.getElementById('ticket-title').textContent,'Өөрсдийн кофе');
  assert.equal(b.d.getElementById('plan-editor').hidden,true);
});

test('claim capability leaves URL immediately and exchange survives a network failure with the same secrets',async t=>{
  const token='a'.repeat(64);let fail=true;
  const b=await browser(t,{owner:false,url:'https://bolzoo.test/date-plan.html?invite=invite123#join='+token,fetch:async(url,config,body)=>{
    if(fail)throw new Error('offline');
    return response({...base(),role:'partner',partner_claimed:true});
  }});
  assert.equal(b.w.location.hash,'');assert.equal(b.calls.length,0);
  const pending=JSON.parse(b.w.localStorage.getItem('bolzoo:date-plan:join:invite123'));
  assert.equal(pending.claim_token,token);assert.equal(pending.participant_token.length,64);
  assert.equal(b.d.getElementById('plan-access').hidden,false);
  await b.click('claim-plan');fail=false;await b.click('claim-plan');
  assert.equal(b.calls[0].body.request_id,b.calls[1].body.request_id);
  assert.equal(b.calls[0].body.participant_token,b.calls[1].body.participant_token);
  assert.equal(b.calls[0].config.headers.Authorization,undefined);
  assert.equal(b.w.localStorage.getItem('bolzoo:date-plan:join:invite123'),null);
  assert.equal(JSON.parse(b.w.localStorage.getItem('bolzoo:date-plan:participant:invite123')),pending.participant_token);
  assert.equal(b.d.getElementById('plan-content').hidden,false);
  assert.equal(b.d.getElementById('share-plan').hidden,true);
  assert.ok(b.calls.every(c=>!c.url.includes(token)&&!c.url.includes(pending.participant_token)));
});

test('a public invite ID gives neither private plan data nor automatic participant rights',async t=>{
  const b=await browser(t,{owner:false});
  assert.equal(b.calls.length,0);assert.equal(b.d.getElementById('plan-content').hidden,true);
  assert.equal(b.d.getElementById('claim-plan').hidden,true);
  assert.equal(b.d.getElementById('plan-access').hidden,false);
});

test('conflict explicitly reloads latest revision, retains typed proposal and sends the new expected version',async t=>{
  let current=base();let conflict=true;
  const b=await browser(t,{fetch:async(url,config,body)=>{
    if(!body)return response(current);
    if(conflict){current={...current,version:2,revision:2,title:'Нөгөө хүний шинэ санал'};return response({code:'version_conflict'},409);}
    current={...current,...body,version:3,revision:3};return response(current);
  }});
  await b.click('edit-plan');b.d.getElementById('plan-title').value='Миний дуусаагүй засвар';b.d.getElementById('plan-title').dispatchEvent(new b.w.Event('input',{bubbles:true}));
  await b.submit('plan-form');
  assert.equal(b.d.getElementById('reload-conflict').hidden,false);
  assert.equal(b.d.getElementById('plan-title').value,'Миний дуусаагүй засвар');
  const count=b.calls.length;await b.submit('plan-form');assert.equal(b.calls.length,count);
  await b.click('reload-conflict');
  assert.equal(b.d.getElementById('ticket-title').textContent,'Нөгөө хүний шинэ санал');
  assert.equal(b.d.getElementById('plan-title').value,'Миний дуусаагүй засвар');
  conflict=false;await b.submit('plan-form');
  assert.equal(b.calls.at(-1).body.expected_version,2);
  assert.equal(b.calls.at(-1).body.title,'Миний дуусаагүй засвар');
});

test('double acceptance is disabled until the server confirms and binds consent to the exact revision',async t=>{
  let release;
  const b=await browser(t,{fetch:async(url,config,body)=>{
    if(!body)return response(base());
    return new Promise(resolve=>{release=()=>resolve(response({...base(),version:2,accepted:{creator:1,partner:null}}));});
  }});
  b.d.getElementById('accept-plan').click();b.d.getElementById('accept-plan').click();await pause();
  assert.equal(b.calls.filter(c=>c.body).length,1);assert.equal(b.d.getElementById('accept-plan').disabled,true);
  assert.equal(b.calls.at(-1).body.expected_revision,1);assert.equal(b.calls.at(-1).body.expected_version,1);
  assert.match(b.d.getElementById('ticket-consent').textContent,/хүлээж/);
  release();await pause();await pause();
  assert.equal(b.d.getElementById('accept-plan').hidden,true);
  assert.doesNotMatch(b.d.getElementById('ticket-consent').textContent,/Хоёулаа тохирлоо/);
});

test('individual outcomes remain distinct, unfinished dates can end, private memory survives an error',async t=>{
  let current={...base(),state:'in_progress',partner_claimed:true,accepted:{creator:1,partner:1}};let memoryFail=true;
  const b=await browser(t,{fetch:async(url,config,body)=>{
    if(!body)return response(current);
    if(body.action==='outcome'){current.steps[0].outcomes.creator=body.outcome;}
    if(body.action==='end')current.state='ended';
    if(body.action==='memory'){if(memoryFail)throw new Error('offline');current.my_memory=body.text;}
    current.version++;return response(current);
  }});
  b.d.querySelector('[data-step-id="before"][data-outcome="skipped"]').click();await pause();await pause();
  assert.match(b.d.querySelector('.step-status').textContent,/Миний тэмдэглэгээ: Алгассан · Нөгөө хүнийх: Тэмдэглээгүй/);
  await b.click('end-plan');await b.click('confirm-action');
  assert.equal(b.d.getElementById('memory-panel').hidden,false);
  b.d.getElementById('memory-text').value='Зөвхөн миний дурсамж';b.d.getElementById('memory-text').dispatchEvent(new b.w.Event('input',{bubbles:true}));
  await b.submit('memory-form');assert.equal(b.d.getElementById('memory-text').value,'Зөвхөн миний дурсамж');
  await b.click('refresh-plan');assert.equal(b.d.getElementById('memory-text').value,'Зөвхөн миний дурсамж');
  memoryFail=false;await b.submit('memory-form');assert.equal(b.calls.at(-1).body.text,'Зөвхөн миний дурсамж');
  assert.match(b.d.getElementById('plan-message').textContent,/хувийн тэмдэглэл хадгалагдлаа/);
});

test('story export receives no names, time, location, ID or capabilities',async t=>{
  const downloads=[];
  const b=await browser(t,{fetch:async()=>response({...base(),state:'agreed',accepted:{creator:1,partner:1}}),before:w=>{w.BolzooTicket={save:async data=>downloads.push(data)};}});
  await b.click('download-story');
  assert.deepEqual(Object.keys(downloads[0]).sort(),['mode','statusText']);
  await b.click('download-ticket');
  assert.equal(downloads[1].locationName,'Тохирсон кафе');
  assert.equal(downloads[1].time,'18:30 · УБ');
  assert.doesNotMatch(JSON.stringify(downloads),/claim_token|participant_token|owner_token|Суудал/);
});

test('dates and ticket exports use unambiguous Ulaanbaatar numeric time without depending on browser locale support',async t=>{
  const downloads=[];
  const b=await browser(t,{fetch:async()=>response({...base(),scheduled_at:'2026-12-31T16:05:00Z',state:'agreed',accepted:{creator:1,partner:1}}),before:w=>{
    w.Intl.DateTimeFormat=function(){throw new Error('Mongolian locale unavailable');};
    w.BolzooTicket={save:async data=>downloads.push(data)};
  }});
  assert.equal(b.d.getElementById('ticket-time').textContent,'2027.01.01 · 00:05 · УБ');
  await b.click('edit-plan');assert.equal(b.d.getElementById('plan-time').value,'2027-01-01T00:05');
  await b.click('download-ticket');
  assert.equal(downloads[0].dateText,'2027 оны 1 сарын 1');
  assert.equal(downloads[0].dateDots,'2027.01.01');
  assert.equal(downloads[0].time,'00:05 · УБ');
});

test('regenerating a join link asks explicitly and persists its new secret before sending, retrying identically',async t=>{
  let fail=true;let persisted;
  const b=await browser(t,{storage:{'bolzoo:date-plan:claim:invite123':'b'.repeat(64)},fetch:async(url,config,body)=>{
    if(!body)return response(base());
    if(fail)throw new Error('offline');
    return response({...base(),version:2});
  }});
  await b.click('rotate-claim');assert.match(b.d.getElementById('confirm-copy').textContent,/өмнөх оролцогчийн эрх, зөвшөөрөл цуцлагдана/);
  assert.equal(b.calls.filter(c=>c.body).length,0);
  await b.click('confirm-action');persisted=JSON.parse(b.w.localStorage.getItem('bolzoo:date-plan:rotation:invite123'));
  assert.equal(persisted.claim_token,b.calls.at(-1).body.claim_token);
  assert.equal(b.w.BolzooDatePlanAPI.joinLink('invite123'),null);
  fail=false;await b.click('confirm-action');
  assert.equal(b.calls.at(-1).body.request_id,persisted.request_id);
  assert.equal(JSON.parse(b.w.localStorage.getItem('bolzoo:date-plan:claim:invite123')),persisted.claim_token);
  assert.match(b.w.BolzooDatePlanAPI.joinLink('invite123'),new RegExp('#join='+persisted.claim_token+'$'));
});
