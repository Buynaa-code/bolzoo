# Signed-candidate acceptance record

Status: **NOT RUN on physical devices in this release-preparation session.** Use only disposable test accounts and synthetic photos. Set each result to PASS/FAIL with evidence after execution; blank/pending is not a pass. Destructive tests apply only to the designated test pair and test accounts.

## Candidate identity (fill from verified artifacts)

| Evidence | Value |
| --- | --- |
| Git commit / clean tree | Pending |
| Android AAB/APK SHA-256, versionCode/versionName, signing-certificate fingerprint | Pending |
| iOS archive/build ID, bundle version, Team/profile, SDK | Pending |
| Phone A model/OS/install source | Pending — iPhone |
| Phone B model/OS/install source | Pending — Android |
| Auth backend / memory backend | Pending — verify both production origins in artifacts/network trace |
| Test accounts A/B | Record privately; two distinct email identities |
| Date/time, tester and evidence directory | Pending |
| Existing app upgrade/reinstall path | Pending |

Production origins are `https://hamtdaa-api-production.mendmedey.workers.dev` and `https://nandin-moch-memories-production.mendmedey.workers.dev`. Verify the final artifacts, not just build command arguments. Do not use one staging and one production build for a pairing acceptance run.

## End-to-end matrix

| # | Action on the signed candidate | Expected result | Result/evidence |
| --- | --- | --- | --- |
| 1 | Fresh install; inspect icon/name; launch with and without network | Correct branding; usable loading/retry; no credentials or stale account shown | Pending |
| 2 | Login A and B via separate emails; test bad/expired code and resend | Correct rejection/cooldown; newest challenge; no duplicate navigation | Pending |
| 3 | Relaunch each app and lock/unlock phone | Session survives as intended; no cross-account cached content | Pending |
| 4 | A generates code, backgrounds, B previews and requests, A resumes and confirms | Code persists; both see correct partner after two consents | Pending |
| 5 | Enter own code, invalid/expired/revoked code; duplicate request/confirm | Clear failure or safe idempotent result, never an unintended pair | Pending |
| 6 | A creates date; B accepts; edit to future time | Both see synchronized state; ownership/version checks preserved | Pending |
| 7 | Disconnect after submitting date, reconnect and retry | One date only; uncertain result reconciles; no false 'saved' message | Pending |
| 8 | Select test photo; cancel picker; deny/limit library permission; deny camera | Graceful return/error and valid alternative, no crash or empty upload | Pending |
| 9 | Upload memory on A; B opens sticker/detail; relaunch | Correct date, photo and text on both; no public image URL requirement | Pending |
| 10 | Large/unsupported/corrupt photo, upload offline/interrupted | Bounded processing, readable error/retry; no half-created visible memory | Pending |
| 11 | Only A answers daily question, then B answers | Hidden until both; both answers after success; double submit safe | Pending |
| 12 | Create wish, both like, propose/approve date, mark completed | Both views agree; no duplicate event; access scoped to pair | Pending |
| 13 | Open florist map, choose manual point, then allow/deny location; location services off | Manual path works; clear permission/error; no background tracking | Pending |
| 14 | Map offline/tile unavailable; select flower marker and external directions | Readable fallback/list; correct chosen destination; no silent navigation | Pending |
| 15 | Enable/deny reminders separately; schedule date; background/terminate/reboot | Valid local reminders within disclosed limits; generic lock-screen content; no crash on denial | Pending |
| 16 | Change/cancel date on B; reopen A; disable reminders/sign out | A reconciles when open; obsolete local notices canceled | Pending |
| 17 | Export data, cancel share, share/save ZIP and inspect contents privately | Correct current identity, authorized data and own media/wishes; temporary app files cleaned | Pending |
| 18 | Change account during slow load/export, then relaunch | No previous user's content/token/ZIP handed to new user | Pending |
| 19 | Unlink designated pair after exporting; B open/background/offline then reconnect | Sharing revoked; pair photos/wishes removed; no stale content remains after acknowledged unlink; notices canceled | Pending |
| 20 | A and B connect again with a new invitation; try former photo IDs | New pair starts isolated; old private photo access denied | Pending |
| 21 | Freshly reauthenticate disposable A, enter УСТГАХ and delete | All A sessions revoked; B pair state updates; correct shared-data loss and server cleanup queued | Pending |
| 22 | Attempt stale-token reads/export/photo after deletion | Unauthorized/not found, no confidential response; pending photo cleanup monitored separately | Pending |
| 23 | With an expendable account, open web deletion without app installed and complete OTP deletion | Public page, accurate consequences, session revocation; no need to email support to finish | Pending |
| 24 | Navigate all free screens and attempt paid entry/deep links | No unfinished purchasing/checkout; production billing disabled | Pending |
| 25 | Small screen, large text, keyboard, landscape/back gestures, iPad if supported | No blocked actions/overflow; labels and controls usable | Pending |

Record network failures without saving authorization headers, OTPs, photo bodies or customer identifiers. For cleanup verification, record counts/status and test resource IDs privately; do not put secrets in the release report. Unit tests and fixture captures supplement this matrix; they do not complete it.

## Submission decision

- Submit a candidate for review only when relevant gates pass and stable reviewer access, accurate metadata/privacy, signed artifacts and account permissions exist.
- If signing or account access is missing, there is no uploadable test release yet; a debug build is not a submitted test version.
- If Google production access/required closed testing is missing but a signed artifact and test access are available, restrict to the permitted test track.
- If any privacy isolation, pairing, account deletion or data-loss defect remains, block public release and record the failed case.
- Approval and public availability are separate from upload; record the store's actual status and submission ID, never infer success from a build.
