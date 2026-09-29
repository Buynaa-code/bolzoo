import { analyzeSnapshot } from './learning-report.mjs';

const MAX_RESPONSE_BYTES = 64 * 1024;
const TIMEOUT_MS = 10000;

class SnapshotFetchError extends Error {}
function fail(message) { throw new SnapshotFetchError(message); }

/**
 * Fetch one aggregate snapshot. No scheduler, retries, persistence or mutations.
 * url must be the exact /api/learning-overview endpoint without credentials,
 * query, or fragment; HTTPS is required except on localhost/127.0.0.0/8/::1.
 * token must contain 32-512 printable nonspace ASCII bytes. It is sent only in
 * Authorization and never included in returned data, URLs or error messages.
 * The caller supplies a completed [from,to) ISO timestamp interval. Provider
 * errors and malformed responses are deliberately replaced by fixed messages.
 */
export async function fetchSnapshot({ url, token, from, to, fetchImpl = globalThis.fetch } = {}) {
  const endpoint = validateEndpoint(url);
  if (typeof token !== 'string' || !/^[\x21-\x7E]{32,512}$/.test(token)) {
    fail('Invalid snapshot credential');
  }
  if (typeof fetchImpl !== 'function') fail('Snapshot fetch is unavailable');
  validatePeriod(from, to);
  endpoint.search = new URLSearchParams({ from, to }).toString();

  const controller = new AbortController();
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new SnapshotFetchError('Snapshot request timed out'));
    }, TIMEOUT_MS);
  });
  const request = async () => {
    const response = await fetchImpl(endpoint.href, {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      redirect: 'error',
      credentials: 'omit',
      cache: 'no-store',
      signal: controller.signal,
    });
    if (!response || response.redirected || !response.ok || !Number.isInteger(response.status) || response.status < 200 || response.status >= 300) {
      fail('Snapshot request was not accepted');
    }
    const raw = await readBoundedBody(response, controller.signal);
    let snapshot;
    let report;
    try {
      snapshot = JSON.parse(raw);
      report = analyzeSnapshot(snapshot, { now: new Date().toISOString() });
    } catch (_) {
      fail('Invalid snapshot response');
    }
    if (report.source.product !== 'bolzoo') fail('Snapshot response has the wrong product');
    if (Date.parse(report.source.period.from) !== Date.parse(from) || Date.parse(report.source.period.to) !== Date.parse(to)) {
      fail('Snapshot response does not match the requested period');
    }
    if (report.freshness.status !== 'fresh') fail('Snapshot response is not fresh');
    return snapshot;
  };
  try {
    return await Promise.race([request(), timeout]);
  } catch (error) {
    if (error instanceof SnapshotFetchError) throw error;
    // No external exception messages, response text, URL, or credential escapes.
    fail('Snapshot request failed');
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}

function validateEndpoint(value) {
  if (typeof value !== 'string' || value.includes('?') || value.includes('#')) fail('Invalid snapshot URL');
  let parsed;
  try { parsed = new URL(value); } catch (_) { fail('Invalid snapshot URL'); }
  const loopback = parsed.hostname === 'localhost' || parsed.hostname === '[::1]' || /^127(?:\.\d{1,3}){3}$/.test(parsed.hostname);
  if (parsed.username || parsed.password || parsed.pathname !== '/api/learning-overview' ||
      (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && loopback))) {
    fail('Invalid snapshot URL');
  }
  return parsed;
}

function validatePeriod(from, to) {
  try {
    analyzeSnapshot({
      schemaVersion: 1,
      source: {
        product: 'bolzoo', environment: 'test', readAt: new Date().toISOString(), period: { from, to },
      },
      money: {
        recordedCount: 0, recordedAmountMnt: 0, providerVerifiedAmountMnt: null,
        verifiedRefundAmountMnt: null, variableCostMnt: null,
      },
      fulfillment: { paidWithoutLinkCount: null },
      funnel: null,
    });
  } catch (_) {
    fail('Invalid snapshot period');
  }
}

async function readBoundedBody(response, signal) {
  const declaredLength = response.headers?.get?.('content-length');
  if (declaredLength !== null && declaredLength !== undefined && /^\d+$/.test(declaredLength) && Number(declaredLength) > MAX_RESPONSE_BYTES) {
    fail('Snapshot response is too large');
  }
  if (!response.body || typeof response.body.getReader !== 'function') fail('Invalid snapshot response');
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  let finished = false;
  const cancel = () => {
    try { Promise.resolve(reader.cancel()).catch(() => {}); } catch (_) {}
  };
  signal.addEventListener('abort', cancel, { once: true });
  try {
    while (true) {
      if (signal.aborted) fail('Snapshot request timed out');
      const { done, value } = await reader.read();
      if (done) { finished = true; break; }
      if (!(value instanceof Uint8Array)) fail('Invalid snapshot response');
      total += value.byteLength;
      if (total > MAX_RESPONSE_BYTES) fail('Snapshot response is too large');
      chunks.push(value);
    }
    const combined = new Uint8Array(total);
    let position = 0;
    for (const chunk of chunks) { combined.set(chunk, position); position += chunk.byteLength; }
    try { return new TextDecoder('utf-8', { fatal: true }).decode(combined); }
    catch (_) { fail('Invalid snapshot response'); }
  } finally {
    signal.removeEventListener('abort', cancel);
    if (!finished) cancel();
    reader.releaseLock();
  }
}
