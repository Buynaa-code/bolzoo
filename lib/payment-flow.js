'use strict';

const crypto = require('crypto');
const STATUSES = new Set(['new', 'requires_payment_method', 'requires_action', 'requires_capture', 'processing', 'succeeded', 'canceled']);
const TOKEN_RE = /^\d{13}-[a-f0-9]{64}$/;
const hashToken = (token) => crypto.createHash('sha256').update(token).digest('hex');
function fail(status, message) { const error = new Error(message); error.status = status; throw error; }
function validateToken(token) {
  if (typeof token !== 'string' || !TOKEN_RE.test(token)) fail(400, 'Төлбөрийн хүсэлтийн түлхүүр буруу байна.');
  return hashToken(token);
}
function authorize(payment, token) {
  // Existing pre-migration invoices retain their original opaque-id recovery path.
  if (!payment.checkout_token_hash) return;
  if (typeof token !== 'string' || !TOKEN_RE.test(token) ||
      !crypto.timingSafeEqual(Buffer.from(hashToken(token)), Buffer.from(payment.checkout_token_hash))) {
    fail(403, 'Төлбөрөө эхлүүлсэн хөтчөөс дахин нээнэ үү.');
  }
}
function amountMinor(mnt) {
  if (!Number.isSafeInteger(mnt) || mnt <= 0 || mnt > 21474836) fail(503, 'PRICE_MNT тохиргоо буруу байна.');
  return mnt * 100;
}
function isUnboundReservation(row) {
  return row.provider === 'wire' && !row.provider_intent_id &&
    /^[a-f0-9]{64}$/.test(row.checkout_token_hash || '') && row.id === 'checkout_' + row.checkout_token_hash;
}
function validateRemote(payment, remote) {
  if (!remote || remote.id !== payment.provider_intent_id ||
      !Number.isSafeInteger(remote.amount) || remote.amount !== payment.amount_minor ||
      remote.currency !== payment.currency || !STATUSES.has(remote.status)) {
    fail(502, 'Төлбөрийн мэдээлэл нэхэмжлэлтэй таарахгүй байна.');
  }
  if (payment.livemode != null && remote.livemode !== payment.livemode) fail(502, 'Төлбөрийн горим таарахгүй байна.');
}
function payload(row, description) {
  return {
    intent_id: row.id, status: row.status, amount: row.amount, currency: row.currency,
    code: row.status === 'succeeded' ? row.code || null : null,
    next_action: row.status === 'succeeded' || row.status === 'canceled' ? null : row.next_action || null,
    expires_at: row.expires_at || null,
    payment_description: row.payment_description || description,
    return_to_create: !!row.return_to_create,
    mode: row.provider === 'mock' ? 'mock' : row.livemode === false ? 'test' : 'live'
  };
}

