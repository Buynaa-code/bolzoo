'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'create.html'), 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
const draftKey = 'bolzoo:pending_draft';
const codeKey = 'bolzoo:pending_code';
const tick = () => new Promise(resolve => setTimeout(resolve, 10));
const response = data => ({ok: true, json: async () => data});
const validDraft = overrides => ({
  experienceType: 'date', askTemplate: 'letter', theme: 'coral',
  recipientName: 'Номин', senderName: 'Бат', step: 3, ...overrides
});

async function browser(t, options = {}) {
  const errors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', error => {
    if(!/Could not parse CSS stylesheet/.test(error.message)) errors.push(error.message);
  });
  const dom = new JSDOM(html, {
    url: 'http://localhost/create.html', runScripts: 'outside-only',
    pretendToBeVisual: true, virtualConsole
  });
  const w = dom.window;
  t.after(() => {
    w.close();
    assert.deepEqual(errors, [], 'creator interactions must not throw or unexpectedly navigate');
  });
  w.matchMedia = () => ({matches: false, addListener(){}, removeListener(){}, addEventListener(){}, removeEventListener(){}});
  w.HTMLElement.prototype.scrollIntoView = function(){};
  w.scrollTo = () => {};
  if(options.draft) w.localStorage.setItem(draftKey, JSON.stringify(options.draft));
  if(options.code) w.localStorage.setItem(codeKey, options.code);
  if(options.storageFails) {
    w.Storage.prototype.setItem = function(){ throw new w.DOMException('Storage is full', 'QuotaExceededError'); };
  }
  const published = [];
  w.BolzooAPI = {
    backendKind: 'same-origin',
    listMyInvites: async () => [],
    validateCode: async () => ({ok: true}),
    createInvite: async (config, code, privateFields) => {
      published.push({config, code, privateFields});
      return {id: 'invite-ux', ownerToken: 'owner-ux'};
    }
  };
  w.fetch = async url => {
    if(url === '/api/health') return response({price: 9900});
    if(String(url).startsWith('/api/youtube-search')) {
      return response({items: [{videoId: 'dQw4w9WgXcQ', title: 'Test song', channelTitle: 'Test artist'}]});
    }
    throw new Error('Unexpected request: ' + url);
  };
  for(const file of ['utils.js', 'posters.js', 'apology-templates.js', 'date-ideas.js']) {
    w.eval(fs.readFileSync(path.join(root, 'assets', file), 'utf8'));
  }
  w.eval(script);
  await tick();
  return {w, d: w.document, published};
}

function input(w, id, value) {
  const field = w.document.getElementById(id);
  field.value = value;
  field.dispatchEvent(new w.Event('input', {bubbles: true}));
  return field;
}
function step(d) {
  return Number(d.querySelector('.wizard-step.active').dataset.step);
}
function saved(w) {
  return JSON.parse(w.localStorage.getItem(draftKey));
}
function startDate(d) {
  d.querySelector('[data-experience-choice="date"]').click();
  d.querySelector('[data-ask-template="letter"]').click();
}

test('Continue explains an empty required name and focuses it, then accepts a correction', async t => {
  const {w, d} = await browser(t);
  startDate(d);
  const next = d.getElementById('continueStep');
  next.click();
  assert.equal(step(d), 2);
  assert.equal(next.disabled, false);
  next.click();
  const name = d.getElementById('recipientName');
  const error = d.getElementById('recipientNameError');
  assert.equal(step(d), 2);
  assert.equal(name.getAttribute('aria-invalid'), 'true');
  assert.equal(d.activeElement, name);
  assert.ok(error.textContent.trim());
  assert.ok(name.getAttribute('aria-describedby').split(' ').includes(error.id));
  input(w, 'recipientName', 'Номин');
  assert.notEqual(name.getAttribute('aria-invalid'), 'true');
  next.click();
  assert.equal(step(d), 3);
});

test('theme choices use native buttons and expose exactly one selected color', async t => {
  const {w, d} = await browser(t, {draft: validDraft()});
  const themes = [...d.querySelectorAll('#themes [data-theme]')];
  assert.ok(themes.length > 1);
  themes.forEach(button => {
    assert.equal(button.tagName, 'BUTTON');
    assert.equal(button.type, 'button');
    assert.ok(button.getAttribute('aria-label'));
    assert.equal(button.tabIndex, 0);
  });
  const chosen = d.querySelector('[data-theme="sky"]');
  chosen.focus();
  chosen.click();
  assert.equal(d.activeElement, chosen);
  assert.equal(chosen.getAttribute('aria-pressed'), 'true');
  assert.equal(d.querySelectorAll('#themes [aria-pressed="true"]').length, 1);
  assert.equal(saved(w).theme, 'sky');
});

