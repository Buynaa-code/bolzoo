# Backend release check — 2026-10-14

Baseline: `62b5d92`, matching `origin/codex/restore-cloudflare-backend` when the
release task fetched GitHub. Work is on `codex/native-release-20261014`.

## Reproduced and repaired pairing failure

An outgoing request could become invisible in pair status when its invitation
creator was disabled, lost email verification, or blocked the requester. The
request endpoint still counted that invisible row as a pending request, so a
different valid invitation previewed successfully but requesting it returned
`invalid_state` until the old invitation expired. Three new regression cases
failed against the baseline with that result.

`cloudflare/src/pair.ts` now uses the same live-invitation predicate for pending
requests and status. When accepting a fresh request, it retires unusable old
requests in the same D1 transaction. Expired requests remain `expired`; other
unusable requests become `revoked`. A valid pending request is preserved, and the
unique index still prevents concurrent duplicate consent paths. Eligibility is
rechecked in the transaction: if the earlier invitation becomes valid again
before commit, the replacement rolls back without losing the prior request or
writing a command receipt.

Five tests were added in `cloudflare/test/pair.test.ts`: the three failure cases,
preserving valid pending consent, and recovery of eligibility immediately before
commit. This establishes one real stuck-request cause, not the cause of an
unobserved historical iPhone/Android failure.

No migration, dependency, Wrangler configuration or billing flag changed.

## Completed local checks

Initial execution used the installed Node **25.7.0**. Final full suites, both
TypeScript checks, the three schema checks and all four bundling dry-runs were
then rerun successfully on **Node 22.23.3**, matching the repository's Node 22
runtime requirement. The runtime was resolved with
`npm exec --yes --package=node@22 -- node -p process.execPath`, and its containing
directory was prepended to `PATH` for each command; no dependencies were changed.
Final dry-run outputs use the `node22-` prefix in the same temporary directory.

| Check | Result |
| --- | --- |
| Auth baseline suite | 171 passed, 9 files |
| New reproductions before fix | 3 failed with `invalid_state`; 22 pair tests passed |
| Auth complete suite after fix | **176 passed, 9 files** |
| Auth TypeScript | passed |
| Auth/combined schema comparison | **3 passed** |
| Auth generated binding types | reproduced unchanged |
| Auth staging and production bundling dry-runs | both passed |
| Memories/wishes complete suite | **32 passed**, including schema assertions |
| Memories/wishes TypeScript | passed |
| Memories/wishes generated binding types | reproduced unchanged |
| Memories/wishes staging and production bundling dry-runs | both passed |
| Diff whitespace check | passed |

Auth tests explicitly inject a disposable test-only auth secret and disable
remote bindings. Wrangler emits a missing-required-secret warning while reading
configuration before the test override; the suite nevertheless exercised real
local D1 and the OTP/auth router. Production secret values were not needed or
read. Email, store and payment providers are mocked.

Commands from `mobile/cloudflare`:

```sh
npm run types
npm run check
npm run test:schema
npm test
npm run deploy:check -- --outdir /tmp/nandin-release-backend-20261014/auth-staging
npm run deploy:check:production -- --outdir /tmp/nandin-release-backend-20261014/auth-production
```

Commands from `mobile/memories_worker`:

```sh
npm run types
npm run check
npm test
npm run dry-run -- --outdir /tmp/nandin-release-backend-20261014/memories-staging
./node_modules/.bin/wrangler deploy --dry-run --env production --outdir /tmp/nandin-release-backend-20261014/memories-production
```

Current Cloudflare D1 batch documentation and Workers best practices were
checked; the latest published Workers type declarations (`5.20261014.1`) were
inspected separately in `/tmp`. The repository's pinned versions were preserved.

## Release boundary

These checks did not deploy either Worker, apply a remote migration, send email,
make a payment, or access real photos. Both backends remain at their existing
live versions until a separate reviewed deployment. The pairing fix therefore
is not yet active in production.

Dry-runs confirm the production memories Worker binds to the production auth
Worker/D1/R2 resources and staging binds only to staging. Both auth build
configurations keep `BILLING_ENABLED`, `BILLING_WEB_ENABLED` and
`BILLING_ALLOW_SANDBOX` false.

