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
- **unelgee.html** — public pricing page (9,900₮, everything included) — shareable on Instagram
- **server.js** — pure Node local dev server (also emulates the Supabase PostgREST API for offline dev)
- **assets/config.js** — Supabase URL + publishable key + email webhook URL
- **assets/bolzoo-paper.js** — letter paper textures (pure CSS/SVG, no image files)
- **assets/bolzoo-sticker.js** — cat artwork options for the letter
- **assets/img/** — cut-out cat photos (WebP with alpha)
- **sql/schema.sql** — Supabase table + RLS policies

`config` is a `jsonb` column, so the sorry-mode fields (`mode`, `sorryReason`, `sorryLetter`,
`paper`, `sticker`, `promises`) needed no schema migration.

Adding a new paper texture or cat image is a one-entry change in the matching
`assets/bolzoo-*.js` module — the pickers in `create.html` are built from those lists.

## How the sender finds out (response notification)

Two independent paths — the second one is a safety net for the first:

1. **The response is always written to the database** (`save_response` RPC) as soon as the
   recipient answers, in both modes. Nothing depends on email for the data to survive.
2. **An email is sent to `config.responseEmail`** — but only once you set
   `emailWebhookUrl` in `assets/config.js`. Setup instructions are at the top of
   `bolzoo-email-apps-script.js` (a Google Apps Script web app, ~5 minutes, one time).

While `emailWebhookUrl` is empty there is **no automatic email**. The date-mode
recipient then sees a "📧 Хариугаа имэйлээр илгээх" button that opens Gmail compose on
*their* device — which only works if they actually press Send. That button hides itself
once the webhook is configured. Do not promise buyers email notifications until it is set.

The Apps Script takes only an `inviteId` and looks the address up in Supabase itself, so
the endpoint cannot be used as an open mail relay.

## Losing the invite list

`dashboard.html` reads `bolzoo:my` from **localStorage**, so switching phones or clearing
history empties the list. The invites themselves are untouched on the server — the
dashboard has a "Урилга нэмэх" box that takes an invite link (or bare ID) and puts it
back in the list. Recovered entries are read-only: the `owner_token` needed for deletion
lives only on the original device.

## Local dev

```bash
node server.js
# → http://localhost:8080
```

## Deploy

Deployed as a pure static site on Vercel. Backend is Supabase (`invites` table with RLS).
