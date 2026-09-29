'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const catalog = require('../assets/mission-catalog');

test('canonical ideas contain ready invitations and bounded three-step snapshots', () => {
  assert.equal(catalog.ideas.length, 18);
  assert.equal(new Set(catalog.ideas.map(x => x.id)).size, catalog.ideas.length);
  for (const idea of catalog.ideas) {
    assert.equal(catalog.get(idea.id), idea);
    assert.equal(idea.version, 1);
    assert.ok(idea.title && idea.description && idea.emoji && idea.preparation && idea.fallback);
    assert.ok(idea.inviteNote.length > 0 && idea.inviteNote.length <= 120);
    assert.ok(['coral','mint','lavender'].includes(idea.theme));
    assert.ok(['letter','ticket','dreamy'].includes(idea.inviteTemplate));
    assert.equal(idea.budget.scope, 'two_people');
    assert.ok(idea.duration.min > 0 && idea.duration.max >= idea.duration.min);
    assert.deepEqual(idea.steps.map(x => x.id), ['before','together','after']);
    for (const step of idea.steps) assert.ok((step.title + ' — ' + step.description).length <= 500);
    assert.equal(Object.isFrozen(idea.steps[0]), true);
  }
  assert.equal(catalog.get('__proto__'), null);
  assert.equal(catalog.get('made-up-place'), null);
  assert.match(catalog.get('movie-and-talk').notice, /тасалбараа тусад нь/);
});

test('filters combine real constraints without inventing an available idea', () => {
  assert.equal(catalog.filter().length, catalog.ideas.length);
  assert.deepEqual(catalog.filter({environment:'outdoor',budget:'free',duration:'short'}).map(x=>x.id), ['city-observations','outdoor-sketch','park-word-games']);
  assert.deepEqual(catalog.filter({environment:'outdoor',duration:'evening'}), []);
  assert.ok(catalog.filter({budget:'free'}).every(x=>x.budget.category==='free'));
});

test('original snapshot IDs and versions remain available when new templates are added', () => {
  const original=['coffee-questions','movie-and-talk','favorite-food','coffee-walk','book-shelves','art-together','two-desserts','board-game','cook-together','tea-break','two-playlists','city-observations'];
  assert.deepEqual(catalog.ideas.slice(0,12).map(x=>x.id),original);
  for(const id of original)assert.equal(catalog.get(id).version,1);
  assert.equal(catalog.get('movie-and-talk').inviteTemplate,'ticket');
  assert.equal(catalog.get('coffee-walk').theme,'mint');
});

test('five quick presets provide three distinct matching suggestions with editorial defaults', () => {
  assert.deepEqual(catalog.quickPresets.map(x=>x.label),['Богино болзоо','Бүтэн орой','Бага зардлаар','Дотор','Гадаа']);
  assert.deepEqual(catalog.getSuggestions().slice(0,3).map(x=>x.id),['coffee-questions','coffee-walk','movie-and-talk']);
  const matches={short:x=>x.duration.category==='short',evening:x=>x.duration.category==='evening'&&x.duration.min>=150,low:x=>['free','low'].includes(x.budget.category),indoor:x=>x.environment==='indoor',outdoor:x=>x.environment==='outdoor'};
  for(const preset of catalog.quickPresets){
    const suggestions=catalog.getSuggestions(preset.id);
    assert.ok(suggestions.length>=3,preset.id);
    assert.equal(new Set(suggestions.map(x=>x.id)).size,suggestions.length);
    assert.ok(suggestions.every(matches[preset.id]),preset.id);
  }
  assert.deepEqual(catalog.getSuggestions('evening').slice(0,3).map(x=>x.id),['cinema-and-dinner','dinner-and-games','art-and-dinner']);
  assert.ok(catalog.getSuggestions('low').some(x=>x.budget.category==='free'));
  assert.ok(catalog.getSuggestions('low').some(x=>x.budget.category==='low'));
  assert.equal(Object.isFrozen(catalog.quickPresets[0]),true);
});

test('suggestion filters preserve criteria and never recycle identical IDs as more results', () => {
  assert.deepEqual(catalog.getSuggestions('evening',{environment:'outdoor'}),[]);
  const outdoors=catalog.getSuggestions('outdoor',{budget:'free'});
  assert.ok(outdoors.length>=3);
  assert.ok(outdoors.every(x=>x.environment==='outdoor'&&x.budget.category==='free'));
  const initial=catalog.getSuggestions().slice(0,3).map(x=>x.id);
  const more=catalog.getSuggestions().slice(3,6).map(x=>x.id);
  assert.ok(more.every(id=>!initial.includes(id)));
  assert.deepEqual(catalog.getSuggestions('__proto__'),catalog.getSuggestions());
});