Before public release, deploy a candidate to staging, exercise the authenticated
two-account flow there, then decide on production rollout. The user cannot
currently connect both phones, so native two-phone acceptance, relaunch/offline
behavior, permission denials and Store review are not proven by these results.
Retain the existing deployment version for rollback; no schema rollback is
needed for this code-only fix.

## Minimum staging acceptance before rollout

No tracked staging smoke script was found. Existing CI uses local tests and
bundling dry-runs; earlier release notes record public health and unauthenticated
rejection checks only. A safe candidate acceptance sequence is:

1. Record the currently deployed staging version. Deploy only the auth Worker
   candidate to staging with all billing flags still false; no migration is
   needed for this pairing change.
2. Read health, disabled billing catalog and legal pages. Confirm missing-token
   pair status and memory/wish list requests are rejected and contain no user
   information. These probes alone cannot validate authenticated pairing.
3. With designated synthetic staging accounts and explicitly authorized email
   recipients, run OTP login, profile, create invite, preview, request, creator
   confirmation and both status reads. Both accounts must see the same pair and
   the other partner. Replay identical command IDs to verify safe retries.
4. Create and approve one synthetic calendar date, upload one nonpersonal test
   photo through the isolated memory Worker and read it as the other partner.
   Then unlink; both services must deny old-pair access. Delete those test
   accounts using fresh sessions and verify their sessions are revoked.
5. Keep blocked/disabled/unverified invitation fixtures in local D1 regressions
   unless a deliberately isolated staging fixture is authorized. Do not change
   real account states to reproduce the failure.

Authenticated acceptance writes staging test data and can send login emails;
it is separate from read-only smoke checks. Phones need not be connected for the
HTTP portion, but the native two-phone acceptance remains a separate release
gate. No step in this proposed sequence has been run against staging by this
backend audit.

## Legal-page implementation cross-check

After the parent task updated `account_pages.ts` and `billing_pages.ts`, the
final candidate was verified again with Node **22.23.3**: the full auth suite
passed (**176 tests in 9 files**, 108.35 seconds), TypeScript checking passed,
and both staging and production bundling dry-runs passed. The final bundles are
under `/tmp/nandin-release-backend-20261014/final-auth-staging` and
`/tmp/nandin-release-backend-20261014/final-auth-production`. Both preserve the
three disabled billing flags. No tests mirroring the new prose were added.

The revised native terms, privacy, support and account-deletion text were checked
against the real code: photo decoding/re-encoding strips EXIF/GPS, images require
current pair authorization, unlink/account-deletion triggers remove the pair's
photo/wish metadata, and R2 deletion uses a durable retry queue. Florist distance
sorting uses bundled shop data locally; OpenStreetMap tile requests still expose
the viewed area/network IP, and directions send the destination but no explicit
origin. Retained pseudonymous account/pair/payment markers have no automatic
expiry configured. The copy appropriately avoids promising a fixed backup
retention interval or complete anonymity of those retained identifiers.

The earlier cross-review found stale web-purchase terms saying that calendar
and memories were not connected, plus a missing prominent disabled-purchase
notice in the web plan/terms copy. The parent corrected both before the final
run. The revised web terms now list the implemented free features and make
future payment terms conditional on reopening purchases; the plans page starts
with an explicit disabled-purchase notice. No remaining mismatch was found in
this scoped source/disclosure cross-check. This is a code/disclosure consistency
check, not legal advice or Store approval. No staging or production deployment
was performed during final verification, and no files outside this audit report
were edited by the final verification agent.

## Release-owner staging rollout

After the final Node 22 checks and copy review, the release owner deployed auth
to staging only: `7d0a527a-faa3-47ac-a398-f27b70c93dca`. All three billing flags
remain false. Staging reports no pending auth migrations; none were applied.
Dart public health/catalog/401 probes and six legal/support/deletion page checks
passed. Production was not redeployed. Authenticated two-account staging
acceptance remains pending; these probes do not replace it.
