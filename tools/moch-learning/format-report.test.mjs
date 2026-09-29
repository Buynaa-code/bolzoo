import test from 'node:test';
import assert from 'node:assert/strict';
import { formatSnapshotReport } from './format-report.mjs';

const REVIEW = { now: '2026-09-29T09:01:00Z' };

function snapshot() {
  return {
    schemaVersion: 1,
    source: {
      product: 'bolzoo', environment: 'production', readAt: '2026-09-29T09:00:00Z',
      period: { from: '2026-09-01T00:00:00Z', to: '2026-09-29T00:00:00Z' },
    },
    money: {
      recordedCount: 4, recordedAmountMnt: 39600,
      providerVerifiedAmountMnt: null, verifiedRefundAmountMnt: null, variableCostMnt: null,
    },
    fulfillment: { paidWithoutLinkCount: null },
    funnel: null,
  };
}

function addCohort(input, complete = true) {
  input.funnel = {
    basis: 'creator_started_cohort', startedCount: 100, previewCount: 80, checkoutCount: 30,
    paidCount: 20, publishedCount: 20, sourceComplete: complete,
  };
  return input;
}

test('unknown financial and fulfillment measurements stay unknown in the human report', () => {
  const output = formatSnapshotReport(snapshot(), REVIEW);
  assert.match(output, /Төлбөртэй гэж бүртгэсэн мөнгөн дүн \| 39 600 ₮/);
  for (const label of ['Төлбөрийн байгууллагаар баталгаажуулсан орлого', 'Баталгаажсан буцаалт', 'Хувьсах зардал', 'Хувьсах зардлын дараах үлдэгдэл']) {
    assert.ok(output.includes(`| ${label} | Тодорхойгүй |`));
  }
  assert.match(output, /холбоосгүй төлбөртэй бүртгэл: \*\*Тодорхойгүй\*\*/);
  assert.match(output, /Тодорхойгүйг 0 гэж үзэхгүй/);
  assert.match(output, /\*\*Мэдээлэл байхгүй\.\*\*/);
  assert.match(output, /\[2026-09-01T00:00:00Z, 2026-09-29T00:00:00Z\)/);
  assert.equal((output.match(/\*\*Эхний алхам:\*\*/g) ?? []).length, 1);
  assert.match(output, /тайлан.*автомат өөрчлөлт ажилласны нотолгоо биш/is);
});

test('known zeros and negative contribution are formatted as data, not unknowns or net profit', () => {
  const input = snapshot();
  Object.assign(input.money, { providerVerifiedAmountMnt: 0, verifiedRefundAmountMnt: 2000, variableCostMnt: 500 });
  input.fulfillment.paidWithoutLinkCount = 0;
  const output = formatSnapshotReport(input, REVIEW);
  assert.match(output, /байгууллагаар баталгаажуулсан орлого \| 0 ₮/);
  assert.match(output, /Хувьсах зардлын дараах үлдэгдэл \| -2 500 ₮/);
  assert.match(output, /Энэ нь цэвэр ашиг биш/);
  assert.match(output, /холбоосгүй төлбөртэй бүртгэл: \*\*0\*\*/);
});

test('demo and test data remain non-actionable even when fresh and delivery looks broken', () => {
  for (const environment of ['demo', 'test']) {
    const input = snapshot();
    input.source.environment = environment;
    input.fulfillment.paidWithoutLinkCount = 2;
    const output = formatSnapshotReport(input, REVIEW);
    assert.ok(output.includes(`(${environment})`));
    assert.match(output, /Энэ мэдээллээр бизнесийн шийдвэр гаргахгүй/);
    assert.match(output, /4 бүртгэлээс 2 нь/);
    assert.match(output, /\*\*Эхний алхам:\*\* Бизнесийн шийдвэрээс өмнө бодит үйлчилгээний/);
    assert.doesNotMatch(output, /\*\*Эхний алхам:\*\* Холбоос үүсэх ажиллагаа/);
  }
});

