# Нандин мөч

Flutter mobile application. The installed package stays `mn.moch.hamtdaa` so the display-name change does not change its identity.

## Run

```sh
flutter pub get
flutter run -d <device-id>
```

`lib/main.dart` starts Cloudflare mode. The default API is `https://hamtdaa-api-production.mendmedey.workers.dev`; override it with `--dart-define-from-file=config/cloudflare.production.json` or a staging configuration. No secret belongs in these JSON files.

Android requires JDK 17 and the Android SDK. On this Mac the JDK is `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`.
iOS requires the full Xcode application, an available device or simulator, and appropriate signing. Only the launcher assets and project configuration have been prepared here; iOS has not been rebuilt on this machine.

### Connect two phones

Install the same current production build on both phones. When running from Flutter, use the production configuration explicitly on each device:

```sh
flutter run -d <device-id> --dart-define-from-file=config/cloudflare.production.json
```

Sign in with a different email address on each phone. Staging and production have separate accounts, sessions and invitations: a code from one environment cannot connect to the other, and using one account on two phones does not create a couple.

1. The first person opens **Хосоор холбогдох**, creates a code and copies it to the other person. A replacement code invalidates the previous one.
2. The second person pastes the full code, checks the inviter's name, then taps **Зөвшөөрч хүсэлт илгээх**. Previewing alone does not send a request.
3. The first person reopens **Хосоор холбогдох** and approves **Танд хүсэлт ирлээ**. Both phones then show the connection; refresh is available if needed.

Invitation codes expire after 24 hours. Do not log or attach codes, session tokens or private screenshots to bug reports. Report the on-screen error and whether each build is production or staging instead.

## Recovery scope

This source was reconstructed on 2026-10-08 from saved editing records after the original `mobile/` folder was omitted from Git. Immutable recovery material is in `../recovery/2026-10-08/`.

The Cloudflare entrypoint exposes email login, mutual pairing, shared calendar/date proposals, calendar photo memories, daily questions, account controls, and subscription/card screens. The server controls paid-feature availability. Legacy local/Supabase screens are preserved in `main_supabase_legacy.dart`; their photo assets and native shortcut integration are not fully recovered and those screens are not connected to the Cloudflare home.

The debug Android build is a development build, not a Store submission or production-readiness certification. Production signing credentials and billing secrets are intentionally absent.

Launcher artwork is in `assets/branding/nandin-moch.png` and the iOS/Android icon catalogs. Nunito is distributed under the license in `assets/fonts/OFL.txt`.

## Photo calendar (2026-10-08)

From **Бид хоёр → Хуанли**, choose a day and tap the photo-add button or **Энэ өдрийг хадгалъя**. Select a photo, enter a title/note, and choose a rounded or polaroid sticker. Days with memories show a thumbnail; the selected day's list opens full photos. The **Зураг** switch hides photos and **Өнөөдөр** returns to today. Changes refresh for the connected partner while the page is open (approximately every 20 seconds); manual refresh is also available.

Photos are private, fetched with the current session, and available only while the original pair remains active. Only the creator can delete an individual memory. Unlinking deletes the pair's photo memories; the unlink dialog explains this before confirmation. Account export includes the user's own current-pair photos, thumbnails and metadata in a ZIP. Account deletion and unlink immediately revoke access and queue object cleanup.

The native app normalizes photos and strips metadata before upload; the server validates/re-encodes JPEGs too. Storage bounds: 10 uploads per member per day, 10 memories per calendar day per pair, and 1,000 memories per pair. These are storage limits, independent of paid subscriptions.

The isolated service is in `memories_worker/`; production and staging use their own private R2 buckets and bind to the existing matching authentication service. Both are deployed. Set `CLOUDFLARE_MEMORIES_API_URL` alongside the auth URL when using a custom build configuration. Existing auth Workers were not redeployed.

Verification includes calendar add/view/toggle/delete flows, unsaved-draft protection, narrow display/enlarged text layout, stale login/pair rejection, retry idempotency, image bounds/metadata stripping, and streamed account ZIP export. Automated calendar screenshots use synthetic test images, not live user data. A real two-phone authenticated photo-sharing session has not been exercised on this machine.

## Shared wishes — first feature in the next sequence (2026-10-08)

**Бид хоёр → Хүслүүд** opens the new shared board. Add a wish or adapt one of twelve original Mongolian date ideas, choose a category/budget, and optionally enter a location and note. Adding a wish selects your own heart; your partner chooses theirs separately. Both hearts unlock scheduling. A planned wish creates one pending calendar invitation; the other person still approves its date and time. An accepted event whose start time has arrived can be marked fulfilled, then opened in the photo-memory editor on that day. Filters show shared choices, planned wishes and fulfilled wishes.

Retries preserve the exact original command, preventing duplicate wishes or dates after a lost response. Account/pair changes clear shared records and editors. Backgrounding hides shared data while preserving an unsaved local draft. Deleting a wish is creator-only and leaves an existing calendar event intact; deleting a calendar event makes a planned wish available again. Unlinking removes the pair's wishes. Account ZIP export includes own-authored wishes and own likes in `wishlist.json`.

The backend is an additive `0002_wishes.sql` migration and `/v1/wishes/*` routes in the existing isolated `memories_worker`. **Staging and production deployment completed on 2026-10-08.** Migration `0002_wishes.sql` is applied to both databases. Production Worker version is `038b45ef-6f8c-40ef-a552-b4f17e744625`; staging is `10a41ced-9bb6-434b-885e-ff42b66904e1`. Both passed health, unauthorized-request, and foreign-key checks. All 32 local backend tests passed. See `memories_worker/README.md` for release evidence. An authenticated flow on two real phones remains unverified; unauthenticated health checks do not establish end-to-end sharing.

Next feature sequence: (1) shared wishes and mutual date choice (implemented and deployed; paired-device validation pending); (2) future-opening letters; (3) memory reactions, partner notes and monthly album; (4) shared flower garden and home-screen widget. Later features are planned, not yet implemented.

## Release gate

The current production-readiness findings are in `docs/production-readiness.md`. Android release builds require the existing upload key and refuse debug signing. The recovered `cloudflare/` authentication source is reproducible; read its recovery and staging-acceptance notes before deployment. The 2026-10-12 full Flutter audit, current-app Android debug build and both backend checks passed in [GitHub Actions run 38229271500](https://github.com/Buynaa-code/bolzoo/actions/runs/38229271500). GitHub Actions checks the current and restored scopes separately and never deploys. Real two-phone acceptance, signed Store builds and billing verification remain release gates.
