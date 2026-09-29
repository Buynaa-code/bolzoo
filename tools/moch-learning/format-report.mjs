import { analyzeSnapshot } from './learning-report.mjs';

/**
 * Produce a concise Mongolian Markdown report from a validated aggregate snapshot.
 * See learning-report.mjs for the input and injected review-time options schema.
 * Validation always runs here; callers cannot supply a preformatted analysis.
 * No network, clock, storage, scheduled work, or business mutation is performed.
 */
export function formatSnapshotReport(snapshot, options = {}) {
  const report = analyzeSnapshot(snapshot, options);
  const { source, freshness, money, fulfillment, funnel, priority } = report;
  const product = { bolzoo: 'Болзоо', mend: 'Төрсөн өдрийн мэндчилгээ' }[source.product];
  const environment = {
    production: 'бодит үйлчилгээ (production)',
    test: 'туршилт (test)',
    demo: 'жишээ (demo)',
  }[source.environment];
  const freshnessLabel = {
    fresh: 'Шалгасан үед шинэ — зөвшөөрсөн хугацаанд',
    stale: 'Хуучирсан — дахин унших шаардлагатай',
    future: 'Цагийн зөрүүтэй — уншсан цаг нь шалгасан цагаас хойш',
    unverified: 'Шинэ эсэх нь шалгагдаагүй',
  }[freshness.status];
  const observation = describePriority(priority);
  const nextAction = nextReviewAction(report, observation.action);
  const lines = [
    `# МӨЧ · ${product} — хэмжилтийн тайлан`,
    '',
    `Эх сурвалжийн тэмдэглэгээ: **${environment}**. Шинэ эсэх: **${freshnessLabel}**.`,
    '',
    report.actionableForBusinessDecisions
      ? '**Тайлан шалгасан үед хүний хяналтаар дараагийн алхмыг шийдэхэд хугацааны шаардлага хангасан.**'
      : '**Энэ мэдээллээр бизнесийн шийдвэр гаргахгүй.**',
    '',
    'Энэ нь хадгалсан тайлан. Дараа ашиглахдаа мэдээллийг дахин уншиж, шинэ эсэхийг шалгана.',
    '',
    `- Хамрах хугацаа: [${source.period.from}, ${source.period.to}) — эхлэх цаг орно, дуусах цаг орохгүй.`,
    `- Мэдээлэл уншсан цаг: ${source.readAt}.`,
    `- Тайлан шалгасан цаг: ${freshness.checkedAt ?? 'өгөөгүй'}. Шинэ гэж үзэх хязгаар: ${number(freshness.maxAgeMs)} мс.`,
    ...(freshness.ageMs === null ? [] : [`- Уншсанаас хойших хугацаа: ${number(freshness.ageMs)} мс${freshness.ageMs < 0 ? ' (сөрөг утга нь цагийн зөрүүг илэрхийлнэ)' : ''}.`]),
    '',
    '## Мөнгө ба хүргэлт',
    '',
    '| Үзүүлэлт | Дүн |',
    '| --- | ---: |',
    `| Төлбөртэй гэж тэмдэглэсэн бүртгэл | ${number(money.recordedCount)} |`,
    `| Төлбөртэй гэж бүртгэсэн мөнгөн дүн | ${amount(money.recordedAmountMnt)} |`,
    `| Төлбөрийн байгууллагаар баталгаажуулсан орлого | ${amount(money.providerVerifiedAmountMnt)} |`,
    `| Баталгаажсан буцаалт | ${amount(money.verifiedRefundAmountMnt)} |`,
    `| Хувьсах зардал | ${amount(money.variableCostMnt)} |`,
    `| Хувьсах зардлын дараах үлдэгдэл | ${amount(money.contributionMnt)} |`,
    '',
    'Үлдэгдэл = баталгаажсан орлого − баталгаажсан буцаалт − хувьсах зардал. Аль нэг нь тодорхойгүй бол үлдэгдлийг тооцохгүй. Энэ нь цэвэр ашиг биш; тогтмол зардал, татвар, эзний цаг ороогүй.',
    '',
    `Үүссэн байх ёстой холбоосгүй төлбөртэй бүртгэл: **${fulfillment.paidWithoutLinkCount === null ? 'Тодорхойгүй' : number(fulfillment.paidWithoutLinkCount)}**.${fulfillment.paidWithoutLinkCount === null ? ' Тодорхойгүйг 0 гэж үзэхгүй.' : ''} Хэрэглэгч хараахан ашиглаагүй эрхийг энэ тоонд оруулахгүй.`,
    '',
    '## Бүтээж эхэлсэн хүмүүсийн урсгал',
    '',
  ];

  if (funnel === null) {
    lines.push('**Мэдээлэл байхгүй.** Үүнийг 0 хүн эсвэл 0% гэж тайлбарлахгүй.');
  } else {
    lines.push(
      `Хэмжилт: **${funnel.sourceComplete ? 'бүрэн гэж тэмдэглэсэн' : 'дутуу — доорх хувь урьдчилсан; алдагдлыг дүгнэхэд ашиглахгүй'}**.`,
      '',
      'Нэг хугацаанд бүтээж эхэлсэн, давхар тоолоогүй хүмүүс; хүлээн авагчийн нээлт ороогүй. Энэ бүлгийн төлбөр төлөгчдийн тоог дээрх хугацааны төлбөрийн бүртгэлтэй тэнцүүлэхгүй.',
      '',
      '| Алхам | Хүн |',
      '| --- | ---: |',
      ...[
        ['Эхэлсэн', funnel.startedCount],
        ['Урьдчилан харсан', funnel.previewCount],
        ['Төлбөрийн алхамд орсон', funnel.checkoutCount],
        ['Төлбөр төлсөн', funnel.paidCount],
        ['Холбоос нийтлэгдсэн', funnel.publishedCount],
      ].map(([label, count]) => `| ${label} | ${number(count)} |`),
      '',
      `Эхэлсэн хүмүүсээс төлбөр төлсөн: **${percent(funnel.paidConversionRate)}**. Холбоос нийтлэгдсэн: **${percent(funnel.publishedConversionRate)}**.${funnel.startedCount === 0 ? ' Эхэлсэн хүн 0 тул хувь тодорхойгүй.' : ''}`,
    );
  }

  lines.push(
    '',
    '## Хянах нэг зүйл',
    '',
    `**Ажиглалт:** ${observation.evidence}`,
    '',
    `**Эхний алхам:** ${nextAction}`,
    '',
    'Энэ бол өгсөн нэгтгэлийн ажиглалт. Шалтгаан, туршилтын ялагч, борлуулалт өсөхийг батлахгүй. Эх сурвалжийн үнэн зөв байдал, төлбөрийн баталгааг мэдээлэл нийлүүлэгч шалгасан байх шаардлагатай. Тайлан үүсгэх нь сайттай шууд холболт, хуваарьт ажил, эсвэл автомат өөрчлөлт ажилласны нотолгоо биш.',
    '',
  );
  return lines.join('\n');
}

