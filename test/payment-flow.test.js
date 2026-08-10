const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const createHtml = fs.readFileSync(path.join(root, 'create.html'), 'utf8');
const payHtml = fs.readFileSync(path.join(root, 'pay.html'), 'utf8');
const paymentApi = fs.readFileSync(path.join(root, 'lib', 'payment-api.js'), 'utf8');
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

test('mobile template picker is explicit and keeps two touch-friendly columns', () => {
  assert.match(createHtml, /Crush-д эхэлж харагдах загвараа сонго/);
  assert.match(createHtml, /ask-template-state">✓ Сонгосон/);
  assert.match(createHtml, /\.template-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\); gap:10px;\}/);
  assert.match(createHtml, /доорх “Preview” товчоор бүтнээр нь хараарай/);
});

test('opening discount appears only on final step and price is 9,900 MNT', () => {
  const step1 = createHtml.indexOf('class="wizard-step active" data-step="1"');
  const step2 = createHtml.indexOf('class="wizard-step" data-step="2"');
  const step5 = createHtml.indexOf('class="wizard-step" data-step="5"');
  const discount = createHtml.indexOf('🔥 Нээлтийн хямдрал');

  assert.equal(createHtml.slice(step1, step2).includes('price-splash'), false);
  assert.ok(discount > step5, 'discount panel must be in the payment step');
  assert.equal(createHtml.includes('10,100'), false);
  assert.match(createHtml, /9,900₮/);
  assert.match(paymentApi, /env\.PRICE_MNT \|\| 9900/);
  assert.match(serverJs, /process\.env\.PRICE_MNT \|\| 9900/);
});

test('create page intro is visible only on the first wizard step', () => {
  assert.match(createHtml, /class="title-block" id="createIntro"/);
  assert.match(createHtml, /if\(createIntro\) createIntro\.hidden = n !== 1/);
  assert.match(createHtml, /\.title-block\[hidden\]\{display:none;\}/);
});