test('a saved draft restores its step, written content and selected theme', async t => {
  const draft = validDraft({step: 4, theme: 'mint', customNote: 'Маргааш кофе уух уу?'});
  const {w, d} = await browser(t, {draft});
  assert.equal(step(d), 4);
  assert.equal(d.getElementById('createFormCard').hidden, false);
  assert.equal(d.getElementById('recipientName').value, draft.recipientName);
  assert.equal(d.getElementById('customNote').value, draft.customNote);
  assert.equal(d.querySelector('[data-theme="mint"]').getAttribute('aria-pressed'), 'true');
  assert.equal(d.getElementById('draftState').getAttribute('role'), 'status');
  assert.ok(d.getElementById('draftState').textContent.trim());
  assert.equal(saved(w).customNote, draft.customNote);
});

test('storage failure warns the user while preserving editing and step navigation', async t => {
  const {w, d} = await browser(t, {draft: validDraft({step: 2}), storageFails: true});
  const name = input(w, 'recipientName', 'Саруул');
  const notice = d.getElementById('draftState');
  assert.ok(notice.classList.contains('warning'));
  assert.ok(notice.textContent.trim());
  assert.equal(notice.getAttribute('aria-live'), 'polite');
  assert.equal(name.value, 'Саруул');
  assert.equal(saved(w).recipientName, 'Номин', 'a failed write must not pretend the new value was persisted');
  d.getElementById('continueStep').click();
  assert.equal(step(d), 3);
  assert.equal(name.value, 'Саруул');
});

test('an invalid map URL blocks Continue and a corrected HTTPS URL can advance', async t => {
  const {w, d} = await browser(t, {draft: validDraft({step: 4})});
  for(const value of ['javascript:alert(1)', 'maps.app.goo.gl/place', 'https://']) {
    const field = input(w, 'locationUrl', value);
    d.getElementById('continueStep').click();
    assert.equal(step(d), 4);
    assert.equal(field.getAttribute('aria-invalid'), 'true');
    assert.equal(d.activeElement, field);
    assert.ok(d.getElementById('locationUrlError').textContent.trim());
  }
  input(w, 'locationUrl', 'https://maps.app.goo.gl/example');
  d.getElementById('continueStep').click();
  assert.equal(step(d), 5);
});

test('a restored invalid map URL cannot consume a purchased code during publishing', async t => {
  const {w, d, published} = await browser(t, {
    draft: validDraft({step: 5, locationUrl: 'javascript:alert(1)'}), code: 'LOV-ABC234'
  });
  d.getElementById('generate').click();
  await tick();
  assert.equal(published.length, 0);
  assert.equal(step(d), 4);
  assert.equal(d.getElementById('locationUrl').getAttribute('aria-invalid'), 'true');
  assert.equal(w.localStorage.getItem(codeKey), 'LOV-ABC234');
  input(w, 'locationUrl', 'https://maps.app.goo.gl/example');
  d.getElementById('continueStep').click();
  d.getElementById('generate').click();
  await tick();
  assert.equal(published.length, 1);
  assert.equal(published[0].code, 'LOV-ABC234');
  assert.equal(published[0].config.locationUrl, 'https://maps.app.goo.gl/example');
});

test('a selected song can be removed from the player, selection and saved draft', async t => {
  const {w, d} = await browser(t, {draft: validDraft()});
  input(w, 'songSearch', 'Test song');
  d.getElementById('songSearchBtn').click();
  await tick();
  d.querySelector('.song-result').click();
  assert.ok(d.getElementById('videoId').value.includes('dQw4w9WgXcQ'));
  d.getElementById('videoPlayToggle').click();
  assert.ok(d.querySelector('#videoPlayer iframe'));
  d.getElementById('removeSong').click();
  assert.equal(d.getElementById('videoId').value, '');
  assert.equal(d.getElementById('videoPreview').style.display, 'none');
  assert.equal(d.querySelector('#videoPlayer iframe'), null);
  assert.equal(d.querySelector('.song-result.selected'), null);
  assert.equal(saved(w).videoId, '');
  assert.equal(d.activeElement, d.getElementById('songSearch'));
});

test('an early preview returns to editing instead of starting payment', async t => {
  const {d, published} = await browser(t);
  startDate(d);
  d.getElementById('openPreview').click();
  assert.equal(d.getElementById('previewModal').hidden, false);
  const cta = d.getElementById('previewPrimaryCta');
  assert.equal(cta.dataset.mode, 'edit');
  cta.click();
  assert.equal(d.getElementById('previewModal').hidden, true);
  assert.equal(step(d), 2);
  assert.equal(published.length, 0);
});

