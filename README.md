# bolzoo 💌

Personalised Mongolian date invitation web app.

Two invite modes, picked in `create.html`:

| Mode | Recipient page | What it does |
|---|---|---|
| 💌 Болзоо (date) | `bolzoo.html?id=xxx` | Suggest a date, recipient picks day/time/kind |
| 🥺 Аргадах (sorry) | `argadah.html?id=xxx` | Apology letter, promise coupons, forgiveness meter |

- **create.html** — seller fills a form and gets a short invite URL (both modes)
- **bolzoo.html?id=xxx** — date invite; redirects to `argadah.html` if the record is a sorry letter
- **argadah.html?id=xxx** — apology letter on a textured paper, ends with a 0–100% forgiveness answer
- **dashboard.html** — seller sees invites and responses
- **server.js** — pure Node local dev server (also emulates the Supabase PostgREST API for offline dev)
- **assets/config.js** — Supabase URL + publishable key
- **assets/bolzoo-paper.js** — letter paper textures (pure CSS/SVG, no image files)
- **assets/bolzoo-sticker.js** — cat artwork options for the letter
- **assets/img/** — cut-out cat photos (WebP with alpha)
- **sql/schema.sql** — Supabase table + RLS policies

`config` is a `jsonb` column, so the sorry-mode fields (`mode`, `sorryReason`, `sorryLetter`,
`paper`, `sticker`, `promises`) needed no schema migration.

Adding a new paper texture or cat image is a one-entry change in the matching
`assets/bolzoo-*.js` module — the pickers in `create.html` are built from those lists.

## Local dev

```bash
node server.js
# → http://localhost:8080
```

## Deploy

Deployed as a pure static site on Vercel. Backend is Supabase (`invites` table with RLS).
