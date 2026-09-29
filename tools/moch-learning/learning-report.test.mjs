import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeSnapshot } from './learning-report.mjs';

const FRESH_REVIEW = { now: '2026-09-29T09:01:00Z' };

function snapshot() {
  return {
    schemaVersion: 1,
    source: {
      product: 'bolzoo',
      environment: 'production',
      readAt: '2026-09-29T09:00:00Z',
      period: { from: '2026-09-01T00:00:00Z', to: '2026-09-29T00:00:00Z' },
    },
    money: {
      recordedCount: 4,
      recordedAmountMnt: 39600,
      providerVerifiedAmountMnt: null,
      verifiedRefundAmountMnt: null,
      variableCostMnt: null,
    },
    fulfillment: { paidWithoutLinkCount: 0 },
    funnel: null,
  };
}

function cohort(counts = [100, 80, 30, 20, 20], sourceComplete = true) {
  return {
    basis: 'creator_started_cohort',
    ...Object.fromEntries(['startedCount', 'previewCount', 'checkoutCount', 'paidCount', 'publishedCount']
      .map((key, i) => [key, counts[i]])),
    sourceComplete,
  };
}

test('unknown funnel and payment verification stay unknown', () => {
  const result = analyzeSnapshot(snapshot());
  assert.equal(result.funnel, null);
  assert.equal(result.priority.kind, 'instrumentation_missing');
  assert.equal(result.money.recordedAmountMnt, 39600);
  assert.equal(result.money.providerVerifiedAmountMnt, null);
  assert.equal(result.money.providerMinusRecordedMnt, null);
  assert.equal(result.money.contributionMnt, null);
  assert.deepEqual(result.money.missingContributionInputs,
    ['providerVerifiedAmountMnt', 'verifiedRefundAmountMnt', 'variableCostMnt']);
});

test('contribution requires all verified receipts, refunds, and costs', () => {
  for (const missing of ['providerVerifiedAmountMnt', 'verifiedRefundAmountMnt', 'variableCostMnt']) {
    const input = snapshot();
    Object.assign(input.money, { providerVerifiedAmountMnt: 30000, verifiedRefundAmountMnt: 5000, variableCostMnt: 1000 });
    input.money[missing] = null;
    const result = analyzeSnapshot(input, FRESH_REVIEW);
    assert.equal(result.money.contributionMnt, null);
    assert.deepEqual(result.money.missingContributionInputs, [missing]);
  }
});

test('recorded revenue is never substituted for provider receipts', () => {
  const input = snapshot();
  Object.assign(input.money, { providerVerifiedAmountMnt: 30000, verifiedRefundAmountMnt: 5000, variableCostMnt: 1000 });
  const result = analyzeSnapshot(input);
  assert.equal(result.money.providerMinusRecordedMnt, -9600);
  assert.equal(result.money.contributionMnt, 24000);
  assert.match(result.decisionLimitations.join(' '), /not net profit/);
  input.money.providerVerifiedAmountMnt = 50000;
  assert.equal(analyzeSnapshot(input).money.providerMinusRecordedMnt, 10400);
});

test('refunds from earlier purchases can yield negative contribution', () => {
  const input = snapshot();
  Object.assign(input.money, { providerVerifiedAmountMnt: 1000, verifiedRefundAmountMnt: 2000, variableCostMnt: 500 });
  assert.equal(analyzeSnapshot(input).money.contributionMnt, -1500);
});

test('known zeros are data, and zero denominators produce null rates', () => {
  const input = snapshot();
  Object.assign(input.money, { recordedCount: 0, recordedAmountMnt: 0, providerVerifiedAmountMnt: 0, verifiedRefundAmountMnt: 0, variableCostMnt: 0 });
  input.funnel = cohort([0, 0, 0, 0, 0]);
  const result = analyzeSnapshot(input);
  assert.equal(result.money.contributionMnt, 0);
  assert.equal(result.funnel.paidConversionRate, null);
  assert.equal(result.funnel.publishedConversionRate, null);
  assert.equal(result.priority.kind, 'baseline_needed');
  for (const step of result.funnel.steps) {
    assert.equal(step.droppedCount, 0);
    assert.equal(step.dropRate, null);
    assert.equal(step.continuationRate, null);
  }
});

