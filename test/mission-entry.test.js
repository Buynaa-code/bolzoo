'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');
const root = path.join(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const tick = () => new Promise(resolve => setTimeout(resolve, 20));

async function createPage(t, {url = 'http://localhost/create.html?idea=movie-and-talk', draft, code = true, createFailures = 0, invites = [], health = {price:9900}} = {}) {
  const errors = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', e => { if (!/Could not parse CSS stylesheet/.test(e.message)) errors.push(e.message); });
  const html = read('create.html');
  const dom = new JSDOM(html, {url, runScripts:'outside-only', pretendToBeVisual:true, virtualConsole:vc});
  const w = dom.window;
  t.after(() => { w.close(); assert.deepEqual(errors, []); });
  w.HTMLElement.prototype.scrollIntoView = function(){};
  w.scrollTo = () => {};
  w.matchMedia = () => ({matches:false,addListener(){},removeListener(){},addEventListener(){},removeEventListener(){}});
  if(draft) w.localStorage.setItem('bolzoo:pending_draft', JSON.stringify(draft));
  if(code)w.localStorage.setItem('bolzoo:pending_code', 'LOV-ABCDEF');
  const published = [];
  w.BolzooAPI = {backendKind:'same-origin',listMyInvites:async()=>invites,validateCode:async()=>({ok:true}),createInvite:async(config,code)=>{
    if(createFailures-- > 0)throw new Error('Холболт тасарлаа.');
    published.push({config,code});return {id:'mission_invite_01',ownerToken:'940837b8-3a70-441b-bf9a-b849ee7bac38'};
  }};
  w.fetch = async url => {assert.equal(url,'/api/health');return {ok:true,json:async()=>health};};
  for(const file of ['utils.js','posters.js','apology-templates.js','date-ideas.js','mission-catalog.js','responses.js','campaign.js']) w.eval(read('assets/'+file));
  w.eval([...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1]);
  await tick();
  return {w,d:w.document,published};
}

test('selected mission survives invitation creation without changing an existing note, theme or purchased code',async t=>{
  const draft={experienceType:'date',askTemplate:'letter',theme:'mint',recipientName:'Номин',senderName:'Бат',customNote:'Өөрийн бичсэн үг.',step:4};
  const {w,d,published}=await createPage(t,{draft});
  assert.equal(d.getElementById('customNote').value,draft.customNote);
  assert.equal(d.getElementById('accessCode').value,'LOV-ABCDEF');
  assert.equal(d.getElementById('missionSelection').hidden,false);
  assert.equal(new URL(w.location.href).searchParams.has('idea'),false);
  const saved=JSON.parse(w.localStorage.getItem('bolzoo:pending_draft'));
  assert.equal(saved.missionIdeaId,'movie-and-talk');
  assert.equal(saved.theme,'mint');
  d.getElementById('generate').click();await tick();
  assert.equal(published.length,1);
  assert.equal(published[0].config.missionIdeaId,'movie-and-talk');
  assert.equal(published[0].code,'LOV-ABCDEF');
  const link=d.getElementById('successPlanLink');
  assert.equal(link.hidden,false);
  assert.equal(link.getAttribute('href'),'date-plan.html?invite=mission_invite_01&idea=movie-and-talk');
  assert.ok(!link.href.includes('940837b8'));
  assert.equal(d.getElementById('successResponseLink').getAttribute('href'),'dashboard.html?invite=mission_invite_01');
});

function input(w,id,value){const field=w.document.getElementById(id);field.value=value;field.dispatchEvent(new w.Event('input',{bubbles:true}));return field;}
const activeStep=d=>Number(d.querySelector('.wizard-step.active').dataset.step);

test('quick template requires only the name and goes directly to final preview with ready content',async t=>{
  const {w,d,published}=await createPage(t,{url:'http://localhost/create.html?idea=movie-and-talk&quick=1',code:false});
  assert.equal(d.body.dataset.quick,'true');assert.equal(activeStep(d),2);
  assert.equal(d.getElementById('quickSteps').hidden,false);
  assert.equal(d.getElementById('quickCustomize').open,false);
  assert.equal(d.querySelector('#askTemplates .on').dataset.askTemplate,'ticket');
  assert.equal(d.querySelector('#themes [aria-pressed="true"]').dataset.theme,'lavender');
  assert.equal(d.querySelectorAll('#missionSelectionSteps li').length,3);
  d.getElementById('continueStep').click();
  await new Promise(resolve=>setTimeout(resolve,80));
  assert.equal(activeStep(d),2);assert.equal(d.activeElement.id,'recipientName');
  assert.equal(d.getElementById('previewModal').hidden,true);
  input(w,'recipientName','Номин');d.getElementById('continueStep').click();
  assert.equal(activeStep(d),5);assert.equal(d.getElementById('previewModal').hidden,false);
  assert.equal(d.getElementById('previewPrimaryCta').dataset.mode,'pay');
  assert.equal(published.length,0);
  const draft=JSON.parse(w.localStorage.getItem('bolzoo:pending_draft'));
  assert.equal(draft.quickFlow,true);assert.equal(draft.step,5);assert.equal(draft.missionIdeaId,'movie-and-talk');
  assert.equal(draft.customNote,w.BolzooMissionCatalog.get('movie-and-talk').inviteNote);
  assert.ok(!w.location.search.includes('quick'));
});

test('quick optional edits and preview edit-return retain personal content and validate a bad map link',async t=>{
  const {w,d}=await createPage(t,{url:'http://localhost/create.html?idea=coffee-questions&quick=1'});
  input(w,'recipientName','Номин');
  d.querySelector('[data-quick-edit="4"]').click();
  input(w,'customNote','Миний өөрийн бичсэн зурвас.');input(w,'locationName','Бидний кафе');
  input(w,'locationUrl','javascript:alert(1)');d.getElementById('continueStep').click();
  await new Promise(resolve=>setTimeout(resolve,80));
  assert.equal(activeStep(d),4);assert.equal(d.activeElement.id,'locationUrl');
  assert.equal(d.getElementById('previewModal').hidden,true);
  input(w,'locationUrl','https://example.com/place');d.getElementById('continueStep').click();
  assert.equal(activeStep(d),5);assert.equal(d.getElementById('previewPrimaryCta').dataset.mode,'publish');
  d.getElementById('editPreview').click();
  assert.equal(activeStep(d),2);assert.equal(d.getElementById('previewModal').hidden,true);
  assert.equal(d.getElementById('customNote').value,'Миний өөрийн бичсэн зурвас.');
  assert.equal(d.getElementById('locationName').value,'Бидний кафе');
  const saved=JSON.parse(w.localStorage.getItem('bolzoo:pending_draft'));
  const restored=await createPage(t,{url:'http://localhost/create.html',draft:saved});
  assert.equal(restored.d.body.dataset.quick,'true');assert.equal(activeStep(restored.d),2);
  assert.equal(restored.d.getElementById('customNote').value,saved.customNote);
});

test('quick payment return publishes the paid snapshot once and ignores incoming template changes',async t=>{
  const draft={experienceType:'date',askTemplate:'letter',theme:'mint',recipientName:'Номин',customNote:'Яг төлсөн зурвас.',missionIdeaId:'coffee-questions',quickFlow:true,step:5};
  const {w,d,published}=await createPage(t,{url:'http://localhost/create.html?idea=movie-and-talk&quick=1#code=LOV-ABCDEF&publish=1',draft});
  await new Promise(resolve=>setTimeout(resolve,430));
  assert.equal(published.length,1);assert.equal(published[0].config.missionIdeaId,'coffee-questions');
  assert.equal(published[0].config.customNote,'Яг төлсөн зурвас.');assert.equal(published[0].config.theme,'mint');
  assert.equal(d.body.dataset.quick,'true');assert.equal(d.getElementById('successModal').hidden,false);
  assert.equal(d.getElementById('successResponseLink').search,'?invite=mission_invite_01');
  assert.ok(!d.getElementById('successResponseLink').href.includes('940837b8'));
});

test('failed quick publishing preserves the paid code and draft for a successful retry',async t=>{
  const draft={experienceType:'date',askTemplate:'letter',theme:'coral',recipientName:'Номин',missionIdeaId:'coffee-questions',quickFlow:true,step:5};
  const {w,d,published}=await createPage(t,{url:'http://localhost/create.html',draft,createFailures:1});
  d.getElementById('generate').click();await tick();
  assert.equal(published.length,0);assert.equal(d.getElementById('successModal').hidden,true);
  assert.equal(w.localStorage.getItem('bolzoo:pending_code'),'LOV-ABCDEF');
  assert.equal(JSON.parse(w.localStorage.getItem('bolzoo:pending_draft')).quickFlow,true);
  d.getElementById('generate').click();await tick();
  assert.equal(published.length,1);assert.equal(published[0].code,'LOV-ABCDEF');
});

test('switching quick ideas preserves custom text and styling, reset exits quick mode',async t=>{
  const draft={experienceType:'date',askTemplate:'dreamy',theme:'sky',recipientName:'Номин',customNote:'Өөрийн зурвасыг хадгална.',missionIdeaId:'coffee-questions',quickFlow:true,step:2};
  const {w,d}=await createPage(t,{url:'http://localhost/create.html?idea=movie-and-talk&quick=1',draft});
  const saved=JSON.parse(w.localStorage.getItem('bolzoo:pending_draft'));
  assert.equal(saved.theme,'sky');assert.equal(saved.askTemplate,'dreamy');assert.equal(saved.customNote,draft.customNote);
  d.getElementById('confirmReset').click();assert.equal(d.body.dataset.quick,'false');assert.equal(d.getElementById('quickSteps').hidden,true);
});

test('homepage picnic shortcut opens the actual picnic mission in the quick flow',async t=>{
  const {w,d}=await createPage(t,{url:'http://localhost/create.html',code:false});
  d.querySelector('[data-date-idea="picnic"]').click();
  const saved=JSON.parse(w.localStorage.getItem('bolzoo:pending_draft'));
  assert.equal(saved.missionIdeaId,'picnic-for-two');assert.equal(saved.quickFlow,true);
  assert.match(d.getElementById('missionSelectionTitle').textContent,/пикник/);
  input(w,'recipientName','Номин');d.getElementById('continueStep').click();
  assert.equal(activeStep(d),5);assert.equal(d.getElementById('previewModal').hidden,false);
});

test('an alternative date response is never celebrated as acceptance on the creator page',async t=>{
  const {d}=await createPage(t,{invites:[{id:'invite_later_01',config:{recipientName:'Номин'},responded_at:'2026-09-21T10:00:00Z',response:{answer:'later',date:'2026 оны 10-р сарын 1',dateISO:'2026-10-01',time:'18:00'}}]});
  assert.ok(!d.getElementById('ownerResponseEntry').classList.contains('accepted'));
  assert.ok(!d.getElementById('ownerResponseTitle').textContent.includes('зөвшөөр'));
  assert.equal(d.getElementById('ownerResponseEntry').search,'?invite=invite_later_01');
});

test('removing an idea clears the draft association without deleting the personal invitation',async t=>{
  const {w,d}=await createPage(t,{draft:{experienceType:'date',askTemplate:'letter',recipientName:'Номин',customNote:'Үгээ хадгална.',missionIdeaId:'coffee-questions'}});
  d.getElementById('removeMissionIdea').click();
  assert.equal(d.getElementById('missionSelection').hidden,true);
  assert.equal(d.getElementById('customNote').value,'Үгээ хадгална.');
  assert.equal(JSON.parse(w.localStorage.getItem('bolzoo:pending_draft')).missionIdeaId,'');
});

test('payment return restores the paid draft idea rather than overriding it from a new query',async t=>{
  const {w,d}=await createPage(t,{url:'http://localhost/create.html?idea=movie-and-talk#code=LOV-ABCDEF',draft:{experienceType:'date',askTemplate:'letter',recipientName:'Номин',missionIdeaId:'coffee-questions',step:5}});
  assert.match(d.getElementById('missionSelectionTitle').textContent,/Кофе/);
  assert.equal(JSON.parse(w.localStorage.getItem('bolzoo:pending_draft')).missionIdeaId,'coffee-questions');
});

test('unknown idea parameters are ignored and an apology draft never publishes a mission association',async t=>{
  const {w,d,published}=await createPage(t,{url:'http://localhost/create.html?idea=constructor',draft:{experienceType:'apology',recipientName:'Номин',apologyIssue:'misunderstanding',apologyTone:'gentle',apologyWhatHappened:'Би буруу ойлгосон.',apologyRegret:'Чамайг гомдоосондоо харамсаж байна.',apologyRepair:'Дараа нь сайн сонсоно.',missionIdeaId:'coffee-questions',step:5}});
  assert.equal(d.getElementById('missionSelection').hidden,true);
  assert.equal(w.document.body.dataset.experience,'apology');
  // Public preview is the actual apology configuration, not a date plan.
  const preview=d.getElementById('preview').src;
  if(preview.includes('#c=')){
    const encoded=new URL(preview).hash.slice(3);
    const cfg=JSON.parse(Buffer.from(decodeURIComponent(encoded),'base64').toString('utf8'));
    assert.equal(cfg.missionIdeaId,undefined);
  }
  assert.equal(published.length,0);
});

test('ticket PNG contains no invented seat and public story strips every private field',async t=>{
  const dom=new JSDOM('<!doctype html>',{runScripts:'outside-only'});t.after(()=>dom.window.close());
  const w=dom.window,drawn=[],downloads=[];
  const ctx=new Proxy({fillText:value=>drawn.push(String(value)),createLinearGradient:()=>({addColorStop(){}}),createRadialGradient:()=>({addColorStop(){}})},{get:(target,key)=>key in target?target[key]:()=>{},set:(target,key,value)=>{target[key]=value;return true;}});
  w.HTMLCanvasElement.prototype.getContext=()=>ctx;w.HTMLCanvasElement.prototype.toDataURL=()=> 'data:image/png;base64,AAAA';
  w.HTMLAnchorElement.prototype.click=function(){downloads.push(this.download);};
  w.eval(read('assets/bolzoo-ticket.js'));
  const privateValues={ticketNo:'PRIVATE-ID-100',time:'19:45',dateText:'2040-05-10',subtitle:'PRIVATE-NAME',locationName:'PRIVATE-LOCATION',locationAddress:'PRIVATE-ADDRESS',kindTicket:'Кофе',statusText:'ХОЁУЛАА ТОХИРЛОО'};
  await w.BolzooTicket.save({...privateValues,mode:'card'});
  assert.ok(drawn.includes('ХОЁУЛАА ТОХИРЛОО'));
  assert.ok(drawn.includes('PRIVATE-LOCATION'));
  assert.ok(!drawn.includes('A5'));
  assert.ok(drawn.some(text=>text.includes('Үйлчилгээний төлбөр, захиалга ороогүй')));
  drawn.length=0;
  await w.BolzooTicket.save({...privateValues,mode:'story'});
  for(const secret of ['PRIVATE-ID-100','19:45','2040-05-10','PRIVATE-NAME','PRIVATE-LOCATION','PRIVATE-ADDRESS']) assert.ok(!drawn.join(' ').includes(secret));
  assert.equal(downloads.at(-1),'bolzoo-story.png');
});

const campaignHealth = {price:9023,regular_price:9900,promotion:{id:'newyear100-2026',active:true,ends_at:'2026-09-23T16:00:00Z'}};
test('campaign invitation metadata survives draft reload, preview and public creation',async t=>{
  const {w,d,published}=await createPage(t,{url:'http://localhost/create.html?idea=coffee-questions&quick=1',health:campaignHealth});
  input(w,'recipientName','Номин');d.getElementById('continueStep').click();
  const draft=JSON.parse(w.localStorage.getItem('bolzoo:pending_draft'));
  assert.equal(draft.campaign,'newyear100-2026');
  const preview=new URL(d.getElementById('previewFull').src);
  const encoded=new URLSearchParams(preview.hash.slice(1)).get('c');
  if(encoded)assert.equal(JSON.parse(decodeURIComponent(escape(w.atob(encoded)))).campaign,'newyear100-2026');
  d.getElementById('generate').click();await tick();
  assert.equal(published[0].config.campaign,'newyear100-2026');
  assert.match(d.getElementById('bloomPrice').textContent,/9,023/);
  const restored=await createPage(t,{url:'http://localhost/create.html',draft,health:{price:9900}});
  restored.d.getElementById('generate').click();await tick();
  assert.equal(restored.published[0].config.campaign,'newyear100-2026');
});
test('campaign never changes an older paid snapshot or marks apology invitations',async t=>{
  const paidDraft={experienceType:'date',askTemplate:'letter',theme:'coral',recipientName:'Номин',step:5};
  const paid=await createPage(t,{url:'http://localhost/create.html#code=LOV-ABCDEF&publish=1',draft:paidDraft,health:campaignHealth});
  await new Promise(resolve=>setTimeout(resolve,430));
  assert.equal(paid.published.length,1);assert.equal(paid.published[0].config.campaign,undefined);
  const apology=await createPage(t,{url:'http://localhost/create.html?mode=apology',health:campaignHealth});
  assert.equal(apology.d.body.dataset.experience,'apology');
  const preview=new URL(apology.d.getElementById('preview').src);
  const encoded=new URLSearchParams(preview.hash.slice(1)).get('c');
  if(encoded)assert.equal(JSON.parse(decodeURIComponent(escape(apology.w.atob(encoded)))).campaign,undefined);
});
