# Шинэ он хүртэл 100 хоног — 2026.09.22

## Урамшуулал

- 2026.09.22 00:00–2026.09.24 00:00, Asia/Ulaanbaatar. Эхлэл багтана, төгсгөл багтахгүй.
- Шинэ нэхэмжлэл 9,023₮; Wire рүү 902300 minor unit дамжуулна.
- Хугацаа дуусахад `PRICE_MNT` үндсэн үнэ (анхдагч 9,900₮) сервер дахин асаахгүйгээр сэргэнэ.
- Нэхэмжлэлийн үнэ provider руу хүсэлт явуулахаас өмнө хадгалагдана. Сүлжээ тасрах, дахин оролдох, хугацааны зааг, сервер restart үед өмнөх үнэ хадгалагдана.
- Удаан нээлттэй browser дээр server time-аар тооцсон тусдаа timer хугацааг дуусгана. Нэхэмжлэл эхэлсэн бол өөрийн дүнг хэвээр харуулна.

## Урилга ба сурталчилгаа

Нүүр хуудас болон санааны хэсэгт «9/23-нд багтаад крашаа болзоонд уриарай» баннер.
Энэ хугацаанд бэлдсэн date урилгын `campaign: newyear100-2026` тэмдэглэгээ ноорог,
preview болон нийтэлсэн урилгад хадгалагдана. Өмнө төлсөн ноорог, эвлэрлийн захидлын
агуулгыг автоматаар өөрчлөхгүй.

Хүлээн авагчид 2026.09.23 → 2027.01.01 гэсэн яг 100 хоногийн утгыг харуулна.
9/23-ныг 1 дэх өдөр гэж багтаан тоолоход 100 дахь өдөр нь 12/31 тул 1/1-ийг
«харилцааны 100 дахь өдөр» гэж нэрлэхгүй. Хариугаа амжилттай хадгалсны дараа
шинэ жилийн хоног, гурван жижиг санаа, хүсвэл календарьт нэмэх all-day сануулга
гарна. Энэ нь болзооны тохирсон өдөр, цагийг өөрчлөхгүй.

Сошиал нийтлэлийн бэлэн эх: `marketing/newyear100-2026.md`. Сошиал сувгаар
автоматаар нийтлэх, хэрэглэгчдэд зурвас илгээх үйлдэл хийгдээгүй.

## Production шилжилтийн тэмдэглэл

Өмнөх release-ийн payment integrity, retry-safe redemption, private date plans
migration-ууд production-д байгаагүй. Шилжилтийн өмнөх шалгалтаар хүчинтэй,
дуусаагүй Wire нэхэмжлэл 0; invalid amount болон provider ID давхардал 0.

`bolzoo_release_backup` нэртэй нийтэд нээлтгүй schema-д 20260922 нэртэй payments,
access_codes, хуучин функцийн тодорхойлолт ба grant-ийн backup үүсгэсэн.
Schema/table эрхийг public, anon, authenticated, service_role-оос хасаж, RLS идэвхжүүлсэн.
Backup хэрэглэгчийн browser руу экспортлоогүй.

Шилжилтэд дөрвөн migration орно:

1. `20260907090000_payment_integrity.sql`
2. `20260907090001_retry_safe_redemption.sql`
3. `20260909064508_date_plans.sql`
4. `20260922090728_payment_insert_compatibility.sql`

Дөрөв дэх migration хуучин зэрэгцээ INSERT-д `amount_minor`-ийг нөхөж,
шинэ API-ийн өгсөн илэрхий дүнг өөрчлөхгүй. Нэг transaction-аар schema-г
оруулж, хуучин `process_wire_event` эрхийг шинэ API идэвхжсэний дараа хасна.
Нэгтгэсэн migration artifact: `output/campaign-validation/production-migration.sql`.

Өмнөх `PAYMENT_FLOW.md` дахь хуучин бага дүнтэй нэхэмжлэлийг автоматаар
зөвшөөрөхгүй байх бодлого хэвээр. 2026.09.08-ны `succeeded` боловч code-гүй
нэг хуучин бүртгэл preflight-д байсан; шинэчлэлт түүнийг өөрчлөөгүй.
Тусад нь Wire-тэй тулгаж шийдвэрлэнэ. Шинэ гүйлгээ эхэлсний дараа хуучин
backup-ыг бүхэлд нь буцааж бичихгүй; шинэ төлбөр, эрхийг хадгалан засна.