test('paid records without links take priority over missing or incomplete funnel', () => {
  for (const funnel of [null, cohort([100, 80, 30, 20, 20], false), cohort()]) {
    const input = snapshot();
    input.funnel = funnel;
    input.fulfillment.paidWithoutLinkCount = 2;
    const result = analyzeSnapshot(input);
    assert.equal(result.priority.kind, 'payment_without_link');
    assert.deepEqual(result.priority.evidence, { paidWithoutLinkCount: 2, recordedCount: 4 });
    assert.equal(result.priority.requiresHumanReview, true);
  }
});

test('incomplete funnel is displayed provisionally but not used for recommendations', () => {
  const input = snapshot();
  input.funnel = cohort([100, 80, 30, 20, 20], false);
  const result = analyzeSnapshot(input);
  assert.equal(result.priority.kind, 'instrumentation_incomplete');
  assert.match(result.decisionLimitations.join(' '), /INCOMPLETE_FUNNEL/);
  assert.equal(result.funnel.sourceComplete, false);
});

test('largest absolute drop is a candidate with counts and rounded fractional rates', () => {
  const input = snapshot();
  input.funnel = cohort([103, 100, 34, 1, 1]);
  const result = analyzeSnapshot(input);
  assert.equal(result.priority.kind, 'funnel_drop_candidate');
  assert.deepEqual(result.priority.evidence, {
    from: 'previewCount', to: 'checkoutCount', fromCount: 100, toCount: 34,
    droppedCount: 66, dropRate: 0.66, continuationRate: 0.34,
    selectionBasis: 'largest_absolute_creator_loss',
  });
  assert.equal(result.funnel.paidConversionRate, 0.0097);
  assert.equal(result.funnel.steps[0].dropRate, 0.0291);
  assert.match(result.priority.nextStep, /does not establish its cause/);
});

test('ties use the earliest step and small samples never imply a winning experiment', () => {
  const input = snapshot();
  input.funnel = cohort([2, 1, 0, 0, 0]);
  const result = analyzeSnapshot(input);
  assert.equal(result.priority.evidence.from, 'startedCount');
  assert.equal(result.priority.evidence.droppedCount, 1);
  assert.equal(result.funnel.steps[2].dropRate, null);
  assert.match(result.decisionLimitations.join(' '), /do not establish causality, statistical significance, or experiment winners/);
});

test('a complete cohort with no drop stays an observation', () => {
  const input = snapshot();
  input.funnel = cohort([3, 3, 3, 3, 3]);
  const result = analyzeSnapshot(input);
  assert.equal(result.priority.kind, 'no_observed_drop');
  assert.equal(result.funnel.paidConversionRate, 1);
});

test('funnel cohort and payment-interval counts are not falsely equated', () => {
  const input = snapshot();
  input.funnel = cohort([100, 80, 30, 20, 20]);
  assert.equal(analyzeSnapshot(input).funnel.paidCount, 20);
  assert.equal(input.money.recordedCount, 4);
});

test('test and demo data cannot support business decisions, including delivery issues', () => {
  for (const environment of ['test', 'demo']) {
    const input = snapshot();
    input.source.environment = environment;
    input.fulfillment.paidWithoutLinkCount = 1;
    const result = analyzeSnapshot(input, FRESH_REVIEW);
    assert.equal(result.freshness.status, 'fresh');
    assert.equal(result.actionableForBusinessDecisions, false);
    assert.equal(result.priority.actionableForBusinessDecision, false);
    assert.match(result.decisionLimitations.join(' '), /NONPRODUCTION_DATA/);
  }
  const production = analyzeSnapshot(snapshot(), FRESH_REVIEW);
  assert.equal(production.actionableForBusinessDecisions, true);
});

test('freshness is unverified without injected review time and cannot enable decisions', () => {
  for (const options of [undefined, {}, { maxAgeMs: 60000 }]) {
    const result = analyzeSnapshot(snapshot(), options);
    assert.deepEqual(result.freshness, {
      status: 'unverified', checkedAt: null, ageMs: null, maxAgeMs: options?.maxAgeMs ?? 300000,
    });
    assert.equal(result.actionableForBusinessDecisions, false);
    assert.equal(result.priority.actionableForBusinessDecision, false);
    assert.match(result.decisionLimitations.join(' '), /FRESHNESS_UNVERIFIED/);
  }
});

