# Restored Flutter test audit — 2026-10-08

This classifies `verification/production-audit-tests.log`. The original inspection stopped at **01:49 +305 ~4 -40** while the legacy map test was stalled. The parent task subsequently interrupted the full suite after more than seven minutes. Its final log says **07:57 +305 ~4 -41**, including the map test marked “did not complete” and shutdown errors. This is an interrupted failing run, not a normally completed or passing full-suite result. The separately authorized authentication repair and focused rerun are recorded below.

## Result

- **305 passed, 4 skipped, 40 original failure entries across 18 files**, plus **1 interruption-related incomplete test** in the final log (41 failure entries total).
- **7 failure entries are test-file compilation/load failures**; they do not represent seven executed test cases.
- **2 failures exercise the shared AuthScreen used by the current Cloudflare entrypoint.** One exposes missing resend/email-change UX. The other exposes a duplicate optional callback that the current Cloudflare root does not supply.
- **38 original failure entries belong to legacy flows or legacy test infrastructure:** 30 executed legacy behavior/UI failures, 7 legacy compilation failures, and 1 missing legacy golden image. The additional interrupted map test is also legacy.
- No `[E]` entries occur under `test/cloudflare/`, `test/together/`, `test/memories/`, or `test/wishes/`, or for `test/account/cloudflare_account_export_test.dart`, in this snapshot. This does **not** establish a fully passing current-app suite: execution is incomplete and the concurrent reporter does not identify every successful test. No `test/billing/` test path is visibly reported in this log.

Reachability is based on `lib/main.dart` delegating to `lib/main_cloudflare.dart`. The latter opens PairScreen, TogetherScreen, SubscriptionScreen, PremiumCardsScreen, and CloudflareAccountScreen, with AuthScreen for signed-out users. The older five-tab AppShell, AppController screens, Supabase adapters, CloudAuthGate, and SessionCoordinator are not instantiated by that entrypoint. TogetherScreen uses its own calendar/daily-question flow and `lib/memories/` / `lib/wishes/`, rather than `lib/features/calendar/` / `lib/features/memories/`.

## Current shared authentication widget

`test/auth/auth_screen_test.dart` is not safely classifiable as legacy merely because it lives under `test/auth/`.

| Recorded failing test | Evidence and effect | Action needed |
| --- | --- | --- |
| `email OTP screen moves from request to verify` | Test line 67 expects one `onSignedIn` callback but receives two. `AuthScreen` invokes it from its repository session listener (`lib/features/auth/auth_screen.dart:119-120`) and after `verifyEmailCode` (`:139-145`). The current Cloudflare root creates `AuthScreen(repository: ...)` without that callback (`lib/main_cloudflare.dart:226`), so the duplicate callback itself does not duplicate the current root's navigation. | Make shared callback delivery single-shot and retain this regression test. Do not report this as a demonstrated duplicate-login incident in production. |
| `resend is disabled for 60 seconds and email change clears code` | Test line 80 cannot find the cooldown button. Current screen has no cooldown state; its resend button is enabled whenever `_busy` is false (`auth_screen.dart:243-247`). Email remains editable without resetting `_codeSent` / `_code` (`:200-210`), and there is no explicit email-change action. This affects the reachable Cloudflare sign-in screen. | Restore resend cooldown and clear/reset code state when changing email. Server rate limiting is a separate safeguard and does not provide the missing client UX. |

The third test in that file, duplicate send taps and disposal handling, is observed running without a recorded failure.

## Every failing file

Counts below sum to the 40 original failures; the extra interrupted map test is described separately. “Legacy” means outside the current default Cloudflare flow; it does not mean that a failure is harmless if that legacy flow is reintroduced. Source line references in the failure analysis refer to the source at the time of the original log, before the authentication repair.

