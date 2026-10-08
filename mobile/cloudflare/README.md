# Recovered auth backend — do not deploy

**This directory cannot currently reproduce the deployed staging or production
API. Do not deploy this source or apply its recovered migrations to a live
database.** It was recovered from incomplete editing records after the original
mobile project was omitted from Git. The production auth, pairing, calendar,
account and billing Worker is a newer, different artifact.

The photo/wish service is maintained and deployed separately in
[`../memories_worker`](../memories_worker/README.md). Its successful tests and
releases do not validate the recovered backend in this directory.

## Known missing build and schema inputs

As verified on 2026-10-08, this directory has source, tests, and migrations
`0002_pair.sql` through `0005_account.sql`, but is missing:

- `package.json` and a dependency lockfile with the original dependency versions.
- Wrangler configuration, generated binding types, and TypeScript configuration.
- Test-runner configuration that provides `TEST_MIGRATIONS` and the mocked email
  binding used by `test/setup.ts` and the integration tests.
- The initial auth migration defining Better Auth's user, session, account,
  verification and rate-limit tables.
- Schema changes present in the live billing database but absent from the
  recovered `migrations/0003_billing.sql`.

Do not fill these gaps by selecting arbitrary current dependency versions or
re-running the recovered migration sequence against production.

## Confirmed source and database drift

| Area | Recovered source | Deployed evidence / expected behavior |
| --- | --- | --- |
| Pair scope | `src/together.ts:146` accepts only `command_id` as a common mutation field. | The audited deployed bundle requires and validates `expected_pair_id`; `test/together.test.ts` already exercises that contract. Recovered code rejects the current app's valid requests. |
| Account deletion identity | `src/index.ts:156` does not return a session ID and `:190` does not pass one. | `AccountActor` in `src/account.ts:3` requires `sessionId`; deployed routing carries the authenticated session ID to deletion. |
| Account deletion timestamps | `src/account.ts:141` casts session timestamps to integer milliseconds. | Better Auth-created sessions use ISO text, as tested by `test/account.test.ts:91`. The deployed deletion guard compares normalized ISO strings and verifies the same live session inside the transaction. |
| Billing orders | Recovered `0003_billing.sql` omits `checkout_url`. | Production `PRAGMA table_info` confirms `checkout_url TEXT`. Later recovered account code/triggers already reference it. |
| Billing grants | Recovered `0003_billing.sql` omits `environment`, `refresh_cipher`, and `is_active`. | Production schema confirms `environment TEXT`, `refresh_cipher TEXT`, `is_active INTEGER`; account export/deletion already relies on these columns. |
| Billing transactions | Recovered `0003_billing.sql` omits `environment`. | Production schema confirms `environment TEXT`. |

Billing schema evidence was obtained on 2026-10-08 using only `PRAGMA table_info`
on the three named production tables. No user rows, payment records, credentials,
or receipt contents were read or changed. A complete recovery must also compare
indexes, constraints, triggers and migration history; column presence alone does
not establish schema parity.

## Deployed artifact evidence

The 2026-10-08 audit downloaded the deployed `hamtdaa-api-production` and
`hamtdaa-api-staging` bundles. Both `src/index.js` files have SHA-256:

```text
fd27a902ddc87dd21105a7cc378ac601e2e5cf7829189363960f624e8dfded38
```

The digest was rechecked during the source-protection audit. Original local audit
locations (temporary storage, not a durable backup) are:

```text
/tmp/nandin-auth-audit-20261008/downloaded/hamtdaa-api-production/src/index.js
/tmp/nandin-auth-audit-20261008/downloaded/hamtdaa-api-production/wrangler.jsonc
/tmp/nandin-auth-audit-20261008/downloaded/hamtdaa-api-staging/src/index.js
```

In that exact production bundle, lines 63861–63880 contain the expected-pair
contract, lines 64110–64125 contain the ISO-session deletion guard, and lines
64373–64411 carry session identity through routing. The hash fixes the identity of
the audited files; it is not a claim that every future production version has the
same digest. Unchanged copies were also saved locally under
`../../recovery/2026-10-08/deployed-auth-audit/` and their hashes rechecked.
That private, Git-ignored directory protects against temporary-file cleanup; it
is not an off-device backup or a complete recovered source repository. The compiled bundle and downloaded config
are recovery evidence, not authorization to redeploy them or overwrite bindings.

## Recovery acceptance steps

1. Preserve the deployed artifact, its exact Worker version and configuration,
   and a schema-only database snapshot in durable recovery storage. Keep secret
   values in the platform's secret store, outside source control and logs.
2. Recover the original package/lockfile, build and test configuration, generated
   binding types, complete migration sequence, and source edits. Reconcile the
   confirmed differences above against the identified deployed version.
3. Build and run migrations from an empty **local** database, then compare all
   tables, columns, keys, constraints, indexes and triggers with a schema-only
   live reference. Do not rewrite already-applied production migrations.
4. Pass type checking and the complete auth, pairing, Together, account and
   billing suites. Include real library-created ISO session fixtures, same-session
   deletion guards, stale-pair rejection, revoked-session/account races, safe
   exports, billing environment isolation and all photo/wish cleanup triggers.
   Use synthetic accounts and mocked email/payment providers locally.
5. Produce a reproducible build and a staging deployment dry-run with audited
   bindings. Document a versioned rollback path and rehearse database/photo
   recovery without restoring deleted personal data into an active service.
6. Review the recovered change independently, then validate staging using
   designated test accounts and an explicitly approved release. Only after these
   checks should any production auth/billing deployment be considered.

No auth source reconstruction, auth deployment, or live data migration was
performed by this source-protection task.
