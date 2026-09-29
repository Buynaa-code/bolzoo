'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
const OWNER_TOKEN = 'b633f0d5-722a-4661-b6d7-6d731ad1e539';
const DATE = '2026-09-20';
const NOW = '2026-09-07T09:00:00Z';

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function invitation(id, name, response = null, extra = {}) {
  return Object.assign({
    id, config: {recipientName: name, senderName: 'Бат'}, response,
    created_at: '2026-09-01T00:00:00Z', opened_at: null,
    responded_at: response ? NOW : null
  }, extra);
}

function dashboard(t, {invites = [], api = {}, hash = '', query = '', seen, planAPI, omitUtils = false, now} = {}) {
  const errors = [];
  const console = new VirtualConsole();
  console.on('jsdomError', error => errors.push(error.message));
  const html = read('dashboard.html');
  const dom = new JSDOM(html, {
    url: 'https://bolzoo.example/dashboard.html' + query + hash,
    runScripts: 'outside-only', virtualConsole: console
  });
  const w = dom.window;
  w.addEventListener('error', event => errors.push(event.message));
  w.addEventListener('unhandledrejection', event => errors.push(String(event.reason)));
  const scrolls=[];
  w.HTMLElement.prototype.scrollIntoView = function() {scrolls.push(this.id);};
  if (now !== undefined) w.Date.now = () => now;
  if (!omitUtils) w.eval(read('assets/utils.js'));
  w.eval(read('assets/responses.js'));
  if(seen)w.localStorage.setItem('bolzoo:responses:seen:v1',JSON.stringify(seen));
  w.BolzooDatePlanAPI=planAPI===undefined?{get:async()=>{const error=new Error('no plan');error.status=404;error.code='plan_not_found';throw error;}}:planAPI;
  const remembered = [];
  w.BolzooAPI = Object.assign({
    backendKind: 'supabase',
    listMyInvites: async () => invites,
    recoverInvite: async () => ({ok: true, id: 'invite-recovered', owner_token: OWNER_TOKEN}),
    rememberOwnedInvite(id, token) {
      remembered.push({id, token});
      w.localStorage.setItem('bolzoo:owner:' + id, JSON.stringify(token));
      w.localStorage.setItem('bolzoo:my', JSON.stringify([{id, createdAt: NOW}]));
      return true;
    },
    getOwnerToken(id) {
      return JSON.parse(w.localStorage.getItem('bolzoo:owner:' + id))||OWNER_TOKEN;
    }
  }, api);
  const inline = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
  w.eval(inline);
  t.after(() => {
    w.close();
    assert.deepEqual(errors, [], 'dashboard must not emit uncaught browser errors');
  });
  return {
    w, remembered, scrolls,
    get: id => w.document.getElementById(id),
    card: id => w.document.querySelector('[data-invite-id="' + id + '"]'),
    cards: () => [...w.document.querySelectorAll('#list article')],
    async refresh() { w.document.getElementById('refresh').click(); await tick(); },
    recover(code = 'LOV-ABC234') {
      w.document.getElementById('recoverCode').value = code;
      w.document.getElementById('recoverForm').dispatchEvent(new w.Event('submit', {cancelable: true}));
    }
  };
}

test('alternate date stays a proposal and never gains acceptance or a calendar action', async t => {
  const d = dashboard(t, {invites: [invitation('invite-later', 'Номин', {
    answer: 'later', date: '2026 оны 9-р сар 20', dateISO: DATE, time: '18:30'
  })]});
  await tick();
  const card = d.card('invite-later');
  assert.match(card.querySelector('.response-title').textContent, /Өөр өдөр санал болгосон/);
  assert.match(card.querySelector('.response-details').textContent, /2026 оны 9-р сарын 20/);
  assert.equal(card.querySelector('.accepted'), null);
  assert.equal(card.querySelector('[data-calendar]'), null);
  assert.doesNotMatch(card.textContent, /Тийм ээ|Урилгыг зөвшөөрсөн/);
});

