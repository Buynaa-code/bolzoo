'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM, VirtualConsole}=require('jsdom');
const root=path.join(__dirname,'..');
const html=fs.readFileSync(path.join(root,'pay.html'),'utf8');
const script=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
const token=Date.now()+'-'+'a'.repeat(64);
const response=(data,status=200)=>({ok:status<400,status,headers:{get:()=> 'application/json'},text:async()=>JSON.stringify(data),json:async()=>data});
const tick=()=>new Promise(r=>setTimeout(r,10));
const pending={intent_id:'pi_browser',amount:9900,status:'requires_action',mode:'mock',expires_at:new Date(Date.now()+600000).toISOString(),next_action:null,return_to_create:false};
function browser(t,url,fetch,stored){
  const dom=new JSDOM(html,{url,runScripts:'outside-only',virtualConsole:new VirtualConsole()});
  if(stored)dom.window.localStorage.setItem('bolzoo:active_checkout',JSON.stringify(stored));
  dom.window.fetch=async(u,o)=>u==='/api/health'?response({price:9900}):fetch(u,o);
  dom.window.eval(script); t.after(()=>dom.window.close());
  return dom.window;
}
test('double clicks send one request and a lost response retry keeps the same token',async t=>{
  const requests=[]; let first=true;
  const w=browser(t,'http://localhost/pay.html',async(url,opts)=>{
    if(url==='/api/checkout'){
      const body=JSON.parse(opts.body); requests.push(body);
      assert.equal(JSON.parse(w.localStorage.getItem('bolzoo:active_checkout')).token,body.checkout_token);
      if(first){first=false;throw new Error('network lost');}
      return response(pending);
    }
    return response(pending);
  });
  const start=w.document.getElementById('startBtn');
  start.click();start.click();await tick();assert.equal(requests.length,1);
  start.click();await tick();assert.equal(requests.length,2);
  assert.equal(requests[0].checkout_token,requests[1].checkout_token);
  assert.equal(w.location.search,'?intent=pi_browser');
});
test('return from bank restores token, amount, mock UI and create continuation',async t=>{
  let calls=0;
  const w=browser(t,'http://localhost/pay.html?intent=pi_browser#payment_token='+token,async(url,opts)=>{
    assert.match(url,/payment-status/); assert.equal(opts.headers.Authorization,'Bearer '+token);calls++;
    return response({...pending,amount:12300,return_to_create:true});
  });
  await tick(); assert.equal(calls,1);
  assert.match(w.document.getElementById('priceAmt').textContent,/12.?300/);
  assert.equal(w.document.getElementById('devPanel').style.display,'block');
  assert.equal(w.document.getElementById('retryBtn').hidden,true);
});
test('saved attempt without intent id retries checkout automatically using original key',async t=>{
  const calls=[];
  browser(t,'http://localhost/pay.html?from=create',async(url,opts)=>{
    calls.push(url); if(url==='/api/checkout'){assert.equal(JSON.parse(opts.body).checkout_token,token);return response(pending);}
    return response(pending);
  },{token,id:null,from:'create'});
  await tick();assert.equal(calls[0],'/api/checkout');
});
test('successful payment saves code and uses URL fragment to continue publishing',async t=>{
  let statusCalls=0;
  const w=browser(t,'http://localhost/pay.html?from=create&intent=pi_browser#payment_token='+token,async()=>{
    statusCalls++;return response({...pending,status:'succeeded',code:'LOV-ABC234',return_to_create:true});
  });
  await tick();
  assert.equal(w.document.getElementById('codeValue').textContent,'LOV-ABC234');
  assert.equal(w.localStorage.getItem('bolzoo:pending_code'),'LOV-ABC234');
  assert.equal(w.document.getElementById('continueBtn').getAttribute('href'),'create.html#code=LOV-ABC234&publish=1');
  w.document.dispatchEvent(new w.Event('visibilitychange'));await tick();assert.equal(statusCalls,1);
});
test('pending polls do not overlap, transient errors stay visible, and cancellation enables retry',async t=>{
  let resolveStatus, calls=0;
  const w=browser(t,'http://localhost/pay.html?intent=pi_browser#payment_token='+token,async(url)=>{
    if(url==='/api/cancel-payment')return response({...pending,status:'canceled'});
    calls++; if(calls===1)return new Promise(resolve=>{resolveStatus=resolve;});
    return response({...pending,status:'canceled'});
  });
  await tick();w.document.getElementById('checkBtn').click();w.document.dispatchEvent(new w.Event('visibilitychange'));await tick();
  assert.equal(calls,1);
  resolveStatus(response({error:'түр саатал'},503));await tick();
  assert.match(w.document.getElementById('errBox').textContent,/түр саатал/);
  assert.equal(w.document.getElementById('retryBtn').hidden,true);
  w.document.getElementById('cancelBtn').click();await tick();
  assert.equal(w.document.getElementById('retryBtn').hidden,false);
});
test('malicious gateway links and unknown action payloads are not executable or exposed',async t=>{
  const w=browser(t,'http://localhost/pay.html?intent=pi_browser',async()=>response({...pending,next_action:{secret:'private-debug-value',deeplinks:[{name:'bad',link:'javascript://alert(1)'},{name:'bank',link:'khanbank://pay'}]}}));
  await tick();
  assert.equal(w.document.querySelectorAll('a[href^="javascript:"]').length,0);
  assert.equal(w.document.getElementById('actionJson').style.display,'none');
  assert.equal(w.document.getElementById('actionJson').textContent.includes('private-debug-value'),false);
});
test('browser redemption retries reuse the same invite id after a dropped response',async t=>{
  const dom=new JSDOM('',{url:'http://localhost/create.html',runScripts:'outside-only'});t.after(()=>dom.window.close());
  const w=dom.window;w.BOLZOO_CONFIG={};const calls=[];
  w.fetch=async(url,opts)=>{
    const body=JSON.parse(opts.body);calls.push(body);
    if(calls.length===1)throw new Error('response lost');
    return {ok:true,headers:{get:()=> 'application/json'},json:async()=>[{id:body.p_invite_id,owner_token:'owner',created_at:'now'}]};
  };
  w.eval(fs.readFileSync(path.join(root,'assets/api.js'),'utf8'));
  await assert.rejects(w.BolzooAPI.createInvite({recipientName:'Номин'},'LOV-ABC234',{}));
  const created=await w.BolzooAPI.createInvite({recipientName:'Номин'},'LOV-ABC234',{});
  assert.equal(calls[0].p_invite_id,calls[1].p_invite_id);assert.equal(created.id,calls[0].p_invite_id);
});