test('restarting requires confirmation, allows cancellation and keeps the purchased code', async t => {
  const draft = validDraft({step: 5, customNote: 'Хадгалах зурвас'});
  const {w, d, published} = await browser(t, {draft, code: 'LOV-ABC234'});
  const restart = d.getElementById('resetForm');
  restart.click();
  assert.equal(d.getElementById('resetConfirm').hidden, false);
  assert.equal(d.getElementById('recipientName').value, draft.recipientName);
  assert.equal(saved(w).customNote, draft.customNote);
  d.getElementById('cancelReset').click();
  assert.equal(d.getElementById('resetConfirm').hidden, true);
  assert.equal(d.getElementById('customNote').value, draft.customNote);
  restart.click();
  d.getElementById('confirmReset').click();
  await tick();
  assert.equal(d.getElementById('recipientName').value, '');
  assert.equal(d.getElementById('customNote').value, '');
  assert.equal(d.getElementById('purposeGate').hidden, false);
  assert.equal(w.localStorage.getItem(draftKey), null);
  assert.equal(w.localStorage.getItem(codeKey), 'LOV-ABC234');
  assert.equal(d.getElementById('accessCode').value, 'LOV-ABC234');
  assert.equal(new URLSearchParams(w.location.hash.slice(1)).get('code'), 'LOV-ABC234');
  assert.equal(published.length, 0);
});

test('the landing CTA opens a date invitation with the letter template ready', async t => {
  const {w, d, published} = await browser(t);
  assert.equal(d.getElementById('createFormCard').hidden, true);
  d.getElementById('bloomStart').click();
  assert.equal(d.body.dataset.experience, 'date');
  assert.equal(d.getElementById('createFormCard').hidden, false);
  assert.equal(d.getElementById('purposeGate').hidden, true);
  assert.equal(step(d), 1);
  assert.equal(d.querySelector('[data-ask-template="letter"]').getAttribute('aria-pressed'), 'true');
  assert.equal(saved(w).askTemplate, 'letter');
  assert.equal(saved(w).experienceType, 'date');
  assert.equal(saved(w).customNote, '');
  assert.deepEqual(published, []);
  d.getElementById('continueStep').click();
  assert.equal(step(d), 2, 'the default template must satisfy step 1 validation');
});

for(const ideaId of ['coffee', 'picnic', 'cinema']) {
  test(`the ${ideaId} date idea prepares its template, color and note and opens the names step`, async t => {
    const {w, d, published} = await browser(t);
    const idea = w.BolzooDateIdeas.presets.find(preset => preset.id === ideaId);
    d.querySelector(`[data-date-idea="${ideaId}"] .idea-card-copy strong`).click();
    assert.equal(step(d), 2);
    assert.equal(d.body.dataset.experience, 'date');
    assert.equal(d.activeElement, d.getElementById('recipientName'));
    assert.equal(d.querySelector(`[data-ask-template="${idea.template}"]`).getAttribute('aria-pressed'), 'true');
    assert.equal(d.querySelector(`[data-theme="${idea.theme}"]`).getAttribute('aria-pressed'), 'true');
    assert.equal(d.querySelectorAll('#themes [aria-pressed="true"]').length, 1);
    assert.equal(d.getElementById('customNote').value, idea.note);
    assert.equal(d.getElementById('customNoteCount').textContent, `${idea.note.length} / 120`);
    const draft = saved(w);
    assert.equal(draft.step, 2);
    assert.equal(draft.askTemplate, idea.template);
    assert.equal(draft.theme, idea.theme);
    assert.equal(draft.customNote, idea.note);
    assert.equal(draft.recipientName, '');
    assert.deepEqual(published, []);
  });
}

test('choosing an idea preserves existing personal fields and a purchased access code', async t => {
  const draft = validDraft({
    step: 4, customNote: 'Чамд зориулж өөрөө бичсэн зурвас.',
    locationName: 'Миний сонгосон газар', locationUrl: 'https://maps.app.goo.gl/example',
    specialLetter: 'Бидний дурсамжийн тухай захиа.'
  });
  const {w, d, published} = await browser(t, {draft, code: 'LOV-ABC234'});
  d.querySelector('[data-date-idea="cinema"]').click();
  const persisted = saved(w);
  for(const field of ['recipientName', 'senderName', 'customNote', 'locationName', 'locationUrl', 'specialLetter']) {
    assert.equal(d.getElementById(field).value, draft[field], `${field} must remain editable without being overwritten`);
    assert.equal(persisted[field], draft[field], `${field} must remain in the saved draft`);
  }
  assert.equal(persisted.askTemplate, 'ticket');
  assert.equal(persisted.theme, 'lavender');
  assert.equal(persisted.step, 2);
  assert.equal(w.localStorage.getItem(codeKey), 'LOV-ABC234');
  assert.equal(d.getElementById('accessCode').value, 'LOV-ABC234');
  assert.deepEqual(published, []);
});

