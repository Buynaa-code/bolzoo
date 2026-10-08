-- Minimal compatible fixture for the existing shared schema, not a migration.
PRAGMA foreign_keys=ON;

CREATE TABLE "user" (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT 'Test user',
  email TEXT NOT NULL UNIQUE,
  emailVerified INTEGER NOT NULL DEFAULT 0 CHECK(emailVerified IN (0,1)),
  image TEXT,
  createdAt INTEGER NOT NULL DEFAULT 0,
  updatedAt INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE hamtdaa_profiles (
  user_id TEXT PRIMARY KEY REFERENCES "user"(id) ON DELETE RESTRICT,
  display_name TEXT NOT NULL DEFAULT 'Хэрэглэгч' CHECK(length(trim(display_name)) BETWEEN 1 AND 40),
  account_state TEXT NOT NULL DEFAULT 'active' CHECK(account_state IN ('active','deleting','disabled')),
  version INTEGER NOT NULL DEFAULT 1 CHECK(version>0)
);

CREATE TABLE hamtdaa_pairs (
  id TEXT PRIMARY KEY,
  -- Invitations are irrelevant to memories, so their table is omitted here.
  invitation_id TEXT UNIQUE,
  state TEXT NOT NULL DEFAULT 'forming' CHECK(state IN ('forming','active','unlinked')),
  version INTEGER NOT NULL DEFAULT 1 CHECK(version>0),
  created_at INTEGER NOT NULL DEFAULT 0,
  unlinked_at INTEGER,
  CHECK(state<>'unlinked' OR unlinked_at IS NOT NULL)
);

CREATE TABLE hamtdaa_pair_members (
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  slot INTEGER NOT NULL CHECK(slot IN (1,2)),
  revoked_at INTEGER,
  PRIMARY KEY(pair_id,user_id),
  UNIQUE(pair_id,slot)
);
CREATE UNIQUE INDEX hamtdaa_pair_one_active_membership
  ON hamtdaa_pair_members(user_id) WHERE revoked_at IS NULL;

CREATE TABLE hamtdaa_blocks (
  blocker_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  blocked_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  PRIMARY KEY(blocker_id,blocked_id),
  CHECK(blocker_id<>blocked_id)
);
CREATE INDEX hamtdaa_blocks_blocked ON hamtdaa_blocks(blocked_id);

CREATE TABLE hamtdaa_deleted_accounts (
  user_id TEXT PRIMARY KEY REFERENCES "user"(id) ON DELETE RESTRICT,
  deleted_at INTEGER NOT NULL
);
