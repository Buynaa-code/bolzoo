# Invitation responses — 2026-09-07

Response dashboard release. Live URL: https://bolzoodate.vercel.app/dashboard

## Behavior

- Clear waiting/responded status filters and case-insensitive recipient search.
- Explicit accepted, alternate-day, declined, pending and apology response states.
- Separate date/time details and Ulaanbaatar timestamps; accepted scheduled dates
  can download an ICS calendar event with an explained one-hour default.
- Recovery codes and private ownership links, accurate success/error feedback,
  safe retries, preserved cards during network failure, and 30-second refreshes.
- Sender preview does not mark the recipient link opened. Malformed owner links
  are rejected, absent readiness is not shown as zero, and expired apology links
  stop appearing active, including after an unchanged-data refresh.
- Phone layout and clearly labelled sample responses.

## Verification

- Full workspace: `npm test`, 133 passed, 0 failed.
- Exact staged dashboard/helper source: 36 passed, 0 failed.
- Browser: desktop, 390px and 320px; no horizontal overflow.
- Local HTTP: mock checkout/publish/respond followed by recovery through the UI.
- Browser actions: recovery, filters/search, private details and calendar download.
- Independent review and regression coverage for missing scripts, expiry and the
  calendar click path. `git diff --check` passed.

## Scope

The stage `/private/tmp/bolzoo-bloom-deploy` retains the previously released
floral creator. This release overlays only `dashboard.html`,
`assets/dashboard.css` and `assets/responses.js`.

18 payment/backend/config/package files were verified byte-for-byte unchanged
against `/private/tmp/bolzoo-production-baseline`. Pre-existing workspace payment
changes and unapplied database migrations remain excluded; see BLOOM_RELEASE.md
and PAYMENT_FLOW.md. No database change or real payment was made for this release.

## Deployment

Promoted successfully: `dpl_7MhjUoCypK33b75ZX5qxBskcGTMr`
(`https://bolzoo-773gg9cxw-gbuy.vercel.app`). The public domain returns HTTP 200
and byte-matches the staged dashboard, its two assets, the floral creator, payment
page and API client. `/api/health` reports `ok: true` and no missing configuration.
Live browser sample rendering and calendar download succeeded with no production
console errors.
