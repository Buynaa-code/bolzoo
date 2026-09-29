'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');
const path = require('node:path');
const { createLearningOverviewHandler } = require('../lib/learning-reader');

test('private reader, HTTP client and report CLI preserve unknowns and test labeling end to end', async t => {
  const token = 'fixture_learning_reader_token_0123456789';
  const to = new Date(Date.now() - 1000).toISOString();
  const from = new Date(Date.parse(to) - 86400000).toISOString();
  let databaseReads = 0;
  const handler = createLearningOverviewHandler({
    env: { MOCH_LEARNING_TOKEN: token, MOCH_LEARNING_ENVIRONMENT: 'test',
      SUPABASE_URL: 'https://database.example', SUPABASE_SERVICE_ROLE_KEY: 'fixture_server_key' },
    fetch: async (url, options) => {
      databaseReads++;
      const query = new URL(url);
      assert.equal(query.pathname, '/rest/v1/rpc/moch_learning_overview');
      assert.equal(query.searchParams.get('p_from'), from);
      assert.equal(query.searchParams.get('p_to'), to);
      assert.equal(options.redirect, 'error');
      return new Response(JSON.stringify({ read_at: new Date().toISOString(), measurement_available: true,
        recorded_count: 2, recorded_amount_mnt: 19800 }), { headers: { 'Content-Type': 'application/json' } });
    }
  });
  const server = http.createServer((req, res) => { handler(req, res).catch(() => { res.statusCode = 500; res.end(); }); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const url = `http://127.0.0.1:${server.address().port}/api/learning-overview`;
  const denied = await fetch(url + '?from=' + from + '&to=' + to);
  assert.equal(denied.status, 401);
  assert.equal(databaseReads, 0);

  const result = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['tools/moch-learning/read-overview.mjs'], {
      cwd: path.join(__dirname, '..'), windowsHide: true,
      env: { ...process.env, MOCH_READER_URL: url, MOCH_READER_TOKEN: token,
        MOCH_READER_FROM: from, MOCH_READER_TO: to }, stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    child.on('error', reject);
    child.on('close', code => resolve({ code, stdout, stderr }));
  });
  assert.equal(result.code, 0, result.stderr);
  assert.equal(databaseReads, 1);
  assert.match(result.stdout, /туршилт \(test\)/);
  assert.match(result.stdout, /19 800 ₮/);
  assert.match(result.stdout, /бизнесийн шийдвэр гаргахгүй/);
  assert.match(result.stdout, /Хувьсах зардлын дараах үлдэгдэл \| Тодорхойгүй/);
  assert.match(result.stdout, /Мэдээлэл байхгүй/);
  assert.equal(result.stdout.includes(token), false);
  assert.equal(result.stdout.includes('fixture_server_key'), false);
  assert.equal(result.stderr, '');
});
