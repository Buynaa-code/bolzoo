# Production readiness — updated 2026-10-12

**Status: not ready for unrestricted public or paid launch.** The current Cloudflare app has working local checks and live photo/wish services, but this is not an App Store/Google Play release certification. Do not enable paid plans or submit the restored legacy UI based solely on a debug build.

## Backend recovery completed on 2026-10-12

- Restored the missing Cloudflare auth build/configuration/types and complete historical migration definitions. All ten application modules match the preserved deployed logic; the four billing modules emit identical module bytes. No authentication Worker was deployed and no live migration, email or payment was performed.
- Read-only schema comparisons confirmed staging/production equality. Empty local databases reproduce all 57 auth objects and all 91 application objects after the separate memories/wishes migrations, including keys, indexes and triggers. Three offline schema tests pass.
- Reconstructed the missing dependency lock from recorded versions/overrides, then installed from scratch. `npm ls --all` and TypeScript pass. The original historical lock remains unavailable; whole-bundle byte equality is not claimed.
- Final combined backend suite on Node **22.23.3**: **171 tests passed in 9 files**, with no skipped tests. Staging and production build dry runs pass. These are local checks, not real-device or store payment acceptance.
- Added an auth CI job enforcing dependency resolution, generated types, schema parity, every backend test and both dry runs. CI uses no deployment credentials; its GitHub execution remains unverified.
- See [`../cloudflare/README.md`](../cloudflare/README.md) and the schema recovery evidence for reproducible commands and limits. Changes are local; billing remains disabled.

## Completed in the 2026-10-08 audit

- Applied the additive wish migration and deployed the isolated memories/wishes Worker to staging and production. Production version: `038b45ef-6f8c-40ef-a552-b4f17e744625`. Both environments return healthy responses, reject missing/invalid credentials, and have clean foreign keys. Production's photo deletion queue was empty at inspection. No live account, email, photo, or payment was created by this audit.
- Fixed authentication service-binding client-IP forwarding, preventing photo/wish users from sharing the same fallback auth rate-limit bucket. All 32 backend tests and type checks pass. Authentication Worker was not redeployed.
- Removed Android debug signing from release builds. Missing real upload credentials now stop the build. Existing app identity stays `mn.moch.hamtdaa`; no signing identity was generated.
- Disabled Android automatic backup and explicitly excluded private app storage from cloud backup and device transfer. Added scheduled-notification receivers and reboot permission; blocked cleartext traffic. The current Cloudflare calendar still needs scheduler integration before notifications can be advertised.
- Linked the existing iOS Keychain entitlement file to all three Runner configurations. Plist validation passed; an actual iOS archive/device remains untested.
- Fixed reachable OTP resend cooldown, email-change challenge reset, stale response handling, and duplicate callback delivery. Eight authentication widget regressions pass alongside 17 Cloudflare onboarding tests.
- Corrected the Plus free-feature description to match reachable features; account export copy now includes own wishes/likes.
- Stabilized the account-export widget test by waiting for both filesystem cleanup and the UI busy state. Its prior timeout was a test-clock/file-I/O race; no export assertion was removed.
- Narrowed the root Git ignore rule from `data` to `/data/`; it was accidentally excluding `mobile/lib/data` and `mobile/test/data` source. Private recovery files, captures, secrets and generated output stay ignored.
- Added pinned CI toolchains/actions with independent current-app checks, full restored-suite audit, and worker checks. Full-suite failures remain visible. CI never deploys or uploads private captures. GitHub execution is still unverified.

## Final local validation for the current app

- Current Cloudflare/shared-auth/billing/calendar/photo/wish/account-export suite: **207 passed, 4 opt-in capture tests skipped**.
- Scoped current-app analysis: **0 errors, 0 warnings, 46 style information messages**. This is not the full restored repository analysis.
- Final Android debug APK build: passed. Merged manifest confirms backup exclusions, cleartext blocking and non-exported notification receivers. No phone is currently connected; no new device installation occurred.
- Worker: **32 tests passed**, type checking and staging/production dry runs passed.
- iOS property lists/project configuration: valid; full Xcode/signing/device validation pending.
- The complete restored suite remains failing. The original log and classified failures are retained; the two reachable shared-auth failures were repaired and retested. A current-flow account-export test-clock race was also fixed without weakening assertions.