test('suggested note cancellation preserves the draft and confirmed replacement reaches the published invitation', async t => {
  const originalNote = 'Чамтай хамт өнгөрүүлсэн өдөр бүр сайхан.';
  const {w, d, published} = await browser(t, {
    draft: validDraft({step: 4, customNote: originalNote}), code: 'LOV-ABC234'
  });
  const suggestion = w.BolzooDateIdeas.presets.find(idea => idea.id === 'picnic');
  const button = d.querySelector('#noteIdeas [data-note-idea="picnic"]');
  button.click();
  assert.equal(d.getElementById('noteIdeaConfirm').hidden, false);
  assert.equal(d.getElementById('pendingIdeaNote').textContent, suggestion.note);
  assert.equal(d.getElementById('customNote').value, originalNote);
  assert.equal(saved(w).customNote, originalNote);
  d.getElementById('cancelIdeaNote').click();
  assert.equal(d.getElementById('noteIdeaConfirm').hidden, true);
  assert.equal(saved(w).customNote, originalNote);
  assert.equal(d.activeElement, button);
  button.click();
  d.getElementById('confirmIdeaNote').click();
  assert.equal(d.getElementById('customNote').value, suggestion.note);
  assert.equal(saved(w).customNote, suggestion.note);
  assert.equal(d.getElementById('customNoteCount').textContent, `${suggestion.note.length} / 120`);
  assert.equal(d.getElementById('noteIdeaConfirm').hidden, true);
  assert.equal(w.localStorage.getItem(codeKey), 'LOV-ABC234');
  assert.deepEqual(published, []);
  d.getElementById('continueStep').click();
  assert.equal(step(d), 5);
  d.getElementById('generate').click();
  await tick();
  assert.equal(published.length, 1);
  assert.equal(published[0].code, 'LOV-ABC234');
  assert.equal(published[0].config.customNote, suggestion.note);
  assert.equal(published[0].config.recipientName, 'Номин');
});

test('opening and closing the landing demo and shuffling ideas leaves a fresh visit untouched', async t => {
  const {w, d, published} = await browser(t);
  const button = d.getElementById('openWelcomeDemo');
  const initialIdea = d.getElementById('ideaSpotlight').dataset.selectedIdea;
  button.click();
  assert.equal(button.getAttribute('aria-expanded'), 'true');
  assert.equal(d.getElementById('welcomeDemoReveal').hidden, false);
  assert.ok(d.getElementById('welcomeLetter').classList.contains('is-open'));
  button.click();
  assert.equal(button.getAttribute('aria-expanded'), 'false');
  assert.equal(d.getElementById('welcomeDemoReveal').hidden, true);
  assert.equal(d.getElementById('welcomeLetter').classList.contains('is-open'), false);
  d.getElementById('shuffleDateIdea').click();
  assert.notEqual(d.getElementById('ideaSpotlight').dataset.selectedIdea, initialIdea);
  assert.equal(d.body.dataset.experience, '');
  assert.equal(d.getElementById('createFormCard').hidden, true);
  assert.equal(w.localStorage.getItem(draftKey), null);
  assert.equal(w.localStorage.getItem(codeKey), null);
  assert.deepEqual(published, []);
});

test('a confirmed reset clears pending note replacement and allows another idea to start with the paid code', async t => {
  const {w, d, published} = await browser(t, {
    draft: validDraft({step: 4, customNote: 'Арилгах ноорог'}), code: 'LOV-ABC234'
  });
  d.querySelector('#noteIdeas [data-note-idea="coffee"]').click();
  assert.equal(d.getElementById('noteIdeaConfirm').hidden, false);
  d.getElementById('resetForm').click();
  d.getElementById('confirmReset').click();
  await tick();
  assert.equal(d.getElementById('noteIdeaConfirm').hidden, true);
  assert.equal(d.getElementById('customNote').value, '');
  assert.equal(w.localStorage.getItem(draftKey), null);
  d.getElementById('confirmIdeaNote').click();
  assert.equal(d.getElementById('customNote').value, '', 'an old note confirmation cannot revive the discarded draft');
  d.querySelector('[data-date-idea="cinema"]').click();
  await tick();
  const idea = w.BolzooDateIdeas.presets.find(preset => preset.id === 'cinema');
  assert.equal(step(d), 2);
  assert.equal(saved(w).customNote, idea.note);
  assert.equal(saved(w).askTemplate, 'ticket');
  assert.equal(saved(w).theme, 'lavender');
  assert.equal(d.getElementById('recipientName').value, '');
  assert.equal(w.localStorage.getItem(codeKey), 'LOV-ABC234');
  d.querySelector('#noteIdeas [data-note-idea="coffee"]').click();
  assert.equal(d.getElementById('noteIdeaConfirm').hidden, false, 'note suggestions stay bound after reset');
  d.getElementById('cancelIdeaNote').click();
  assert.equal(saved(w).customNote, idea.note);
  assert.deepEqual(published, []);
});