test('five-minute freshness boundary is inclusive and stale data remains non-actionable', () => {
  const input = snapshot();
  input.fulfillment.paidWithoutLinkCount = 1;
  const fresh = analyzeSnapshot(input, { now: '2026-09-29T09:05:00Z' });
  assert.deepEqual(fresh.freshness, {
    status: 'fresh', checkedAt: '2026-09-29T09:05:00Z', ageMs: 300000, maxAgeMs: 300000,
  });
  assert.equal(fresh.actionableForBusinessDecisions, true);
  assert.equal(fresh.priority.actionableForBusinessDecision, true);
  const stale = analyzeSnapshot(input, { now: '2026-09-29T09:05:00.001Z' });
  assert.equal(stale.freshness.status, 'stale');
  assert.equal(stale.freshness.ageMs, 300001);
  assert.equal(stale.priority.kind, 'payment_without_link');
  assert.equal(stale.actionableForBusinessDecisions, false);
  assert.equal(stale.priority.actionableForBusinessDecision, false);
  assert.match(stale.decisionLimitations.join(' '), /STALE_DATA/);
});

test('future snapshots are not actionable even when internally consistent', () => {
  const input = snapshot();
  input.funnel = cohort();
  const result = analyzeSnapshot(input, { now: '2026-09-29T08:59:59.999Z' });
  assert.deepEqual(result.freshness, {
    status: 'future', checkedAt: '2026-09-29T08:59:59.999Z', ageMs: -1, maxAgeMs: 300000,
  });
  assert.equal(result.priority.kind, 'funnel_drop_candidate');
  assert.equal(result.actionableForBusinessDecisions, false);
  assert.equal(result.priority.actionableForBusinessDecision, false);
  assert.match(result.decisionLimitations.join(' '), /FUTURE_DATA/);
});

test('injected freshness policy is deterministic and honors custom maximum age', () => {
  const input = snapshot();
  const options = { now: '2026-09-29T17:01:00+08:00', maxAgeMs: 60000 };
  const before = structuredClone(options);
  const result = analyzeSnapshot(input, options);
  assert.equal(result.freshness.status, 'fresh');
  assert.equal(result.freshness.ageMs, 60000);
  assert.deepEqual(result, analyzeSnapshot(input, options));
  assert.deepEqual(options, before);
  assert.equal(analyzeSnapshot(input, { ...options, maxAgeMs: 59999 }).freshness.status, 'stale');
  assert.equal(analyzeSnapshot(input, { now: input.source.readAt }).freshness.ageMs, 0);
});

test('invalid freshness options, private fields and accessors are rejected', () => {
  for (const maxAgeMs of [0, -1, 0.5, null, undefined, '300000', Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => analyzeSnapshot(snapshot(), { ...FRESH_REVIEW, maxAgeMs }), /positive safe integer/);
  }
  for (const now of [null, undefined, '2026-09-29', '2026-02-30T09:00:00Z']) {
    assert.throws(() => analyzeSnapshot(snapshot(), { now }), /Invalid snapshot at options.now/);
  }
  for (const options of [null, [], 'options']) {
    assert.throws(() => analyzeSnapshot(snapshot(), options), /expected.*object/);
  }
  assert.throws(() => analyzeSnapshot(snapshot(), { ...FRESH_REVIEW, token: 'private-token' }), /unexpected property/);
  const accessor = {};
  Object.defineProperty(accessor, 'now', { get() { throw new Error('must never execute'); } });
  assert.throws(() => analyzeSnapshot(snapshot(), accessor), /accessor properties are not allowed/);
});

test('unavailable fulfillment is unknown and takes priority over every funnel state', () => {
  for (const funnel of [null, cohort([100, 80, 30, 20, 20], false), cohort(), cohort([0, 0, 0, 0, 0])]) {
    const input = snapshot();
    input.fulfillment.paidWithoutLinkCount = null;
    input.funnel = funnel;
    const result = analyzeSnapshot(input, FRESH_REVIEW);
    assert.equal(result.fulfillment.paidWithoutLinkCount, null);
    assert.equal(result.priority.kind, 'fulfillment_measurement_missing');
    assert.deepEqual(result.priority.evidence, { paidWithoutLinkCount: null });
    assert.match(result.decisionLimitations.join(' '), /FULFILLMENT_UNKNOWN/);
    assert.match(result.priority.nextStep, /Exclude intentionally unused entitlements/);
  }
});

