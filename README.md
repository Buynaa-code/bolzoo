> **Measurement source snapshot — not deployed.** See [SOURCE_HANDOFF.md](docs/SOURCE_HANDOFF.md) before using this branch. Production credentials, Git workflows and the separate Flutter/Cloudflare app are excluded. Automatic Git deployment is disabled.

# bolzoo 💌

Personalised Mongolian date invitation and relationship-repair web app.

The floral welcome in `create.html` includes an interactive sample letter and
three date ideas (coffee, picnic, cinema). Selecting an idea sets a matching
template, color and editable message, then opens the names step. Existing names,
messages and access codes are preserved. The message step also offers suggestions
with an explicit choice before replacing written text. Shuffling ideas and opening
the sample never publish an invitation or start payment.

The feature lives in `assets/date-ideas.js`, with its botanical styles in
`assets/bloom.css` and a local SVG bouquet. It needs no new backend or schema.

`create.html` starts with two product modes:

- **Болзоонд урих** — the existing personalised date invitation flow
- **Bolzoo · Эвлэрье** — a no-AI, template-based apology letter with five
  recipient-controlled response states, six paper textures, a self-reported
  0–100% reconciliation-readiness bar, a 30-day private link, and the same
  one-time 9,900₮ checkout

The apology flow deliberately does not guess a “forgiven percentage”. The
recipient may voluntarily choose a 0–100% readiness value in 10% steps; the
sender sees only that self-reported value and the exact status they chose.

- **create.html** — seller fills a form and gets a short invite URL
- **bolzoo.html?id=xxx** — recipient opens the invite and answers
- **dashboard.html** — seller sees invites and responses
- **ideas.html** — 18 ready date templates, five quick choices and three matching suggestions
- **date-plan.html?invite=xxx** — private two-person Хамтдаа plan, consent, missions and memories
- **server.js** — pure Node local dev server (also emulates the Supabase PostgREST API for offline dev)
- **assets/config.js** — Supabase URL + publishable key
- **sql/schema.sql** — Supabase table + RLS policies

Урилга бэлэн болсны дараа **QR зураг татах · PNG** товчоор QR-аа зураг болгон
хадгална. Амжилтын цонхыг хаасны дараа линкний доорх **QR татах**, эсвэл
«Урилгын хариу» хуудсан дахь урилгын **QR татах** товчоор дахин авч болно.
QR нь хүлээн авагчийн урилгыг нээнэ. Зургийг браузер дотор үүсгэдэг бөгөөд
QR үүсгэх гадаад үйлчилгээ рүү линк илгээхгүй. Хэрэгжилт: `assets/qr.js`,
MIT лицензтэй `assets/vendor/qrcode.js` (qrcode-generator 2.0.4).

## Local dev

```bash
cp .env.example .env   # анх удаа. Үндсэн placeholder-уудыг өөрийн утгаар солино.
ALLOW_MOCK_PAYMENT=1 node server.js  # локал mock QPay
# → http://localhost:8080
```

`server.js` эхлэхдээ repo root дахь `.env` (болон `.env.local`) файлыг автоматаар
уншиж `process.env` руу нэмнэ. Урьтамжлал: **shell env > `.env.local` > `.env`**.
`.env` файлууд `.gitignore`-т орсон тул real key-үүд commit хийгдэхгүй.

## Environment variables

Бүх ашиглагдаж буй хувьсагчийн бичлэгийг `.env.example`-ээс уншина уу. Хамгийн
чухал нь:

| Хувьсагч | Хэрэглээ | Тохируулаагүй үед |
|---|---|---|
| `YOUTUBE_API_KEY` (or `GOOGLE_API_KEY`) | YouTube Data API v3 key — `/api/youtube-search` серверийн прокси-д ашиглагдана | `create.html` YouTube хайлт 503 буцаана; `bolzoo.html` Tone.js fallback мелоди тоглуулна |
| `WIRE_API_KEY`, `WIRE_WEBHOOK_SECRET` | Wire QPay эрхийн код борлуулалт live горим | Төлбөр идэвхгүй; mock-ийг локалд тусад нь зөвшөөрнө |
| `ADMIN_PASSWORD` | `admin.html` + debug endpoint-ийн basic auth | Локал default `"admin123"` |
| `PRICE_MNT` | QPay нэхэмжлэлийн үнэ | `9900` |

