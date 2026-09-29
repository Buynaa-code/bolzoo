'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
const PNG = 'data:image/png;base64,iVBORw0KGgo=';
const URL_ONE = 'https://bolzoo.example/bolzoo.html?id=invite-one';

function qrBrowser(t, options = {}) {
  const dom = new JSDOM('<body><div id="downloads"></div></body>', {
    url: 'https://bolzoo.example/create.html', runScripts: 'outside-only'
  });
  t.after(() => dom.window.close());
  const w = dom.window;
  const canvases = [], payloads = [], codes = [], clicks = [], requests = [];
  w.fetch = url => { requests.push(url); throw new Error('Unexpected network request'); };
  w.XMLHttpRequest = function() { requests.push('XMLHttpRequest'); throw new Error('Unexpected network request'); };
  w.HTMLCanvasElement.prototype.getContext = function(type) {
    assert.equal(type, '2d');
    if (options.contextError) throw new Error('Canvas unavailable');
    if (options.noContext) return null;
    const entry = {canvas: this, rects: []};
    canvases.push(entry);
    return {
      fillStyle: '#000000',
      fillRect(x, y, width, height) {
        entry.rects.push({x, y, width, height, color: this.fillStyle});
      }
    };
  };
  w.HTMLCanvasElement.prototype.toDataURL = function(type) {
    assert.equal(type, 'image/png');
    if (options.exportError) throw new Error('PNG export unavailable');
    return options.exportValue === undefined ? PNG : options.exportValue;
  };
  w.HTMLAnchorElement.prototype.click = function() {
    clicks.push({href: this.href, filename: this.download, parent: this.parentElement, connected: this.isConnected});
    if (options.clickError) throw new Error('Download unavailable');
  };
  if (!options.omitEncoder) {
    w.eval(read('assets/vendor/qrcode.js'));
    const encoder = w.qrcode;
    w.qrcode = function(...args) {
      const code = encoder(...args);
      const addData = code.addData;
      code.addData = function(value, ...rest) { payloads.push(value); return addData(value, ...rest); };
      codes.push(code);
      return code;
    };
  }
  w.eval(read('assets/qr.js'));
  t.after(() => assert.deepEqual(requests, [], 'QR generation and download must remain local'));
  return {w, qr: w.BolzooQR, canvases, payloads, codes, clicks};
}