test('fulfillment cannot default to zero or substitute an attention-required metric', () => {
  const input = snapshot();
  input.fulfillment.paidWithoutLinkCount = undefined;
  assert.throws(() => analyzeSnapshot(input), /nonnegative safe integer/);
  input.fulfillment = { attentionRequired: 0 };
  assert.throws(() => analyzeSnapshot(input), /unexpected property/);
  input.fulfillment = { paidWithoutLinkCount: null, attentionRequired: 0 };
  assert.throws(() => analyzeSnapshot(input), /unexpected property/);
  input.fulfillment = { paidWithoutLinkCount: 0 };
  assert.equal(analyzeSnapshot(input, FRESH_REVIEW).priority.kind, 'instrumentation_missing');
});

test('both supported products are accepted; unsupported environments and versions are not', () => {
  const input = snapshot();
  input.source.product = 'mend';
  assert.equal(analyzeSnapshot(input).source.product, 'mend');
  for (const [section, key, value] of [
    ['source', 'product', 'other'], ['source', 'environment', 'staging'], [null, 'schemaVersion', '1'], [null, 'schemaVersion', 2],
  ]) {
    const invalid = snapshot();
    (section ? invalid[section] : invalid)[key] = value;
    assert.throws(() => analyzeSnapshot(invalid), /Invalid snapshot/);
  }
});

test('strict nested sequence rejects each impossible funnel step', () => {
  for (let stage = 1; stage < 5; stage += 1) {
    const input = snapshot();
    const counts = [10, 10, 10, 10, 10];
    counts[stage] = 11;
    input.funnel = cohort(counts);
    assert.throws(() => analyzeSnapshot(input), /must not exceed .* in the same creator cohort/);
  }
});

test('invalid numeric values are rejected for counts and all amounts', () => {
  for (const value of [-1, 0.5, NaN, Infinity, '1', undefined, Number.MAX_SAFE_INTEGER + 1]) {
    for (const field of Object.keys(snapshot().money)) {
      const input = snapshot();
      input.money[field] = value;
      assert.throws(() => analyzeSnapshot(input), /nonnegative safe integer/);
    }
    const input = snapshot();
    input.funnel = cohort();
    input.funnel.startedCount = value;
    assert.throws(() => analyzeSnapshot(input), /nonnegative safe integer/);
  }
});

test('payment count/amount, fulfillment bounds, and derived overflow are validated', () => {
  const emptyWithAmount = snapshot();
  emptyWithAmount.money.recordedCount = 0;
  assert.throws(() => analyzeSnapshot(emptyWithAmount), /zero recordedCount requires zero recordedAmountMnt/);
  const tooMany = snapshot();
  tooMany.fulfillment.paidWithoutLinkCount = 5;
  assert.throws(() => analyzeSnapshot(tooMany), /must not exceed recordedCount/);
  const overflow = snapshot();
  Object.assign(overflow.money, { providerVerifiedAmountMnt: 0, verifiedRefundAmountMnt: Number.MAX_SAFE_INTEGER, variableCostMnt: 1 });
  assert.throws(() => analyzeSnapshot(overflow), /derived amount exceeds/);
  const zeroPrice = snapshot();
  zeroPrice.money.recordedAmountMnt = 0;
  assert.equal(analyzeSnapshot(zeroPrice).money.recordedCount, 4);
});

test('timestamp validation rejects invalid calendars, unsupported formats and offsets', () => {
  const badDates = [
    null, 0, '', '2026-09-29', '2026-09-29T09:00:00', 'not a date',
    '2026-02-29T09:00:00Z', '2026-04-31T09:00:00Z', '2026-13-01T09:00:00Z',
    '2026-00-01T09:00:00Z', '2026-01-00T09:00:00Z', '0000-01-01T00:00:00Z',
    '2026-09-29T24:00:00Z', '2026-09-29T09:60:00Z', '2026-09-29T09:00:60Z',
    '2026-09-29T09:00:00+15:00', '2026-09-29T09:00:00+14:01', '2026-09-29T09:00:00+08:60',
  ];
  for (const value of badDates) {
    const input = snapshot();
    input.source.readAt = value;
    assert.throws(() => analyzeSnapshot(input), /Invalid snapshot at snapshot.source.readAt/);
  }
});

