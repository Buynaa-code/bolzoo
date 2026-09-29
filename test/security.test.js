'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { Readable } = require('stream');

const {
  readBody,
  verifyWireSignature
} = require('../lib/payment-api');

function signature(payload, secret, timestamp) {
  const digest = crypto
    .createHmac('sha256', secret)
    .update(timestamp + '.' + payload)
    .digest('hex');
  return 't=' + timestamp + ',v1=' + digest;
}

test('accepts a fresh valid Wire signature', () => {
  const payload = '{"id":"evt_test"}';
  const secret = 'whsec_test';
  const now = 1_800_000_000;
  assert.equal(
    verifyWireSignature(payload, signature(payload, secret, now), secret, 300, now),
    true
  );
});

test('rejects stale and malformed Wire signatures', () => {
  const payload = '{"id":"evt_test"}';
  const secret = 'whsec_test';
  const now = 1_800_000_000;
  assert.equal(
    verifyWireSignature(payload, signature(payload, secret, now - 301), secret, 300, now),
    false
  );
  assert.equal(verifyWireSignature(payload, 't=abc,v1=nope', secret, 300, now), false);
  assert.equal(verifyWireSignature(payload, '', secret, 300, now), false);
});

test('accepts one valid signature during secret rotation', () => {
  const payload = '{"id":"evt_test"}';
  const secret = 'whsec_test';
  const now = 1_800_000_000;
  const valid = signature(payload, secret, now).split('v1=')[1];
  const header = 't=' + now + ',v1=' + '00'.repeat(32) + ',v1=' + valid;
  assert.equal(verifyWireSignature(payload, header, secret, 300, now), true);
});

test('rejects oversized request bodies', async () => {
  const request = Readable.from([Buffer.alloc(65, 'a')]);
  await assert.rejects(readBody(request, 64), (error) => error && error.status === 413);
});