function isBlack(color) { return /^(?:black|#000(?:000)?|rgb\(0,\s*0,\s*0\))$/i.test(color); }
function isWhite(color) { return /^(?:white|#fff(?:fff)?|rgb\(255,\s*255,\s*255\))$/i.test(color); }
function pixel(entry, x, y) {
  for (let i = entry.rects.length - 1; i >= 0; i--) {
    const rect = entry.rects[i];
    if (x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height) return rect.color;
  }
  return 'transparent';
}

test('QR exports an opaque PNG with crisp modules, a quiet border and three finder patterns', t => {
  const d = qrBrowser(t);
  const result = d.qr.create(URL_ONE);
  assert.equal(result.dataUrl, PNG);
  assert.match(result.filename, /\.png$/);
  assert.deepEqual(d.payloads, [URL_ONE]);
  assert.equal(d.canvases.length, 1);
  const entry = d.canvases[0], size = entry.canvas.width, count = d.codes[0].getModuleCount();
  assert.equal(entry.canvas.height, size);
  assert.ok(size >= 1024 && size < 2048, 'export should remain clear when printed or shared');
  const scale = size / (count + 8);
  assert.ok(Number.isInteger(scale) && scale > 0);
  assert.ok(entry.rects.every(rect => [rect.x, rect.y, rect.width, rect.height].every(Number.isInteger)));
  assert.ok(entry.rects.every(rect => isBlack(rect.color) || isWhite(rect.color)));
  for (let r = -4; r < count + 4; r++) {
    for (let c = -4; c < count + 4; c++) {
      const color = pixel(entry, (c + 4.5) * scale, (r + 4.5) * scale);
      if (r < 0 || c < 0 || r >= count || c >= count) assert.ok(isWhite(color), 'all four border modules must be white');
      else assert.equal(isBlack(color), d.codes[0].isDark(r, c), 'exported pixels must preserve the QR matrix');
    }
  }
  for (const [row, col] of [[0, 0], [0, count - 7], [count - 7, 0]]) {
    for (let r = 0; r < 7; r++) {
      for (let c = 0; c < 7; c++) {
        const dark = r === 0 || r === 6 || c === 0 || c === 6 || (r >= 2 && r <= 4 && c >= 2 && c <= 4);
        assert.equal(isBlack(pixel(entry, (col + c + 4.5) * scale, (row + r + 4.5) * scale)), dark);
      }
    }
  }
});

test('QR retains the recipient ID and strips private query fields and fragments', t => {
  const d = qrBrowser(t);
  const id = 'Номин & Бат/../"<илгээх>?';
  const input = new URL('https://bolzoo.example/nested/bolzoo.html');
  input.searchParams.set('id', id);
  input.searchParams.set('owner_token', 'OWNER-SECRET');
  input.searchParams.set('recovery_code', 'LOV-SECRET');
  input.searchParams.set('preview', '1');
  input.hash = 'recover=PRIVATE-OWNER';
  const result = d.qr.create(input.href);
  const encoded = new URL(d.payloads[0]);
  assert.equal(encoded.origin + encoded.pathname, 'https://bolzoo.example/nested/bolzoo.html');
  assert.equal(encoded.searchParams.get('id'), id);
  assert.deepEqual([...encoded.searchParams.keys()], ['id']);
  assert.equal(encoded.hash, '');
  assert.doesNotMatch(d.payloads[0], /OWNER-SECRET|LOV-SECRET|PRIVATE-OWNER|preview/);
  assert.match(result.filename, /\.png$/);
  assert.doesNotMatch(result.filename, /[\\/:*?"<>|\x00-\x1f]/);
  assert.doesNotMatch(result.filename, /OWNER-SECRET|LOV-SECRET|PRIVATE-OWNER/);
});

test('distinct invitation IDs produce distinct QR matrices, including localhost and extensionless routes', t => {
  const d = qrBrowser(t);
  d.qr.create(URL_ONE);
  d.qr.create('http://localhost:3000/bolzoo?id=invite-two');
  const matrices = d.codes.map(code => Array.from({length: code.getModuleCount()}, (_, r) =>
    Array.from({length: code.getModuleCount()}, (_, c) => code.isDark(r, c) ? '1' : '0').join('')).join('\n'));
  assert.notEqual(matrices[0], matrices[1]);
  assert.deepEqual(d.payloads, [URL_ONE, 'http://localhost:3000/bolzoo?id=invite-two']);
});

test('invalid or private-management URLs cannot be turned into a recipient QR', t => {
  const d = qrBrowser(t);
  for (const value of [
    '', null, 'not-a-url', '/bolzoo.html?id=invite-one',
    'javascript:alert(1)', 'data:text/plain,secret', 'ftp://bolzoo.example/bolzoo?id=one',
    'https://owner:secret@bolzoo.example/bolzoo.html?id=one',
    'https://bolzoo.example/dashboard.html?id=one#recover=private',
    'https://bolzoo.example/not-bolzoo.html?id=one',
    'https://bolzoo.example/bolzoo.html', 'https://bolzoo.example/bolzoo.html?id='
  ]) assert.throws(() => d.qr.create(value), String(value));
  assert.equal(d.canvases.length, 0);
  assert.equal(d.clicks.length, 0);
});

test('download starts synchronously with a safe filename and removes its temporary anchor', t => {
  const d = qrBrowser(t);
  const container = d.w.document.getElementById('downloads');
  d.qr.download(URL_ONE, container);
  assert.equal(d.clicks.length, 1);
  assert.equal(d.clicks[0].href, PNG);
  assert.match(d.clicks[0].filename, /^[a-zA-Z0-9._-]+\.png$/);
  assert.equal(d.clicks[0].connected, true);
  assert.equal(d.clicks[0].parent, container);
  assert.equal(container.children.length, 0);
  assert.equal(d.w.document.querySelectorAll('a[download]').length, 0);
  d.qr.download(URL_ONE);
  assert.equal(d.clicks.length, 2);
  assert.equal(d.w.document.querySelectorAll('a[download]').length, 0);
});

test('failed anchor click is reported and still removes the temporary download element', t => {
  const d = qrBrowser(t, {clickError: true});
  assert.throws(() => d.qr.download(URL_ONE), /Download unavailable/);
  assert.equal(d.clicks.length, 1);
  assert.equal(d.w.document.querySelectorAll('a[download]').length, 0);
});

test('missing encoder, unavailable canvas and failed PNG exports never trigger a download', t => {
  for (const options of [
    {omitEncoder: true}, {noContext: true}, {contextError: true}, {exportError: true},
    {exportValue: 'data:,'}, {exportValue: 'data:image/jpeg;base64,broken'}
  ]) {
    const d = qrBrowser(t, options);
    assert.throws(() => d.qr.download(URL_ONE), JSON.stringify(options));
    assert.equal(d.clicks.length, 0);
    assert.equal(d.w.document.querySelectorAll('a[download]').length, 0);
  }
});

function invitation(id, config = {}) {
  return {id, config: {recipientName: 'Номин', ...config}, created_at: '2026-09-01T00:00:00Z',
    response: null, recovery_code: 'LOV-PRIVATE'};
}

function dashboard(t, {invites = [], demo = false, download, omitQR = false} = {}) {
  const errors = [], downloads = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', error => errors.push(error.message));
  const html = read('dashboard.html');
  const dom = new JSDOM(html, {url: 'https://bolzoo.example/dashboard.html' + (demo ? '?demo=responses' : ''),
    runScripts: 'outside-only', virtualConsole});
  const w = dom.window;
  let now = Date.parse('2026-09-13T00:00:00Z');
  w.Date.now = () => now;
  w.HTMLElement.prototype.scrollIntoView = function() {};
  w.eval(read('assets/utils.js'));
  w.eval(read('assets/responses.js'));
  w.BolzooAPI = {backendKind: 'supabase', listMyInvites: async () => invites, getOwnerToken: () => 'PRIVATE-OWNER'};
  if (!omitQR) w.BolzooQR = {download(url) { downloads.push(url); if (download) return download(url); }};
  w.eval([...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1]);
  t.after(() => { w.close(); assert.deepEqual(errors, [], 'QR actions must not cause uncaught browser errors'); });
  return {w, downloads, feedback: () => w.document.getElementById('pageFeedback'),
    setNow(value) { now = Date.parse(value); },
    button(id) { return [...w.document.querySelectorAll('[data-qr]')].find(node => node.dataset.qr === id); },
    clickInjected(id) {
      const button = w.document.createElement('button');
      button.dataset.qr = id;
      w.document.body.appendChild(button);
      button.click();
      button.remove();
    }};
}

test('dashboard QR downloads use only the current invitation recipient URL', async t => {
  const d = dashboard(t, {invites: [invitation('invite-one'), invitation('invite-two')]});
  await tick();
  d.button('invite-two').click();
  assert.deepEqual(d.downloads, ['https://bolzoo.example/bolzoo.html?id=invite-two']);
  assert.equal(d.feedback().hidden, false);
  assert.equal(d.feedback().classList.contains('bad'), false);
  d.clickInjected('invite-missing');
  assert.equal(d.downloads.length, 1, 'stale IDs must not create a recipient QR');
  assert.equal(d.feedback().classList.contains('bad'), true);
});

test('dashboard excludes demo and expired QR actions and rechecks expiry at click time', async t => {
  const d = dashboard(t, {invites: [
    invitation('invite-expired', {experienceType: 'apology', expiresAt: '2026-09-12T00:00:00Z'}),
    invitation('invite-active', {experienceType: 'apology', expiresAt: '2026-09-14T00:00:00Z'})
  ]});
  await tick();
  assert.equal(d.button('invite-expired'), undefined);
  assert.ok(d.button('invite-active'));
  d.setNow('2026-09-15T00:00:00Z');
  d.button('invite-active').click();
  d.clickInjected('invite-expired');
  assert.deepEqual(d.downloads, []);
  assert.equal(d.feedback().classList.contains('bad'), true);
  const demo = dashboard(t, {demo: true});
  await tick();
  assert.equal(demo.w.document.querySelector('[data-qr]'), null);
  demo.clickInjected('demo-accepted');
  assert.deepEqual(demo.downloads, []);
  assert.equal(demo.feedback().classList.contains('bad'), true);
});

test('dashboard reports QR export or missing dependency failures without claiming success', async t => {
  for (const options of [{omitQR: true}, {download() { throw new Error('PNG export failed'); }}]) {
    const d = dashboard(t, {invites: [invitation('invite-one')], ...options});
    await tick();
    d.button('invite-one').click();
    assert.equal(d.feedback().hidden, false);
    assert.equal(d.feedback().classList.contains('bad'), true);
    assert.match(d.feedback().textContent, /татаж чадсангүй/);
    assert.doesNotMatch(d.feedback().textContent, /татаж эхэллээ/);
  }
});
