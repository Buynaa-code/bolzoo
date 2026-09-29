'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');
const root = path.join(__dirname, '..');
const tick = () => new Promise(resolve => setTimeout(resolve, 10));
const htmlFor = file => fs.readFileSync(path.join(root, file), 'utf8');
const inlineFor = html => [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
const invite = {
  id: 'invitation-one', created_at: '2026-09-01T00:00:00Z',
  config: {recipientName: 'Номин', senderName: 'Бат'},
  recovery_code: 'LOV-ABC234'
};

function dashboard(t, overrides = {}) {
  const html = htmlFor('dashboard.html');
  const dom = new JSDOM(html, {url: 'https://bolzoo.example/dashboard.html', runScripts: 'outside-only', virtualConsole: new VirtualConsole()});
  const w = dom.window;
  t.after(() => w.close());
  w.HTMLElement.prototype.scrollIntoView = function() {};
  w.eval(htmlFor('assets/utils.js'));
  w.eval(htmlFor('assets/responses.js'));
  w.BolzooAPI = Object.assign({
    backendKind: 'supabase', listMyInvites: async () => [],
    recoverInvite: async () => ({id: invite.id, owner_token: '11111111-1111-4111-8111-111111111111'}),
    rememberOwnedInvite() {}
  }, overrides);
  w.eval(inlineFor(html));
  return w;
}

test('empty dashboard recovery remains usable after list rerenders', async t => {
  const w = dashboard(t);
  await tick();
  const first = w.document.getElementById('emptyRecoverBtn');
  first.click();
  assert.equal(w.document.getElementById('recoverBox').open, true);
  assert.equal(w.document.activeElement.id, 'recoverCode');
  w.document.getElementById('recoverBox').open = false;
  w.document.getElementById('refresh').click();
  await tick();
  w.document.getElementById('emptyRecoverBtn').click();
  assert.equal(w.document.getElementById('recoverBox').open, true);
});

test('dashboard rejects incomplete codes, then keeps successful recovery feedback visible', async t => {
  let recovered = false;
  let calls = 0;
  const w = dashboard(t, {
    listMyInvites: async () => recovered ? [invite] : [],
    recoverInvite: async code => {calls++; assert.equal(code, 'LOV-ABC234'); recovered = true; return {id: invite.id, owner_token: '11111111-1111-4111-8111-111111111111'};}
  });
  await tick();
  w.document.getElementById('emptyRecoverBtn').click();
  const field = w.document.getElementById('recoverCode');
  const form = w.document.getElementById('recoverForm');
  form.dispatchEvent(new w.Event('submit', {cancelable: true}));
  await tick();
  assert.equal(calls, 0);
  assert.equal(field.getAttribute('aria-invalid'), 'true');
  field.value = 'lov-abc234';
  form.dispatchEvent(new w.Event('submit', {cancelable: true}));
  await tick();
  assert.equal(calls, 1);
  assert.equal(w.document.querySelectorAll('#list article').length, 1);
  assert.equal(w.document.getElementById('recoverBox').open, true);
  assert.match(w.document.getElementById('recoverStatus').textContent, /сэргээлээ/);
  assert.equal(field.hasAttribute('aria-invalid'), false);
});

test('failed refresh preserves cards and unchanged refresh preserves a focused action', async t => {
  let fail = false;
  const w = dashboard(t, {listMyInvites: async () => {if(fail) throw new Error('offline'); return [invite];}});
  await tick();
  const copy = w.document.querySelector('[data-copy]');
  copy.focus();
  w.document.getElementById('refresh').click();
  await tick();
  assert.equal(w.document.querySelector('[data-copy]'), copy);
  assert.equal(w.document.activeElement, copy);
  fail = true;
  w.document.getElementById('refresh').click();
  await tick();
  assert.equal(w.document.getElementById('loadError').hidden, false);
  assert.equal(w.document.querySelector('[data-copy]'), copy);
  assert.equal(w.document.getElementById('list').getAttribute('aria-busy'), 'false');
  fail = false;
  w.document.getElementById('retryLoadBtn').click();
  await tick();
  assert.equal(w.document.getElementById('loadError').hidden, true);
});

test('failed initial dashboard load offers retry without implying invitations are missing', async t => {
  let fail = true;
  const w = dashboard(t, {listMyInvites: async () => {if(fail) throw new Error('offline'); return [invite];}});
  await tick();
  assert.equal(w.document.getElementById('empty'), null);
  assert.equal(w.document.getElementById('loadError').hidden, false);
  assert.equal(w.document.getElementById('statTotal').textContent, '—');
  fail = false;
  w.document.getElementById('retryLoadBtn').click();
  await tick();
  assert.equal(w.document.querySelectorAll('#list article').length, 1);
});

test('dashboard clipboard denial offers a manual copy path', async t => {
  const w = dashboard(t, {listMyInvites: async () => [invite]});
  Object.defineProperty(w.navigator, 'clipboard', {value: {writeText: async () => {throw new Error('denied');}}});
  w.document.execCommand = () => false;
  await tick();
  w.document.querySelector('[data-copy]').click();
  await tick();
  const feedback = w.document.getElementById('pageFeedback');
  assert.equal(feedback.hidden, false);
  assert.match(feedback.textContent, /гараар/);
  assert.match(feedback.textContent, /bolzoo\.html\?id=invitation-one/);
  assert.match(w.document.querySelector('[data-copy]').textContent, /Линк хуулах/);
});

function checkout(t, payment) {
  const html = htmlFor('pay.html');
  const token = Date.now() + '-' + 'a'.repeat(64);
  const dom = new JSDOM(html, {url: 'https://bolzoo.example/pay.html?intent=pi_ux#payment_token=' + token, runScripts: 'outside-only', virtualConsole: new VirtualConsole()});
  const w = dom.window;
  t.after(() => w.close());
  w.fetch = async url => ({ok: true, status: 200,
    json: async () => ({price: 9900}),
    text: async () => JSON.stringify(Object.assign({intent_id:'pi_ux', amount:9900, mode:'live', next_action:null}, payment))
  });
  w.eval(inlineFor(html));
  return w;
}

test('canceled checkout removes unusable payment methods while keeping explicit retry', async t => {
  const w = checkout(t, {status: 'canceled'});
  await tick();
  assert.equal(w.document.getElementById('paymentMethods').hidden, true);
  assert.equal(w.document.getElementById('retryBtn').hidden, false);
  assert.equal(w.document.getElementById('cancelBtn').hidden, true);
  assert.match(w.document.getElementById('statusGuidance').textContent, /Төлбөр хийгээгүй бол/);
});

test('paid checkout never reports false clipboard success', async t => {
  const w = checkout(t, {status: 'succeeded', code: 'LOV-ABC234'});
  w.document.execCommand = () => false;
  await tick();
  assert.equal(w.document.getElementById('completeStep').getAttribute('aria-current'), 'step');
  w.document.getElementById('copyBtn').click();
  await tick();
  assert.match(w.document.getElementById('copyFeedback').textContent, /Хуулж чадсангүй/);
  assert.equal(w.document.getElementById('copyBtn').classList.contains('copied'), false);
});