test('leap day, fractions and timezone offsets are compared by their actual instants', () => {
  const input = snapshot();
  input.source.period = { from: '2024-02-29T00:00:00+08:00', to: '2024-03-01T00:00:00+08:00' };
  input.source.readAt = '2024-02-29T16:00:00.001Z';
  assert.equal(analyzeSnapshot(input).source.readAt, input.source.readAt);
  input.source.readAt = '2024-02-29T15:59:59.999Z';
  assert.throws(() => analyzeSnapshot(input), /to must be no later than readAt/);
});

test('empty, reversed and unfinished periods are rejected', () => {
  for (const period of [
    { from: '2026-09-01T00:00:00Z', to: '2026-09-01T00:00:00Z' },
    { from: '2026-09-29T00:00:00Z', to: '2026-09-01T00:00:00Z' },
    { from: '2026-09-01T00:00:00Z', to: '2026-09-30T00:00:00Z' },
  ]) {
    const input = snapshot();
    input.source.period = period;
    assert.throws(() => analyzeSnapshot(input), /Invalid snapshot at snapshot.source.period/);
  }
});

test('missing required fields cannot silently become zeros or nulls', () => {
  for (const section of [null, 'source', 'money', 'fulfillment']) {
    const original = snapshot();
    for (const key of Object.keys(section ? original[section] : original)) {
      const input = snapshot();
      delete (section ? input[section] : input)[key];
      assert.throws(() => analyzeSnapshot(input), /required field is missing/);
    }
  }
  const input = snapshot();
  input.funnel = cohort();
  delete input.funnel.sourceComplete;
  assert.throws(() => analyzeSnapshot(input), /required field is missing/);
});

test('private and unknown fields are rejected at every object level without echoing values', () => {
  for (const path of [[], ['source'], ['source', 'period'], ['money'], ['fulfillment'], ['funnel']]) {
    const input = snapshot();
    input.funnel = cohort();
    const target = path.reduce((value, key) => value[key], input);
    target['sensitive@example.com'] = 'secret-token-and-private-message';
    assert.throws(() => analyzeSnapshot(input), error => {
      assert.match(error.message, /unexpected property/);
      assert.doesNotMatch(error.message, /sensitive|secret-token|private-message/);
      return true;
    });
  }
});

test('non-plain objects, symbols, getters, arrays and wrong field types are rejected', () => {
  for (const value of [null, undefined, [], new Date(), 'input']) {
    assert.throws(() => analyzeSnapshot(value), /expected.*object/);
  }
  const symbolInput = snapshot();
  symbolInput[Symbol('private')] = 'secret';
  assert.throws(() => analyzeSnapshot(symbolInput), /unexpected property/);
  const getterInput = snapshot();
  Object.defineProperty(getterInput.money, 'recordedCount', { get() { throw new Error('must never execute'); } });
  assert.throws(() => analyzeSnapshot(getterInput), /accessor properties are not allowed/);
  const wrong = snapshot();
  wrong.funnel = cohort();
  wrong.funnel.sourceComplete = 'true';
  assert.throws(() => analyzeSnapshot(wrong), /expected a boolean/);
  wrong.funnel.sourceComplete = true;
  wrong.funnel.basis = 'all_visitors';
  assert.throws(() => analyzeSnapshot(wrong), /creator_started_cohort/);
});

test('analysis is deterministic, preserves the input and returns independent nested objects', () => {
  const input = snapshot();
  input.funnel = cohort();
  const before = structuredClone(input);
  const first = analyzeSnapshot(input);
  assert.deepEqual(first, analyzeSnapshot(input));
  assert.deepEqual(input, before);
  first.source.period.from = 'changed';
  first.money.recordedAmountMnt = 1;
  first.fulfillment.paidWithoutLinkCount = 1;
  first.funnel.startedCount = 1;
  assert.deepEqual(input, before);
});
