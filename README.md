# bolzoo 💌

Personalised Mongolian date invitation and relationship-repair web app.

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
- **server.js** — pure Node local dev server (also emulates the Supabase PostgREST API for offline dev)
- **assets/config.js** — Supabase URL + publishable key
- **sql/schema.sql** — Supabase table + RLS policies

## Local dev

```bash
cp .env.example .env   # анх удаа. Үндсэн placeholder-уудыг өөрийн утгаар солино.
node server.js
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
| `WIRE_API_KEY`, `WIRE_WEBHOOK_SECRET` | Wire QPay эрхийн код борлуулалт live горим | `server.js` mock QPay горим |
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

Deployed as a pure static site on Vercel. Backend is Supabase (`invites` table
with RLS). Env хувьсагчдыг **Vercel Project Settings → Environment Variables**
дээр нэмнэ — `.env` файл serverless function-д хамаагүй.
