'use strict';
// Uses temporary local fixtures only. No real payment or external messages.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawn}=require('node:child_process');
const {chromium}=require(process.env.BOLZOO_PLAYWRIGHT_PATH||'playwright');
const cwd=path.resolve(__dirname,'..');
const artifacts=path.join(cwd,'output/simple-flow-validation');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bolzoo-simple-flow-'));
fs.mkdirSync(artifacts,{recursive:true});
fs.writeFileSync(path.join(dir,'access_codes.json'),JSON.stringify({'LOV-ABCDEF':{code:'LOV-ABCDEF',used:false,created_at:new Date().toISOString()}}));
const server=spawn(process.execPath,['server.js'],{cwd,env:{PATH:process.env.PATH,PORT:'0',HOST:'127.0.0.1',BOLZOO_DATA_DIR:dir,WIRE_API_KEY:'',WIRE_WEBHOOK_SECRET:'',ALLOW_MOCK_PAYMENT:'0',YOUTUBE_API_KEY:'',GOOGLE_API_KEY:''},stdio:['ignore','pipe','pipe']});
let browser;
const errors=[];
async function noOverflow(page){const sizes=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));assert.ok(sizes.scroll<=sizes.width,JSON.stringify(sizes));}
async function settled(page,selector){await page.locator(selector).first().waitFor({state:'visible'});await page.waitForFunction(()=>!document.querySelector('[aria-busy="true"]'));}
(async()=>{
  const origin=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Server startup timeout')),15000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Create page\s+:\s+(http:\/\/[^/]+)/);if(match){clearTimeout(timer);resolve(match[1]);}});server.once('exit',code=>reject(Error('Server exited '+code)));});
  browser=await chromium.launch({headless:true,executablePath:process.env.BOLZOO_CHROME_PATH||undefined,timeout:60000});
  const owner=await browser.newContext({viewport:{width:1280,height:900},timezoneId:'UTC',acceptDownloads:true});
  const recipient=await browser.newContext({viewport:{width:390,height:844},timezoneId:'America/Los_Angeles'});
  for(const context of [owner,recipient]){await context.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());context.on('page',p=>p.on('pageerror',e=>errors.push(e.message)));}
  const page=await owner.newPage();
  const partner=await recipient.newPage();
  await page.goto(origin+'/ideas.html');await settled(page,'.idea-use');
  assert.equal(await page.locator('.idea-card').count(),3);
  assert.equal(await page.locator('#advanced-filters').getAttribute('open'),null);
  const presets=await page.locator('[data-idea-preset]').evaluateAll(nodes=>nodes.map(node=>({id:node.dataset.ideaPreset,label:node.textContent})));
  assert.equal(presets.length,5);
  for(const preset of presets){await page.locator('[data-idea-preset="'+preset.id+'"]').click();assert.equal(await page.locator('.idea-card').count(),3);assert.equal(await page.locator('[data-idea-preset][aria-pressed="true"]').count(),1);}
  await page.getByRole('button',{name:'Гадаа',exact:true}).click();
  const first=await page.locator('.idea-card').evaluateAll(nodes=>nodes.map(node=>node.dataset.ideaId));
  await page.locator('#show-more').click();
  const more=await page.locator('.idea-card').evaluateAll(nodes=>nodes.map(node=>node.dataset.ideaId));
  assert.deepEqual(more.slice(0,3),first);assert.equal(new Set(more).size,more.length);assert.ok(more.length>3);
  await page.getByRole('button',{name:'Бүтэн орой',exact:true}).click();
  await page.screenshot({path:path.join(artifacts,'ideas-desktop.png'),fullPage:true});
  for(const width of [320,390,768,1280]){await page.setViewportSize({width,height:900});await noOverflow(page);}
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:path.join(artifacts,'ideas-mobile.png'),fullPage:true});
  const selected=await page.locator('.idea-card').first().getAttribute('data-idea-id');
  await page.locator('.idea-use').first().click();await settled(page,'#recipientName');
  assert.equal(await page.locator('body').getAttribute('data-quick'),'true');
  assert.equal(await page.locator('.wizard-step.active').getAttribute('data-step'),'2');
  await page.locator('#continueStep').click();await page.locator('#recipientName[aria-invalid="true"]').waitFor();
  await page.locator('#recipientName').fill('Номин');await page.locator('#senderName').fill('Бат');
  for(const width of [320,390]){await page.setViewportSize({width,height:844});await noOverflow(page);}
  await page.screenshot({path:path.join(artifacts,'quick-create-mobile.png'),fullPage:true});await noOverflow(page);
  await page.locator('#continueStep').click();await page.locator('#previewModal').waitFor({state:'visible'});
  assert.equal(await page.locator('#previewPrimaryCta').getAttribute('data-mode'),'pay');
  await page.locator('#editPreview').click();assert.equal(await page.locator('.wizard-step.active').getAttribute('data-step'),'2');
  await page.locator('#quickCustomize summary').click();await page.locator('[data-quick-edit="4"]').click();
  await page.locator('#customNote').fill('Киногоо үзээд, тухтай ярилцъя.');await page.locator('#locationName').fill('Хамт сонгох газар');
  await page.locator('#continueStep').click();await page.locator('#previewModal').waitFor({state:'visible'});
  await page.locator('#closePreview').click();
  // A fixture access code exercises the normal validation/redemption path.
  await page.evaluate(()=>localStorage.setItem('bolzoo:pending_code','LOV-ABCDEF'));
  await page.reload();await settled(page,'#generate');
  assert.equal(await page.locator('body').getAttribute('data-quick'),'true');
  await page.locator('#generate').click();await page.locator('#successResponseLink').waitFor({state:'visible'});
  const responseLink=await page.locator('#successResponseLink').getAttribute('href');
  const id=new URL(responseLink,origin).searchParams.get('invite');assert.ok(id);
  const shareLink=await page.locator('#successLink').textContent();assert.ok(!shareLink.includes('recover'));
  await page.screenshot({path:path.join(artifacts,'success-mobile.png'),fullPage:false});
  await page.locator('#successResponseLink').click();await settled(page,'.invite-card');
  assert.equal(await page.locator('.invite-card').getAttribute('data-invite-id'),id);await noOverflow(page);
  await page.screenshot({path:path.join(artifacts,'response-waiting-mobile.png'),fullPage:true});
  // Send a response through the unchanged recipient API, then verify the new dashboard.
  await partner.goto(origin+'/ideas.html');
  await partner.evaluate(async id=>BolzooAPI.saveResponse(id,{answer:'later',dateISO:'2027-03-12',date:'2027 оны 3-р сарын 12',time:'18:30',kind:'Кино'}),id);
  await page.locator('#refresh').click();await settled(page,'.invite-card');
  assert.ok((await page.locator('.invite-card').textContent()).includes('Өөр өдөр'));
  assert.ok(!(await page.locator('.invite-card').textContent()).includes('Хоёулаа тохирлоо'));
  await partner.evaluate(async id=>BolzooAPI.saveResponse(id,{answer:'yes',dateISO:'2027-03-12',date:'2027 оны 3-р сарын 12',time:'18:30',kind:'Кино'}),id);
  await page.locator('#refresh').click();await settled(page,'.invite-card');
  await page.waitForFunction(()=>document.querySelector('.invite-card')?.textContent.includes('зөвшөөр'));
  await page.screenshot({path:path.join(artifacts,'response-accepted-mobile.png'),fullPage:true});await noOverflow(page);
  await page.locator('[data-focus-key="plan"]').click();await settled(page,'#plan-editor');
  assert.equal(await page.locator('#plan-template').inputValue(),selected);
  await page.locator('#plan-time').fill('2027-03-13T19:00');await page.locator('#plan-location').fill('Шинэ тохирсон кафе');
  await page.locator('#save-plan').click();await settled(page,'#plan-content');
  const join=await page.evaluate(id=>BolzooDatePlanAPI.joinLink(id),id);
  await partner.goto(join);await partner.locator('#claim-plan').click();await settled(partner,'#plan-content');
  await partner.locator('#accept-plan').click();await settled(partner,'#start-panel');
  await page.goto(origin+'/dashboard.html?invite='+encodeURIComponent(id));await settled(page,'.invite-card');
  await page.waitForFunction(()=>document.querySelector('.plan-summary.agreed'));
  assert.ok((await page.locator('.plan-summary').textContent()).includes('Хоёулаа тохирлоо'));
  const calendar=page.waitForEvent('download');await page.locator('[data-calendar]').click();const download=await calendar;const destination=path.join(artifacts,'agreed-date.ics');await download.saveAs(destination);
  const ics=fs.readFileSync(destination,'utf8');assert.match(ics,/DTSTART:20270313T110000Z/);assert.ok(!ics.includes('DTSTART:20270312T103000Z'));
  await page.screenshot({path:path.join(artifacts,'response-agreed-mobile.png'),fullPage:true});
  for(const width of [320,390,768,1280]){await page.setViewportSize({width,height:900});await noOverflow(page);}
  await page.screenshot({path:path.join(artifacts,'response-desktop.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(artifacts,'browser-verification.json'),JSON.stringify({passed:true,checks:['five quick presets each show three','nonrepeating more ideas','one-name direct preview','optional edits and draft reload','real fixture code redemption','focused response link','later not treated as accepted','real shared-plan consent','calendar uses newly agreed date','320/390/768/1280 no horizontal overflow','no JavaScript page errors']},null,2));
  console.log('PASS simple ideas → quick invitation → response → agreed date, with calendar and responsive screenshots.');
})().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();server.kill();await new Promise(resolve=>server.exitCode!==null?resolve():server.once('exit',resolve));fs.rmSync(dir,{recursive:true,force:true});});