test('apology readiness omits absent values in current and past responses but retains explicit zero', async t => {
  const items = [null, undefined, '', 0].map((value, index) => invitation('apology-' + index, 'Саруул', {
    type: 'apology', status: 'read', readinessPercent: value
  }, {
    config: {experienceType: 'apology', recipientName: 'Саруул'},
    response_history: [{response: {type: 'apology', status: 'read', readinessPercent: value}, responded_at: NOW}]
  }));
  const d = dashboard(t, {invites: items});
  await tick();
  for (let index = 0; index < 3; index++) {
    assert.equal(d.card('apology-' + index).querySelector('[role="meter"]'), null);
    assert.doesNotMatch(d.card('apology-' + index).textContent, /0%/);
  }
  assert.equal(d.card('apology-3').querySelector('[role="meter"]').getAttribute('aria-valuenow'), '0');
  assert.match(d.card('apology-3').querySelector('.card-history').textContent, /0%/);
});

test('name search is case insensitive, combines with status filters, and leaves total counts accurate', async t => {
  const d = dashboard(t, {invites: [
    invitation('invite-one', 'Номин', {answer: 'yes', dateISO: DATE, time: '18:30'}),
    invitation('invite-two', 'Номингоо'),
    invitation('invite-three', 'Ану', {answer: 'no'}),
    invitation('invite-four', 'Билгүүн', null, {opened_at: NOW})
  ]});
  await tick();
  const totals = () => ['statTotal', 'statWaiting', 'statResponded'].map(id => d.get(id).textContent);
  assert.deepEqual(totals(), ['4', '2', '2']);
  d.get('inviteSearch').value = '  НОМИН  ';
  d.get('inviteSearch').dispatchEvent(new d.w.Event('input'));
  assert.equal(d.cards().length, 2);
  assert.equal(d.get('listCount').textContent, '2 / 4 урилга');
  const responded = d.w.document.querySelector('[data-filter="new"]');
  responded.click();
  assert.equal(responded.getAttribute('aria-pressed'), 'true');
  assert.deepEqual(d.cards().map(card => card.dataset.inviteId), ['invite-one']);
  assert.deepEqual(totals(), ['4', '2', '2']);
  d.get('inviteSearch').value = 'ОЛДОХГҮЙ';
  d.get('inviteSearch').dispatchEvent(new d.w.Event('input'));
  assert.equal(d.cards().length, 0);
  assert.match(d.get('list').textContent, /Энэ нэрээр урилга олдсонгүй/);
  d.w.document.querySelector('[data-clear-filter]').click();
  assert.equal(d.get('inviteSearch').value, '');
  assert.equal(d.cards().length, 4);
  assert.equal(d.w.document.querySelector('[data-filter="all"]').getAttribute('aria-pressed'), 'true');
});

test('updated cards preserve focus and open details while unchanged refresh keeps the existing action node', async t => {
  let record = invitation('invite-focus', 'Номин', {answer: 'later'}, {
    response_history: [{response: {answer: 'yes'}, responded_at: NOW}]
  });
  const d = dashboard(t, {api: {listMyInvites: async () => [record]}});
  await tick();
  const original = d.card(record.id);
  original.querySelector('[data-panel="history"]').open = true;
  original.querySelector('[data-panel="options"]').open = true;
  const copy = original.querySelector('[data-copy]');
  copy.focus();
  await d.refresh();
  assert.equal(d.card(record.id), original);
  assert.equal(d.w.document.activeElement, copy);
  assert.equal(original.querySelector('[data-copy]'), copy);
  record = Object.assign({}, record, {response: {answer: 'yes', dateISO: DATE, time: '18:30'}});
  await d.refresh();
  assert.equal(d.card(record.id), original);
  assert.match(original.querySelector('.response-title').textContent, /Урилгыг зөвшөөрсөн/);
  assert.equal(d.w.document.activeElement.getAttribute('data-focus-key'), 'copy');
  assert.equal(original.contains(d.w.document.activeElement), true);
  assert.equal(original.querySelector('[data-panel="history"]').open, true);
  assert.equal(original.querySelector('[data-panel="options"]').open, true);
});

