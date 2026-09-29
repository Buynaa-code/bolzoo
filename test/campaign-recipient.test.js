'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const campaign=require('../assets/campaign');
const recipient=require('../assets/campaign-recipient');
const root=path.join(__dirname,'..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');

test('the campaign uses 100 elapsed days from Sep23, while remaining days follow Ulaanbaatar calendar boundaries',()=>{
  assert.equal((Date.parse(campaign.NEW_YEAR_AT)-Date.parse(campaign.START_AT))/86400000,100);
  assert.equal(recipient.timing('2026-09-21T16:00:00Z').days,101);
  assert.equal(recipient.timing('2026-09-22T15:59:59Z').days,101);
  assert.equal(recipient.timing('2026-09-22T16:00:00Z').days,100);
  assert.equal(recipient.timing('2026-12-31T15:59:59Z').days,1);
  assert.deepEqual(recipient.timing('2026-12-31T16:00:00Z'),{days:0,phase:'today'});
  assert.deepEqual(recipient.timing('2027-01-01T16:00:00Z'),{days:0,phase:'past'});
  assert.equal(recipient.timing('bad date'),null);
});

test('only the exact persisted campaign tag enables date invitations; apology and missing/unknown tags stay excluded',()=>{
  assert.equal(recipient.enabled({campaign:campaign.ID,experienceType:'date'}),true);
  assert.equal(recipient.enabled({campaign:campaign.ID,experienceType:'apology'}),false);
  for(const value of [undefined,null,'',true,'newyear100','newyear100-2027','NEWYEAR100-2026'])assert.equal(recipient.enabled({campaign:value}),false);
  assert.equal(recipient.enabled(null),false);
});

test('the optional reminder is all-day and contains no private invitation fields or confirmed appointment',()=>{
  const ics=recipient.createCalendar('2026-09-22T16:00:00Z');
  assert.match(ics,/DTSTART;VALUE=DATE:20270101\r\n/);
  assert.match(ics,/DTEND;VALUE=DATE:20270102\r\n/);
  assert.match(ics,/TRANSP:TRANSPARENT/);
  assert.doesNotMatch(ics,/ATTENDEE|ORGANIZER|LOCATION:|URL:|VALARM|owner_token|claim_token|invite_id/);
  assert.match(ics.replace(/\r\n /g,''),/Болзооны тохирсон өдөр эсвэл газрын захиалга биш/);
  for(const line of ics.split('\r\n'))assert.ok(Buffer.byteLength(line,'utf8')<=75);
  assert.equal(recipient.createCalendar('bad date'),null);
});

function fixture(t,{config={campaign:campaign.ID,experienceType:'date'},now='2026-09-22T16:00:00Z',preview=false}={}){
  const dom=new JSDOM(read('bolzoo.html'),{url:'https://bolzoo.test/bolzoo.html?id=private-invite',runScripts:'outside-only'});
  t.after(()=>dom.window.close());
  const w=dom.window;let current=now;
  w.eval(read('assets/campaign.js'));w.eval(read('assets/campaign-recipient.js'));
  const controller=w.BolzooCampaignRecipient.mount({getConfig:()=>config,now:()=>Date.parse(current),preview});
  return {w,d:w.document,controller,setNow:value=>{current=value;controller.update();},config};
}

test('a tagged invitation retains campaign copy after the offer ends, but the target appears only after a saved yes',t=>{
  const f=fixture(t,{now:'2026-10-10T04:00:00Z'});
  assert.equal(f.d.getElementById('campaignInviteBadge').hidden,false);
  assert.equal(f.d.getElementById('campaignNewYearCard').hidden,true);
  for(const value of [true,'later','no','pending']){f.controller.setAccepted(value);assert.equal(f.d.getElementById('campaignNewYearCard').hidden,true);}
  f.controller.setAccepted('yes');assert.equal(f.d.getElementById('campaignNewYearCard').hidden,false);
  assert.equal(f.d.getElementById('campaignDaysLeft').textContent,'83');
  assert.match(f.d.getElementById('campaignTargetCopy').textContent,/сонгосон болзооны өдөр, цагийг өөрчлөхгүй/);
  assert.doesNotMatch(f.d.getElementById('campaignNewYearCard').textContent,/хос бол|100 дахь|хосын|₮|хямдрал|50%/i);
  f.controller.setAccepted('later');assert.equal(f.d.getElementById('campaignNewYearCard').hidden,true);
});

test('Jan1 and later become commemorative instead of negative countdowns or past reminders',t=>{
  const f=fixture(t);f.controller.setAccepted('yes');
  f.setNow('2026-12-31T16:00:00Z');assert.equal(f.d.getElementById('campaignDaysLeft').textContent,'Өнөөдөр');
  assert.match(f.d.getElementById('campaignTargetCaption').textContent,/ирлээ/);
  f.setNow('2027-02-01T00:00:00Z');assert.equal(f.d.getElementById('campaignDaysLeft').textContent,'Дурсамж');
  assert.equal(f.d.getElementById('campaignCalendar').hidden,true);
  assert.match(f.d.getElementById('campaignTargetCopy').textContent,/зориулсан урилгын дурсамж/);
  assert.doesNotMatch(f.d.getElementById('campaignInviteCopy').textContent,/хүртэл/);
});

test('preview switches clear the campaign without affecting the normal invitation controls',t=>{
  const f=fixture(t,{preview:true});f.controller.setAccepted('yes');
  assert.equal(f.d.getElementById('campaignPreviewNote').hidden,false);
  f.config.campaign='';f.controller.update();
  assert.equal(f.d.getElementById('campaignInviteBadge').hidden,true);
  assert.equal(f.d.getElementById('campaignNewYearCard').hidden,true);
  assert.ok(f.d.getElementById('yesBtn'));assert.ok(f.d.getElementById('noBtn'));
});

test('reminder download is explicit, bounded to this idea and reports a failed browser download honestly',async t=>{
  const f=fixture(t);let blob,clicks=0;
  f.w.URL.createObjectURL=value=>{blob=value;return 'blob:campaign';};f.w.URL.revokeObjectURL=()=>{};
  f.w.HTMLAnchorElement.prototype.click=function(){clicks++;assert.equal(this.download,'bolzoo-new-year-idea.ics');};
  f.d.getElementById('campaignCalendar').click();assert.equal(clicks,0);
  f.controller.setAccepted('yes');assert.equal(clicks,0);
  f.d.getElementById('campaignCalendar').click();assert.equal(clicks,1);assert.ok(blob);
  const text=await new Promise(resolve=>{const reader=new f.w.FileReader();reader.onload=()=>resolve(reader.result);reader.readAsText(blob);});
  assert.doesNotMatch(text,/private-invite|https:/);
  assert.match(f.d.getElementById('campaignCalendarStatus').textContent,/хүсвэл нэмээрэй/);
  f.w.URL.createObjectURL=()=>{throw new Error('blocked');};
  f.d.getElementById('campaignCalendar').click();
  assert.match(f.d.getElementById('campaignCalendarStatus').textContent,/татаж чадсангүй/);
  assert.equal(f.d.getElementById('campaignCalendar').disabled,false);
});
