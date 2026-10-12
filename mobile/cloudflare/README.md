# Nandin Moch authentication backend

Cloudflare Worker for email login, consent-based pairing, the shared calendar,
daily questions, account controls and billing. Source recovery on 2026-10-12
restored the missing build inputs, database definitions and application changes
from the deployed backend. This is a source recovery, not a new live release.

**Billing stays disabled. No remote migration or deployment is required to
repair the lost local source.** The recovered application logic already exists
in the preserved deployment. Public/paid launch still has the gates listed in
[`../docs/production-readiness.md`](../docs/production-readiness.md).

The photo/wish service is maintained separately in
[`../memories_worker`](../memories_worker/README.md). Both Workers share D1;
their migration histories are separate.

## Local validation

Use Node 22 and Python 3. From this directory:

```sh
npm ci --no-audit --no-fund
npm ls --all
npm run types
npm run check
npm run test:schema
npm test
npm run deploy:check -- --outdir dist
npm run deploy:check:production -- --outdir dist-production
```

Tests use local D1/Workers instances, synthetic accounts and mocked email/store/
Wire providers. `remoteBindings: false` prevents test bindings from accessing
live resources. Dry runs bundle locally and do not deploy. No Cloudflare API
credential, email delivery, real purchase or production secret is needed for
these checks. CI runs the same gates without deployment credentials.

Final recovery validation on Node 22.23.3: **171 tests passed in 9 files**, three
schema checks passed, type checking/dependency resolution passed, and both dry
runs passed. Generated types reproduce unchanged. The dependency audit reported
zero known advisories at this check; this is not a security certification.

`npm run types` generates binding/runtime definitions from Wrangler and the
configuration. Required secret **names** are declared in `secrets.required`;
values are never stored in source. For manual local development, copy
`.dev.vars.example` to an ignored `.dev.vars`, generate a disposable auth
secret, and run `npm run db:local`. Do not copy production secrets into tests.

## Environments and migrations

- The default configuration targets staging; production must be explicitly
  selected. Account, database IDs, sender, compatibility date and billing flags
  are preserved from the deployed configuration. Local commands use `--local`
  or `--dry-run`; none of the package scripts performs a live deployment.
- Keep `compatibility_date: 2026-10-05` and the restored dependency versions
  during recovery validation. Dependency/runtime upgrades are separate changes.
- Both environments already record auth migrations `0001_auth.sql` through
  `0005_account.sql`. The recovered `0001` and `0003` are their original complete
  definitions, not new upgrade migrations. **Do not reapply or rename them on
  live databases.** Recreate only disposable local databases built from the
  incomplete recovery. Future schema changes need new numbered migrations.
- The schema gate rebuilds the auth schema independently, then the combined
  photo/wish schema, and compares against a committed schema-only reference.
  See [`docs/schema-recovery.md`](docs/schema-recovery.md) for provenance and
  the read-only staging/production comparison.

## Recovery provenance and limits

The 2026-10-08 downloaded staging and production bundles were identical:

```text
SHA-256 fd27a902ddc87dd21105a7cc378ac601e2e5cf7829189363960f624e8dfded38
```

Private copies and original editing records are retained outside Git under
`../../recovery/2026-10-08/`. The temporary `/tmp` copy is no longer required.
The compiled artifact is evidence; it is not a replacement for typed source or
an off-device backup.

- All ten application modules were compared with that preserved bundle. Four
  billing modules emit the same module bytes. Six core modules match after
  reviewed bundler-only differences (class lowering, symbol names, shorthand
  properties and the default export). No behavior change was introduced to the
  deployed application while recovering source.
- Recovery includes atomic OTP consumption, session identity/ISO timestamp
  deletion guards, stale-pair rejection, calendar revision pagination, native
  store verification, encrypted receipt refresh, immutable payment ownership,
  refund reconciliation and the nested entitlement contract expected by Flutter.
- Original package/configuration records identify Better Auth 1.7.6, Wrangler
  4.147.0 and the test runtime overrides. The original lockfile was not recovered.
  The committed lockfile is newly resolved from those recorded versions and
  overrides, then checked with a clean install. It does **not** prove historical
  transitive dependencies or the whole bundle are byte-identical.
- Schema-only reads on 2026-10-12 confirmed staging/production parity. No account,
  session, verification, payment or photo rows were exported. This check is not
  a backup/restore rehearsal.
- The read-only production deployment listing on 2026-10-12 still ends with
  version `8e3a9914-08bc-486b-8016-015e0c834cd2`, deployed on 2026-10-06. Both
  environments' `/v1/health` checks returned 200. Neither environment was
  redeployed by this recovery. Retain the deployment listing as rollback
  evidence; verify the active version again before a future release.

## Release boundaries

Passing local tests and matching the schema do not prove a live two-phone flow,
Store purchases, sandbox/App Review behavior, sender capacity, alerting or
disaster recovery. The deployed production verifier still has the same sandbox
restriction; purchases must remain disabled until that separate release gate is
resolved and tested. Private photo/wish policy disclosures and native signed
builds also remain release work. Do not advertise these checks as full app
production certification.
