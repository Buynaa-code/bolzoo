# Native release decision — 2026-10-14

**Decision: hold Store review and public release.** Local preparation is complete
for the changes below, but account access, signing, authenticated staging
acceptance, native device acceptance and final Store artifacts are not complete.
An Android debug APK is not a Play internal-test upload or a signed release AAB.
No App Store / Play review submission has been made.

## Source and changes

- Fetched GitHub on October 14. The latest Flutter branch was
  `origin/codex/restore-cloudflare-backend` at `62b5d92`; local tracked source
  matched it (0 commits ahead / 0 behind). `origin/main` is the older web project,
  so it was not substituted for the native app. Work is consolidated on
  `codex/native-release-20261014`.
- No pre-existing tracked code modifications needed merging. Existing untracked
  branding/output files were preserved and were not blindly staged.
- Fixed a reproduced stuck-invite case: an old pending invitation hidden because
  its creator is disabled, unverified or has blocked the requester no longer
  prevents a new valid request. Five regressions preserve mutual consent and
  transaction-race behavior. This does not prove it caused the earlier reported
  iPhone/Android failure.
- Disabled unfinished Plus/card entry points by default and explicitly in the
  production build defines. Server purchase flags remain disabled.
- Corrected account-deletion consequences and public-page source for the current
  photos, wishes, local reminders, florist map, data retention and app name.
