# Native mobile release audit — 2026-10-14

**Result: automated Flutter checks pass and a production-configured Android debug APK builds. A signed Store release is still blocked.** This report covers the mobile client; account access, backend deployment and Store materials have separate reports.

Baseline: fetched GitHub `codex/restore-cloudflare-backend`, commit `62b5d92`, reviewed on `codex/native-release-20261014`. Existing bundle/application identity and signing settings were preserved. No replacement key, certificate or profile was generated.

## Changes made

- Added `NANDIN_ENABLE_PAID_FEATURES`, compiled **false** by default and explicitly false in `config/cloudflare.production.json`. Plus and premium-card entry points are hidden in this release candidate. Existing server entitlement checks and the session-owned unfinished-purchase listener remain in place; enabling a UI flag cannot authorize a purchase or grant Plus.
- Corrected account-deletion confirmation: unlinking also removes the pair's shared photo memories and wishes from both people's access. It asks the user to export first. The wording does not promise instantaneous deletion of underlying photo bytes; object cleanup is queued by the backend. Retained payment references are described as without name/email, rather than anonymous.
- Added a regression for photo-library permission refusal: the editor displays a recoverable error, preserves title/note, allows a later selection, and saves exactly once. This is an injected native-error boundary test, not an OS permission-dialog test.
- Added a default-off paid-route regression and deletion-disclosure assertions; retained the explicit opt-in route and billing entitlement tests.

## Automated verification

| Check | Result |
| --- | --- |
| Complete Flutter suite before changes | 472 passed, 4 existing opt-in capture tests skipped |
| Focused onboarding/account/billing/photo suite after changes | 70 passed, 1 existing opt-in capture test skipped |
| Complete Flutter suite after changes | **474 passed, 4 existing opt-in capture tests skipped, 0 failed** |
| Flutter analysis | No errors or warnings; 58 existing informational style items |
| iOS Info.plist and Runner.entitlements | `plutil -lint` passed |
| Android debug build, explicit production configuration | Passed after final client edits |
| Android release signing preflight | Correctly rejected missing upload-key inputs; no debug-signing fallback |

Reproduction from `mobile/`:

```sh
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub --target-platform android-arm64 \
  --dart-define-from-file=config/cloudflare.production.json
```

Logs and binary inspection results are saved under `../../output/release-readiness/2026-10-14/` (ignored generated evidence).

## Android artifact and permissions

- Artifact: `build/app/outputs/flutter-apk/app-debug.apk`, **debug-signed development build**, not a Play submission AAB.
- SHA-256: `a256a435942ea72dc8c164d2a6c7750da14b553e84653b440e29bb6360491241`.
- Package `mn.moch.hamtdaa`, displayed name `Нандин мөч`, version `0.1.0+1`.
- Resolved compile and target SDK **36**, minimum SDK **24**, AGP **8.11.1**, NDK **28.2.13676358**, Flutter **3.41.6**, Dart **3.11.4**, configured JDK **17**.
- Both expected public production URLs are present in the compiled kernel: `https://hamtdaa-api-production.mendmedey.workers.dev` and `https://nandin-moch-memories-production.mendmedey.workers.dev`. No iOS binary exists yet to make the equivalent assertion.
- Merged manifest requests INTERNET, optional foreground COARSE location, POST_NOTIFICATIONS and boot notification rescheduling, plus library Billing/VIBRATE/network-state permissions and the generated private receiver permission. No FINE or BACKGROUND location permission was found. Backup is disabled and cleartext traffic is disabled.
- Build requested `android-arm64`; dependency libraries also package some 32-bit/x86_64 files. This is not a claim that all ABIs were runtime-tested.

## 16 KB checks and their limits

