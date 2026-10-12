# Native release readiness

Checked 2026-10-08. These are local build and source findings, not confirmation that either store has approved this app.

## Android signing

Release builds now use a dedicated signing configuration. They cannot silently fall back to the debug key. Every app release task depends on `checkReleaseSigning`; debug builds and IDE configuration do not need release credentials.

Use the existing Google Play upload key for `mn.moch.hamtdaa`. Copy `android/key.properties.example` to ignored `android/key.properties` and fill in the four values locally. Relative keystore paths resolve from `mobile/android/`. Do not create a replacement key until the existing Play App Signing identity and upload certificate have been checked in Play Console. [Flutter signing guide](https://docs.flutter.dev/deployment/android#sign-the-app) and [Android signing guide](https://developer.android.com/studio/publish/app-signing).

CI can supply the same inputs through environment variables, which override the file:

| Local property | Environment variable |
| --- | --- |
| `storeFile` | `HAMTDAA_ANDROID_STORE_FILE` |
| `storePassword` | `HAMTDAA_ANDROID_STORE_PASSWORD` |
| `keyAlias` | `HAMTDAA_ANDROID_KEY_ALIAS` |
| `keyPassword` | `HAMTDAA_ANDROID_KEY_PASSWORD` |

Keep credentials in the CI secret store, keep keystores outside source control, and do not pass passwords in command-line arguments. The preflight reports missing input names without printing their values. A successful preflight confirms inputs exist; the signing task still validates the actual keystore and passwords.

Local checks, using the JDK configured in Flutter:

```sh
cd android
./gradlew :app:checkReleaseSigning --console=plain
./gradlew :app:assembleDebug --dry-run --console=plain
```

On this Mac, Flutter's configured JDK is `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`; the shell's default `java` is unavailable. Set `JAVA_HOME` to that JDK when calling Gradle directly.

The release preflight correctly rejects the currently absent signing inputs. The debug task graph configures successfully without them. A signed release artifact has not been created because the existing upload key is not configured. Once credentials and Android licenses are ready, build the AAB with the project's production defines and verify its certificate against the Play upload certificate before uploading to an internal test track.

## Android manifest and SDK checks

- `INTERNET` and `POST_NOTIFICATIONS` are present in the main manifest, so internet access is available outside debug builds.
- Flutter 3.41.6 currently resolves `compileSdk=36`, `targetSdk=36`, and `minSdk=24`. The target meets Google's API 36 requirement for new phone app submissions and updates from August 31, 2026. [Google Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en).
- The source declares no broad media, microphone, or location permission. Existing merged debug output includes Billing, vibration, and network-state permissions from dependencies. Inspect the final release merged manifest as part of the AAB review.
- The main manifest explicitly sets `usesCleartextTraffic=false`; no cleartext-network exceptions were added. [Android network security configuration](https://developer.android.com/privacy-and-security/security-config).
- The manifest now disables automatic backup and references explicit full-backup and Android 12+ cloud/device-transfer exclusions for private app files, preferences, databases, and external app storage. This avoids restoring encrypted sessions without their device keys. A new phone signs in and fetches current server data. Verify backup/transfer behavior on the release build. [Android backup documentation](https://developer.android.com/identity/data/autobackup).
- The existing reminder implementation uses `inexactAllowWhileIdle`. The manifest now registers the plugin's non-exported `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`, and `RECEIVE_BOOT_COMPLETED` permission. As of 2026-10-12 the current Cloudflare calendar is wired to an opt-in, account-scoped local scheduler and widget/native-plugin-boundary tests pass. This has not yet been verified on a physical device; remote changes reconcile only while the app is open. Exact-alarm permission is not needed for this mode. Verify scheduling after process exit and device reboot with notification permission granted and denied. The dependency's version-specific instructions are in `flutter_local_notifications` 22.3.1, `README.md`, “AndroidManifest.xml setup”.

## iOS findings and remaining validation

The project retains bundle ID `mn.moch.hamtdaa`, existing team `9M6WPV755A`, and iOS deployment target 13.0. Camera and photo-library purpose strings are present in Mongolian. `Info.plist` and `Runner.entitlements` pass `plutil -lint`. No App Transport Security exception was found.

Full Xcode is not installed/configured on this Mac: `xcode-select` points to Command Line Tools and `flutter doctor` reports an incomplete Xcode installation. Install the full Xcode app, select it, complete first launch, and use the existing Apple Developer team/profile. No signing key, team, bundle ID, or version was changed. [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios).

`Runner.entitlements`, with the empty Keychain access-groups array prescribed by the installed secure-storage plugin, is now linked through `CODE_SIGN_ENTITLEMENTS` in Runner Debug, Release, and Profile. Bundle identity and group contents are unchanged. Plist validation and structured build-configuration assertions passed; this does not demonstrate that login was previously broken or confirm device behavior. A physical-device test must confirm login persistence after relaunch and credential removal on logout/account deletion. The Cloudflare session uses `unlocked_this_device` accessibility.

There is no app-owned `PrivacyInfo.xcprivacy`. The installed Flutter engine and relevant plugins already contain manifests, including Flutter file-timestamp/system-boot-time reasons and the preferences/notification plugins' UserDefaults reasons. Custom Runner Swift code only registers plugins. Do not add a blanket “no data collected” declaration: the app handles account and relationship data. Once Xcode is available, archive the app, generate its privacy report, and verify all dependency manifests are bundled, required-reason API declarations match the actual binary, and App Store privacy answers match the production services. [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [Apple third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).

A signed archive, App Store validation, Play internal-track install, and real-device purchase/restore, photo, notification, export, logout, unlink, and account-deletion checks remain release gates. Store account access and certificates were not inspected during this audit.
