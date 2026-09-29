'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const { createDatePlanService } = require('../lib/date-plan-service');
const { createLocalDatePlanRepository } = require('../lib/date-plan-repository');

const browserSource = fs.readFileSync(path.join(__dirname, '../assets/date-plan-api.js'), 'utf8');

function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'bolzoo-plan-contract-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const invite = { id: 'contract_invite_123', owner_token: crypto.randomUUID(), config: { experienceType: 'date', missionIdeaId: 'coffee-questions' } };
  const repo = createLocalDatePlanRepository({ file: path.join(directory, 'plans.json'), getInvite: id => id === invite.id ? invite : null });
  const service = createDatePlanService({ repo });
  let truncateNextSuccess = false;
  const writes = [];
  function browser({ owner = false, url = 'https://bolzoo.test/date-plan.html?invite=' + invite.id, storage } = {}) {
    const dom = new JSDOM('<!doctype html><title>API contract</title>', { url, runScripts: 'outside-only' });
    t.after(() => dom.window.close());
    const w = dom.window;
    if (storage) for (const [key, value] of Object.entries(storage)) w.localStorage.setItem(key, value);
    w.BolzooAPI = { getOwnerToken: () => owner ? invite.owner_token : null };
    w.fetch = async (url, options) => {
      const token = (options.headers.Authorization || '').replace(/^Bearer /, '');
      try {
        let data;
        if (options.body) {
          const body = JSON.parse(options.body); writes.push(body);
          data = await service.execute(body, token);
        } else data = await service.get({ invite_id: new URL(url, w.location.origin).searchParams.get('invite_id') }, token);
        const truncate = truncateNextSuccess; truncateNextSuccess = false;
        return { ok: true, status: 200, async json() { if (truncate) throw new SyntaxError('Truncated JSON response'); return data; } };
      } catch (cause) {
        return { ok: false, status: cause.status || 503, async json() { return { code: cause.code, user_error: cause.message }; } };
      }
    };
    w.eval(browserSource);
    return { window: w, api: w.BolzooDatePlanAPI, storage: () => Object.fromEntries(Object.keys(w.localStorage).map(key => [key, w.localStorage.getItem(key)])) };
  }
  return { browser, invite, repo, writes, truncate() { truncateNextSuccess = true; } };
}

test('recipient reopening the original join URL in the same browser retains its claimed identity', async t => {
  const f = fixture(t);
  const creator = f.browser({ owner: true });
  await creator.api.mutate(f.invite.id, 'create', { template_id: 'coffee-questions' });
  const originalURL = creator.api.joinLink(f.invite.id);
  const recipient = f.browser({ url: originalURL });
  assert.equal(recipient.api.captureJoin(f.invite.id), true);
  const first = await recipient.api.claim(f.invite.id);
  const resumed = f.browser({ url: originalURL, storage: recipient.storage() });
  const pending = resumed.api.captureJoin(f.invite.id);
  const reopened = pending ? await resumed.api.claim(f.invite.id) : await resumed.api.get(f.invite.id);
  assert.equal(resumed.window.location.hash, '');
  assert.equal(reopened.role, 'partner');
  assert.equal(reopened.id, first.id);
  assert.equal(reopened.version, first.version, 'reopening does not rebind or modify the participant');
  assert.equal((await f.repo.getByInvite(f.invite.id)).document.audit.filter(event => event.action === 'claim').length, 1);
});

test('a committed write with a truncated successful response retries using its original request id', async t => {
  const f = fixture(t);
  const creator = f.browser({ owner: true });
  const plan = await creator.api.mutate(f.invite.id, 'create', { template_id: 'coffee-questions' });
  const fields = { expected_version: plan.version, location: 'Тохирсон шинэ газар' };
  f.truncate();
  await assert.rejects(creator.api.mutate(f.invite.id, 'propose', fields), /Серверийн хариуг/);
  const retried = await creator.api.mutate(f.invite.id, 'propose', fields);
  assert.equal(retried.version, plan.version + 1);
  assert.equal(retried.revision, plan.revision + 1);
  const proposals = f.writes.filter(body => body.action === 'propose');
  assert.equal(proposals.length, 2);
  assert.equal(proposals[0].request_id, proposals[1].request_id);
  assert.equal((await f.repo.getByInvite(f.invite.id)).document.audit.filter(event => event.action === 'propose').length, 1);
});
