# Floral welcome and date ideas — 2026-09-07

Live: https://bolzoodate.vercel.app/

Promoted deployment: `dpl_8QcXtFY2N4vfJNSvhkNsVxv1UDNo`
(`https://bolzoo-5o5ok67ne-gbuy.vercel.app`). Vercel reported READY and promotion
succeeded. The live domain serves the staged creator and new assets; `/api/health`
returns HTTP 200 with Wire live, webhook secret set and no missing configuration.

The creator now opens with a botanical welcome, a sample letter that opens on
click, and a clear invitation creation action. Coffee, picnic and cinema presets
prepare the template, color and editable message and advance to the name fields.
Message suggestions require an explicit choice before replacing existing writing.
Existing names, messages, locations and purchased access codes are preserved.

## Verification

- Workspace `npm test`: 97 passed, 0 failed.
- Creator tests against the actual deployment stage: 17 passed, 0 failed.
- Browser: desktop, 390px and 320px; no horizontal overflow or console errors.
- Browser: sample letter, preset selection, message replacement cancellation,
  recipient preview and draft restoration after reload.
- Independent review: fixed contrast in process descriptions, caption and footer.
- `git diff --check` passed.

## Deployment scope

This release uses the exact source of the existing production deployment
`dpl_H26hLjdKrGNPahah6fjW1NrKeGa4` as its baseline. Its 71 files were retrieved from
Vercel and SHA1-verified against the deployment file identifiers. The stage is
`/private/tmp/bolzoo-bloom-deploy`; the baseline and source manifest are in
`/private/tmp/bolzoo-production-baseline`.

The only deployment overlays are:

- `create.html`
- `assets/create-ux.css`
- `assets/styles.css`
- `assets/bloom.css`
- `assets/date-ideas.js`
- `assets/images/bloom-bouquet.svg`
- `assets/images/download (2).png`

The production payment page, API, API client, server libraries, package files and
Vercel configuration remain byte-for-byte identical to the baseline. The current
creator remains compatible with its query-string payment return, storage keys,
invite creation API and recipient preview messages.

The workspace already contained separate payment backend changes before this
task. Production does not yet have `payments.amount_minor`; Supabase management
authentication returned 401. Those backend changes and their migrations were
therefore excluded from this UI release and remain in the workspace. Apply and
verify their migrations before a future full-workspace deployment, following
`PAYMENT_FLOW.md`. This feature itself needs no database migration.

No real payment was made during verification.
