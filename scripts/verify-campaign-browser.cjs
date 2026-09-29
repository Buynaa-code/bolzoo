'use strict';
// Isolated browser fixtures only: no real checkout, payment, or social publishing.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawn}=require('node:child_process');
const {chromium}=require(process.env.BOLZOO_PLAYWRIGHT_PATH||'playwright');
const campaign=require('../assets/campaign');
const cwd=path.resolve(__dirname,'..'),artifacts=path.join(cwd,'output/campaign-validation');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bolzoo-campaign-'));
fs.mkdirSync(artifacts,{recursive:true});
fs.writeFileSync(path.join(dir,'access_codes.json'),JSON.stringify({'LOV-ABCDEF':{code:'LOV-ABCDEF',used:false,created_at:new Date().toISOString()}}));
const server=spawn(process.execPath,['server.js'],{cwd,env:{PATH:process.env.PATH,PORT:'0',HOST:'127.0.0.1',BOLZOO_DATA_DIR:dir,WIRE_API_KEY:'',WIRE_WEBHOOK_SECRET:'',ALLOW_MOCK_PAYMENT:'0',YOUTUBE_API_KEY:'',GOOGLE_API_KEY:''},stdio:['ignore','pipe','pipe']});
let browser;const errors=[],checks=[],blockedPayments=[];
const activeAt=Date.parse('2026-09-22T16:00:00Z'),end=Date.parse(campaign.PROMOTION_END_AT);
const health=at=>({ok:true,...campaign.pricing(at),server_time:new Date(at).toISOString()});
async function noOverflow(page,label){const sizes=await page.evaluate(()=>({width:innerWidth,scroll:Math.max(document.documentElement.scrollWidth,document.body.scrollWidth),overflow:[...document.querySelectorAll('body *')].filter(el=>{const box=el.getBoundingClientRect();return box.width&&box.right>innerWidth+1;}).slice(0,8).map(el=>({tag:el.tagName,id:el.id,class:el.className,right:el.getBoundingClientRect().right}))}));assert.ok(sizes.scroll<=sizes.width,label+' '+JSON.stringify(sizes));}
async function capture(page,label,widths=[320,390,1280]){for(const width of widths){await page.setViewportSize({width,height:900});await page.evaluate(()=>document.fonts.ready);await noOverflow(page,label);await page.screenshot({path:path.join(artifacts,label+'-'+width+'.png'),fullPage:true});await noOverflow(page,label);}}
(async()=>{
  const origin=await new Promise((resolve,reject)=>{let output='';const timeout=setTimeout(()=>reject(Error('Server timeout')),15000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Create page\s+:\s+(http:\/\/[^/]+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});server.once('exit',code=>reject(Error('Server exited '+code)));});
  browser=await chromium.launch({headless:true,executablePath:process.env.BOLZOO_CHROME_PATH||undefined,timeout:60000});
  async function contextFor(state,options={}){
    const context=await browser.newContext({viewport:{width:390,height:900},timezoneId:'Asia/Ulaanbaatar',reducedMotion:'reduce',...options});
    context.on('page',page=>page.on('pageerror',error=>errors.push(error.message)));
    await context.route('**/*',route=>{
      const url=new URL(route.request().url());
      if(!route.request().url().startsWith(origin))return route.abort();
      if(url.pathname==='/api/health')return state.offline?route.abort():route.fulfill({json:health(state.at)});
      if(['/api/checkout','/api/dev-mark-paid','/api/cancel-payment'].includes(url.pathname)){blockedPayments.push(url.pathname);return route.abort();}
      if(url.pathname==='/api/payment-status'&&state.invoice)return route.fulfill({json:state.invoice});
      return route.continue();
    });return context;
  }
  const state={at:activeAt},context=await contextFor(state),page=await context.newPage();
  await page.goto(origin+'/ideas.html');await page.locator('[data-campaign-banner]:not([hidden])').waitFor();
  assert.equal(await page.locator('.campaign-current').textContent(),'9,023₮');await capture(page,'ideas-active');
  await page.goto(origin+'/create.html');await page.locator('[data-campaign-banner]:not([hidden])').waitFor();
  await page.waitForFunction(()=>document.querySelector('#bloomPrice').textContent.includes('9,023'));
  await capture(page,'creator-welcome-active');
  await page.goto(origin+'/create.html?idea=coffee-questions&quick=1');await page.locator('#recipientName').waitFor({state:'visible'});
  await page.locator('#recipientName').fill('Саруул');await page.locator('#senderName').fill('Тэмүүлэн');await page.locator('#continueStep').click();
  await page.locator('#previewModal').waitFor({state:'visible'});await page.waitForFunction(()=>document.querySelector('#previewPrimaryCta').textContent.includes('9,023'));
  for(const selector of ['#generate','#previewPrimaryCta','.price-splash-new','#bloomPrice','#welcomePrice'])assert.match(await page.locator(selector).textContent(),/9,023/);
  const previewConfig=await page.locator('#previewFull').getAttribute('src');
  const encoded=new URLSearchParams(new URL(previewConfig,origin).hash.slice(1)).get('c');
  assert.equal(JSON.parse(Buffer.from(encoded,'base64').toString('utf8')).campaign,campaign.ID);
  await capture(page,'creator-preview-active',[390]);await page.locator('#closePreview').click();
  await page.evaluate(()=>localStorage.setItem('bolzoo:pending_code','LOV-ABCDEF'));
  await page.reload();await page.locator('#generate').waitFor({state:'visible'});await page.locator('#generate').click();await page.locator('#successLink').waitFor({state:'visible'});
  const link=await page.locator('#successLink').textContent(),id=new URL(link,origin).searchParams.get('id');assert.ok(id);
  const stored=await page.evaluate(async id=>BolzooAPI.getInvite(id),id);assert.equal(stored.config.campaign,campaign.ID);
  checks.push('preview, draft reload, fixture-code creation and public invite retain campaign metadata');
  await page.goto(origin+'/pay.html?from=create');await page.waitForFunction(()=>document.querySelector('#priceAmt').textContent.replace(/\D/g,'')==='9023');
  assert.equal(await page.locator('#regularPriceBlock').isVisible(),true);await capture(page,'pay-active');
  checks.push('creator payment CTAs and pay display 9023 during promotion');
  state.invoice={intent_id:'pi_campaign_existing',amount:9900,status:'requires_action',mode:'mock',expires_at:'2041-01-01T00:00:00Z',next_action:null};
  await page.goto(origin+'/pay.html?intent=pi_campaign_existing#payment_token='+('a'.repeat(64)));
  await page.locator('#afterStart').waitFor({state:'visible'});assert.equal((await page.locator('#priceAmt').textContent()).replace(/\D/g,''),'9900');
  assert.equal(await page.locator('#regularPriceBlock').isVisible(),false);assert.equal(await page.locator('#promotionNote').isVisible(),false);await capture(page,'pay-existing-invoice',[390]);
  checks.push('existing invoice amount stays 9900 and hides promotional comparison');
  const expired=await contextFor({at:end}),expiredPage=await expired.newPage();
  for(const route of ['ideas','create','pay']){
    await expiredPage.goto(origin+'/'+route+'.html');
    if(route==='pay')await expiredPage.waitForFunction(()=>document.querySelector('#priceAmt').textContent.replace(/\D/g,'')==='9900');
    else if(route==='create')await expiredPage.waitForFunction(()=>document.querySelector('#bloomPrice').textContent.includes('9,900'));
    else await expiredPage.locator('.idea-card').first().waitFor();
    if(route!=='pay')assert.equal(await expiredPage.locator('[data-campaign-banner]').isVisible(),false);
    else{assert.equal(await expiredPage.locator('#regularPriceBlock').isVisible(),false);assert.equal(await expiredPage.locator('#promotionNote').isVisible(),false);}
    await capture(expiredPage,route+'-expired');
  }
  checks.push('expired routes display regular price with no stale banner or comparison; 320/390/1280 fit');
  const boundary={at:end-3000},longContext=await contextFor(boundary),longPage=await longContext.newPage();
  await longContext.addInitScript(()=>{Date.now=()=>Date.parse('2040-01-01T00:00:00Z');});
  await longPage.goto(origin+'/pay.html');await longPage.waitForFunction(()=>document.querySelector('#priceAmt').textContent.replace(/\D/g,'')==='9023');
  boundary.offline=true;await longPage.waitForFunction(()=>document.querySelector('#priceAmt').textContent.replace(/\D/g,'')==='9900',{timeout:6000});
  assert.equal(await longPage.locator('#promotionNote').isVisible(),false);checks.push('long-lived offline tab with skewed device clock expires to 9900');
  const recipient=await contextFor({at:activeAt}),recipientPage=await recipient.newPage();
  await recipient.addInitScript(at=>{const OriginalDate=Date;class FixedDate extends OriginalDate{constructor(...args){super(...(args.length?args:[at]));}static now(){return at;}}window.Date=FixedDate;},activeAt);
  const config={campaign:campaign.ID,experienceType:'date',senderName:'Тэмүүлэн',recipientName:'Саруул',askTemplate:'letter',theme:'coral'};
  await recipientPage.goto(origin+'/bolzoo.html?preview=1#c='+Buffer.from(JSON.stringify(config)).toString('base64url'));
  await recipientPage.locator('#campaignInviteBadge').waitFor({state:'visible'});await capture(recipientPage,'recipient-invitation');
  await recipientPage.locator('#yesBtn').click();await recipientPage.locator('#okBtn').click();
  await recipientPage.locator('#calGrid button:not(:disabled)').last().click();await recipientPage.locator('#kindGrid button').first().click();await recipientPage.locator('#nextBtn').click();
  await recipientPage.locator('#campaignNewYearCard').waitFor({state:'visible'});assert.equal(await recipientPage.locator('#campaignDaysLeft').textContent(),'100');
  assert.equal(await recipientPage.locator('#campaignPreviewNote').isVisible(),true);await capture(recipientPage,'recipient-accepted');
  await recipientPage.locator('#campaignNewYearCard summary').click();await capture(recipientPage,'recipient-ideas-expanded',[320,390]);
  checks.push('recipient 100-day badge, accepted preview and optional ideas fit 320/390/1280');
  assert.deepEqual(blockedPayments,[]);assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(artifacts,'browser-verification.json'),JSON.stringify({passed:true,checks,pageErrors:errors,realPaymentRequests:0},null,2));
  console.log('PASS campaign browser validation: '+checks.join('; '));
})().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();server.kill();await new Promise(resolve=>server.exitCode!==null?resolve():server.once('exit',resolve));fs.rmSync(dir,{recursive:true,force:true});});
