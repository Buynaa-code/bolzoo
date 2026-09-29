const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

const root = path.join(__dirname, '..');
const createHtml = fs.readFileSync(path.join(root, 'create.html'), 'utf8');
const payHtml = fs.readFileSync(path.join(root, 'pay.html'), 'utf8');
const paymentApi = fs.readFileSync(path.join(root, 'lib', 'payment-api.js'), 'utf8');
const browserApi = fs.readFileSync(path.join(root, 'assets', 'api.js'), 'utf8');
const serverJs = fs.readFileSync(path.join(root, 'server.js'), 'utf8');

test('access code gate is shown only on the final create step', () => {
  const step2 = createHtml.indexOf('class="wizard-step" data-step="2"');
  const step3 = createHtml.indexOf('class="wizard-step" data-step="3"');
  const step5 = createHtml.indexOf('class="wizard-step" data-step="5"');
  const codeGate = createHtml.indexOf('id="codeGate"');

  assert.ok(step2 >= 0 && step3 > step2 && step5 > step3);
  assert.ok(codeGate > step5, 'code gate must be inside the final step');
  assert.equal(createHtml.slice(step2, step3).includes('id="accessCode"'), false);
});

test('create payment preserves the draft and asks pay page to return and publish', () => {
  assert.match(createHtml, /saveDraft\(\);\s*window\.location\.href = 'pay\.html\?from=create'/);
  assert.match(createHtml, /step: \(typeof currentStep === 'number'/);
  assert.match(createHtml, /urlCode && urlHasPublishIntent\(\) && validCode/);
  assert.match(createHtml, /setTimeout\(function\(\)\{ \$\('generate'\)\.click\(\); \}, 350\)/);
});

test('successful create payment returns with the one-time code and auto-publishes', () => {
  assert.match(payHtml, /returnToCreate = new URLSearchParams\(location\.search\)\.get\('from'\) === 'create'/);
  assert.match(payHtml, /createHref \+= '&publish=1'/);
  assert.match(payHtml, /location\.replace\(createHref\)/);
});

test('published invite clearly shows the private response recovery code', () => {
  assert.match(createHtml, /id="successAccessCode"/);
  assert.match(createHtml, /Энэ кодоор урилгын хариуг харна/);
  assert.match(createHtml, /openSuccessModal\(url, \$\('recipientName'\)\.value\.trim\(\), buildRecoveryUrl\(inviteId, ownerToken\), accessCode\)/);
  assert.match(payHtml, /Энэ кодоор урилгын хариугаа харна/);
  assert.match(browserApi, /setRecoveryCode\(row\.id, accessCode\)/);
});

test('mobile template picker is explicit and keeps two touch-friendly columns', () => {
  const document = JSDOM.fragment(createHtml);
  const choices = [...document.querySelectorAll('#askTemplates [data-ask-template]')];
  assert.equal(choices.length, 4);
  choices.forEach(choice => {
    assert.equal(choice.tagName, 'BUTTON');
    assert.equal(choice.type, 'button');
    assert.ok(choice.getAttribute('aria-label'));
    assert.match(choice.querySelector('.ask-template-state').textContent, /Сонгосон/);
  });
  assert.match(createHtml, /\.template-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\); gap:10px;\}/);
  assert.match(document.querySelector('.template-preview-hint').textContent, /“Урьдчилан харах” товчоор/);
  assert.equal(document.querySelector('#previewDockText').textContent.trim(), 'Урьдчилан харах');
});

test('the one-time price is disclosed upfront and the payment panel belongs to the final step', () => {
  const document = JSDOM.fragment(createHtml);
  const checkout = JSDOM.fragment(payHtml);
  const pricePanel = document.querySelector('.price-splash');

  assert.equal(document.querySelector('#welcomePrice').textContent.trim(), '9,900₮');
  assert.equal(pricePanel.closest('.wizard-step').dataset.step, '5');
  assert.equal(document.querySelector('.wizard-step[data-step="1"] .price-splash'), null);
  assert.match(pricePanel.textContent, /Нэг удаагийн төлбөр/);
  assert.equal(pricePanel.querySelector('.price-splash-new').textContent.trim(), '9,900₮');
  assert.match(checkout.querySelector('#priceBlock').textContent, /Нэг удаагийн төлбөр/);
  assert.equal(pricePanel.querySelector('.price-splash-old, .price-splash-badge'), null);
  assert.equal(checkout.querySelector('#regularPriceBlock').hidden, true);
  assert.equal(checkout.querySelector('#regularPrice').textContent, '');
  assert.equal(checkout.querySelector('#promotionNote').hidden, true);
  assert.match(paymentApi, /env\.PRICE_MNT \|\| 9900/);
  assert.match(serverJs, /process\.env\.PRICE_MNT \|\| 9900/);
});

test('choosing an invitation type hides the welcome intro and gate throughout editing', async t => {
  const dom = new JSDOM(createHtml, {
    url: 'http://localhost/create.html', runScripts: 'outside-only',
    pretendToBeVisual: true, virtualConsole: new VirtualConsole()
  });
  const w = dom.window;
  t.after(() => w.close());
  w.matchMedia = () => ({matches:false, addListener(){}, removeListener(){}, addEventListener(){}, removeEventListener(){}});
  w.HTMLElement.prototype.scrollIntoView = function(){};
  w.scrollTo = () => {};
  w.fetch = async () => ({ok:true, json:async () => ({price:9900})});
  w.BolzooAPI = {backendKind:'same-origin', listMyInvites:async () => []};
  for(const file of ['utils.js', 'posters.js', 'apology-templates.js']) {
    w.eval(fs.readFileSync(path.join(root, 'assets', file), 'utf8'));
  }
  w.eval([...createHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1]);
  await new Promise(resolve => setTimeout(resolve, 10));
  const d = w.document;
  assert.equal(d.getElementById('createIntro').hidden, false);
  assert.equal(d.getElementById('purposeGate').hidden, false);
  assert.equal(d.getElementById('createFormCard').hidden, true);

  d.querySelector('[data-experience-choice="date"]').click();
  assert.equal(d.getElementById('createIntro').hidden, true);
  assert.equal(d.getElementById('purposeGate').hidden, true);
  assert.equal(d.getElementById('createFormCard').hidden, false);
  d.querySelector('[data-ask-template="letter"]').click();
  d.getElementById('continueStep').click();
  assert.equal(d.querySelector('.wizard-step.active').dataset.step, '2');
  assert.equal(d.getElementById('createIntro').hidden, true);
  assert.equal(d.getElementById('purposeGate').hidden, true);
  d.querySelector('.steps .step[data-step="1"]').click();
  assert.equal(d.querySelector('.wizard-step.active').dataset.step, '1');
  assert.equal(d.getElementById('createIntro').hidden, true);
  assert.equal(d.getElementById('purposeGate').hidden, true);
});