test('initial load failure offers retry and later network failure preserves the last useful cards', async t => {
  let fail = true;
  const d = dashboard(t, {api: {listMyInvites: async () => {
    if (fail) throw new Error('Failed to fetch');
    return [invitation('invite-retry', 'Номин')];
  }}});
  await tick();
  assert.equal(d.get('loadError').hidden, false);
  assert.equal(d.get('empty'), null);
  assert.equal(d.get('statTotal').textContent, '—');
  assert.equal(d.get('list').getAttribute('aria-busy'), 'false');
  fail = false;
  d.get('retryLoadBtn').click();
  await tick();
  const card = d.card('invite-retry');
  assert.ok(card);
  assert.equal(d.get('loadError').hidden, true);
  fail = true;
  await d.refresh();
  assert.equal(d.card('invite-retry'), card);
  assert.equal(d.get('loadError').hidden, false);
  assert.equal(d.get('statTotal').textContent, '1');
});

test('missing shared helpers produce a visible retry error instead of an uncaught crash or endless loading', t => {
  let listCalls = 0;
  const d = dashboard(t, {omitUtils: true, api: {listMyInvites: async () => {listCalls++; return [];}}});
  assert.equal(d.get('loadError').hidden, false);
  assert.match(d.get('loadErrorText').textContent, /бүрэн ачаалж чадсангүй/);
  assert.equal(d.get('retryLoadBtn').disabled, false);
  assert.equal(d.get('list').getAttribute('aria-busy'), 'false');
  assert.equal(d.get('list').children.length, 0);
  assert.equal(listCalls, 0);
});

test('code recovery waits for an in-flight load then fetches a fresh list before reporting success', async t => {
  const pending = deferred();
  let listCalls = 0;
  const item = invitation('invite-recovered', 'Сэргэсэн', {answer: 'yes'});
  const d = dashboard(t, {api: {listMyInvites: async () => ++listCalls === 1 ? pending.promise : [item]}});
  await tick();
  d.recover(' lov-abc234 ');
  await tick();
  assert.equal(listCalls, 1);
  assert.equal(d.remembered.length, 1);
  assert.equal(d.get('recoverBtn').disabled, true);
  assert.doesNotMatch(d.get('recoverStatus').textContent, /сэргээлээ/);
  pending.resolve([]);
  await tick();
  assert.equal(listCalls, 2);
  assert.ok(d.card(item.id));
  assert.equal(d.card(item.id).classList.contains('recovered'), true);
  assert.equal(d.w.document.activeElement, d.card(item.id));
  assert.match(d.get('recoverStatus').textContent, /сэргээлээ/);
  assert.equal(d.get('recoverCode').value, '');
  assert.equal(d.get('recoverBtn').disabled, false);
});

test('malformed or invalid ownership hashes neither crash nor write ownership and still load the dashboard', async t => {
  for (const hash of ['#recover=%XX~' + OWNER_TOKEN, '#recover=invite-valid~owner-token', '#recover=short~' + OWNER_TOKEN, '#recover=invite-valid']) {
    let loads = 0;
    const d = dashboard(t, {hash, api: {listMyInvites: async () => {loads++; return [];}}});
    await tick();
    assert.equal(loads, 1, hash);
    assert.equal(d.remembered.length, 0, hash);
    assert.equal(d.w.location.hash, '', hash);
    assert.equal(d.get('recoverStatus').classList.contains('bad'), true, hash);
    assert.ok(d.get('empty'), hash);
  }
});

test('ownership hashes reject UUID versions and variants unsupported by the invitation API', async t => {
  for (const token of [
    'b633f0d5-722a-0661-b6d7-6d731ad1e539',
    'b633f0d5-722a-7661-b6d7-6d731ad1e539',
    'b633f0d5-722a-4661-06d7-6d731ad1e539',
    'b633f0d5-722a-4661-f6d7-6d731ad1e539'
  ]) {
    const d = dashboard(t, {hash: '#recover=invite-valid~' + token});
    await tick();
    assert.equal(d.remembered.length, 0, token);
    assert.equal(d.w.localStorage.getItem('bolzoo:owner:invite-valid'), null, token);
    assert.equal(d.get('recoverStatus').classList.contains('bad'), true, token);
    assert.ok(d.get('empty'), token);
  }
});

