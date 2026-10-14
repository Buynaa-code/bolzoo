# Privacy declaration worksheet

Source audit date: 2026-10-14. Scope: current Cloudflare app and its auth/couple and memories/wishes Workers. This is an evidence-backed worksheet, not a submitted declaration. Inspect the final signed binary, all distributed versions and actual provider retention/settings before the owner certifies the forms.

Local policy sources have since been updated with this inventory and deletion semantics; those edits are deployed to staging only, not production. The old unsupported 7–30 day backup claim is removed locally, and the draft runtime policy discloses that opaque deletion/linkage/payment markers currently have no automatic expiry. This is more accurate disclosure, not resolution of the remaining retention/compliance decision.

## Verified data inventory

| Data/use | Source evidence | Collection and proposed purpose |
| --- | --- | --- |
| Email, verified account ID, optional display name | `cloudflare/src/auth.ts`; `cloudflare/migrations/0001_auth.sql`, `0002_pair.sql`; `lib/features/pair/pair_screen.dart` | Server collected, linked to account. Email/ID required for login; chosen display name optional (default Хэрэглэгч). Authentication, account management and sharing with the invited partner. |
| Session token, IP address, user agent, abuse counters | `cloudflare/src/auth.ts`; session schema; facade forwards edge IP in `cloudflare/src/index.ts` | Authentication and fraud/security. Session schema supports IP/user agent; do not claim these are never retained. Confirm deployed row population and infrastructure-log retention without exposing customer values. HMAC identifiers are pseudonymous, not automatically anonymous. |
| Pair IDs, invitation/consent states, linkage history | `cloudflare/src/pair.ts`; `0002_pair.sql` | Linked account/pair identifiers and relationship state; core app functionality, consent enforcement and security. Invite code is hashed server-side. |
| Calendar title, time, free-form place/note, creator and approval state | `cloudflare/src/together.ts`; `0004_together.sql` | Optional user content, linked to account/pair; app functionality. Does not read the phone's system calendar. |
| Daily-question answer and submission time | same files | Optional user content, linked to account/pair; functionality. Partner answer is released only after both answer; export follows that rule. |
| Memory photo/thumbnail, date, title, note, sticker | `lib/memories/memory_photo.dart`; `memories_worker/src/index.ts`; `0001_memories.sql` | Optional photos and user content, linked to account/pair; app functionality. Client and server re-encode uploaded images to discard EXIF/GPS/comments. Private R2 objects are served only after current account/pair checks. HTTPS/access control is not end-to-end encryption. |
| Wish title/note/place/category/budget, likes, planning state | `memories_worker/src/wishes.ts`; `0002_wishes.sql` | Optional user content and stored interactions, linked to account/pair; functionality. Budget is a category, not a bank/payment credential. |
| One foreground device position | `lib/florists/florist_location.dart`; `nearby_florists_screen.dart` | Optional, used in device memory to sort bundled shops. No coordinate field is sent to the application's APIs or partner. Android requests coarse location only; iOS When-In-Use accuracy depends on OS/user settings. |
| Requested map area, IP/network metadata | `nearby_florists_screen.dart` tile URL and map center; `docs/florist-map.md` | OpenStreetMap tile service receives viewed-area tile coordinates and normal request metadata. Do not answer 'no location leaves the device' merely because there is no GPS POST to the app backend. Map requests can describe a narrow area at high zoom. |
| Reminder settings and scheduled dates | `lib/together/together_reminders.dart`; `lib/notifications/reminders.dart` | Per-device opt-in and scheduling. No remote push token/provider is implemented in this flow. Generic notification content, account/pair cleanup, remote changes reconcile when app is open. |
| Account export ZIP | `lib/account/cloudflare_account_export.dart`; account screen | User-initiated share of an export assembled in temporary device storage. App cleanup does not delete a copy saved in the user's chosen destination. Shared ZIP includes current authorized information, own photo memories and own wishes/likes. |
| Billing transaction/product/entitlement data | `cloudflare/src/billing.ts`, `store_verification.ts`; billing migrations | Existing code stores purchase references when billing is used; no card numbers/bank passwords are requested. Both production billing flags are false in configuration. Determine whether earlier distributed app versions or existing users have these records before excluding purchase history from the global Play form. |
| Operational failures/logs | `cloudflare/src/index.ts` catch; both `wrangler.jsonc` observability | Auth logger disabled; app error log emits a generic failure plus random request ID. Provider logging may still store network/operational information. No app analytics/ad SDK was found in the current dependency and entry-point inspection; final archive/dependency audit remains necessary. |

## Proposed App Privacy selections

For core server data: **collected, linked to the user, App Functionality, not used for tracking**. Mark Name, Email Address and User ID; Photos or Videos (photos only here); Other User Content (dates, notes, answers, wishes). Add Product Interaction for persistently stored wish likes/planning interactions. Review Customer Support for content sent to the designated support mailbox. Add Purchases if any shipped behavior collects or restores purchase records. These are proposed classifications of the source behavior, not automatically verified console answers.