| Failing path | Entries | Classification | Observed root cause / actionable repair |
| --- | ---: | --- | --- |
| `test/app_flow_test.dart` | 4 | Legacy AppShell/UI | Gifts row overflow and missing expected heading; missing navigation back button when opening linked memories; missing updated profile greeting; 45px overflow at large text. Recover the matching legacy screens/controller behavior and verify narrow layouts before enabling AppShell. |
| `test/home_icon_test.dart` | 1 | Legacy profile route | `openHomeIconScreen` cannot be found/revealed from recovered ProfileScreen (test line 357). Restore the intended profile destination if this feature is retained. |
| `test/auth/cloud_auth_gate_test.dart` | 1 load | Legacy gate API recovery mismatch | Missing constructor parameters `storeFactory`, `accountInitializer`, and `session`. Recover the corresponding CloudAuthGate/AppShell versions before evaluating behavior. This is not CloudflareOnboardingApp. |
| `test/auth/app_environment_test.dart` | 1 load | Legacy bootstrap/API mismatch | Tests expect `AppBootstrap`/`AppShell` exported from `main.dart`, plus `AppEnvironment.isAbsent` and `validationError`. Current `main.dart` is the Cloudflare entrypoint; recovered Supabase environment lacks these members. Reconcile the legacy test target and implementation deliberately. |
| `test/auth/session_coordinator_test.dart` | 3 | Legacy session coordinator + test timing | Sign-out reaches `next.userId!` with a null user (`session_coordinator.dart:39`), and two tests inspect state immediately after an asynchronous broadcast event, receiving signed-out state. Repair signed-out transitions and review asynchronous test expectations. Current Cloudflare repository owns its own credential scopes. |
| `test/auth/secure_auth_storage_test.dart` | 1 load | Legacy Supabase storage test dependency mismatch | Test fake overrides use `IOSOptions?`/`MacOsOptions?`; installed FlutterSecureStorage methods require `AppleOptions?`. Reconcile fake signatures with the pinned dependency. Current Cloudflare secure session storage has a separate test file. |
| `test/auth/auth_screen_test.dart` | 2 | Shared current widget | Duplicate optional callback and absent resend/email-change behavior; detailed above. |
| `test/auth/supabase_auth_repository_test.dart` | 1 | Legacy Supabase auth | SDK refresh emits extra account-lifetime events; one expected event becomes multiple. Restore lifetime handling before any Supabase path is used. |
| `test/auth/pinned_request_identity_test.dart` | 7 | Legacy Supabase identity boundaries | Four operations use the new account's Authorization after a switch; old same-account login adapter remains usable; content refresh proceeds under a changed session; valid same-login refresh is rejected. These are substantive legacy security regressions. Restore request/session pinning rather than weakening assertions. They exercise SupabaseContentRepository/SupabasePairRepository, not the Cloudflare adapters. |
| `test/calendar_proposal_test.dart` | 2 | Legacy calendar | Expected proposal UI cannot be found/scrolled into view (`_open`, test line 87) for readable and missing-time cases. Recover proposal detail/confirmation UI. Current TogetherScreen is a different implementation. |
| `test/calendar_reference_flow_test.dart` | 3 | Legacy calendar/content | Missing actual ownership/filter count; missing shared event editor control; partner sees an edit action that should be absent. Restore intended owner/partner visibility and consent behavior before exposing legacy calendar. |
| `test/gift_export_test.dart` | 1 load | Legacy gift export API mismatch | `documentsDirectory` parameter is absent from recovered exporter. Reconcile implementation with the intended export boundary. |
| `test/privacy_flow_test.dart` | 1 load | Legacy profile API mismatch | Recovered ProfileScreen lacks expected `session` parameter. Current account screen is CloudflareAccountScreen. |
| `test/gift_design_capture_test.dart` | 1 | Missing legacy golden baseline | `../../output/mobile-ui-check/home.png` does not exist. This is a missing comparison artifact, not evidence of a rendered pixel mismatch. Restore a reviewed baseline; do not blindly regenerate it to make the test green. |
| `test/account/account_boundary_regression_test.dart` | 1 load | Legacy Supabase account test API mismatch | `SupabaseAuthRepository.withAuthClient` is absent. No behavioral assertions from this file execute. Restore the intended injection boundary before interpreting these account tests. |
| `test/reminders_test.dart` | 1 load | Legacy reminders API mismatch | `Reminders.withPlugin` is absent. Recover the plugin-injection constructor/implementation before running reminder boundary tests. Current Cloudflare screens do not use this reminders service. |
| `test/memories_places_flow_test.dart` | 5 | Legacy memory/place UI | Missing month filter/control; missing paired-coordinate validation UI; missing place detail/link controls; missing create-memory-from-place route; missing heart/comment/edit controls. These tests use `features/memories` and `features/places`, not the current Cloudflare photo-memory flow. See unfinished map test below. |
| `test/home_notifications_flow_test.dart` | 4 | Legacy home/notification UI | Invitation flow has a 5px bottom overflow; two tests find the notices list empty where a read notice is expected; populated large-text home overflows by 45px. Recover notice retention/read behavior and responsive legacy layouts. |