test('malformed recovery API ownership cannot poison local storage or announce successful recovery', async t => {
  for (const payload of [
    {id: 'short', owner_token: OWNER_TOKEN},
    {id: 'invite-recovered', owner_token: 'owner-token'},
    {id: 'invite-recovered', owner_token: 'b633f0d5-722a-0661-b6d7-6d731ad1e539'},
    {id: 'invite-recovered', owner_token: 'b633f0d5-722a-4661-f6d7-6d731ad1e539'}
  ]) {
    let listCalls = 0;
    const d = dashboard(t, {api: {
      listMyInvites: async () => {listCalls++; return [];},
      recoverInvite: async () => Object.assign({ok: true}, payload)
    }});
    await tick();
    d.recover();
    await tick();
    assert.equal(d.remembered.length, 0, JSON.stringify(payload));
    assert.equal(d.w.localStorage.getItem('bolzoo:my'), null);
    assert.equal(listCalls, 1, 'invalid ownership must not trigger an authenticated list reload');
    assert.equal(d.get('recoverStatus').classList.contains('bad'), true);
    assert.doesNotMatch(d.get('recoverStatus').textContent, /сэргээлээ/);
    assert.equal(d.get('recoverCode').hasAttribute('aria-invalid'), false);
    assert.equal(d.get('recoverBtn').disabled, false);
  }
});

test('network recovery failures explain retry without marking a correctly formatted code invalid', async t => {
  const d = dashboard(t, {api: {recoverInvite: async () => {throw new TypeError('Failed to fetch');}}});
  await tick();
  d.recover();
  await tick();
  assert.equal(d.remembered.length, 0);
  assert.equal(d.get('recoverCode').hasAttribute('aria-invalid'), false);
  assert.equal(d.get('recoverBtn').disabled, false);
  assert.match(d.get('recoverStatus').textContent, /холболтоо шалгаад дахин оролдоорой/);
  assert.doesNotMatch(d.get('recoverStatus').textContent, /Failed to fetch/);
});

test('valid private hash reports success only after the matching owned invitation has loaded', async t => {
  const pending = deferred();
  const item = invitation('invite-private', 'Номин', {answer: 'yes'});
  const d = dashboard(t, {hash: '#recover=' + item.id + '~' + OWNER_TOKEN, api: {listMyInvites: async () => pending.promise}});
  assert.equal(d.remembered.length, 1);
  assert.equal(d.w.location.hash, '');
  assert.equal(d.get('recoverStatus').classList.contains('ok'), false);
  assert.doesNotMatch(d.get('recoverStatus').textContent, /сэргээлээ/);
  pending.resolve([item]);
  await tick();
  assert.equal(d.get('recoverStatus').classList.contains('ok'), true);
  assert.match(d.get('recoverStatus').textContent, /сэргээлээ/);
  assert.ok(d.card(item.id));
});

test('valid private hash never reports success when only a different invitation was returned', async t => {
  const d = dashboard(t, {
    hash: '#recover=invite-missing~' + OWNER_TOKEN,
    invites: [invitation('invite-different', 'Бусад')]
  });
  await tick();
  assert.equal(d.get('recoverStatus').classList.contains('bad'), true);
  assert.doesNotMatch(d.get('recoverStatus').textContent, /сэргээлээ/);
  assert.match(d.get('recoverStatus').textContent, /LOV кодоороо/);
  assert.ok(d.card('invite-different'));
});

test('sender preview uses preview mode without a live invitation ID while share link remains the recipient link', async t => {
  const item = invitation('invite-preview', 'Номин', null, {config: {recipientName: 'Номин', senderName: 'Бат', customNote: '🌷 Чамдаа'}});
  const d = dashboard(t, {invites: [item]});
  await tick();
  const card = d.card(item.id);
  const preview = new URL(card.querySelector('[data-focus-key="preview"]').href);
  assert.equal(preview.searchParams.get('preview'), '1');
  assert.equal(preview.searchParams.has('id'), false);
  const config = JSON.parse(Buffer.from(decodeURIComponent(preview.hash.slice(3)), 'base64').toString('utf8'));
  assert.deepEqual(config, item.config);
  const share = new URL(card.querySelector('[data-copy]').dataset.copy);
  assert.equal(share.searchParams.get('id'), item.id);
  assert.equal(share.searchParams.has('preview'), false);
});