test('create page restores a paid code from fragment and displays the configured price',async t=>{
  const createHtml=fs.readFileSync(path.join(root,'create.html'),'utf8');
  const dom=new JSDOM(createHtml,{url:'http://localhost/create.html#code=LOV-ABC234&publish=1',runScripts:'outside-only',pretendToBeVisual:true,virtualConsole:new VirtualConsole()});
  t.after(()=>dom.window.close());const w=dom.window;
  w.matchMedia=()=>({matches:false,addListener(){},removeListener(){},addEventListener(){},removeEventListener(){}});
  w.HTMLElement.prototype.scrollIntoView=function(){};w.scrollTo=()=>{};
  w.localStorage.setItem('bolzoo:pending_draft',JSON.stringify({experienceType:'date',recipientName:'Номин',senderName:'Бат',askTemplate:'letter',theme:'coral',step:5}));
  var publishCount=0;
  w.fetch=async(url,opts)=>{
    if(url==='/api/health')return response({price:12300});
    if(url==='/api/validate-code')return response({ok:true});
    if(url==='/rest/v1/rpc/create_invite_with_code'){
      publishCount++; var body=JSON.parse(opts.body); assert.equal(body.p_access_code,'LOV-ABC234');
      return response([{id:body.p_invite_id,owner_token:'ef7d5da0-2f1e-4e6a-b233-1304814b524b',created_at:new Date().toISOString()}]);
    }
    return response([]);
  };
  for(const file of ['utils.js','posters.js','apology-templates.js','api.js'])w.eval(fs.readFileSync(path.join(root,'assets',file),'utf8'));
  const inline=[...createHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
  w.eval(inline);await tick();
  assert.equal(w.document.querySelector('.price-splash-new').textContent,'12,300₮');
  assert.equal(w.document.getElementById('accessCode').value,'LOV-ABC234');
  assert.equal(w.localStorage.getItem('bolzoo:pending_code'),'LOV-ABC234');
  assert.equal(new URLSearchParams(w.location.hash.slice(1)).get('publish'),'1');
  assert.equal(w.location.search.includes('code'),false);
  await new Promise(resolve=>setTimeout(resolve,500));
  assert.equal(publishCount,1);
  assert.equal(w.document.getElementById('successAccessCode').textContent,'LOV-ABC234');
  assert.equal(w.localStorage.getItem('bolzoo:pending_code'),null);
});