## Unfinished map test and missing assets

The last active test was `test/memories_places_flow_test.dart:179`, **“bundled map has Mongolia geometry and places remain usable at large text.”** When the parent task interrupted the stalled run, Flutter reported this as **“did not complete [E]”**, increasing the failure counter from 40 to 41. It is not an additional completed assertion failure. Shutdown also reported `Bad state: Cannot add event while adding stream`.

The test directly awaits `rootBundle.loadString('assets/maps/natural_earth_countries_110m.geojson')` at line 180. That file is absent from the recovered `assets` directory, and `pubspec.yaml:37-38` declares only `assets/branding/` as a non-font asset. `PlacesMap` also requests the same missing GeoJSON at `lib/features/places/places_map.dart:40`. The missing/unbundled asset is proven; the log does not prove that it is the sole reason the test has stopped progressing. The widget test's asynchronous asset-load boundary also warrants examination when this legacy flow is restored.

## Appropriate release interpretation

1. Preserve the full-suite failure report. Do not label the whole repository or production build “all tests passed.”
2. Fix or deliberately resolve the reachable authentication UX regression, then run the current-entrypoint tests with an explicit file list and obtain a completion summary. Include shared AuthScreen tests as well as Cloudflare, Together, current memories/wishes, billing/cards, and Cloudflare account export tests.
3. Keep legacy reconstruction and missing golden/map assets tracked separately. Their exclusion from the current route tree does not erase the failures or authorize re-enabling them.
4. Flutter widget/unit results alone do not prove deployed backend schema consistency, physical-device behavior, IAP readiness, or production end-to-end success.

## Authorized authentication follow-up

After this classification, the parent task authorized repairing only the reachable AuthScreen issues. `lib/features/auth/auth_screen.dart` now:

- Starts a 60-second resend cooldown per normalized email address and preserves it if the address is edited away and back.
- Clears code/challenge/error state when the email changes or the explicit email-change action is selected.
- Pins asynchronous send/verify results to a challenge version, so obsolete responses/errors cannot repaint or unlock a newer request.
- Delivers its optional signed-in callback only from the current verification result; the app shell continues observing repository events independently.
- Cancels its cooldown timer and invalidates pending screen work on disposal.

The original three `test/auth/auth_screen_test.dart` tests were retained; five regression cases were added for synchronous auth events, email-change/cooldown behavior, stale success, stale failure, and obsolete verification callbacks. No assertion was weakened. No repository contract was changed.

Validation completed successfully with an explicit two-file run:

```text
flutter test --no-pub --reporter expanded test/auth/auth_screen_test.dart test/cloudflare/cloudflare_onboarding_test.dart
25 passed, 0 failed
```

This is **8 AuthScreen tests + 17 Cloudflare onboarding tests**. It resolves the two shared-widget failures found above; it does not erase the original full-suite log or claim that the unrelated legacy failures are fixed. Focused static analysis reports only the pre-existing unused `_session` field in the legacy CloudAuthGate portion of `auth_screen.dart`; there are no new analyzer findings from the repair.

Files changed for this follow-up: the shared AuthScreen, its targeted test file, and this audit document. No assets or production services were changed.

The root audit subsequently made the legacy gate's rendered-controller condition explicitly require its signed-in session state. This consumes the previously unused field without suppressing analyzer warnings. It does not restore the legacy gate's missing APIs.