test('calendar action appears only for accepted invitations with a complete date and time', async t => {
  const d = dashboard(t, {invites: [
    invitation('calendar-complete', 'Бүрэн', {answer: 'yes', dateISO: DATE, time: '18:30'}),
    invitation('calendar-no-time', 'Цаггүй', {answer: 'yes', dateISO: DATE}),
    invitation('calendar-no-date', 'Өдөргүй', {answer: 'yes', time: '18:30'}),
    invitation('calendar-proposed', 'Санал', {answer: 'later', dateISO: DATE, time: '18:30'})
  ]});
  await tick();
  assert.deepEqual([...d.w.document.querySelectorAll('[data-calendar]')].map(button => button.dataset.calendar), ['calendar-complete']);
  assert.match(d.card('calendar-no-time').querySelector('.response-details').textContent, /Хараахан сонгоогүй/);
});

test('clicking the calendar action downloads an ICS blob and reports how to add it', async t => {
  const item = invitation('calendar-download', 'Номин', {answer: 'yes', dateISO: DATE, time: '18:30'});
  const d = dashboard(t, {invites: [item]});
  const downloads = [], revoked = [];
  const downloadUrl = 'blob:https://bolzoo.example/calendar-download';
  let blob;
  d.w.URL.createObjectURL = value => {blob = value; return downloadUrl;};
  d.w.URL.revokeObjectURL = url => revoked.push(url);
  d.w.HTMLAnchorElement.prototype.click = function() {
    downloads.push({url: this.href, filename: this.download});
  };
  const schedule = d.w.setTimeout.bind(d.w);
  d.w.setTimeout = (callback, delay, ...args) => schedule(callback, delay === 1000 ? 0 : delay, ...args);
  await tick();
  d.card(item.id).querySelector('[data-calendar]').click();
  await tick();
  assert.ok(blob instanceof d.w.Blob);
  assert.equal(blob.type, 'text/calendar;charset=utf-8');
  assert.deepEqual(downloads, [{url: downloadUrl, filename: 'bolzoo-date.ics'}]);
  assert.equal(d.w.document.querySelector('a[download]'), null, 'temporary download element is removed');
  const content = await new Promise((resolve, reject) => {
    const reader = new d.w.FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });
  assert.match(content, /^BEGIN:VCALENDAR\r\n/);
  assert.match(content, /DTSTART:20260920T103000Z\r\n/);
  assert.match(content, /DTEND:20260920T113000Z\r\n/);
  assert.match(content, /SUMMARY:Болзоо · Номин\r\n/);
  assert.match(content, /END:VCALENDAR\r\n$/);
  await tick();
  assert.deepEqual(revoked, [downloadUrl]);
  assert.equal(d.get('pageFeedback').hidden, false);
  assert.equal(d.get('pageFeedback').classList.contains('bad'), false);
  assert.match(d.get('pageFeedback').textContent, /Календарийн файлыг нээгээд/);
});

test('unknown answers remain neutral and expired invitations retain answers without active share or preview links', async t => {
  const expiredConfig = {experienceType: 'apology', recipientName: 'Саруул', expiresAt: '2020-01-01T00:00:00Z'};
  const d = dashboard(t, {invites: [
    invitation('invite-unknown', 'Тодорхойгүй', {answer: 'surprise', dateISO: DATE, time: '18:30'}, {created_at: 'broken'}),
    invitation('invite-expired', 'Дууссан', null, {config: expiredConfig}),
    invitation('expired-response', 'Уншсан', {type: 'apology', status: 'read'}, {config: expiredConfig})
  ]});
  await tick();
  const unknown = d.card('invite-unknown');
  assert.match(unknown.querySelector('.response-title').textContent, /Хариуны мэдээлэл бүрэн харагдахгүй/);
  assert.equal(unknown.querySelector('[data-calendar]'), null);
  assert.doesNotMatch(unknown.textContent, /Invalid Date|Урилгыг зөвшөөрсөн/);
  for (const id of ['invite-expired', 'expired-response']) {
    assert.equal(d.card(id).querySelector('[data-copy]'), null);
    assert.equal(d.card(id).querySelector('[data-focus-key="preview"]'), null);
  }
  assert.match(d.card('invite-expired').querySelector('.response-title').textContent, /Урилгын хугацаа дууссан/);
  assert.match(d.card('expired-response').querySelector('.response-title').textContent, /Захиаг уншсан/);
  assert.match(d.card('expired-response').textContent, /линкний хугацаа дууссан/);
  assert.equal(d.get('statWaiting').textContent, '0');
  assert.equal(d.get('statResponded').textContent, '2');
});

