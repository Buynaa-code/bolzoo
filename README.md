# bolzoo 💌

Personalised Mongolian date invitation web app.

- **create.html** — seller fills a form and gets a short invite URL
- **bolzoo.html?id=xxx** — recipient opens the invite and answers
- **dashboard.html** — seller sees invites and responses
- **server.js** — pure Node local dev server (also emulates the Supabase PostgREST API for offline dev)
- **assets/config.js** — Supabase URL + publishable key
- **sql/schema.sql** — Supabase table + RLS policies

## Local dev

```bash
node server.js
# → http://localhost:8080
```

## Deploy

Deployed as a pure static site on Vercel. Backend is Supabase (`invites` table with RLS).
