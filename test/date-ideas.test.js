'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('jsdom');

const source = fs.readFileSync(path.join(__dirname, '..', 'assets', 'date-ideas.js'), 'utf8');
function browser(t, initialNote = '') {
  const dom = new JSDOM(`<!doctype html><body data-experience="date">
    <button type="button" data-date-idea="coffee"><span>Coffee</span></button>
    <button type="button" data-date-idea="unknown">Unknown</button>
    <button type="button" data-experience-choice="apology">Change mode</button>
    <section id="ideaSpotlight"><h3 id="ideaSpotlightTitle"></h3><p id="ideaSpotlightNote"></p></section>
    <button type="button" id="shuffleDateIdea">Another idea</button>
    <button type="button" id="useSpotlightIdea">Use this idea</button>
    <textarea id="customNote" maxlength="120"></textarea>
    <div id="noteIdeas"></div>
    <div id="noteIdeaConfirm" hidden><p id="pendingIdeaNote"></p>
      <button type="button" id="confirmIdeaNote">Replace</button>
      <button type="button" id="cancelIdeaNote">Keep my note</button>
    </div><p id="noteIdeaStatus"></p>
  </body>`, {runScripts: 'outside-only'});
  t.after(() => dom.window.close());
  const w = dom.window;
  const d = w.document;
  const appliedIdeas = [];
  const appliedNotes = [];
  d.getElementById('customNote').value = initialNote;
  w.eval(source);
  const options = {
    applyIdea(idea) { appliedIdeas.push(idea); },
    applyNote(note) {
      appliedNotes.push(note);
      d.getElementById('customNote').value = note;
    }
  };
  const controller = w.BolzooDateIdeas.init(options);
  return {w, d, options, controller, appliedIdeas, appliedNotes,
    note: d.getElementById('customNote'), panel: d.getElementById('noteIdeaConfirm')};
}

test('presets fit the supported invitation themes, templates and note length', t => {
  const {w} = browser(t);
  const presets = Array.from(w.BolzooDateIdeas.presets);
  assert.deepEqual(presets.map(idea => [idea.id, idea.theme, idea.template]), [
    ['coffee', 'coral', 'letter'], ['picnic', 'mint', 'dreamy'], ['cinema', 'lavender', 'ticket']
  ]);
  for(const idea of presets) {
    assert.ok(idea.note.length > 0 && idea.note.length <= 120);
    assert.ok(idea.title && idea.label && idea.emoji && idea.description);
  }
});

test('initialization offers native note buttons without changing the draft', t => {
  const {d, appliedIdeas, appliedNotes, note} = browser(t, 'Миний өөрийн зурвас');
  assert.equal(note.value, 'Миний өөрийн зурвас');
  assert.equal(d.querySelectorAll('#noteIdeas button[type="button"]').length, 3);
  assert.equal(d.getElementById('noteIdeaStatus').getAttribute('role'), 'status');
  assert.equal(d.getElementById('ideaSpotlight').dataset.selectedIdea, 'coffee');
  assert.deepEqual(appliedIdeas, []);
  assert.deepEqual(appliedNotes, []);
});

test('shuffle always shows a different idea and applies it only on explicit use', t => {
  const {w, d, appliedIdeas, appliedNotes} = browser(t);
  w.Math.random = () => 0;
  const spotlight = d.getElementById('ideaSpotlight');
  d.getElementById('shuffleDateIdea').click();
  assert.equal(spotlight.dataset.selectedIdea, 'picnic');
  assert.equal(d.getElementById('ideaSpotlightNote').textContent, w.BolzooDateIdeas.presets[1].note);
  assert.deepEqual(appliedIdeas, []);
  assert.deepEqual(appliedNotes, []);
  d.getElementById('shuffleDateIdea').click();
  assert.equal(spotlight.dataset.selectedIdea, 'coffee');
  d.getElementById('useSpotlightIdea').click();
  assert.equal(appliedIdeas.length, 1);
  assert.equal(appliedIdeas[0].id, 'coffee');
});