## Release gates, in order

| Priority | Gate | Evidence / required result |
| --- | --- | --- |
| 1 — local recovery passed; release acceptance pending | Reproducible authentication backend | Missing source/build inputs and schema drift are repaired; 171 backend tests, three schema checks, type checking and both build dry runs pass. The original historical dependency lock is unavailable. Validate a rebuilt candidate in staging before any subsequent production auth release; do not reapply already-recorded historical migrations. See `cloudflare/README.md`. |
| 2 — blocker | Finish the restored application/test boundary | The complete restored Flutter test run reached 305 passes, 4 skips and 40 failure entries before it was stopped on a stalled legacy places test. The failures include missing legacy APIs/assets and UI regressions; see `restored-test-audit.md`. Two shared authentication failures are now fixed; 38 recorded legacy/recovery failures remain unresolved. Repair or explicitly archive unsupported legacy screens/tests with a product scope decision; never silently suppress them to claim all features work. |
| 3 — blocker | Signed native builds and store identity | Configure the existing Google Play upload key, complete Android licenses, install/select full Xcode, and use the existing Apple team/profile. Produce and validate an AAB and iOS archive. See `native-release-readiness.md`. |
| 4 — blocker | Authenticated two-phone acceptance test | Test both real accounts through signup, consent-based pairing, date approval, wishes, photo sharing, relaunch/offline/reconnect, export, unlink, account deletion and lost access after unlink. Neither unit tests nor public health checks prove this. Use designated test accounts and synthetic photos. |
| 5 — paid-launch blocker | Store payment setup and proof | Live native and web billing are disabled. Verify products, pricing, keys, ownership, purchase/restore, renewal, cancellation, expiry, refund and provider downtime. Preserve the agreed 9,900₮ monthly / 79,900₮ yearly per-pair offer; native displayed prices come from the store. Do not take a real payment just to test. |
| 6 — paid-launch blocker | Apple review/sandbox routing | Deployed verification accepts Production transactions only. Apple reviews IAP in sandbox and TestFlight uses sandbox. Design and test a secure, server-verified sandbox/review path without granting real paid entitlements from fabricated client environment flags. A staging-only purchase test does not prove the submitted production build works. |
| 7 — release requirement | Privacy and account-deletion disclosures | Update live policy/deletion pages to describe private photo storage, wishes, unlink loss, retention/cleanup and exports. Existing operator is `moch`, support is `gbuyandelger277@gmail.com`. Match App Store privacy and Play Data Safety answers to actual data use. Ship these as a separately tested change after backend recovery acceptance. |
| 8 — operational requirement | Capacity, alerts and recovery | Live auth limits all OTP sends to 100/day. Review sender capacity/abuse controls before increasing it. Verify dependency health, auth failures and deletion backlog alerts (alert API audit was denied by available scopes, not evidence that alerts are absent). D1 Time Travel responds, but a restore/photo-recovery drill remains unverified. |

## Current product boundary

The shipped entry point is `lib/main.dart` → `main_cloudflare.dart`: email login, profile/pairing, shared calendar/date proposals, daily questions, photo memories, wishes, account controls, and conditional Plus/cards.

The earlier reference UI's flower/gift/invitation, map, ideas, home-icon and notification screens remain in the disconnected legacy entry point and are not complete current-app features. Avoid screenshots or Store copy promising those until connected and tested. The current calendar also does not call the legacy reminder scheduler; native receiver setup alone is insufficient.

## Payment and native source references

- [Apple: configure in-app purchases for App Review](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases/).
- [Apple: testing with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).
- [Android: application backup and device transfer](https://developer.android.com/identity/data/autobackup).
- [Flutter: signing Android apps](https://docs.flutter.dev/deployment/android#sign-the-app).

A full restored-suite result and current-app result are deliberately separate. Keep release approvals tied to signed build identifiers and recorded device/store outcomes, not to this checklist alone.