The account/pair cannot meaningfully operate without email/ID. Photo/answer/wish entry is optional but is central functionality, so optional use does not justify omitting it from Apple's privacy label. No Contacts, Audio, Health, Advertising Data or broad photo-library enumeration was found. Free-form text/photos are not analyzed to infer ethnicity, health, sexual orientation or biometric identity in this implementation.

**Resolve before final certification:** classify session IP/user-agent security data and infrastructure diagnostics according to actual storage/use. For OSM, review map-request metadata and the provider's retention and linkage: no Nandin account ID is attached, but IP and a viewed map area are not proof of anonymity. Determine appropriate Coarse/Precise Location and Other Usage Data declarations from the final network trace and provider practices; do not infer precision merely from Android's permission name. No advertising/tracking behavior was found; do not request ATT without an actual tracking use.

Apple's definitions distinguish on-device processing from collection, require disclosure of central optional features, and consider identity linkage. Use [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) and [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) for the final field definitions.

## Proposed Play Data Safety selections

| Category | Initial recommendation | Purpose/choice |
| --- | --- | --- |
| Personal info → Email address, User IDs | Collected; required | Account management, app functionality, fraud/security where applicable |
| Personal info → Name | Collected; optional | App functionality/account management; user can keep default display name |
| Photos and videos → Photos | Collected; optional | App functionality |
| Calendar → Calendar events | Collected; optional | App functionality; app-owned events, no system-calendar permission |
| App activity → Other user-generated content | Collected; optional | Answers, notes, wishes; app functionality |
| App activity → App interactions | Collected; optional | Stored wish likes/planning; app functionality |
| Device or other IDs/security/network metadata | Finalize after deployment/network-log audit | Session/IP handling for security; avoid treating every random event ID as device ID |
| Approximate/precise location; other usage data | Provider review required | Local GPS use is not itself a backend collection; OSM viewed-area requests are off-device. Confirm classification/precision and retention. |
| Financial info → Purchase history | Resolve prior distributed behavior first | Disabled free candidate alone does not establish that all distributed versions collect none |

State encryption in transit only after confirming every final dependency endpoint uses it; the configured API, memory and tile endpoints use HTTPS. Both in-app and web account deletion are implemented, with remaining device/live end-to-end verification in the checklist.

Do not equate partner visibility with advertising/data sale. Apply Play's service-provider and deliberate user-initiated transfer exceptions only where their conditions are documented. Cloudflare processing on moch's instructions and an intentional export differ from an independent map provider's collection. Do not declare blanket 'no sharing' until that provider analysis is complete. Off-device transient processing still belongs in the form even where an ephemeral-processing exception affects public display. The form must cover all versions still distributed. See [Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).

## Deletion, unlink and retention findings

- Account deletion requires a current session created within ten minutes and the literal confirmation УСТГАХ. It replaces direct profile identifiers, revokes sessions, removes own calendar entries/answers and clears refresh/checkout payment secrets. Sources: `cloudflare/src/account.ts`, `0005_account.sql`.
- Deletion markers trigger removal of own memories/wishes. Unlinking removes **all photo memories and wishes in the pair**, including the partner's. Memory rows disappear and photo access is revoked transactionally; R2 bytes enter a durable cleanup queue. Sources: `memories_worker/migrations/0001_memories.sql`, `0002_wishes.sql`.
- The photo queue becomes due after five minutes; a 15-minute cron retries failed deletes. Tombstone rows remain at least 24 hours for late-write cleanup; a paginated sweep checks unreferenced objects older than a day. This is an implementation schedule, not a maximum deletion SLA. Monitor backlog.
- Unlinking alone does not delete account identities or every old calendar/answer row. Access to old partner content is revoked; permitted own-data export can still include own historical data. New pairs do not inherit old shared data.
- Opaque deleted-account/relationship records and payment ownership/audit metadata remain in D1. They are pseudonymous and should not be advertised as all data permanently erased or fully anonymized. Establish a justified retention policy and bound retention before claiming compliance; deletion does not cancel a store subscription.
- Public policy previously claimed backups expire in 7–30 days. Actual plan/configuration and other operational logs/exports were not inspected here. Confirm concrete retention, recovery behavior and a deletion-safe restore procedure before promising a maximum period.
- Saved user exports, screenshots or copies already held by the partner are outside app-controlled deletion. Disclose this plainly.

[Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/) describes removal of account-associated data except justified required retention. Current opaque tombstones/audit retention needs owner review rather than a blanket 'anonymous' assertion.

## Provider and operational confirmations still needed

Review [OSMF Privacy Policy](https://osmfoundation.org/wiki/Privacy_Policy) with its map-service collection, the actual Cloudflare plan/log and D1 Time Travel retention, support-mailbox retention/access, and all final archived SDK manifests. Confirm registered operator/legal address and target audience/age ratings in the consoles. User-provided public brand 'moch' is not proof of a registered company name. This worksheet does not replace those operational facts.
