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

## Plans

Access codes carry a plan. Sell the code, the code decides what the buyer can build.

| | Энгийн — 9,900₮ | Онцгой — 14,900₮ |
|---|---|---|
| Modes, themes, song, email reply | ✅ | ✅ |
| Letter length | 300 | 600 |
| Paper textures | 3 | all 8 |
| Cat artwork | drawn only | real photos too |
| Promise coupons | — | up to 5 |
| Location + Maps, special letter | — | ✅ |

- **assets/bolzoo-plans.js** — the single source of truth for prices and limits
- **unelgee.html** — public pricing page, built from that same file (share it on Instagram)
- **admin.html** — pick the plan when generating codes

Gating is enforced in **three** places and all three must be updated together:
`assets/bolzoo-plans.js` (UI), `sql/schema.sql` → `_apply_plan_limits()` (Supabase),
and `server.js` → `applyPlanLimits()` (local dev). The client-side lock is only a
convenience — the RPC is what actually strips premium fields from a basic invite.

Codes created before plans existed have no `plan` value and are treated as
**premium**, so nobody who already paid gets downgraded. Change `DEFAULT_PLAN`
in `assets/bolzoo-plans.js` (and the column default in `sql/schema.sql`) to flip that.

Deploying the plan change to an existing Supabase project means re-running
`sql/schema.sql` — it is written to be idempotent (`add column if not exists`, `create or replace`).

`config` is a `jsonb` column, so the sorry-mode fields (`mode`, `sorryReason`, `sorryLetter`,
`paper`, `sticker`, `promises`, `plan`) needed no schema migration.

Adding a new paper texture or cat image is a one-entry change in the matching
`assets/bolzoo-*.js` module — the pickers in `create.html` are built from those lists.

## Local dev

```bash
node server.js
# → http://localhost:8080
```

## Deploy

Deployed as a pure static site on Vercel. Backend is Supabase (`invites` table with RLS).