test('an existing apology response updates its expired link state after refresh even when API data is unchanged', async t => {
  const clock = Date.parse(NOW);
  const item = invitation('expiring-response', 'Саруул', {type: 'apology', status: 'read'}, {
    config: {experienceType: 'apology', recipientName: 'Саруул', expiresAt: new Date(clock + 1000).toISOString()}
  });
  const d = dashboard(t, {invites: [item], now: clock});
  await tick();
  const card = d.card(item.id);
  assert.ok(card.querySelector('[data-copy]'));
  assert.ok(card.querySelector('[data-focus-key="preview"]'));
  assert.doesNotMatch(card.textContent, /линкний хугацаа дууссан/);
  d.w.Date.now = () => clock + 2000;
  await d.refresh();
  assert.equal(d.card(item.id), card);
  assert.equal(card.querySelector('[data-copy]'), null);
  assert.equal(card.querySelector('[data-focus-key="preview"]'), null);
  assert.match(card.textContent, /линкний хугацаа дууссан/);
  assert.match(card.querySelector('.response-title').textContent, /Захиаг уншсан/);
  assert.equal(d.get('statResponded').textContent, '1');
  assert.equal(d.get('statWaiting').textContent, '0');
});

function sharedPlan(inviteId,fields={}) {
  return Object.assign({id:'plan-for-'+inviteId,invite_id:inviteId,role:'creator',state:'agreed',version:2,revision:2,accepted:{creator:2,partner:2},title:'Бидний шинэ төлөвлөгөө',scheduled_at:'2026-10-02T11:00:00Z',location:'Шинэ кафе',my_memory:'Хувийн тэмдэглэл DOM-д орох ёсгүй'},fields);
}

test('cards expose one main action and keep sharing and detailed history secondary',async t=>{
  const d=dashboard(t,{invites:[invitation('accepted-one','Зөвшөөрсөн',{answer:'yes'}),invitation('later-one','Өөр өдөр',{answer:'later'}),invitation('waiting-one','Хүлээгдсэн'),invitation('declined-one','Татгалзсан',{answer:'no'})]});
  await tick();
  for(const card of d.cards())assert.equal(card.querySelectorAll('[data-primary-action]').length,1);
  assert.match(d.card('accepted-one').querySelector('[data-primary-action]').textContent,/Өдөр, цагаа тохирох/);
  assert.match(d.card('later-one').querySelector('[data-primary-action]').textContent,/Шинэ өдрөө тохирох/);
  assert.ok(d.card('waiting-one').querySelector('[data-primary-action][data-copy]'));
  assert.ok(d.card('declined-one').querySelector('[data-primary-action][data-open-response]'));
  assert.equal(d.card('declined-one').querySelector('a[href*="date-plan"]'),null);
  assert.equal(d.card('accepted-one').querySelector('[data-panel="response"]').open,false);
  assert.equal(d.card('accepted-one').querySelector('[data-panel="options"]').open,false);
});

test('one invitation opens immediately and records its visible response as seen on this browser',async t=>{
  const item=invitation('single-invite','Номин',{answer:'yes'});
  const d=dashboard(t,{invites:[item]});await tick();
  assert.equal(d.card(item.id).querySelector('[data-panel="response"]').open,true);
  assert.equal(d.get('inviteSearch').closest('.search-field').hidden,true);
  assert.equal(d.get('statNew').textContent,'0');
  const stored=JSON.parse(d.w.localStorage.getItem('bolzoo:responses:seen:v1'));
  assert.equal(stored[item.id],d.w.BolzooResponses.responseVersion(item));
});

