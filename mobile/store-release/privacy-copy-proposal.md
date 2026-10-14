# Public policy copy proposal — 2026-10-14

These paragraphs were applied to runtime sources, reviewed and tested, and deployed to staging by the release owner on October 14. Production policy rollout remains gated on authenticated staging acceptance. This document preserves the copy proposal and evidence. Preserve API identifiers and routes; update the visible product name to **Нандин мөч**.

Status update: the release owner incorporated the main paragraphs into the privacy/native terms/support/deletion runtime sources on 2026-10-14. Cross-reading found these consistent with the implemented data flows. They remain **local and not deployed**. This proposal is retained as audit context; the runtime source is now the implementation record. Operational retention and final provider classifications still require confirmation. The separate web payment terms must also describe current free features accurately before deployment.

Source locations: `cloudflare/src/billing_pages.ts` (`privacy`, `nativeTerms`, visible document branding), `cloudflare/src/account_pages.ts` (`deletionHtml`, `support`). Mobile account-dialog copy is owned by the mobile audit agent.

## Identity and collected information

Нандин мөчийг moch эрхлэн ажиллуулна. Тусламж болон мэдээллийн хүсэлтээ gbuyandelger277@gmail.com хаягт илгээнэ үү. Нэвтрэх код, банкны код, нууц түлхүүрээ имэйлд бүү оруулаарай.

Бүртгэл үүсгэх, нэвтрэхэд имэйл болон бүртгэлийн танигч хэрэглэнэ. Та хосод харагдах нэрээ сонгож болно. Урилга, хоёр талын зөвшөөрөл болон холболтын төлөвийг хадгална. Нэвтрэлтийг хамгаалах, хэт олон хүсэлтээс сэргийлэхэд холболтын техникийн мэдээлэл, нэвтрэх сесс болон хязгаарлалтын бүртгэл ашиглана.

## Shared content and photos

Таны оруулсан болзооны нэр, өдөр, цаг, газар, тайлбар, зөвшөөрлийн төлөв; өдрийн асуултын хариу; зурагт дурсамжийн зураг, жижиг хувилбар, өдөр, гарчиг, тайлбар; хамтын хүсэл, зүрх болон төлөвлөлтийн мэдээллийг хадгална. Хамтын мэдээлэл зөвхөн идэвхтэй холбогдсон хосод нээлттэй. Өдрийн хариуг хоёулаа хариулсны дараа харуулна. Шинэ хосын холбоонд өмнөх хамтын мэдээллийг шилжүүлэхгүй.

Зургуудыг Cloudflare-ийн хувийн хадгалалтад байршуулж, авах хүсэлт бүрт нэвтрэх эрх болон хосын холбоосыг шалгана. Зургийг боловсруулж дахин хадгалахдаа EXIF, GPS зэрэг дагалдах мэдээллийг арилгана. Мэдээллийг HTTPS-ээр дамжуулна. Энэ нь төгсгөл хоорондын шифрлэлт биш. Зурагт өөрт нь харагдах байршил, хүний мэдээлэл автоматаар арилахгүй.

## Florist map and local reminders

Ойрхон цэцгийн дэлгүүр олохдоо та байршлаа ашиглахыг өөрөө сонгоно. Нэг удаагийн байршлыг утасны санах ойд ашиглаж дэлгүүрүүдийг эрэмбэлэх бөгөөд аппын бүртгэлийн серверт илгээхгүй, хосод харуулахгүй. Газрын зураг дээр гараар цэг сонгож ашиглаж болно. Арын горимд тасралтгүй байршил хянахгүй.

Газрын зургийг үзүүлэхэд OpenStreetMap-ийн зураг үйлчилгээ үзэж буй хэсгийн хүсэлт болон IP зэрэг сүлжээний мэдээллийг хүлээн авна. Үзсэн газрын зургийн хэсэг утасны кэшид үлдэж болно. Чиглэл товчийг дарвал сонгосон дэлгүүрийн хаягтай Google Maps холбоос нээгдэнэ; апп таны одоогийн байршлыг эхлэх цэг болгон уг холбоост нэмэхгүй. Гаднын газрын зургийн үйлчилгээ өөрийн нууцлалын нөхцөл, зөвшөөрлөөр ажиллана.

