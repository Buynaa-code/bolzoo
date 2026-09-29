/**
 * Pure aggregate-only analyzer. No network, persistence, scheduler, or deployment.
 * This is a preparation module, not an integration with a live Moch product.
 *
 * Exact required input schema (unknown keys, including private data, are rejected):
 * {
 *   schemaVersion: 1,
 *   source: {
 *     product: 'bolzoo' | 'mend',
 *     environment: 'production' | 'test' | 'demo',
 *     readAt: ISO_TIMESTAMP,
 *     period: { from: ISO_TIMESTAMP, to: ISO_TIMESTAMP }
 *   },
 *   money: {
 *     recordedCount: COUNT,
 *     recordedAmountMnt: MONEY,
 *     providerVerifiedAmountMnt: MONEY | null,
 *     verifiedRefundAmountMnt: MONEY | null,
 *     variableCostMnt: MONEY | null
 *   },
 *   fulfillment: { paidWithoutLinkCount: COUNT | null },
 *   funnel: null | {
 *     basis: 'creator_started_cohort',
 *     startedCount: COUNT,
 *     previewCount: COUNT,
 *     checkoutCount: COUNT,
 *     paidCount: COUNT,
 *     publishedCount: COUNT,
 *     sourceComplete: boolean
 *   }
 * }
 *
 * COUNT and MONEY are nonnegative safe integers. MONEY is whole Mongolian tugrik.
 * ISO_TIMESTAMP is a calendar-valid ISO date-time with seconds, an optional 1-3
 * digit fractional second, and Z or an explicit offset up to +/-14:00. Years are
 * 0001-9999. The completed reporting interval is [from, to), with from < to <=
 * readAt. This validator does not compare readAt with the computer's wall clock.
 * Optional second argument: { now?: ISO_TIMESTAMP, maxAgeMs?: POSITIVE_INTEGER }.
 * maxAgeMs defaults to 300000 (five minutes). Inject now at review time to verify
 * freshness. Without now, freshness is 'unverified' and actionability is false.
 * Future readAt values and ages greater than maxAgeMs are non-actionable too.
 * The report's freshness object contains status, checkedAt, ageMs, and maxAgeMs;
 * ageMs is null when unverified and negative for future-dated snapshots.
 * Production data is actionable for review only when freshness is 'fresh'. This
 * function never reads wall-clock time itself and remains deterministic.
 *
 * money contains payment records/receipts/refunds/costs for the reporting interval.
 * A zero recordedCount requires zero recordedAmountMnt. A recorded payment may
 * have zero amount; this module does not invent the product's price rules.
 * paidWithoutLinkCount counts affected records in recordedCount, each once.
 * null means the measurement is unavailable, never zero or a healthy result.
 * Include only cases where link creation was expected to have completed;
 * exclude intentionally unused entitlements awaiting the customer's action.
 * Do not substitute other metrics, including Mend attentionRequired, for it.
 * The trusted reader must define link fulfillment and verify the provider data.
 * Passing a number here does not itself prove provider verification.
 *
 * Funnel counts are distinct creators whose first start was in the interval,
 * restricted to the same observation cutoff (readAt). Preview -> checkout ->
 * paid -> published must be nested within the preceding stage, each creator once.
 * Recipient opens are excluded. Cohort counts are not equated with payment counts
 * because their time bases differ. sourceComplete means all five stages have
 * complete instrumentation for this cohort and observation window; false counts
 * can be displayed but cannot establish a drop-off recommendation. null means
 * unavailable, never zero. A reader unable to provide this basis must pass null.
 *
 * Refunds can exceed this interval's receipts (e.g. refunds of earlier purchases).
 * Verified receipts may differ from recorded amounts. Neither is silently
 * substituted for the other. Contribution = verified receipts - verified refunds
 * - known variable costs, only when all three are known. It is NOT net profit.
 * All rates are fractions in [0, 1], rounded to four decimal places; an undefined
 * zero-denominator rate is null. Candidates use the largest absolute creator
 * loss, ties resolved by the earliest step. They are observations, not causal
 * findings, significance claims, experiment winners, or permission to ship.
 * Nonproduction results are explicitly non-actionable for business decisions.
 */