test('new badges persist until opened, survive reload correctly and detect later changed responses',async t=>{
  let items=[invitation('new-first','Номин',{answer:'yes'}),invitation('new-second','Саруул',{answer:'later'})];
  const d=dashboard(t,{api:{listMyInvites:async()=>items}});await tick();
  assert.equal(d.get('statNew').textContent,'2');
  d.card('new-first').querySelector('[data-view-response]').click();
  assert.equal(d.get('statNew').textContent,'1');
  assert.equal(d.card('new-first').querySelector('.new-badge'),null);
  const stored=JSON.parse(d.w.localStorage.getItem('bolzoo:responses:seen:v1'));
  const restored=dashboard(t,{invites:items,seen:stored});await tick();
  assert.equal(restored.get('statNew').textContent,'1');
  items=items.map(x=>x.id==='new-first'?{...x,response:{answer:'later'}}:x);
  await d.refresh();assert.equal(d.get('statNew').textContent,'2');
  assert.ok(d.card('new-first').querySelector('.new-badge'));
});

test('opening a response from the new filter retains the card while the unread count becomes accurate',async t=>{
  const d=dashboard(t,{invites:[invitation('new-one','Номин',{answer:'yes'}),invitation('waiting-two','Бат')]});await tick();
  d.w.document.querySelector('[data-filter="new"]').click();
  d.card('new-one').querySelector('.new-badge').click();
  assert.equal(d.get('statNew').textContent,'0');
  assert.ok(d.card('new-one'));assert.equal(d.card('new-one').querySelector('[data-panel="response"]').open,true);
  d.w.document.querySelector('[data-filter="all"]').click();d.w.document.querySelector('[data-filter="new"]').click();
  assert.equal(d.cards().length,0);assert.match(d.get('list').textContent,/Шинэ хариу алга/);
});

test('focused invitation links open the matching owned response once and polling never scrolls or reorders it',async t=>{
  let items=[invitation('focus-first','Номин',{answer:'yes'}),invitation('focus-second','Саруул')];
  const d=dashboard(t,{query:'?invite=focus-second',api:{listMyInvites:async()=>items}});await tick();
  assert.deepEqual(d.scrolls,['invite-focus-second']);
  assert.equal(d.card('focus-second').querySelector('[data-panel="response"]').open,true);
  const order=d.cards().map(x=>x.dataset.inviteId);
  items=items.map(x=>x.id==='focus-second'?{...x,response:{answer:'later'},responded_at:'2026-09-22T10:00:00Z'}:x);
  await d.refresh();assert.deepEqual(d.scrolls,['invite-focus-second']);assert.deepEqual(d.cards().map(x=>x.dataset.inviteId),order);
  assert.equal(d.get('newResponseNotice').hidden,false);
  d.get('viewNewResponse').click();assert.deepEqual(d.scrolls,['invite-focus-second','invite-focus-second']);
  assert.equal(d.get('newResponseNotice').hidden,true);
});

test('a focused ID absent from the owned list never grants access and points to recovery',async t=>{
  const d=dashboard(t,{query:'?invite=not-owned-123',invites:[invitation('owned-invite','Номин')]});await tick();
  assert.equal(d.card('not-owned-123'),null);assert.deepEqual(d.scrolls,[]);
  assert.match(d.get('pageFeedback').textContent,/хувийн кодоо/);
  d.w.document.querySelector('.recover-shortcut').click();assert.equal(d.get('recoverBox').open,true);
});

test('an accepted invitation with a pending revised plan never claims mutual agreement or exports its old calendar',async t=>{
  const item=invitation('revised-invite','Номин',{answer:'yes',dateISO:DATE,time:'18:30'});
  const d=dashboard(t,{invites:[item],planAPI:{get:async()=>sharedPlan(item.id,{state:'proposed',accepted:{creator:2,partner:1}})}});await tick();
  assert.match(d.card(item.id).querySelector('.response-title').textContent,/Урилгыг зөвшөөрсөн/);
  assert.match(d.card(item.id).querySelector('.plan-summary').textContent,/зөвшөөрөл хүлээж/);
  assert.doesNotMatch(d.card(item.id).textContent,/Хоёулаа тохирлоо/);
  assert.equal(d.card(item.id).querySelector('[data-calendar]'),null);
  assert.doesNotMatch(d.w.document.body.textContent,/Хувийн тэмдэглэл DOM/);
});