Болзооны сануулгыг төхөөрөмж бүр дээр хүсвэл идэвхжүүлнэ. Сануулгын тохиргоо болон хуваарь тухайн утсанд хадгалагдана. Нөгөө утасны өөрчлөлтийг апп нээлттэй үед шинэчилнэ; энэ нь алсын push мэдэгдэл биш. Гарах, бүртгэл солих, хосын холбоос салсныг баталгаажуулах үед тухайн нэвтрэлтийн сануулгууд цуцлагдана.

## Export, unlink and deletion

Миний бүртгэл → Мэдээллээ татах хэсгээс боломжтой мэдээллийн хуулбараа авч болно. Өөрийн зурагтай дурсамж, хүслийн хуулбарыг хосын холбоос идэвхтэй байх үед аваарай. Экспортолсон файлаа өөрийн сонгосон газар хадгалсан бол апп тухайн хуулбарыг буцаан устгах боломжгүй.

Хосын холбоос салгахад тухайн холбооны бүх зурагтай дурсамж болон хамтын хүсэл хоёр талд нээгдэхгүй болж устгагдана. Зургийн үндсэн файлуудыг тусдаа цэвэрлэгээний дарааллаар устгана; үйлчилгээ тасарсан үед дахин оролдоно. Хэрэгтэй мэдээллээ салгахаасаа өмнө татаарай. Зөвхөн холбоос салгах нь таны бүртгэл болон өөрийн бүх өмнөх хуанли, хариуг устгахгүй.

Аппын Миний бүртгэл → Бүртгэл устгах хэсэг эсвэл бүртгэл устгах вэб хуудсаар имэйлээ баталгаажуулж устгана. Нэр, имэйл, таны бичсэн хуанли, хариу болон бүх төхөөрөмжийн нэвтрэх эрх арилж, холбогдсон хосын холбоос сална. Үүний улмаас тухайн хосын бүх зурагтай дурсамж, хамтын хүсэл мөн устах тул эхлээд хэрэгтэй мэдээллээ татаарай. Өмнө нь бусдын хадгалсан зураг, экспорт, дэлгэцийн хуулбарыг апп устгаж чадахгүй.

Нэр, имэйлгүй устгалын танигч болон харилцааны техникийн тэмдэглэгээ, төлбөр байсан бол давхар ашиглалт, буцаалтыг шалгах гүйлгээний лавлагаа үлдэж болно. Эдгээрийг бүрэн нэргүйжсэн мэдээлэл гэж үзэхгүй. Бүртгэл устгах нь Apple, Google захиалгыг цуцлахгүй; идэвхтэй захиалга байвал дэлгүүрээс тусад нь цуцална.

## Short web deletion consequences

- Нэр, имэйл, таны бичсэн хуанли болон өдрийн хариу устаж, бүх төхөөрөмжийн нэвтрэх эрх цуцлагдана.
- Хосын холбоос салж, энэ холбооны бүх зурагтай дурсамж, хамтын хүсэл хоёр талд нээгдэхгүй болж устгагдана. Хэрэгтэй мэдээллээ эхлээд татаарай.
- Зургийн үндсэн файл цэвэрлэгээний дарааллаар устдаг. Нэр, имэйлгүй техникийн устгалын тэмдэглэгээ, төлбөрийн лавлагаа шаардлагатай хэмжээнд үлдэнэ.
- Дэлгүүрийн захиалга болон өмнө экспортолсон гаднын хуулбар тусдаа үлдэнэ.

## Retention paragraph: do not invent the missing fact

The operational owner must verify exact backup/log/support/audit retention and any legal basis. The old blanket 7–30 day backup statement is not proven by source inspection. Do not publish a newly invented maximum or promise immediate physical erasure. Root may retain a carefully bounded truthful statement only after checking the actual Cloudflare plan and retention settings; record that evidence in the final release report.
