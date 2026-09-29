# Bolzoo measurement source snapshot — 2026-09-29

This branch is an isolated **web source snapshot for local measurement work**.
It is newer than the public site and is **not a production-equivalent release**.
No analytics feature, production deployment, database query/migration, payment,
or customer-data export was performed while preparing this snapshot.

## Provenance

- Original working branch: `qpay-integration`, HEAD `c32944346ff9c981cc3591e3900fd08bb83a1726` plus uncommitted work.
- Snapshot parent: public GitHub `main` at `8cfafac453771717503a1b428dd678c1291c6564`.
- Snapshot branch: `codex/moch-measurement-source-20260929`.
- GitHub repository: `https://github.com/Buynaa-code/bolzoo` (public).
- Live Bolzoo creator, linked from Moch: `https://bolzoodate.vercel.app/create`.
- Vercel production target observed: `dpl_8Sq2nTY8m9CDRneLP16HrC6SUGiw`, `https://bolzoo-2mkl4zlxl-gbuy.vercel.app`.
- Unpromoted candidate recorded in project metadata: `dpl_42ojPfiiT64WZm1WWrwu8bqBWysY`.

`docs/source-provenance.json` compares 143 selected workspace files to the live
Vercel deployment's source manifest: 50 have equal SHA-1, 28 differ, and 65 are
not present in that deployment source. Absence can mean development-only
material excluded from deployment; it does not by itself mean an app feature.

Public creator SHA-256: `517a075e10cf57e11a24747a5fec82e7a6555d37afe5b57b61840ace4ac4dea4`.
Snapshot creator SHA-256: `f38dc712897c632e8aa95136f5d3ea29824c082b7f298c408c89519ec1a99e80`.

The public creator has `bloomTitle`, `dateIdeasTitle`, `purposeGate` and the five
steps template → names → color/music → message → link. GitHub main lacks these
markers. This snapshot contains them plus further unpublished changes.
Live `/assets/campaign.js` and `/assets/date-plan.js` returned 404 during inspection.

## Scope and deliberate snapshot-only differences

Included: web HTML/CSS/JS, runtime artwork/licenses, API/server libraries,
automated tests, local browser verification scripts, package manifests,
SQL schema/migration source, and relevant README/release notes.

Excluded: `.env`/`.env.local`, local auth, `.vercel`, admin credentials,
customer data, logs, screenshots/archives, `output`, `node_modules`, temporary
Supabase state, GitHub workflows, marketing/prototype outputs, and `mobile`.
The Flutter app and incomplete Cloudflare backend stay in the original Mac
checkout; neither is represented as completed or included in this web snapshot.
`.env.example` contains placeholders and the documented local demo password only.

Three configuration/documentation-only adjustments make the snapshot portable:

1. `assets/config.js` has an empty config; the public production endpoint/key
   were intentionally omitted. Local `server.js` handles mock storage.
2. `vercel.json` has `git.deploymentEnabled: false`; do not remove this or deploy
   this branch without a separate release review. This changes no Vercel account setting.
3. `.gitignore` excludes local credentials, logs, generated output and other apps;
   this handoff, provenance manifest and README notice were added.

The original checkout, branch, index and working files remain unchanged.

## Run locally on Windows

Use a separate checkout of this branch. Do not copy production environment files.

```powershell
git clone --branch codex/moch-measurement-source-20260929 --single-branch https://github.com/Buynaa-code/bolzoo.git bolzoo-measurement
cd bolzoo-measurement
npm ci --ignore-scripts
npm test
$env:ALLOW_MOCK_PAYMENT = '1'
npm start
```

Open `http://127.0.0.1:8080`. Optional mock payment is local only. No real Wire,
Supabase, Resend, or YouTube credentials are included. If an older Windows Node
version does not expand the test glob, use `node --test (Get-ChildItem test/*.test.js).FullName`.
A future remote preview needs a separate test database and test credentials;
never reuse the production database for measurement experiments.

## Payment and publishing entrypoints

- `api/payment.js` and `vercel.json`: current snapshot payment router/rewrites.
- `lib/payment-handlers.js`: checkout, payment status, cancellation, raw-body
  webhook HMAC verification and HTTP error handling.
- `lib/payment-flow.js`: provider re-fetch, provider ID/amount/currency/live-mode
  verification, retry/idempotency rules and entitlement reconciliation.
- `lib/payment-repository.js`: storage boundary; calls `reconcile_wire_payment`.
- `lib/payment-api.js`: Wire gateway/helpers used by the above.
- `api/checkout.js`, `api/payment-status.js`, `api/wire-webhook.js`,
  `api/cancel-payment.js`, `api/dev-mark-paid.js`: local/compatibility wrappers.
- Publishing is **`assets/api.js:createInvite` → `create_invite_with_code` RPC**.
  `api/invite.js` POST retrieves an owned invitation, not a publish operation.
- `create.html`, `pay.html`, `assets/api.js`: creator/payment return/client state.
- `server.js`: isolated local JSON-backed implementation for test/development.

The current public deployment has the older direct API endpoints and older
`lib/payment-api.js`; it does not have this new shared payment router. Instrument
only this local snapshot initially. Do not assume new payment fields exist live.

## Database source; no migration executed

- `sql/schema.sql`: consolidated target schema.
- `sql/prod-catchup.sql`: historical catch-up source, not a current applied-state report.
- `supabase/migrations/`: ordered migration source.

`CAMPAIGN_RELEASE.md` records these four as pending after a failed migration and
an unpromoted candidate:

1. `20260907090000_payment_integrity.sql`
2. `20260907090001_retry_safe_redemption.sql`
3. `20260909064508_date_plans.sql`
4. `20260922090728_payment_insert_compatibility.sql`

No live schema introspection was performed for this handoff. Treat the above as
unverified on production; source presence never establishes applied DB state.
Do not run these files against production as part of local measurement work.

## Existing and unpublished capabilities

Unpublished local work includes stricter payment integrity/retry handling,
18 date ideas/missions, quick two-step creation, private two-party date plans
with consent on revisions, progress/memories, tickets, improved response UI,
and the now-expired September 22–24 campaign.

No dedicated GA/gtag/dataLayer, PostHog, Mixpanel, Plausible, Meta pixel,
analytics sender, or sendBeacon was found in app source/live creator.
There are operational `opened_at`, `responded_at`, response history,
payment and webhook records. These are not a verified purchase funnel.
Hosting-dashboard analytics configuration was not inspected.

## Validation and publishing guard

- Fresh isolated copy: `npm ci --ignore-scripts`, then **270 tests passed**, 0 failed,
  0 skipped, on macOS/Node 25. Windows execution has not yet been verified.
- Credential-pattern scan and comparison with available local sensitive env
  values: no real credential matches. The sole credential-URL pattern hit is
  the intentional rejection fixture at `test/qr.test.js:139` on `.example`.
- Placeholder `.env.example` reviewed; no account auth/customer files selected.
- Vercel project API showed no linked Git repository on `bolzoo`; the account's
  project inventory showed no additional linked project for this repository.
- GitHub repository hooks were empty; Pages is disabled; the existing keep-alive
  workflow is scheduled/manual and is excluded from this snapshot.
- This snapshot's Vercel Git deployments are disabled in its own config.

Official Git deployment setting: https://vercel.com/docs/project-configuration/git-configuration#git.deploymentenabled