### `YOUTUBE_API_KEY` авах алхам

1. https://console.cloud.google.com/apis/library/youtube.googleapis.com
2. **Enable** YouTube Data API v3
3. **Credentials** → *Create Credentials* → *API key*
4. Restrictions:
   - **Application restrictions** → *HTTP referrers*: `*.vercel.app`, `localhost:8080`, өөрийн prod домэйн
   - **API restrictions** → зөвхөн *YouTube Data API v3*
5. Гарсан key-ыг `.env` файлд `YOUTUBE_API_KEY=…` гэж бичнэ (эсвэл Vercel Project
   Settings → Environment Variables → *Production/Preview/Development* дээр нэмнэ)

## Deploy

Vercel serves the static pages and Node functions under `api/`. Supabase stores
payments, access codes and invites with restricted table access and transactional RPCs. Env хувьсагчдыг **Vercel Project Settings → Environment Variables**
дээр нэмнэ — `.env` файл serverless function-д хамаагүй.

## Bolzoo · Хамтдаа

«Богино болзоо», «Бүтэн орой», «Бага зардлаар», «Дотор», «Гадаа» сонголт бүр
гурван санал харуулна. «Энэ загварыг ашиглах» нь бэлэн зурвас, өнгөтэй хоёр алхмын
богино урсгалыг нээнэ: нэрээ бичих → урьдчилан хараад линкээ авах. Нэмэлт засвар
заавал биш. «Хариу харах» нь үүсгэсэн урилгыг шууд нээнэ; хариуны карт эхэндээ
сонгосон хариу, хэрэгтэй нэг үндсэн үйлдэл, бодит хамтын тохиролцоог харуулна.
Энэ шинэчлэлтийн шалгалтыг [SIMPLE_FLOW_RELEASE.md](SIMPLE_FLOW_RELEASE.md)-ээс үзнэ үү.

Санаагаа сонгоод урилга үүсгэсний дараа амжилтын дэлгэц эсвэл «Миний урилгууд»
дээрээс гурван алхамтай болзоогоо төлөвлөнө. Илгээгч оролцох тусгай холбоосоо
нөгөө хүнд өгч, хоёр тал ижил хувилбарыг зөвшөөрсний дараа болзоогоо эхлүүлнэ.
Өдөр, газар, төсөв, алхам өөрчлөгдвөл дахин зөвшөөрнө. Хүн бүр өөрийн явцаа
тэмдэглэж, бүх алхмыг дуусгалгүй өндөрлөж болно. Дараа нь зөвхөн өөрт харагдах
дурсамж хадгална.

Тикет нь зураг болгон татах болзооны төлөвлөгөө; кино, хоолны төлбөр, захиалга
агуулахгүй. Story зураг хувийн нэр, өдөр, газар, оролцох холбоос агуулахгүй.

Локал сервер `data/date_plans.json`-д хадгална. Production API Supabase-ийн
`date_plans` хүснэгт болон атомик RPC ашиглана. Шинэ API-г deploy хийхээс өмнө
`supabase/migrations/20260909064508_date_plans.sql` migration-ийг хэрэгжүүлнэ.
Хэрэгжилт, туршилт, ашиглалтад оруулах зааврыг [HAMTDAA_RELEASE.md](HAMTDAA_RELEASE.md)-ээс үзнэ үү.


## Төлбөрийн засвар ба тест

```bash
npm ci
npm test
```

Wire-ийн дүн, давхар хүсэлт, webhook, код олголт, урилгын сэргэлтийн зөрүүг
зассан. Урсгал, эх сурвалж болон production-д оруулах дарааллыг
[PAYMENT_FLOW.md](PAYMENT_FLOW.md)-ээс үзнэ үү. Тэнд жагсаасан хоёр migration-ийг
Supabase-д **API шинэчлэхээс өмнө** хэрэгжүүлнэ. Локал тест бодит төлбөр татахгүй.
