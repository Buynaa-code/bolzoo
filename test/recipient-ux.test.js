'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'bolzoo.html'), 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
const tick = () => new Promise(resolve => setTimeout(resolve, 10));
const fixedNow = Date.parse('2026-09-07T10:00:00Z'); // 18:00 in Ulaanbaatar.
function browser(t, options = {}) {
  const dom = new JSDOM(html, {
    url: options.url || 'http://localhost/bolzoo.html?id=invite123',
    runScripts: 'outside-only', pretendToBeVisual: true, virtualConsole: new VirtualConsole()
  });
  t.after(() => dom.window.close());
  const w = dom.window;
  const clock = options.now === undefined ? fixedNow : options.now;
  const NativeDate = w.Date;
  w.Date = class extends NativeDate {
    constructor(...args) { super(...(args.length ? args : [clock])); }
    static now() { return clock; }
  };
  w.matchMedia = () => ({ matches: true });
  w.scrollTo = () => {};
  w.HTMLElement.prototype.scrollIntoView = function() {};
  w.fetch = async () => ({ ok: true });
  w.BolzooAPI = {
    getInvite: options.getInvite || (async () => ({ config: options.config || {} })),
    saveResponse: options.saveResponse || (async () => {}),
    markOpened: async () => {}
  };
  w.BolzooCat = { mountAll() {} };
  const noop = () => {};
  w.BolzooAudio = { init: () => ({ setVideoId: noop, initFX: noop, pop: noop, twinkle: noop, chime: noop }) };
  w.BolzooDateRoom = { init: () => ({ reset: noop }) };
  w.BolzooTicket = { save: noop };
  for (const file of ['utils.js', 'apology-templates.js', 'posters.js', 'campaign.js', 'campaign-recipient.js']) {
    w.eval(fs.readFileSync(path.join(root, 'assets', file), 'utf8'));
  }
  w.eval(script);
  return w;
}
const byId = (w, id) => w.document.getElementById(id);
async function open(w) { await tick(); byId(w, 'introOpen').click(); await tick(); }
async function schedule(w) {
  await open(w);
  byId(w, 'yesBtn').click(); await tick();
  byId(w, 'okBtn').click();
}
function chooseDate(w, day = '8') {
  [...byId(w, 'calGrid').querySelectorAll('button')].find(button => button.textContent === day).click();
  byId(w, 'kindGrid').querySelector('button').click();
}

test('decline works on the first click, reports failed delivery, and retries without pretending success', async t => {
  const saves = []; let first = true;
  const w = browser(t, { saveResponse: async (_, payload) => {
    saves.push(payload); if (first) { first = false; throw new Error('offline'); }
  }});
  await open(w);
  byId(w, 'noBtn').click(); await tick();
  assert.equal(w.document.body.dataset.screen, 'declined');
  assert.equal(saves.length, 1);
  assert.equal(saves[0].answer, 'no');
  assert.equal(saves[0].final, true);
  assert.equal(byId(w, 'retryDecline').hidden, false);
  assert.match(byId(w, 'declineNote').textContent, /баталгаажуулж чадсангүй/);
  byId(w, 'retryDecline').click(); await tick();
  assert.equal(saves.length, 2);
  assert.equal(byId(w, 'retryDecline').hidden, true);
  assert.match(byId(w, 'declineNote').textContent, /илгээгчид хүргэлээ/);
});

test('date response remains on the form until saved, prevents duplicate submissions, and preserves choices after failure', async t => {
  let resolveSave, rejectSave; const saves = [];
  const w = browser(t, { saveResponse: (_, payload) => {
    saves.push(payload); return new Promise((resolve, reject) => { resolveSave = resolve; rejectSave = reject; });
  }});
  await schedule(w); chooseDate(w);
  byId(w, 'nextBtn').click(); byId(w, 'nextBtn').click();
  assert.equal(saves.length, 1);
  assert.equal(w.document.body.dataset.screen, 'date');
  assert.equal(byId(w, 'dateBack').disabled, true);
  rejectSave(new Error('offline')); await tick();
  assert.equal(w.document.body.dataset.screen, 'date');
  assert.equal(byId(w, 'calGrid').querySelector('.sel').textContent, '8');
  assert.equal(byId(w, 'nextBtn').disabled, false);
  assert.match(byId(w, 'dateSaveStatus').textContent, /Сонголтууд тань хэвээрээ/);
  byId(w, 'nextBtn').click();
  assert.equal(saves.length, 2);
  assert.equal(saves[1].dateISO, '2026-09-08');
  resolveSave(); await tick();
  assert.equal(w.document.body.dataset.screen, 'done');
  assert.match(byId(w, 'responseSaved').textContent, /илгээгчид хүргэлээ/);
  assert.equal(w.document.activeElement, byId(w, 'doneKindTitle'));
  const dates = new URL(byId(w, 'calGoogle').href).searchParams.get('dates');
  assert.equal(dates, '20260908T100000Z/20260908T120000Z');
});

