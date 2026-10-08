# Private shared photo memories

This Worker is deployed separately from the existing Hamtdaa API. It authenticates
each request through the existing API's `GET /v1/auth/session` service binding,
uses the same D1 database for live pair authorization, and stores JPEGs in a private
R2 bucket. It does not change or redeploy the authentication Worker.

## API

All routes except health require the existing `Authorization: Bearer …` token.
JSON requests require `Content-Type: application/json`. Browser origins and URL
query parameters are rejected. Errors are `{ "ok": false, "code": "…" }`.

| Route | Request | Success |
| --- | --- | --- |
| `POST /v1/memories/list` | `expected_pair_id`, `month` (`YYYY-MM`) | `ok`, `pair_id`, `memories` |
| `POST /v1/memories/create` | `expected_pair_id`, UUID `command_id`, `day`, `title`, `note`, `sticker`, `photo_base64`, `thumbnail_base64` | `ok`, `memory` |
| `POST /v1/memories/delete` | `expected_pair_id`, UUID `command_id`, `id`, `expected_version` | `ok`, `deleted: true` |
| `GET /v1/memories/{id}/photo` | — | authenticated JPEG |
| `GET /v1/memories/{id}/thumbnail` | — | authenticated JPEG |
| `POST /v1/memories/export` | `expected_pair_id`, optional `cursor` | `ok`, one authored `memories` record with both base64 images, `next_cursor` or null |
| `GET /v1/health` | — | `ok`, service name |

Metadata: `id`, `pair_id`, `creator_id`, `day` (`YYYY-MM-DD`), `title`, `note`,
`sticker` (`rounded` or `polaroid`), positive `version`, ISO `created_at`.
Creation is immutable; only its creator can delete it. Both current partners can
read it. Send the same command ID and identical body when retrying a creation or
deletion. `upload_in_progress` is retryable using that same command.

Limits: title 1–80 characters, note up to 2,000; JPEG photo up to 768 KiB and
4 megapixels, thumbnail up to 64 KiB and 0.25 megapixels; streamed JSON up to
1,200 KiB. Server decoding/re-encoding removes EXIF/GPS and comments. Normalized
output must also fit the byte caps. The client uses 1280px photos and 160px thumbs.
Ten upload reservations per actor per UTC+8 day, ten memories per pair per calendar
day, and 1,000 total memories per pair. A monthly list has at most 310 records.
Monthly lists need a 4 MiB response bound for Unicode notes; exports need a response byte limit of at least 1,200 KiB. Pin the pair and account
scope for the entire export, and do not share an incomplete export.

## Consistency and privacy

Every operation resolves verified, active, unrevoked pair membership and checks
blocks and deleted-account markers. Writes repeat that predicate inside a D1
transaction. Object keys and pair/creator identity never change. New records stay
pending and unreadable until both R2 writes finish and a second transaction
authorizes publication. Ready objects are read through the Worker only, with
`private, no-store` cache headers.

The additive migration attaches cleanup to the existing account-deletion marker
and pair-unlink transaction. Unlinking permanently deletes that pair's memories.
Deletion removes metadata immediately and adds both object keys to a durable
queue. The scheduled collector retries deletion for 24 hours, then performs a
persistent, paginated orphan sweep. This also handles a PUT that finishes after
its owning record was deleted. The existing account export API is unchanged;
the app separately combines the memories export.

## Verification

```sh
npm ci
npm run types
npm run check
npm run dry-run -- --outdir dist
npm test
```

Tests use local Miniflare D1/R2 and mocked authentication only. Schema tests use
Python's standard SQLite library. No live accounts or photos are used.

## Deployment

Review bindings and migration before the first deployment. The default environment
is staging; production must always be explicitly selected. The separate
`hamtdaa_memory_migrations` table avoids consuming or replaying old auth migrations.

```sh
npx wrangler r2 bucket create nandin-moch-memories-staging
npx wrangler d1 migrations apply hamtdaa-staging --remote --env=""
npx wrangler deploy --env=""
```

Production uses the corresponding `production` bucket/database/Worker and
`--env=production`. Keep R2 public access disabled and do not attach a public
custom domain. Inspect the new Worker version's D1/R2/service bindings after
deployment. A safe unauthenticated smoke test must return 401 on list/photo
requests; functional account tests require explicitly authorized test accounts.