test('plan reads use two workers and load only the initial six visible fallback cards',async t=>{
  const pending=[],calls=[];let active=0,maxActive=0;
  const d=dashboard(t,{invites:Array.from({length:9},(_,i)=>invitation('bounded-'+i,'Нэр '+i,{answer:'yes'})),planAPI:{get:id=>{calls.push(id);active++;maxActive=Math.max(maxActive,active);return new Promise(resolve=>pending.push(()=>{active--;resolve(sharedPlan(id));}));}}});
  await tick();assert.equal(calls.length,2);
  while(pending.length){pending.splice(0).forEach(resolve=>resolve());await tick();}
  assert.equal(maxActive,2);assert.equal(calls.length,6);
  assert.equal(d.cards().length,9);
});

test('a failed or forbidden plan refresh removes an old agreement and keeps invitation answers available',async t=>{
  for(const status of [403,503]){
    const item=invitation('plan-fail-'+status,'Номин',{answer:'yes',dateISO:DATE,time:'18:30'});let fail=false;
    const d=dashboard(t,{invites:[item],planAPI:{get:async()=>{if(fail){const e=new Error('private backend error');e.status=status;throw e;}return sharedPlan(item.id);}}});
    await tick();assert.match(d.card(item.id).textContent,/Хоёулаа тохирлоо/);
    fail=true;await d.refresh();await tick();
    assert.doesNotMatch(d.card(item.id).textContent,/Хоёулаа тохирлоо|private backend error/);
    assert.match(d.card(item.id).querySelector('.response-title').textContent,/Урилгыг зөвшөөрсөн/);
    assert.equal(d.card(item.id).querySelector('[data-calendar]'),null);
  }
});

test('calendar download revalidates the plan and exports its latest agreed date instead of the invitation date',async t=>{
  const item=invitation('calendar-plan','Номин',{answer:'yes',dateISO:DATE,time:'18:30'});let plan=sharedPlan(item.id),reads=0,blob;
  const d=dashboard(t,{invites:[item],planAPI:{get:async()=>{reads++;return plan;}}});await tick();
  d.w.URL.createObjectURL=value=>{blob=value;return 'blob:test';};d.w.URL.revokeObjectURL=()=>{};d.w.HTMLAnchorElement.prototype.click=function(){};
  plan={...plan,version:3,revision:3,accepted:{creator:3,partner:3},scheduled_at:'2026-10-03T12:00:00Z'};
  d.card(item.id).querySelector('[data-calendar]').click();await tick();
  assert.equal(reads,2);assert.ok(blob);
  const content=await new Promise(resolve=>{const reader=new d.w.FileReader();reader.onload=()=>resolve(reader.result);reader.readAsText(blob);});
  assert.match(content,/DTSTART:20261003T120000Z/);assert.doesNotMatch(content,/DTSTART:20260920/);
  assert.match(d.card(item.id).querySelector('.plan-date').textContent,/2026\.10\.03 · 20:00/);
});

test('a mutually agreed plan can be calendared before a separate invitation answer without relabeling that answer',async t=>{
  const item=invitation('plan-no-answer','Номин');
  const d=dashboard(t,{invites:[item],planAPI:{get:async()=>sharedPlan(item.id)}});await tick();
  assert.match(d.card(item.id).querySelector('.response-title').textContent,/Линк хараахан нээгдээгүй/);
  assert.match(d.card(item.id).querySelector('.plan-summary').textContent,/Хоёулаа тохирлоо/);
  assert.ok(d.card(item.id).querySelector('[data-calendar]'));
  assert.match(d.card(item.id).querySelector('.plan-date').textContent,/2026\.10\.02 · 19:00/);
});