test('stale, future and unverified data recommend review of evidence before business actions', () => {
  const input = snapshot();
  input.fulfillment.paidWithoutLinkCount = 1;
  const cases = [
    [{ now: '2026-09-29T09:06:00Z' }, /Хуучирсан/, /\*\*Эхний алхам:\*\* Хуучирсан мэдээллийг шинэ хэмжилтээр/],
    [{ now: '2026-09-29T08:59:00Z' }, /Цагийн зөрүүтэй/, /\*\*Эхний алхам:\*\* Уншсан болон шалгасан цагийн зөрүүг/],
    [undefined, /Шинэ эсэх нь шалгагдаагүй/, /\*\*Эхний алхам:\*\* Тайланг шалгаж буй бодит цагийг/],
  ];
  for (const [options, label, nextStep] of cases) {
    const output = formatSnapshotReport(input, options);
    assert.match(output, label);
    assert.match(output, nextStep);
    assert.match(output, /Энэ мэдээллээр бизнесийн шийдвэр гаргахгүй/);
    assert.doesNotMatch(output, /\*\*Эхний алхам:\*\* Холбоос үүсэх ажиллагаа/);
  }
});

test('delivery issue has priority over a measured drop and requires provider confirmation', () => {
  const input = addCohort(snapshot());
  input.fulfillment.paidWithoutLinkCount = 1;
  const output = formatSnapshotReport(input, REVIEW);
  assert.match(output, /\*\*Ажиглалт:\*\* Төлбөртэй гэж бүртгэсэн 4 бүртгэлээс 1 нь/);
  assert.match(output, /тухайн төлбөрийг төлбөрийн байгууллагаар баталгаажуул/);
  assert.doesNotMatch(output, /Шалгах боломжит хэсэг:/);
  assert.equal((output.match(/\*\*Эхний алхам:\*\*/g) ?? []).length, 1);
});

test('funnel loss is expressed as an observation and candidate, with creator rates', () => {
  const input = addCohort(snapshot());
  input.fulfillment.paidWithoutLinkCount = 0;
  const output = formatSnapshotReport(input, REVIEW);
  assert.match(output, /Эхэлсэн хүмүүсээс төлбөр төлсөн: \*\*20%\*\*/);
  assert.match(output, /Шалгах боломжит хэсэг: урьдчилан харсан → төлбөрийн алхамд орсон/);
  assert.match(output, /80-аас 30 хүн үргэлжилсэн; 50 хүн \(62\.5%\)/);
  assert.match(output, /шалтгааны нотолгоо биш/);
  assert.match(output, /Хэрэгжүүлэх эсэхийг хүн шийднэ/);
  assert.match(output, /хүлээн авагчийн нээлт ороогүй/);
});

test('incomplete funnel is provisional and unknown fulfillment outranks it', () => {
  const input = addCohort(snapshot(), false);
  const unknownDelivery = formatSnapshotReport(input, REVIEW);
  assert.match(unknownDelivery, /дутуу — доорх хувь урьдчилсан/);
  assert.match(unknownDelivery, /\*\*Ажиглалт:\*\* Холбоосын хүргэлтийн хэмжилт тодорхойгүй/);
  input.fulfillment.paidWithoutLinkCount = 0;
  const incomplete = formatSnapshotReport(input, REVIEW);
  assert.match(incomplete, /\*\*Ажиглалт:\*\* Урсгалын хэмжилт дутуу/);
  assert.doesNotMatch(incomplete, /Шалгах боломжит хэсэг:/);
});

test('zero-start cohort produces no invented zero-percent conversion', () => {
  const input = addCohort(snapshot());
  input.fulfillment.paidWithoutLinkCount = 0;
  for (const key of ['startedCount', 'previewCount', 'checkoutCount', 'paidCount', 'publishedCount']) input.funnel[key] = 0;
  const output = formatSnapshotReport(input, REVIEW);
  assert.match(output, /төлбөр төлсөн: \*\*Тодорхойгүй\*\*/);
  assert.match(output, /Эхэлсэн хүн 0 тул хувь тодорхойгүй/);
  assert.doesNotMatch(output, /\*\*0%\*\*/);
});

test('formatter always validates and never interpolates untrusted extra data', () => {
  const input = snapshot();
  input.privateMessage = 'PRIVATE-CONTENT';
  assert.throws(() => formatSnapshotReport(input, REVIEW), error => {
    assert.match(error.message, /unexpected property/);
    assert.doesNotMatch(error.message, /PRIVATE-CONTENT/);
    return true;
  });
  const badSource = snapshot();
  badSource.source.product = '[click](https://untrusted.example)';
  assert.throws(() => formatSnapshotReport(badSource, REVIEW), /expected one of/);
});