// Both Vercel and the local server use this orchestration. The repository owns
// atomic state transitions and code issuance; provider responses are never trusted by the browser.
function createPaymentFlow({ repo, wire, price, description, wireEnabled, testMode = false, allowMock = false, now = Date.now }) {
  async function ensureProvider(row) {
    if (row.provider !== 'wire' || row.provider_intent_id) return row;
    // Pre-reservation invoices used their provider id as the primary key, even
    // if older local data omitted the duplicate provider_intent_id field.
    if (!isUnboundReservation(row)) return { ...row, provider_intent_id: row.id };
    if (!wireEnabled || row.livemode !== !testMode) fail(503, 'Төлбөрийн үйлчилгээний горим өөрчлөгдсөн байна. Түр хүлээгээд дахин оролдоно уу.');
    const age = now() - Date.parse(row.created_at);
    if (!Number.isFinite(age) || age < -60000 || age > 47 * 3600000) {
      const error = new Error('Төлбөр эхлүүлэх хүсэлтийн хугацаа дууссан. Шинээр эхлүүлнэ үү.');
      error.status = 409; error.code = 'checkout_expired'; throw error;
    }
    // The reservation freezes every create parameter before this external side
    // effect. A lost response can therefore replay even across a price boundary
    // or server restart without sending a different body to Wire's same key.
    const pi = await wire('POST', '/v1/payment_intents', {
      amount: row.amount_minor, currency: row.currency, automatic_operator: true,
      ...(row.livemode === false ? { allowed_operators: ['sandbox'] } : {}),
      description: row.payment_description, metadata: { product: 'bolzoo_access_code', checkout: row.checkout_token_hash }
    }, 'bolzoo-create-' + row.checkout_token_hash);
    if (!pi || typeof pi.id !== 'string' || !pi.id) fail(502, 'Invalid payment intent');
    validateRemote({ ...row, provider_intent_id: pi.id }, pi);
    const linked = await repo.bindProvider(row.id, pi.id);
    if (linked.provider_intent_id !== pi.id) fail(502, 'Төлбөрийн хүсэлт өмнөх нэхэмжлэлтэй таарахгүй байна.');
    return linked;
  }
  async function reconcile(row, remote) {
    validateRemote(row, remote);
    return repo.reconcile(row.id, remote);
  }
  async function refresh(row) {
    if (row.provider === 'mock' || (row.status === 'succeeded' && row.code)) return row;
    if (isUnboundReservation(row)) return row; // Durable reservation; no payable QR yet.
    if (!row.provider_intent_id) row = { ...row, provider_intent_id: row.id };
    if (!wireEnabled) fail(503, 'Төлбөр шалгах үйлчилгээ түр идэвхгүй байна.');
    return reconcile(row, await wire('GET', '/v1/payment_intents/' + encodeURIComponent(row.provider_intent_id || row.id)));
  }
  async function checkout(body, origin) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) fail(400, 'Invalid checkout request');
    const tokenHash = validateToken(body.checkout_token);
    let row = await repo.findByToken(tokenHash);
    if (!row) {
      const capturedAt = now();
      const age = capturedAt - Number(body.checkout_token.slice(0, 13));
      // Wire retains idempotency results for 48h. Never recreate an uncertain
      // attempt after that retention window (even after a price/config change).
      if (age < -60000 || age > 47 * 3600000) {
        const error = new Error('Төлбөр эхлүүлэх хүсэлтийн хугацаа дууссан. Шинээр эхлүүлнэ үү.');
        error.status = 409; error.code = 'checkout_expired'; throw error;
      }
      // Resolve once for a new attempt. Existing invoices always retain their
      // persisted amount, including retries after a promotion has ended.
      const capturedPrice = typeof price === 'function' ? price(capturedAt) : price;
      const minor = amountMinor(capturedPrice);
      if (!wireEnabled && !allowMock) fail(503, 'QPay төлбөр түр идэвхгүй байна.');
      const createdAt = new Date(capturedAt).toISOString();
      const id = wireEnabled ? 'checkout_' + tokenHash : 'pi_mock_' + tokenHash.slice(0, 32);
      // Reserve the amount before provider creation. Ignore concurrent inserts;
      // the first durable reservation wins, including at a promotion boundary.
      row = await repo.insert({
        id, provider_intent_id: wireEnabled ? null : id, provider: wireEnabled ? 'wire' : 'mock',
        status: wireEnabled ? 'new' : 'requires_action', amount: capturedPrice, amount_minor: minor, currency: 'MNT',
        checkout_token_hash: tokenHash, return_to_create: body.from === 'create',
        return_origin: origin, payment_description: description, livemode: wireEnabled ? !testMode : false,
        next_action: null, code: null, created_at: createdAt, updated_at: createdAt,
        expires_at: wireEnabled ? null : new Date(capturedAt + 900000).toISOString()
      });
    }
    authorize(row, body.checkout_token);
    if (row.provider === 'wire') {
      row = await ensureProvider(row);
      row = await refresh(row);
      if (row.status === 'new' || row.status === 'requires_payment_method') {
        const returnURL = new URL('/pay.html', row.return_origin || origin);
        returnURL.searchParams.set('intent', row.id);
        if (row.return_to_create) returnURL.searchParams.set('from', 'create');
        // Fragment survives app/browser returns without entering access logs or Referer headers.
        returnURL.hash = 'payment_token=' + body.checkout_token;
        await wire('POST', '/v1/payment_intents/' + encodeURIComponent(row.provider_intent_id) + '/confirm',
          { return_url: returnURL.href }, 'bolzoo-confirm-' + tokenHash);
        // A replayed confirm response may be stale. Fetch the current intent.
        row = await refresh(row);
      }
    }
    return payload(row, description);
  }
  async function status(id, token) {
    if (typeof id !== 'string' || !/^[\w-]{1,160}$/.test(id)) fail(400, 'id required');
    let row = await repo.get(id);
    if (!row) fail(404, 'Payment not found');
    authorize(row, token);
    row = await refresh(row);
    return payload(row, description);
  }
  async function webhook(event) {
    if (!event || typeof event.id !== 'string' || !event.id || event.id.length > 200 || typeof event.type !== 'string') fail(400, 'Invalid event');
    if (!/^(payment_intent\.|charge\.)/.test(event.type)) return { ok: true, ignored: true };
    if (await repo.hasEvent(event.id)) return { ok: true, already_processed: true };
    const data = event.data && (event.data.object && typeof event.data.object === 'object' ? event.data.object : event.data);
    const id = data && (event.type.startsWith('charge.') ? data.payment_intent : data.id);
    if (typeof id !== 'string' || !id) fail(400, 'payment intent required');
    const row = await repo.findByProvider(id);
    // Do not mark an early event processed. Let Wire retry after checkout persists.
    if (!row) fail(503, 'Payment is not stored yet; retry delivery');
    if (row.provider !== 'wire') fail(400, 'Not a Wire payment');
    if (!wireEnabled) fail(503, 'Wire is not configured');
    // Failure/charge events are signals to reconcile, never payment finality.
    await reconcile(row, await wire('GET', '/v1/payment_intents/' + encodeURIComponent(id)));
    await repo.recordEvent(event, row.id);
    return { ok: true };
  }
  async function simulate(id, token) {
    if (!allowMock) fail(403, 'Mock payment simulation is disabled');
    const row = await repo.get(id);
    if (!row) fail(404, 'Payment not found');
    authorize(row, token);
    if (row.provider !== 'mock') fail(403, 'Only mock payments can be simulated');
    if (row.status !== 'succeeded' && row.expires_at && Date.parse(row.expires_at) <= now()) fail(409, 'Mock invoice expired');
    return payload(await repo.simulate(id), description);
  }
  async function cancel(id, token) {
    let row = await repo.get(id);
    if (!row) fail(404, 'Payment not found');
    authorize(row, token);
    if (row.status === 'succeeded') return payload(row, description);
    if (row.provider === 'mock') row = await repo.cancelMock(id);
    else {
      if (!wireEnabled) fail(503, 'Wire is not configured');
      row = await ensureProvider(row);
      await wire('POST', '/v1/payment_intents/' + encodeURIComponent(row.provider_intent_id || row.id) + '/cancel', {}, 'bolzoo-cancel-' + row.id);
      row = await refresh(row);
    }
    return payload(row, description);
  }
  return { checkout, status, webhook, simulate, cancel };
}
module.exports = { createPaymentFlow, amountMinor, validateRemote, authorize, payload };