The current [Android 16 KB guide](https://developer.android.com/guide/practices/page-sizes) was inspected on 2026-10-14. Android SDK Build-Tools 36.1.0 `zipalign -c -P 16 4` passes on the final APK. All six packaged **64-bit** ELF libraries have `PT_LOAD` alignment of at least 16,384 bytes. The ELF program headers were also independently inspected with the NDK's `llvm-objdump -p`.

The same guide additionally describes checking `(GNU_RELRO VirtAddr + MemSiz) % 0x4000`. That strict check is nonzero for these debug APK libraries:

| Library | ABI | Remainder |
| --- | --- | --- |
| libdartjni.so | arm64-v8a | 12,288 |
| libdatastore_shared_counter.so | arm64-v8a | 8,192 |
| libflutter.so | arm64-v8a | 4,096 |
| libdatastore_shared_counter.so | x86_64 | 8,192 |

This is an unresolved compatibility signal, not an observed crash. Do not treat passing ZIP/LOAD alignment alone as full 16 KB acceptance. The final **release** AAB/APKs must be inspected too (including AOT `libapp.so`, absent from a debug APK), and tested on a 16 KB emulator/device. The installed API 36.1 AVD reports a **4,096-byte** page size and contains no alternate 16 KB kernel, so it cannot close this gate.

## Signing and iOS limits

`android/app/build.gradle.kts` has a dedicated release signing configuration and a release-task preflight. At execution time all four inputs were absent: store file, store password, key alias and key password. Nothing printed secret values. Use the already-existing Play upload key after checking its certificate against Play Console; do not create a replacement identity to bypass this gate.

```sh
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./gradlew :app:checkReleaseSigning --console=plain
```

iOS source retains bundle `mn.moch.hamtdaa`, Team `9M6WPV755A`, automatic signing and minimum iOS 13.0. Photo/camera/foreground-location purpose strings and Keychain entitlements are present. The location Pod disables the Always-permission code path. Full Xcode/iOS 26+ SDK is unavailable on this Mac at audit time; only Command Line Tools are selected. No archive, device install or TestFlight validation was performed. Root certificate/profile inspection found a development identity and wildcard development profile, but no app-specific Store profile; these are not proof of distribution readiness.

## Required device acceptance, still outstanding

| Flow | Existing automated evidence | Required native evidence |
| --- | --- | --- |
| Sign in → invite → preview → request → explicit confirmation | Cloudflare HTTP-adapter two-account and pairing lifecycle tests | One iPhone and one Android with distinct designated accounts, same production candidate |
| Calendar/photo change visible to partner | Repository/controller/widget tests, photo normalization and stale-pair rejection | Both phones observe real server data and private image delivery |
| Relaunch and sign out/relogin | Session-storage/account-boundary tests | Keychain/Keystore persistence and credential removal on both devices |
| Offline and reconnect | Transport failures and identical retry-command tests | Airplane mode during reads, pairing and photo save; no duplicate writes on retry |
| Deny location/photo access | Location denial/manual-map tests; photo refusal recovery regression | Actual Android/iOS permission prompts, limited photo selection, return from Settings |
| Unlink/account deletion | Confirmation, fresh-login checks, stale-response and invalidation tests | Both phones lose prior shared access; saved photos handled as disclosed; no stale notices |

No live account was created or deleted, no login email was sent, and no payment was taken by this mobile audit. Four visual capture-only tests remain intentionally opt-in; native integration tests have not been claimed as executed. Several pre-existing native integration files target the preserved legacy entry point, so those alone would not certify the current Cloudflare app.

After key/Xcode/device gates pass, create the signed AAB and iOS archive with the same production defines, record build numbers and certificate hashes, repeat final artifact/permissions/16 KB checks, and verify Store-installed test builds before review submission.

## Native startup follow-up — blocked by host capacity

A fresh startup attempt on 2026-10-14 used the installed `Medium_Phone_API_36.1` ARM64 AVD with `-read-only -no-snapshot`, port `5568`, and the final APK hash recorded above. The emulator exited before boot with `Your device does not have enough disk space to run avd`. The host data volume reported approximately **349 MiB available**. No emulator connected through ADB, so the APK was not installed or launched during this follow-up, and there is no native startup screenshot or application crash result to report. This host-capacity failure is not evidence of an app crash.

The emulator log is saved at `../../output/release-readiness/2026-10-14/android-emulator-runtime.log`; a compact result is in `android-native-startup-followup.json` beside it. No saved AVD userdata or snapshots were cleared, no SDK images or existing build artifacts were removed, and no temporary emulator remains running. The waiting ADB command from this attempt was stopped.

The only installed system image is `android-36.1/google_apis_playstore/arm64-v8a`, revision 4, with one `kernel-ranchu` and no alternate 16 KB kernel. The earlier 4,096-byte page-size observation remains the only completed native page-size measurement. [Android's documented 16 KB emulator setup](https://developer.android.com/guide/practices/page-sizes#16kb-emulator) calls for a specifically labeled 16 KB image and verification that `adb shell getconf PAGE_SIZE` returns `16384`. No additional image was downloaded and no license was accepted. Both ordinary native startup verification and the separate 16 KB runtime gate therefore remain open.