function number(value) {
  return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

function amount(value) {
  return value === null ? 'Тодорхойгүй' : `${number(value)} ₮`;
}

function percent(value) {
  return value === null ? 'Тодорхойгүй' : `${Number((value * 100).toFixed(2))}%`;
}

function describePriority(priority) {
  switch (priority.kind) {
    case 'payment_without_link':
      return {
        evidence: `Төлбөртэй гэж бүртгэсэн ${number(priority.evidence.recordedCount)} бүртгэлээс ${number(priority.evidence.paidWithoutLinkCount)} нь үүссэн байх ёстой холбоосгүй.`,
        action: 'Холбоос үүсэх ажиллагаа болон хүргэлтийг шалга. Аливаа хүргэлтийн үйлдлээс өмнө тухайн төлбөрийг төлбөрийн байгууллагаар баталгаажуул.',
      };
    case 'fulfillment_measurement_missing':
      return {
        evidence: 'Холбоосын хүргэлтийн хэмжилт тодорхойгүй; хүргэлт хэвийн гэж дүгнэх үндэс байхгүй.',
        action: 'Үүссэн байх ёстой холбоосгүй төлбөртэй бүртгэлийг ялгадаг хэмжилт бэлтгэ. Ашиглаагүй эрх болон ерөнхий «анхаарах шаардлагатай» тоог орлуулж ашиглахгүй.',
      };
    case 'instrumentation_missing':
      return {
        evidence: 'Бүтээж эхэлсэн хүмүүсийн дараалсан урсгалын мэдээлэл байхгүй.',
        action: 'Хүлээн авагчийг хасаж, нэг бүлгийн эхлэлтээс холбоос нийтлэгдэх хүртэлх алхмуудыг давхардалгүй хэмждэг болго.',
      };
    case 'instrumentation_incomplete':
      return {
        evidence: 'Урсгалын хэмжилт дутуу тул аль алхамд хүмүүс алдагдсаныг дүгнэхгүй.',
        action: 'Алхам бүрийн бүртгэл, давхардал, нэг бүлэгт хамаарах эсэх болон ажиглалтыг дуусгасан цагийг нягтал.',
      };
    case 'funnel_drop_candidate': {
      const stage = {
        startedCount: 'эхэлсэн', previewCount: 'урьдчилан харсан', checkoutCount: 'төлбөрийн алхамд орсон',
        paidCount: 'төлбөр төлсөн', publishedCount: 'холбоос нийтлэгдсэн',
      };
      const evidence = priority.evidence;
      return {
        evidence: `Шалгах боломжит хэсэг: ${stage[evidence.from]} → ${stage[evidence.to]}. ${number(evidence.fromCount)}-аас ${number(evidence.toCount)} хүн үргэлжилсэн; ${number(evidence.droppedCount)} хүн (${percent(evidence.dropRate)}) дараагийн алхамд бүртгэгдээгүй. Хүний тоогоор хамгийн их буурсан хэсэг; шалтгааны нотолгоо биш.`,
        action: 'Энэ алхмыг шалгаж, буцааж болох нэг туршилтын санал бэлтгэ. Хэрэгжүүлэх эсэхийг хүн шийднэ.',
      };
    }
    case 'baseline_needed':
      return {
        evidence: 'Бүрэн хэмжилтэд бүтээж эхэлсэн хүн 0 байна; хөрвөлтийн хувь тодорхойгүй.',
        action: 'Харьцуулж болох дараагийн бүлгийн бүрэн мэдээллийг цуглуул.',
      };
    case 'no_observed_drop':
      return {
        evidence: 'Энэ бүлэгт алхмуудын хооронд бууралт ажиглагдаагүй. Энэ нь сайжруулах зүйл байхгүйг батлахгүй.',
        action: 'Ижил нөхцөлөөр хэмжсэн дараагийн бүлгийн мэдээллийг цуглуулж харьцуул.',
      };
    default:
      throw new TypeError('Unsupported validated report priority');
  }
}

function nextReviewAction(report, businessAction) {
  if (report.source.environment !== 'production') {
    return 'Бизнесийн шийдвэрээс өмнө бодит үйлчилгээний баталгаажсан шинэ мэдээллээр тайлан гарга. Дээрх ажиглалт нь туршилт эсвэл жишээний мэдээлэлд хамаарна.';
  }
  switch (report.freshness.status) {
    case 'unverified':
      return 'Тайланг шалгаж буй бодит цагийг өгч, мэдээлэл шинэ эсэхийг шалга.';
    case 'future':
      return 'Уншсан болон шалгасан цагийн зөрүүг нягталж, зөв цагтай мэдээллээр тайланг дахин гарга.';
    case 'stale':
      return 'Хуучирсан мэдээллийг шинэ хэмжилтээр сольж, тайланг дахин гарга.';
    case 'fresh':
      return businessAction;
    default:
      throw new TypeError('Unsupported validated freshness status');
  }
}
