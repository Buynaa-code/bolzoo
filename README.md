# bolzoo 💌

Personalised Mongolian date invitation web app.

Гурван төрлийн илгээлт, бүгдийг `create.html`-ээс сонгоно:

| Горим | Хүлээн авагчийн хуудас | Юу хийдэг |
|---|---|---|
| 🌸 Цэцэг + захидал | `greet.html?id=xxx` | Нэг цэцэг, гар бичмэл захидал. Хүлээн авагч «Хүлээж авлаа» гээд богино хариу бичнэ |
| 💌 Болзооны урилга | `bolzoo.html?id=xxx` | Хүлээн авагч өдөр, цаг, болзооны төрлөө сонгоно |
| 🥺 Аргадах захидал | `argadah.html?id=xxx` | Уучлалын захидал, амлалтын купон, 0–100% уучлалын хэмжүүр |

## Файлууд

- **create.html** — нүүр хуудас: горимоо сонгож, формоо бөглөөд линкээ авна
- **greet.html?id=xxx** — цэцэг + захидлын мэндчилгээ
- **bolzoo.html?id=xxx** — болзооны урилга; бичлэг нь өөр горимынх бол зөв хуудас руу шилжүүлнэ
- **argadah.html?id=xxx** — текстуртэй цаасан дээрх уучлалын захидал
- **dashboard.html** — илгээсэн зүйлс ба ирсэн хариунууд
- **unelgee.html** — олон нийтэд харагдах үнийн хуудас (9,900₮, бүх боломж багтсан)
- **server.js** — pure Node local dev server (Supabase PostgREST API-г офлайнаар эмуляц хийнэ)
- **assets/config.js** — Supabase URL + publishable key + имэйл webhook URL
- **assets/bolzoo-garden.js** — 5 цэцгийн inline SVG + 5 захидлын цаасны тодорхойлолт
- **assets/bolzoo-paper.js** — захидлын цаасны 8 текстур (цэвэр CSS/SVG, зураг ашиглахгүй)
- **assets/bolzoo-sticker.js** — захидлын муурын зургийн сонголтууд
- **assets/img/** — тайрсан муурын гэрэл зураг (WebP, alpha-тай)
- **sql/schema.sql** — Supabase table + RLS policies

Бүх горимын өгөгдөл `invites.config` (jsonb) дотор хадгалагдана — `mode`, цэцгийн
`flower`/`paper`/`specialLetter`, аргадахын `sorryReason`/`sorryLetter`/`sticker`/`promises`.
Горим нэмэх бүрд өгөгдлийн сангийн бүтэц өөрчлөгдөхгүй.

Шинэ цаасны текстур эсвэл муурын зураг нэмэх нь холбогдох `assets/bolzoo-*.js`
модульд нэг мөр нэмэхэд л хангалттай — `create.html`-ийн сонгогчид тэр жагсаалтаас угсардаг.

Гар бичмэл фонт: [Caveat](https://fonts.google.com/specimen/Caveat) (кирилл, `Ө/Ү` үсэг дэмждэг).

## How the sender finds out (response notification)

Two independent paths — the second one is a safety net for the first:

1. **The response is always written to the database** (`save_response` RPC) as soon as the
   recipient answers, in every mode. Nothing depends on email for the data to survive.
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

`create.html` switches to the same edit state the moment a link is created: change
anything in the form and a "Өөрчлөлтийг хадгалах" button appears; undo the change and
it disappears. The mode picker is locked from then on — `greet.html` does not redirect
by mode, so changing a sent flower link to another mode would break it. "＋ Шинэ" starts over.

## Losing the invite list

`dashboard.html` reads `bolzoo:my` from **localStorage**, so switching phones or clearing
history empties the list. The invites themselves are untouched on the server — the
dashboard takes an invite link (or bare ID) and puts it back in the list. Recovered
entries are read-only: the `owner_token` needed for deletion lives only on the original
device, which is why `forgetInvite` (list-only removal) and `deleteInvite` (permanent)
are separate actions.

## Local dev

```bash
node server.js
# → http://localhost:8080
```

## Deploy

Vercel дээр цэвэр статик сайтаар deploy хийгддэг (build алхам байхгүй — `vercel.json`-д
`buildCommand: null`, `outputDirectory: "."`). Backend нь Supabase (`invites` хүснэгт, RLS-тэй).

Vercel-ийн GitHub integration холбогдсон бол `main` руу push хийх бүрд production,
бусад branch/PR дээр preview автоматаар deploy болно. CLI-аар гараар хийх бол:

```bash
npx vercel --prod
```

Deploy болсны дараа шалгах хуудсууд:

| Зам | Юу байх ёстой |
| --- | --- |
| `/` эсвэл `/create` | Нүүр хуудас — горим сонгох |
| `/greet.html` | Цэцэг + захидлын мэндчилгээ |
| `/bolzoo.html` | Болзооны урилга |
| `/argadah.html` | Аргадах захидал |
| `/unelgee.html` | Үнийн хуудас |
| `/dashboard.html` | Илгээсэн зүйлс ба ирсэн хариунууд |
| `/assets/bolzoo-garden.js` | Цэцэг, захидлын цаасны сан — 200 буцаах ёстой |

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