const SOURCE_KEYS = ['product', 'environment', 'readAt', 'period'];
const MONEY_KEYS = ['recordedCount', 'recordedAmountMnt', 'providerVerifiedAmountMnt', 'verifiedRefundAmountMnt', 'variableCostMnt'];
const FUNNEL_KEYS = ['basis', 'startedCount', 'previewCount', 'checkoutCount', 'paidCount', 'publishedCount', 'sourceComplete'];
const STAGES = ['startedCount', 'previewCount', 'checkoutCount', 'paidCount', 'publishedCount'];

function fail(path, message) {
  // Do not echo offending values or property names: they may contain private data.
  throw new TypeError(`Invalid snapshot at ${path}: ${message}`);
}

function exactObject(value, requiredKeys, path, optionalKeys = []) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail(path, 'expected an object');
  }
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    fail(path, 'expected a plain object');
  }
  const keys = Reflect.ownKeys(value);
  const allowedKeys = [...requiredKeys, ...optionalKeys];
  if (keys.some(key => typeof key !== 'string' || !allowedKeys.includes(key))) {
    fail(path, 'unexpected property; only documented aggregate fields are allowed');
  }
  for (const key of allowedKeys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor) {
      if (requiredKeys.includes(key)) fail(`${path}.${key}`, 'required field is missing');
      continue;
    }
    if (!Object.hasOwn(descriptor, 'value')) {
      fail(`${path}.${key}`, 'accessor properties are not allowed');
    }
  }
}

function count(value, path) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail(path, 'expected a nonnegative safe integer');
  }
}

function nullableMoney(value, path) {
  if (value !== null) count(value, path);
}

function oneOf(value, choices, path) {
  if (!choices.includes(value)) fail(path, `expected one of ${choices.join(', ')}`);
}

function timestamp(value, path) {
  if (typeof value !== 'string') fail(path, 'expected an ISO timestamp');
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) fail(path, 'expected an ISO timestamp with seconds and a timezone');
  const [, y, m, d, h, minute, second, , zone] = match;
  const year = Number(y);
  const month = Number(m);
  const day = Number(d);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > daysInMonth[month - 1] ||
      Number(h) > 23 || Number(minute) > 59 || Number(second) > 59) {
    fail(path, 'timestamp has an invalid calendar date or time');
  }
  if (zone !== 'Z') {
    const offsetHours = Number(zone.slice(1, 3));
    const offsetMinutes = Number(zone.slice(4, 6));
    if (offsetHours > 14 || offsetMinutes > 59 || (offsetHours === 14 && offsetMinutes !== 0)) {
      fail(path, 'timestamp has an invalid timezone offset');
    }
  }
  const result = Date.parse(value);
  if (!Number.isFinite(result)) fail(path, 'expected a valid ISO timestamp');
  return result;
}

function rate(numerator, denominator) {
  return denominator === 0 ? null : Math.round((numerator / denominator) * 10000) / 10000;
}

function safeDifference(a, b, path) {
  const result = a - b;
  if (!Number.isSafeInteger(result)) fail(path, 'derived amount exceeds the safe integer range');
  return result;
}