Do not deploy files from the incomplete recovered `../cloudflare` directory.
Rollback the new Worker independently; never drop the additive tables while
the existing account-deletion triggers or queued cleanup still need them.

## Initial photo release 2026-10-08

| Environment | URL | Worker version |
| --- | --- | --- |
| Staging | https://nandin-moch-memories-staging.mendmedey.workers.dev | `f4975865-6d92-4d87-9806-a4084d5cba51` |
| Production | https://nandin-moch-memories-production.mendmedey.workers.dev | `e5b113a8-5ea6-4782-accb-8c3d31cd241b` |

Both environments have the additive migration, their respective auth/D1/R2
bindings, disabled R2 public access, and a 15-minute collector schedule. Health
returned 200; missing and synthetic invalid credentials returned 401. D1 foreign
key checks returned no violations. The existing auth Workers were not redeployed.
Their downloaded deployed bundles were identical and confirmed that account
deletion inserts its marker before disabling profiles and unlinking pairs, without
physically deleting profiles/pairs. Local verification passed 16 tests, including
40 schema assertions; TypeScript and deployment dry-run passed, with zero npm
audit findings. Live authenticated creation/deletion was not exercised.

## Collaborative wish board

The same isolated Worker serves the private wish board through the existing auth
service binding. All wish routes use `POST /v1/wishes/<operation>` and bounded
JSON (8 KiB). Every request includes `expected_pair_id`; every mutation includes
a UUID `command_id`. Retry the exact body with the same command ID after an
uncertain reply. The payload hash binds every accepted field and the operation.

| Operation | Additional request fields | Success |
| --- | --- | --- |
| `list` | — | `ok`, `pair_id`, up to 500 `wishes` |
| `create` | `title`, `note`, `location`, `category`, `budget` | `ok`, `wish` |
| `like` | `id`, `expected_version`, explicit Boolean `liked` | `ok`, `wish` |
| `delete` | `id`, `expected_version` | `ok`, `deleted: true` |
| `plan` | `id`, `expected_version`, UTC ISO `starts_at`, nullable UTC ISO `ends_at` | `ok`, `wish`, `event_id` |
| `complete` | `id`, `expected_version` | `ok`, `wish` |
| `export` | — | `ok`, `pair_id`, own-authored `wishes`, own `likes` |

Wish metadata: `id`, `pair_id`, `creator_id`, `title`, `note`, `location`,
`category`, `budget`, `status` (`idea`, `planned`, `done`), positive `version`,
Boolean `my_liked` and `partner_liked`, nullable `event_id`, nullable
`event_starts_at` and `event_status`, and ISO `created_at` / `updated_at`.
Calendar information is derived from the existing calendar row, so subsequent
calendar edits and responses are reflected. The board omits emails and profiles.

Creation auto-likes the creator's idea. Either partner can explicitly like/unlike
an idea. A version changes with every successful like command, even if that
Boolean was already set; replaying its original command does not mutate again.
Text and ownership are immutable. Only the creator can delete a wish. Likes are
locked once planned. Planning requires both likes and atomically inserts exactly
one compatible pending `hamtdaa_calendar_events` invitation; its creator is the
partner who planned it. The other partner responds in the existing calendar.
Completing requires an accepted calendar event whose start is at or before the
server time, and either partner can complete it.

Deleting a wish leaves its calendar event intact. Deleting an event restores a
planned wish to `idea`, preserves both likes, clears the event fields and bumps
the wish version. A completed wish remains `done` after event deletion, with null
event fields. Unlinking removes all wishes, likes and command receipts for that
pair in the existing transaction. Account deletion erases authored wishes, the
actor's likes, receipts and quotas through the existing deleted-account marker.

Limits: title 1–80, note 0–500, location 0–120 UTF-16 code units;
`category`: `home`, `outdoor`, `food`, `travel`, `other`;
`budget`: `free`, `low`, `medium`, `high`.
There are at most 200 unfinished wishes and 500 total wishes per pair, and 100
wish mutations per actor per UTC+8 day. A plan also consumes the existing calendar
quotas (30 new events and 100 total Together mutations per actor per day) and
respects its 500-event pair cap. The list/export response fits within 2 MiB.

