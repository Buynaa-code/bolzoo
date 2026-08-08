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

## Table access is closed — everything goes through RPCs

`anon` has **no SELECT** on `invites` or `access_codes`. Both the RLS policy and the
grant are removed in `sql/schema.sql`. This is not optional hardening — with the old
`using (true)` policies, anyone holding the publishable key (it ships in
`assets/config.js`) could:

- dump every unsold access code and mint free invites,
- read every invite without knowing an ID — private letters, names, sender emails,
- read `owner_token` and delete other people's invites.

Reads now go through two `security definer` functions:

- `check_access_code(p_code)` → `{ok, reason}` only. Never returns a code list or `note`.
- `get_invites(p_ids)` → named IDs only, capped at 200, and **never returns `owner_token`**.

`server.js` rejects direct table access the same way, so a mistake shows up in local
dev instead of only after deploy. If you add a new read path, add an RPC — do not
re-open the table.

## Fixing a typo after sending

One code = one invite, so a typo used to burn the code. `update_own_invite` lets the
creator edit the config **until the recipient answers** (after that it raises, because
they answered based on what they saw). The dashboard shows an "✏️ Засах" button when
both conditions hold: no response yet, and the `owner_token` is on this device.
Editing keeps the same link.

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

### Upgrading a site that is already live — order matters

The frontend switched from reading tables directly to calling RPCs. Get the order wrong
and the live site breaks, in one of two ways (both verified against a simulated backend):

| Wrong order | What the customer sees |
|---|---|
| SQL first, deploy later | Old frontend can no longer read anything — code validation fails, invites won't load |
| Deploy first, SQL later | New frontend calls RPCs that don't exist — buyer can't redeem a code, and **an already-sent invite silently renders the generic default letter instead of the real one** |

So `sql/schema.sql` is split. Run it in three steps for zero downtime:

1. Run `sql/schema.sql` **without** the "АЛХАМ 2 — ХҮСНЭГТИЙГ ТҮГЖИХ" block at the
   bottom. This only adds the new RPCs; the old site keeps working.
2. Merge and deploy. The new frontend now uses the RPCs.
3. Run the "АЛХАМ 2" block. The old direct-table path closes and the security holes
   shut with it.

Between steps 1 and 3 the old permissive policies are still in place, so keep that window
short. A brand-new project can run the whole file at once — it never creates a permissive
SELECT policy, so a fresh install is locked from the start.