test('calendar dates are keyboard buttons, past dates and elapsed Ulaanbaatar time slots cannot be submitted', async t => {
  const w = browser(t); await schedule(w);
  const days = byId(w, 'calGrid');
  assert.equal(days.querySelector('.off').tagName, 'BUTTON');
  assert.equal(days.querySelector('.off').disabled, true);
  assert.match(days.querySelector('.today').getAttribute('aria-label'), /2026 оны 9-р сар 7/);
  days.querySelector('.today').click();
  byId(w, 'kindGrid').querySelector('button').click();
  assert.equal(byId(w, 'nextBtn').disabled, true);
  assert.equal([...byId(w, 'timeGrid').children].find(b => b.textContent === '18:00').disabled, true);
  const upcoming = [...byId(w, 'timeGrid').children].find(b => b.textContent === '18:30');
  upcoming.click();
  assert.equal(upcoming.getAttribute('aria-pressed'), 'true');
  assert.equal(byId(w, 'nextBtn').disabled, false);
  assert.match(byId(w, 'selectionHint').textContent, /18:30/);
});

test('the envelope waits for its real invite and a missing invite never displays a default invitation', async t => {
  let resolveInvite;
  const w = browser(t, { getInvite: () => new Promise(resolve => { resolveInvite = resolve; }) });
  assert.equal(byId(w, 'introOpen').disabled, true);
  byId(w, 'introOpen').click(); await tick();
  assert.equal(byId(w, 'introOverlay').style.display, '');
  resolveInvite(null); await tick();
  assert.equal(byId(w, 'inviteError').hidden, false);
  assert.match(byId(w, 'inviteErrorTitle').textContent, /олдсонгүй/);
  assert.equal(w.document.querySelector('main').style.display, 'none');
  assert.equal(byId(w, 'retryInvite').hidden, true);
});

test('a connection failure explains the problem and provides an invite reload button', async t => {
  const w = browser(t, { getInvite: async () => { throw new Error('Failed to fetch'); } });
  await tick();
  assert.equal(byId(w, 'inviteError').hidden, false);
  assert.equal(byId(w, 'retryInvite').hidden, false);
  assert.match(byId(w, 'inviteErrorText').textContent, /Холболт түр тасарсан/);
});

test('letter dialog traps keyboard focus, Escape closes it and restores the trigger', async t => {
  const w = browser(t); await schedule(w); chooseDate(w);
  byId(w, 'nextBtn').click(); await tick();
  byId(w, 'letterBtn').click();
  assert.equal(byId(w, 'letterModal').getAttribute('role'), 'dialog');
  assert.equal(w.document.activeElement, byId(w, 'letterClose'));
  assert.equal(w.document.querySelector('main').inert, true);
  byId(w, 'letterClose').dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
  assert.equal(w.document.activeElement, byId(w, 'letterClose'));
  w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  assert.equal(byId(w, 'letterModal').style.display, 'none');
  assert.equal(w.document.querySelector('main').inert, false);
  assert.equal(w.document.activeElement, byId(w, 'letterBtn'));
});

test('preview date responses never call saveResponse, even when an invite ID is present', async t => {
  let saves = 0;
  const w = browser(t, { url: 'http://localhost/bolzoo.html?preview=1&id=invite123', saveResponse: async () => { saves++; } });
  await schedule(w); chooseDate(w); byId(w, 'nextBtn').click(); await tick();
  assert.equal(w.document.body.dataset.screen, 'done');
  assert.equal(saves, 0);
  assert.match(byId(w, 'responseSaved').textContent, /Хариу илгээгдээгүй/);
});

test('apology responses keep readiness as the recipient-selected value', async t => {
  const saves = [];
  const w = browser(t, { config: { experienceType: 'apology', apologyDateOffer: true }, saveResponse: async (_, payload) => { saves.push(payload); } });
  await open(w);
  byId(w, 'apologySkipToResponse').click();
  byId(w, 'apologyReadiness').value = '60';
  byId(w, 'apologyReadiness').dispatchEvent(new w.Event('input', { bubbles: true }));
  assert.match(byId(w, 'apologyReadiness').getAttribute('aria-valuetext'), /^60%/);
  w.document.querySelector('[data-apology-status="meet"]').click(); await tick();
  assert.equal(saves[0].readinessPercent, 60);
  assert.equal(saves[0].status, 'meet');
  assert.equal(byId(w, 'apologyScheduleDate').hidden, false);
});