Export includes only the actor's authored wish metadata (without
`partner_liked`) plus their own `{wish_id, liked: true}` records. It never exports
the partner's authored text or liking state. An export client should pin its
account/pair and reject an incomplete or changed-scope response before sharing.

Errors use the same safe envelope as memories: `validation` (400),
`unauthenticated` (401), `forbidden` (403), `not_found` (404),
`pair_required`, `conflict`, `mutual_like_required`, `idempotency_mismatch` (409),
`wish_deleted`, `event_deleted` (410), `quota_exceeded` (429), and
`temporarily_unavailable` (503). A 410 on replay never recreates deleted data.

Migration `0002_wishes.sql` uses the same isolated migration registry. Apply it
before deploying the new Worker. The existing auth Worker remains unchanged.
Local verification uses Miniflare D1 with the checked-in Together schema and
synthetic actors; tests cover both planner identities, concurrent planning and
retries, old versions, unlink at commit, lifecycle cleanup, quotas, and exports.
The previously downloaded deployed auth bundles (2026-10-08 audit) include the
`expected_pair_id` contract used by the mobile calendar, unlike the incomplete
recovered auth source. Their identical SHA-256 is
`fd27a902ddc87dd21105a7cc378ac601e2e5cf7829189363960f624e8dfded38`.

### Wish board validation and release status (2026-10-08)

The wish board migration and Worker are now deployed in both environments.
Cloudflare connectivity recovered, and Wrangler refreshed the existing login.
Only the isolated memories Worker and additive `0002_wishes.sql` migration were
released; the existing authentication Workers were not changed.

| Environment | Worker version |
| --- | --- |
| Staging | `10a41ced-9bb6-434b-885e-ff42b66904e1` |
| Production | `038b45ef-6f8c-40ef-a552-b4f17e744625` |

This release also preserves Cloudflare's edge-provided `CF-Connecting-IP` when
calling the existing authentication service. The deployed auth library otherwise
puts requests without a trusted IP in one shared rate bucket, allowing different
photo/wish users to throttle each other. Caller-supplied forwarding headers,
cookies, and browser Origin remain excluded. A new regression test verifies both
IPv4 and IPv6 propagation and excludes the other headers.

Local validation passed TypeScript, all **32 Worker tests**, and staging plus
production deployment dry-runs. Staging health returned 200; missing and
synthetic invalid wish credentials and unauthenticated photos returned 401.
Production returned the same 200/401 results. Both foreign-key checks were
clean; the production registry contains `0001_memories.sql` and
`0002_wishes.sql`, and the pending photo-deletion queue was empty. No real user, email delivery, photo upload, calendar invitation, or payment
was created by release checks. Paired-device authenticated testing still needs
designated test accounts before declaring the app ready for public launch.

Before the production migration, D1 Time Travel returned this recovery bookmark:
`00000015-00000000-000050fe-920e7f283d2474d7e013ea98e1916684`.
This verifies recovery metadata availability, not a completed restore drill.
Photo recovery and deletion-preserving database recovery remain operational
validation tasks. Prefer independent Worker rollback for an application incident;
do not drop additive tables or restore a live database as an unreviewed rollback.

The earlier deployment delay was a TLS failure reaching Cloudflare's official
OAuth endpoint; a read-only cached-token fallback returned 401. Neither network
settings nor credential files were manually altered. Those transient transport
and authentication blockers are now resolved.

For later releases, inspect the isolated migration registry, apply staging first,
verify it, then apply production. The standard commands are:

```sh
npx wrangler d1 migrations list hamtdaa-staging --remote --env=""
npx wrangler d1 migrations apply hamtdaa-staging --remote --env=""
npx wrangler deploy --env=""
npx wrangler d1 migrations list hamtdaa-production --remote --env=production
npx wrangler d1 migrations apply hamtdaa-production --remote --env=production
npx wrangler deploy --env=production
```

Do not deploy the recovered `../cloudflare` source: its dependency manifest,
Wrangler configuration and initial auth migration are missing, and some source
contracts differ from the working deployed artifact. Recover and validate that
project independently before changing authentication or billing.
