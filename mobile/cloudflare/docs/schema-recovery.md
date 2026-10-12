# Auth database source recovery — 2026-10-12

The recovered migration chain now reproduces the deployed schema. This work
restores lost source; it does not introduce a new database upgrade. No remote
migration, application-row export or database write was performed.

## Evidence

- Read-only `sqlite_master` queries against both staging and production returned
  the same 95 named DDL objects. Four belong to D1/Wrangler bookkeeping; the
  remaining 91 application tables, indexes and triggers are in the committed
  schema-only fixture. No user, session, verification or payment rows are in it.
- Read-only migration-name queries confirmed auth migrations `0001_auth.sql`
  through `0005_account.sql`, and the separate memory worker's
  `0001_memories.sql` / `0002_wishes.sql`, in both environments.
- A schema-only `d1 export --no-data` attempt was denied by the export endpoint
  with authentication error 10000. Ordinary schema queries succeeded. The
  snapshot therefore comes from the schema query, not a successful export.

## Restored sources

`0001_auth.sql` and the final `0003_billing.sql` were recovered verbatim from a
historical successful file-read output, rather than generated from assumptions.
The source is the `cf_auth_finish` execution record dated 2026-10-05, record
1124 (command `cat migrations/0001_auth.sql migrations/0003_billing.sql`). The
private original execution record remains outside Git. The recovered text
matches the live schema after all five existing auth migrations are applied.

| File | SHA-256 of recovered source |
| --- | --- |
| `0001_auth.sql` | `6dd7cee17d6a40dc396a2f68310b9dc30437e82f10266e4a15a7fd10e18b86d0` |
| `0003_billing.sql` | `b53b19229ca56d1a18ca7f5ef4af4a91e71eee0a432d76b03701373cc93df5ee` |

The initial auth migration includes the unique verification identifier used by
the deployed OTP flow. The billing recovery restores checkout URLs, encrypted
receipt refresh state, active-grant state, native store environments, the
environment-scoped transaction key, price/plan consistency and immutable grant
ownership/environment. These were already deployed; they were missing from the
earlier recovered source tree. `0002_pair.sql`, `0004_together.sql` and
`0005_account.sql` needed no changes.

## Verification and future changes

Run `python3 test/schema/check_schema.py` from this folder. This offline check:

- Rebuilds the auth schema independently with foreign keys enabled.
- Rebuilds the complete application schema by then applying the separate memory
  worker migrations, including wishes.
- Compares every application table, index and trigger definition, preserving
  CHECK constraints, foreign keys and string literals, with the deployed fixture.
- Verifies SQLite integrity and foreign-key checks and the observed migration
  filenames.

This fixture intentionally fixes the recovery baseline. Future intentional
schema changes require new numbered migrations and an explicit update to this
gate; do not regenerate a fixture merely to make an unexplained difference pass.
The memory worker retains its separate migration chain and tracking table.

Do not rerun these historical migrations against databases where their names are
already recorded. A local database created from the incomplete recovery is not
a supported deployed baseline; recreate only that disposable local database.
Live staging and production already have the complete definitions. Schema parity
alone does not validate deployed application behavior, payment credentials,
restore procedures or store release readiness.