## Шалгалт

`npm test`, `scripts/verify-campaign-browser.cjs`; үнэ, хугацааны зааг, restart,
давтан хүсэлт, PostgreSQL, raw webhook, гар утасны харагдац, урилгын өгөгдөл,
хариу хадгалсны дараах шинэ жилийн хэсгийг хамарсан.

Chrome тайлан ба зураг: `output/campaign-validation/`. Локал browser шалгалтад
бодит мөнгө төлөөгүй. Production баталгаажуулалтын дүнг нийтэлсний дараа нэмнэ.

Эцсийн автомат шалгалт: **270/270 тэнцсэн**, алгассан тест байхгүй.
Шинэ payment router таван URL-ийг нэг Vercel function руу холбоно; нийт 9 function,
Hobby багцын хязгаарт багтана. Raw webhook bytes, method, authorization хэвээр.
`PUBLIC_BASE_URL=https://bolzoodate.vercel.app` production тохиргоонд нэмсэн.

Domain-тай холбохоос өмнөх бэлэн deployment:
`https://bolzoo-m6efwupd6-gbuy.vercel.app` (`dpl_42ojPfiiT64WZm1WWrwu8bqBWysY`).
Candidate health 9,023₮, regular 9,900₮, Wire live, webhook secret set;
checkout GET нь POST only буцаасан. Candidate build амжилттай.

2026.09.22 17:34 УБ үеийн төлөв: үндсэн `bolzoodate.vercel.app`, `bolzoo-six.vercel.app`,
`bolzoo-gbuy.vercel.app` нь өмнөх `bolzoo-2mkl4zlxl-gbuy.vercel.app` хувилбарт байна.
CLI-ийн `--skip-domain` тохиргоотой байсан ч default alias шилжсэн тул migration
бэлэн болох хүртэл хуучин хувилбарт буцаан холбосон. Canonical public site хэвээр.

Backup амжилттай. Migration SQL editor-ийн урт текст дамжуулалт тасалдсан тул
SQL syntax алдаагаар зогссон; шинэ schema **ороогүй** (REST дээр amount_minor
багана байхгүйг дахин баталгаажуулсан). Хэрэглэгчээс Chrome-ийн SQL Editor-ийг
тогтвортой нээлттэй байлгахыг хүссэн. Үргэлжлүүлэхдээ editor-ийн дутуу текстийг
бүрэн цэвэрлээд artifact-ийг бүхлээр оруулж баталгаажуулна.

Үлдсэн ажил: migration → schema/grant шалгалт → candidate promote, public aliases
→ хуучин process_wire_event эрхийг хасах → live checkout/status/cancel smoke
(мөнгө төлөхгүй) → public banner/price verification. Candidate дээр invalid checkout,
unsigned webhook, mock simulation бүгд хориглогдсоныг шалгасан.

Дахин үргэлжлүүлсэн шалгалт: candidate-ийн 176 source файл workspace-тай таарсан
(зөвхөн энэ release тэмдэглэл шинэчлэгдсэн); дахин build хийх шаардлагагүй.
Нэгтгэсэн migration-ийг PGlite дээр бүтнээр нь ажиллуулах 8 нэмэлт integration
шалгалт тэнцсэн. Transaction rollback, дахин хэрэглэх, grants/RLS, хуучин дүн,
шинэ урамшууллын илэрхий дүн, шилжилтийн дараах RPC revoke баталгаажсан.
Тайлан: `output/campaign-validation/combined-migration-verification.json`.
Chrome-ийн native цонхны зураг авах боломжгүй, UI үйлдлүүд хариу өгөөгүй хэвээр
тул production migration болон alias шилжилт хийгдээгүй. SQL Editor-ийг урд талд
нээж, дэлгэцийг асаалттай байлгах хүсэлт хэрэглэгчид илгээсэн.