test('blocked clipboard sharing provides the actual response text for manual copying', async t => {
  const w = browser(t); await schedule(w); chooseDate(w);
  byId(w, 'nextBtn').click(); await tick();
  byId(w, 'shareInvite').click(); await tick();
  assert.equal(byId(w, 'shareText').hidden, false);
  assert.match(byId(w, 'shareText').value, /2026 оны 9-р сар 8/);
  assert.equal(w.document.activeElement, byId(w, 'shareText'));
  assert.equal(byId(w, 'sendStatus').closest('[role="dialog"]'), null);
});

test('music requires the sound button and remains controllable after turning on', t => {
  const dom = new JSDOM('<head></head><body><button id="sound"><span id="icon"></span><span id="text"></span></button><div id="ytHost"></div></body>', { runScripts: 'outside-only' });
  t.after(() => dom.window.close());
  const w = dom.window;
  let playCount = 0, cueCount = 0, ready;
  w.YT = { Player: function(_, opts) {
    ready = opts.events.onReady;
    return { setVolume() {}, mute() {}, unMute() {}, cueVideoById() { cueCount++; }, loadVideoById() {}, playVideo() { playCount++; } };
  }};
  w.eval(fs.readFileSync(path.join(root, 'assets/bolzoo-audio.js'), 'utf8'));
  const audio = w.BolzooAudio.init({ videoId: 'first', buttonEl: byId(w, 'sound'), iconEl: byId(w, 'icon'), textEl: byId(w, 'text') });
  w.onYouTubeIframeAPIReady(); ready();
  audio.setVideoId('second');
  assert.equal(cueCount, 1);
  w.dispatchEvent(new w.Event('pointerdown'));
  assert.equal(playCount, 0);
  byId(w, 'sound').click();
  assert.equal(playCount, 1);
  assert.equal(byId(w, 'sound').getAttribute('aria-pressed'), 'true');
  byId(w, 'sound').click();
  assert.equal(byId(w, 'sound').getAttribute('aria-pressed'), 'false');
});

test('tagged campaign acceptance appears only after a response is successfully saved and never changes its selected date',async t=>{
  let fail=true;const saves=[];
  const w=browser(t,{now:Date.parse('2026-09-22T16:00:00Z'),config:{campaign:'newyear100-2026'},saveResponse:async(_,payload)=>{saves.push(payload);if(fail)throw new Error('offline');}});
  await schedule(w);chooseDate(w,'24');
  assert.equal(byId(w,'campaignInviteBadge').hidden,false);
  assert.equal(byId(w,'campaignNewYearCard').hidden,true);
  byId(w,'nextBtn').click();await tick();assert.equal(byId(w,'campaignNewYearCard').hidden,true);
  fail=false;byId(w,'nextBtn').click();await tick();
  assert.equal(byId(w,'campaignNewYearCard').hidden,false);
  assert.equal(byId(w,'campaignDaysLeft').textContent,'100');
  assert.equal(saves.at(-1).dateISO,'2026-09-24');
  assert.equal(byId(w,'dateValue').textContent,'2026.09.24');
  assert.equal(w.document.activeElement,byId(w,'doneKindTitle'));
});

test('untagged and apology invitations never acquire the campaign and declining does not show the target card',async t=>{
  for(const config of [{},{campaign:'newyear100-2025'},{campaign:'newyear100-2026',experienceType:'apology'}]){
    const w=browser(t,{config});await open(w);
    assert.equal(byId(w,'campaignInviteBadge').hidden,true);
    assert.equal(byId(w,'campaignNewYearCard').hidden,true);
  }
  const w=browser(t,{now:Date.parse('2026-09-22T16:00:00Z'),config:{campaign:'newyear100-2026'}});
  await open(w);byId(w,'noBtn').click();await tick();
  assert.equal(w.document.body.dataset.screen,'declined');
  assert.equal(byId(w,'campaignNewYearCard').hidden,true);
  assert.doesNotMatch(byId(w,'declineNote').textContent,/хос|100 хоног/);
});

test('campaign previews preserve their tag and can clear it through the live preview channel without saving a response',async t=>{
  const config={campaign:'newyear100-2026',experienceType:'date'};
  const encoded=encodeURIComponent(Buffer.from(JSON.stringify(config)).toString('base64'));
  let saves=0;
  const w=browser(t,{now:Date.parse('2026-09-22T16:00:00Z'),url:'http://localhost/bolzoo.html?preview=1#c='+encoded,saveResponse:async()=>{saves++;}});
  await schedule(w);chooseDate(w,'24');byId(w,'nextBtn').click();await tick();
  assert.equal(byId(w,'campaignNewYearCard').hidden,false);
  assert.equal(byId(w,'campaignPreviewNote').hidden,false);
  assert.equal(saves,0);
  w.dispatchEvent(new w.MessageEvent('message',{data:{type:'bolzoo:config',config:{campaign:''}}}));
  assert.equal(byId(w,'campaignInviteBadge').hidden,true);
  assert.equal(byId(w,'campaignNewYearCard').hidden,true);
});