test('idea cards handle nested click targets and ignore unknown preset IDs', t => {
  const {d, appliedIdeas, appliedNotes} = browser(t);
  d.querySelector('[data-date-idea="coffee"] span').click();
  d.querySelector('[data-date-idea="unknown"]').click();
  d.getElementById('ideaSpotlight').dataset.selectedIdea = '__proto__';
  d.getElementById('useSpotlightIdea').click();
  const invalidNote = d.createElement('button');
  invalidNote.dataset.noteIdea = 'constructor';
  d.getElementById('noteIdeas').appendChild(invalidNote);
  invalidNote.click();
  assert.equal(appliedIdeas.length, 1);
  assert.equal(appliedIdeas[0].id, 'coffee');
  assert.deepEqual(appliedNotes, []);
});

test('an empty note accepts a suggested message and focuses the editable field', t => {
  const {w, d, appliedNotes, note, panel} = browser(t);
  d.querySelector('[data-note-idea="picnic"]').click();
  assert.deepEqual(appliedNotes, [w.BolzooDateIdeas.presets[1].note]);
  assert.equal(note.value, w.BolzooDateIdeas.presets[1].note);
  assert.equal(d.activeElement, note);
  assert.equal(panel.hidden, true);
});

test('cancelling note replacement preserves writing and restores the triggering button', t => {
  const {w, d, appliedNotes, note, panel} = browser(t, 'Чиний төрсөн өдөрт зориуллаа.');
  const trigger = d.querySelector('[data-note-idea="cinema"]');
  trigger.click();
  assert.equal(panel.hidden, false);
  assert.equal(d.activeElement.id, 'confirmIdeaNote');
  assert.equal(d.getElementById('pendingIdeaNote').textContent, w.BolzooDateIdeas.presets[2].note);
  assert.equal(note.value, 'Чиний төрсөн өдөрт зориуллаа.');
  assert.deepEqual(appliedNotes, []);
  d.getElementById('cancelIdeaNote').click();
  assert.equal(panel.hidden, true);
  assert.equal(note.value, 'Чиний төрсөн өдөрт зориуллаа.');
  assert.equal(d.activeElement, trigger);
  assert.deepEqual(appliedNotes, []);
});

test('confirmation replaces the note once and selecting that same note does not ask again', t => {
  const {w, d, appliedNotes, note, panel} = browser(t, 'Миний зурвас');
  d.querySelector('[data-note-idea="coffee"]').click();
  d.getElementById('confirmIdeaNote').click();
  d.getElementById('confirmIdeaNote').click();
  d.querySelector('[data-note-idea="coffee"]').click();
  assert.equal(appliedNotes.length, 1);
  assert.equal(note.value, w.BolzooDateIdeas.presets[0].note);
  assert.equal(panel.hidden, true);
});

test('editing the note invalidates an earlier replacement confirmation', t => {
  const {w, d, appliedNotes, note, panel} = browser(t, 'Эхний зурвас');
  d.querySelector('[data-note-idea="coffee"]').click();
  note.value = 'Дахин зассан миний зурвас';
  note.dispatchEvent(new w.Event('input', {bubbles: true}));
  d.getElementById('confirmIdeaNote').click();
  assert.equal(note.value, 'Дахин зассан миний зурвас');
  assert.deepEqual(appliedNotes, []);
  assert.equal(panel.hidden, true);
});

test('switching experience clears pending confirmation and blocks stale note application', async t => {
  const {d, appliedNotes, note, panel} = browser(t, 'Миний зурвас');
  d.querySelector('[data-note-idea="coffee"]').click();
  d.body.dataset.experience = 'apology';
  d.getElementById('confirmIdeaNote').click();
  d.querySelector('[data-note-idea="picnic"]').click();
  await Promise.resolve();
  assert.equal(panel.hidden, true);
  assert.equal(note.value, 'Миний зурвас');
  assert.deepEqual(appliedNotes, []);
  d.body.dataset.experience = 'date';
  await Promise.resolve();
  d.getElementById('confirmIdeaNote').click();
  assert.deepEqual(appliedNotes, []);
});

test('reinitializing does not duplicate click handlers or generated note buttons', t => {
  const {w, d, options, appliedIdeas} = browser(t);
  w.BolzooDateIdeas.init(options);
  d.querySelector('[data-date-idea="coffee"]').click();
  assert.equal(appliedIdeas.length, 1);
  assert.equal(d.querySelectorAll('#noteIdeas [data-note-idea]').length, 3);
});