export function analyzeSnapshot(snapshot, options = {}) {
  exactObject(snapshot, ['schemaVersion', 'source', 'money', 'fulfillment', 'funnel'], 'snapshot');
  if (snapshot.schemaVersion !== 1) fail('snapshot.schemaVersion', 'expected 1');

  const { source, money, fulfillment, funnel } = snapshot;
  exactObject(source, SOURCE_KEYS, 'snapshot.source');
  oneOf(source.product, ['bolzoo', 'mend'], 'snapshot.source.product');
  oneOf(source.environment, ['production', 'test', 'demo'], 'snapshot.source.environment');
  const readAt = timestamp(source.readAt, 'snapshot.source.readAt');
  exactObject(source.period, ['from', 'to'], 'snapshot.source.period');
  const from = timestamp(source.period.from, 'snapshot.source.period.from');
  const to = timestamp(source.period.to, 'snapshot.source.period.to');
  if (from >= to) fail('snapshot.source.period', 'from must be earlier than to');
  if (to > readAt) fail('snapshot.source.period', 'to must be no later than readAt');

  exactObject(options, [], 'options', ['now', 'maxAgeMs']);
  const maxAgeMs = Object.hasOwn(options, 'maxAgeMs') ? options.maxAgeMs : 300000;
  if (!Number.isSafeInteger(maxAgeMs) || maxAgeMs <= 0) {
    fail('options.maxAgeMs', 'expected a positive safe integer');
  }
  const hasReviewTime = Object.hasOwn(options, 'now');
  const reviewedAt = hasReviewTime ? timestamp(options.now, 'options.now') : null;
  const ageMs = hasReviewTime ? reviewedAt - readAt : null;
  const freshness = {
    status: !hasReviewTime ? 'unverified' : ageMs < 0 ? 'future' : ageMs > maxAgeMs ? 'stale' : 'fresh',
    checkedAt: hasReviewTime ? options.now : null,
    ageMs,
    maxAgeMs,
  };

  exactObject(money, MONEY_KEYS, 'snapshot.money');
  count(money.recordedCount, 'snapshot.money.recordedCount');
  count(money.recordedAmountMnt, 'snapshot.money.recordedAmountMnt');
  for (const key of MONEY_KEYS.slice(2)) nullableMoney(money[key], `snapshot.money.${key}`);
  if (money.recordedCount === 0 && money.recordedAmountMnt !== 0) {
    fail('snapshot.money', 'zero recordedCount requires zero recordedAmountMnt');
  }
  exactObject(fulfillment, ['paidWithoutLinkCount'], 'snapshot.fulfillment');
  if (fulfillment.paidWithoutLinkCount !== null) {
    count(fulfillment.paidWithoutLinkCount, 'snapshot.fulfillment.paidWithoutLinkCount');
    if (fulfillment.paidWithoutLinkCount > money.recordedCount) {
      fail('snapshot.fulfillment.paidWithoutLinkCount', 'must not exceed recordedCount');
    }
  }

  let funnelReport = null;
  if (funnel !== null) {
    exactObject(funnel, FUNNEL_KEYS, 'snapshot.funnel');
    oneOf(funnel.basis, ['creator_started_cohort'], 'snapshot.funnel.basis');
    if (typeof funnel.sourceComplete !== 'boolean') fail('snapshot.funnel.sourceComplete', 'expected a boolean');
    for (const key of STAGES) count(funnel[key], `snapshot.funnel.${key}`);
    for (let index = 1; index < STAGES.length; index += 1) {
      if (funnel[STAGES[index]] > funnel[STAGES[index - 1]]) {
        fail(`snapshot.funnel.${STAGES[index]}`, `must not exceed ${STAGES[index - 1]} in the same creator cohort`);
      }
    }
    funnelReport = {
      ...funnel,
      paidConversionRate: rate(funnel.paidCount, funnel.startedCount),
      publishedConversionRate: rate(funnel.publishedCount, funnel.startedCount),
      steps: STAGES.slice(1).map((stage, index) => {
        const previousStage = STAGES[index];
        const previousCount = funnel[previousStage];
        const nextCount = funnel[stage];
        return {
          from: previousStage,
          to: stage,
          fromCount: previousCount,
          toCount: nextCount,
          droppedCount: previousCount - nextCount,
          dropRate: rate(previousCount - nextCount, previousCount),
          continuationRate: rate(nextCount, previousCount),
        };
      }),
    };
  }

  const missingContributionInputs = MONEY_KEYS.slice(2).filter(key => money[key] === null);
  const contributionMnt = missingContributionInputs.length > 0 ? null : safeDifference(
    safeDifference(money.providerVerifiedAmountMnt, money.verifiedRefundAmountMnt, 'snapshot.money'),
    money.variableCostMnt,
    'snapshot.money',
  );
  const production = source.environment === 'production';
  const actionable = production && freshness.status === 'fresh';
  const priorityBase = { actionableForBusinessDecision: actionable, requiresHumanReview: true };
  let priority;
  if (fulfillment.paidWithoutLinkCount > 0) {
    priority = {
      ...priorityBase,
      kind: 'payment_without_link',
      evidence: { paidWithoutLinkCount: fulfillment.paidWithoutLinkCount, recordedCount: money.recordedCount },
      nextStep: 'Review affected payment records and link delivery before conversion experiments. Confirm payment status with the provider before any fulfillment action.',
    };
  } else if (fulfillment.paidWithoutLinkCount === null) {
    priority = {
      ...priorityBase,
      kind: 'fulfillment_measurement_missing',
      evidence: { paidWithoutLinkCount: null },
      nextStep: 'Establish a trusted measurement of paid records whose expected link creation has failed. Exclude intentionally unused entitlements; do not substitute a general attention-required metric.',
    };
  } else if (funnel === null) {
    priority = {
      ...priorityBase,
      kind: 'instrumentation_missing',
      evidence: { funnelAvailable: false },
      nextStep: 'Implement an aggregate creator-started cohort reader with recipient traffic excluded. Unavailable counts are not zero.',
    };
  } else if (!funnel.sourceComplete) {
    priority = {
      ...priorityBase,
      kind: 'instrumentation_incomplete',
      evidence: { sourceComplete: false },
      nextStep: 'Check stage coverage, deduplication, cohort membership, and observation cutoff before interpreting funnel loss.',
    };
  } else {
    const largestDrop = funnelReport.steps.reduce((best, step) =>
      step.droppedCount > (best?.droppedCount ?? 0) ? step : best, null);
    if (largestDrop) {
      priority = {
        ...priorityBase,
        kind: 'funnel_drop_candidate',
        evidence: { ...largestDrop, selectionBasis: 'largest_absolute_creator_loss' },
        nextStep: 'Inspect this step and formulate one reversible experiment. This observed drop does not establish its cause or justify a winner or deployment decision.',
      };
    } else {
      priority = {
        ...priorityBase,
        kind: funnel.startedCount === 0 ? 'baseline_needed' : 'no_observed_drop',
        evidence: { startedCount: funnel.startedCount, publishedCount: funnel.publishedCount },
        nextStep: funnel.startedCount === 0
          ? 'Collect a complete creator cohort; zero observed starts provide no conversion rate.'
          : 'Continue collecting comparable cohorts. No observed drop does not prove that an improvement is needed or that the product cannot improve.',
      };
    }
  }

  return {
    schemaVersion: 1,
    source: { ...source, period: { ...source.period } },
    freshness,
    actionableForBusinessDecisions: actionable,
    decisionLimitations: [
      ...(production ? [] : ['NONPRODUCTION_DATA: Do not use this report to make business decisions.']),
      ...(freshness.status === 'unverified' ? ['FRESHNESS_UNVERIFIED: Inject the current review time before making business decisions.'] : []),
      ...(freshness.status === 'future' ? ['FUTURE_DATA: Source readAt is later than the supplied review time; check timestamps before making business decisions.'] : []),
      ...(freshness.status === 'stale' ? ['STALE_DATA: Refresh the source snapshot before making business decisions.'] : []),
      'Aggregate observations do not establish causality, statistical significance, or experiment winners.',
      'No changes are shipped, payments acted on, or messages sent by this module.',
      'Provider verification and aggregate correctness must be established by the trusted reader.',
      'Contribution excludes fixed costs, tax, and owner time; it is not net profit.',
      ...(fulfillment.paidWithoutLinkCount === null ? ['FULFILLMENT_UNKNOWN: Unavailable link-delivery measurement does not establish that delivery is healthy.'] : []),
      ...(funnel !== null && !funnel.sourceComplete ? ['INCOMPLETE_FUNNEL: Displayed rates are provisional and cannot support drop-off decisions.'] : []),
    ],
    money: {
      ...money,
      providerMinusRecordedMnt: money.providerVerifiedAmountMnt === null ? null
        : safeDifference(money.providerVerifiedAmountMnt, money.recordedAmountMnt, 'snapshot.money'),
      contributionMnt,
      missingContributionInputs,
    },
    fulfillment: { ...fulfillment },
    funnel: funnelReport,
    priority,
  };
}