- CI Android builds now use the explicit production configuration.
- The first GitHub run passed both backend jobs and the current app/Android build,
  but exposed a timing-dependent account-deletion test in the full Flutter suite.
  The test assumed filesystem cleanup completed within 30 ms; it now waits for
  the repository call and drains both concurrent retries before temporary-file
  teardown. The targeted four-test file passes locally. This is a test-only
  synchronization fix, not a newly observed production deletion failure.
  [Release branch CI runs](https://github.com/Buynaa-code/bolzoo/actions/workflows/mobile-checks.yml?query=branch%3Acodex%2Fnative-release-20261014)
  retain the first failure and subsequent verification results.

The verification rerun for code/test commit `8f39c0a` completed successfully:
[GitHub Actions run 38508662776](https://github.com/Buynaa-code/bolzoo/actions/runs/38508662776).
All four jobs passed: the full Flutter audit, current app flows plus the
production-configured Android debug build, auth/pairing/account/billing checks,
and memories/wishes checks. This does not satisfy the device/signing/Store gates
below. Subsequent report-only edits do not change the verified app or backend.

## Verified locally

| Gate | Evidence |
| --- | --- |
| Flutter analysis | No errors/warnings; 58 existing information-level items |
| Complete final Flutter tests | 474 passed, 4 opt-in screenshot capture tests skipped |
| Auth/pairing backend | 176 passed on Node 22.23.3; TypeScript and 3 schema checks passed |
| Memories/wishes backend | 32 passed on Node 22.23.3; TypeScript passed |
| Worker bundles | Both staging and production dry-runs passed for each backend |
| Android development artifact | Production-configured debug APK built; API 36 / min 24 |
| Android 16 KB static checks | ZIP and all packaged ELF64 LOAD alignment pass; GNU_RELRO findings and actual 16 KB runtime acceptance remain unresolved |
| Release signing guard | Correctly stops when upload-key inputs are missing; no debug fallback |
| iOS source | Plist/entitlements syntax passes; no native archive was built |

See [mobile evidence](release-mobile-2026-10-14.md),
[backend evidence](release-backend-2026-10-14.md), and the
[Store preparation pack](../store-release/README.md).

Development APK: `../build/app/outputs/flutter-apk/app-debug.apk`.
SHA-256: `a256a435942ea72dc8c164d2a6c7750da14b553e84653b440e29bb6360491241`.
Both production service URLs were found in its compiled kernel. This says
nothing about a future iOS archive, which must be verified separately.

## Access and signing evidence

The owner reports a separate company developer account. The accessible Play
session currently opens new-account signup, not the company's Console. App Store
Connect is at login. App records, roles, contracts, production access and upload
certificate fingerprints are therefore unverified. No new developer account,
paid agreement or substitute signing identity was created.

A focused filename search found a keystore under an unrelated iCloud Flutter
project, whose Android application ID is `com.dralien.astra.sdoor`; it is not
evidence of a matching `mn.moch.hamtdaa` upload key. No Nandin key.properties,
matching upload key or repository Actions signing secrets were found. Compare
the existing key certificate against the company's Play Console before use.

Apple Team `9M6WPV755A`, a development certificate and valid wildcard development
profile are present. Other apps have Store profiles; Nandin Moch has no confirmed
app-specific Store profile or valid distribution identity. This Mac has Command
Line Tools, not full Xcode. A macOS CLT SDK version is not an iOS SDK version.
Android SDK 36 and JDK 17 are installed; some Android SDK licenses are outstanding.

The owner cannot connect phones at present. The installed Android API 36.1 AVD
reported 4 KB pages and cannot certify 16 KB behavior. A fresh startup attempt
was blocked by emulator preflight because the Mac has only about 350 MiB free;
no native startup screenshot or successful install is claimed. No unrelated
files or persisted emulator data were removed. No iPhone, Android physical
device or iPad acceptance is marked passed.

## Published service state and deployment boundary

Read-only production checks returned healthy auth/memory responses and a catalog
with Apple, Google and web purchases disabled. Production auth version observed:
`8e3a9914-08bc-486b-8016-015e0c834cd2` (October 6).
The production D1 metadata was readable. Staging reports no pending auth
migrations; no migration or customer-row mutation was performed.

The release candidate was deployed to **staging only** as version
`7d0a527a-faa3-47ac-a398-f27b70c93dca`. Staging auth/memories health, unauthenticated
pair/photo/wish rejection and disabled billing checks passed using Dart
HttpClient, the same native network stack used by the app. All six staging legal/
support/deletion/plan URLs returned HTTP 200 and the corrected copy. Equivalent
Dart public probes against production also passed. No OTP was sent and no live
account was created or deleted.

The rebuilt auth source and new policy text must still pass authenticated staging
acceptance before production deployment. Public health/401 checks do not prove
OTP delivery, mutual consent or two-device synchronization. Production policy
content still needs verification after the eventual production rollout.

## Remaining release gates

1. Sign into the company Play Console and App Store Connect; confirm app records,
   roles, registered entity, review contact and signing identities. Verify whether
   the Play testing rule applies to this actual account.
2. Configure the matching upload key locally without committing it. Free sufficient
   disk space before native tooling and emulator work. Install full
   Xcode with iOS 26+ SDK and establish this app's distribution provisioning.
3. Use designated disposable accounts for authenticated staging acceptance, then
   the exact candidate on iPhone + Android: sign in, pair, synchronize photo/date,
   restart/relogin, offline retries, denied permissions, unlink and deletion.
4. Resolve release-binary 16 KB checks and run a 16 KB Android emulator/device.
5. Supply persistent reviewer access, verify public legal text and operational
   retention, complete privacy/content forms and capture the final real UI in
   accepted Store screenshot sizes. Current marketing concepts are not screenshots.
6. Build signed AAB and iOS archive with the same production URLs and billing off;
   verify Store-installed internal/TestFlight builds before requesting review.

The earliest allowed destination while gates remain is a properly signed test
track, not production. Neither test-track upload nor TestFlight is currently
possible with the missing signing/account/Xcode prerequisites. October 15 is a
planning date, not a promised publication date.

Official requirements checked October 14:
[Google personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-en),
[Google target API](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-EN),
[Android 16 KB](https://developer.android.com/guide/practices/page-sizes),
[Apple SDK requirement](https://developer.apple.com/news/?id=ueeok6yw).
The 12-testers/14-days rule concerns qualifying new personal Play accounts; an
unverified company-account statement alone cannot establish this Console's state.
