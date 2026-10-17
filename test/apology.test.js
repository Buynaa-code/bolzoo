'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const apology = require('../assets/apology-templates.js');
const root = path.join(__dirname, '..');

test('apology template uses the couple-specific facts and preserves recipient choice', () => {
  const letter = apology.buildLetter({
    recipientName: 'Номин',
    senderName: 'Бат',
    apologyIssue: 'harsh_words',
    apologyTone: 'serious',
    apologyWhatHappened: 'уурласан үедээ чамайг сонсолгүй хатуу үг хэлсэн',
    apologyRegret: 'чамд хэрэгтэй үед чинь сонсоогүйдээ харамсаж байна',
    apologyRepair: 'маргаан эхлэхэд 20 минут завсарлаад тайван ярилцана',
    apologyDateOffer: true
  });

  assert.match(letter, /Номин минь/);
  assert.match(letter, /20 минут завсарлаад/);
  assert.match(letter, /шууд уучлах албагүй/);
  assert.match(letter, /— Бат/);
  assert.doesNotMatch(letter, /уучлах ёстой/i);
});

test('pressure phrase checker catches blame and guilt-tripping', () => {
  const warnings = apology.findPressurePhrases(
    'Гэхдээ чи ч гэсэн буруутай. Надад хайртай бол намайг уучлах ёстой.'
  );
  assert.ok(warnings.length >= 3);
});

test('recipient statuses are fixed and include a final no-contact choice', () => {
  assert.deepEqual(Object.keys(apology.statuses), [
    'needs_space', 'read', 'message', 'meet', 'stop'
  ]);
  assert.match(apology.status('stop').label, /холбоо барихгүй/);
});

test('all bundled paper textures are exposed through the safe paper registry', () => {
  assert.deepEqual(Object.keys(apology.papers), [
    'soft', 'dotted', 'grid', 'handmade', 'linen', 'clean'
  ]);
  for (const paper of Object.values(apology.papers)) {
    assert.match(paper.image, /^assets\/images\/papers\//);
    assert.ok(fs.existsSync(path.join(root, paper.image)));
  }
});

test('create, recipient, API and migration all carry the apology contract', () => {
  const createHtml = fs.readFileSync(path.join(root, 'create.html'), 'utf8');
  const recipientHtml = fs.readFileSync(path.join(root, 'bolzoo.html'), 'utf8');
  const inviteApi = fs.readFileSync(path.join(root, 'api', 'invite.js'), 'utf8');
  const migration = fs.readFileSync(
    path.join(root, 'supabase', 'migrations', '20260810063211_apology_invite_safety.sql'),
    'utf8'
  );
  const progressMigration = fs.readFileSync(
    path.join(root, 'supabase', 'migrations', '20260810070502_apology_readiness_progress.sql'),
    'utf8'
  );

  assert.match(createHtml, /data-experience-choice="apology"/);
  assert.match(createHtml, /9,900₮/);
  assert.match(recipientHtml, /id="apologyStatuses"/);
  assert.match(recipientHtml, /id="apologyReadiness"/);
  assert.match(recipientHtml, /readinessPercent/);
  assert.match(recipientHtml, /introFlowerStorm/);
  assert.equal((recipientHtml.match(/data-apology-scene="[1-5]"/g) || []).length, 5);
  assert.match(recipientHtml, /id="sorryHeart"/);
  assert.match(recipientHtml, /Хариу өгөх хэсэг рүү шууд очих/);
  assert.match(createHtml, /id="apologyPapers"/);
  assert.match(inviteApi, /'apologyLetter'/);
  assert.match(inviteApi, /'apologyPaper'/);
  assert.match(inviteApi, /Invite expired/);
  assert.match(migration, /needs_space.*read.*message.*meet.*stop/s);
  assert.match(migration, /interval '31 days'/);
  assert.match(progressMigration, /readinessPercent/);
  assert.match(progressMigration, /mod\(readiness_percent, 10\)/);
  assert.match(progressMigration, /Invalid apology paper/);
});
