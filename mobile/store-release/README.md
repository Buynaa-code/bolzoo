# Нандин мөч — Store release materials

Prepared 2026-10-14 for the Cloudflare entry point, `lib/main.dart` → `main_cloudflare.dart`. Working baseline: Git commit `62b5d92`; use the final release commit/build number in the submission record. This package prepares truthful metadata and acceptance steps. It is not evidence of store submission, review approval, native signing, or completed device testing.

## Files

- [Listing copy](listing.md): Mongolian product copy and English reviewer summary.
- [Privacy and Data Safety evidence](privacy-data-safety.md): source-backed draft answers and unresolved provider/retention questions.
- [Reviewer instructions](reviewer-instructions.md): current navigation and two-account workflow; access credentials are intentionally absent.
- [Physical-device acceptance](device-acceptance.md): run against the exact signed candidate, recording pass/fail evidence.
- [Policy copy proposal](privacy-copy-proposal.md): concrete missing disclosure paragraphs for the public legal pages. A proposal file is not a deployed policy.

## Release gates still requiring proof

1. Store account/app access and existing identity, signing certificate/profiles, legal entity and agreements.
2. Signed Android AAB; archive from full Xcode with the required SDK; actual target/API/16 KB and archive privacy-report checks.
3. Two-account, iPhone + Android acceptance and tablet layout tests where supported. The owner reported no connected phones for this session; do not replace this with unit-test claims.
4. Stable reviewer access to both accounts and a resettable sample pair. Email OTP expires in five minutes; a pasted OTP is not sufficient review access.
5. Updated, public, accurate policy/deletion/support pages, final privacy declarations and age/content questionnaires.
6. Screenshots of the final running release UI in accepted Store dimensions, with synthetic records and permission to use any photo.
7. Confirm paid features remain unavailable in both client and server; no real payment is needed for the free release.

Public developer name supplied by the owner: **moch**. Public support: **gbuyandelger277@gmail.com**. These do not establish the registered legal entity, physical address, review-contact telephone, or account role; obtain those from the store account rather than inventing them.

## Local preparation update — 2026-10-14

The owner confirmed a company developer account exists but has not signed into the relevant consoles in this session. No phones are connected. A keystore candidate was found in an iCloud project; it is not confirmed as Nandin Moch's existing Play upload key. Apple Team `9M6WPV755A` and a wildcard development profile are present, alongside Store profiles for other apps; no Nandin Moch Store distribution profile is confirmed. Full Xcode remains unavailable. These findings do not authorize substituting an unrelated app's identity or signing key.

Runtime source for the privacy, native terms, support and deletion pages has now been updated locally with the Nandin name, photos/wishes, map providers, local reminders, unlink consequences and accurate retention limitations. The source was cross-read against the data paths. **These policy edits are deployed to staging only** (version `7d0a527a-faa3-47ac-a398-f27b70c93dca`). All six staging pages returned 200 with corrected copy. Production policy pages remain unchanged until authenticated staging acceptance is completed. Operational retention decisions and final Store declarations remain outstanding.

## Asset inventory

The icon masters are `assets/app-icon-1024.png` and `assets/play-store-icon-512.png`. PNG headers confirm 1024 × 1024 and 512 × 512 respectively, both 8-bit RGB without alpha. The 1024 px file exactly matches the iOS app icon by SHA-256; both masters are included in this release pack. Verify the final build's linked icon assets before upload. Do not change the existing application ID `mn.moch.hamtdaa` just to change the display name.

The five PNGs in `../../output/app-promotion/` are actual widget captures with fixture records, not device screenshots or proof of live synchronization. Their README records provenance. At 780 × 1688, the raw aspect ratio exceeds Google Play's maximum 2:1 screenshot ratio and is not an accepted App Store device screenshot size. The inspected home PNG also has an alpha channel, which both stores prohibit for screenshots. They are reference material, not upload-ready assets. Re-capture final screens at the chosen device dimensions; do not stretch them.

The AI couple UI boards under `../../output/imagegen/nandin-couple-ui/` and their website crops depict design concepts that differ from the current app. **Do not upload them as Store screenshots.** Website marketing does not establish implementation parity.

Use calendar, photo memory, daily question and wishes as the first four screenshot subjects. Capture account/pairing or florist search fifth; show the actual app interface, with no fabricated ratings, purchases, customer data or store badges. Android listing imagery can use 1080 × 1920 layouts containing undistorted actual Android screen captures. For iOS, use the accepted sizes for the app's device families shown in App Store Connect. The project currently targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), so iPad screenshots/layout acceptance cannot be silently skipped.

Official specifications checked 2026-10-14: [Google preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en), [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). Current Apple documentation requires an iPhone Dynamic Island medium-display screenshot and an iPad 13-inch screenshot when iPad is supported; use the live console's accepted dimensions at upload.
