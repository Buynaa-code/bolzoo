-- Application records reference verified Better Auth identities; never client IDs.
CREATE TABLE hamtdaa_profiles (
  user_id TEXT PRIMARY KEY REFERENCES "user"(id) ON DELETE RESTRICT,
  display_name TEXT NOT NULL DEFAULT 'Хэрэглэгч' CHECK(length(trim(display_name)) BETWEEN 1 AND 40),
  account_state TEXT NOT NULL DEFAULT 'active' CHECK(account_state IN ('active','deleting','disabled')),
  version INTEGER NOT NULL DEFAULT 1 CHECK(version > 0)
);

CREATE TABLE hamtdaa_blocks (
  blocker_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  blocked_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  PRIMARY KEY(blocker_id,blocked_id),
  CHECK(blocker_id <> blocked_id)
);
CREATE INDEX hamtdaa_blocks_blocked ON hamtdaa_blocks(blocked_id);

CREATE TABLE hamtdaa_pair_invitations (
  id TEXT PRIMARY KEY,
  creator_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  requester_id TEXT REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  token_hash TEXT NOT NULL UNIQUE CHECK(length(token_hash)=64 AND token_hash NOT GLOB '*[^0-9a-f]*'),
  state TEXT NOT NULL DEFAULT 'open' CHECK(state IN ('open','awaiting_creator','linked','revoked','declined','cancelled','expired')),
  version INTEGER NOT NULL DEFAULT 1 CHECK(version > 0),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL CHECK(expires_at > created_at),
  requested_at INTEGER,
  confirmed_at INTEGER,
  pair_id TEXT REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  CHECK(requester_id IS NULL OR creator_id <> requester_id),
  CHECK(state NOT IN ('awaiting_creator','linked') OR (requester_id IS NOT NULL AND requested_at IS NOT NULL)),
  CHECK(state <> 'linked' OR (pair_id IS NOT NULL AND confirmed_at IS NOT NULL))
);
CREATE INDEX hamtdaa_pair_invites_creator ON hamtdaa_pair_invitations(creator_id,state);
CREATE INDEX hamtdaa_pair_invites_requester ON hamtdaa_pair_invitations(requester_id,state);
CREATE INDEX hamtdaa_pair_invites_pair ON hamtdaa_pair_invitations(pair_id);
CREATE UNIQUE INDEX hamtdaa_pair_one_pending_request ON hamtdaa_pair_invitations(requester_id) WHERE state='awaiting_creator';
CREATE UNIQUE INDEX hamtdaa_pair_one_live_invite ON hamtdaa_pair_invitations(creator_id) WHERE state IN ('open','awaiting_creator');

CREATE TABLE hamtdaa_pairs (
  id TEXT PRIMARY KEY,
  invitation_id TEXT NOT NULL UNIQUE REFERENCES hamtdaa_pair_invitations(id) ON DELETE RESTRICT,
  state TEXT NOT NULL DEFAULT 'forming' CHECK(state IN ('forming','active','unlinked')),
  version INTEGER NOT NULL DEFAULT 1 CHECK(version > 0),
  created_at INTEGER NOT NULL,
  unlinked_at INTEGER,
  CHECK(state <> 'unlinked' OR unlinked_at IS NOT NULL)
);
CREATE TABLE hamtdaa_pair_members (
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  slot INTEGER NOT NULL CHECK(slot IN (1,2)),
  revoked_at INTEGER,
  PRIMARY KEY(pair_id,user_id),
  UNIQUE(pair_id,slot)
);
-- This database-wide index also prevents a user joining two different pairs
-- through two simultaneous confirmations (a per-pair lock cannot guarantee it).
CREATE UNIQUE INDEX hamtdaa_pair_one_active_membership ON hamtdaa_pair_members(user_id) WHERE revoked_at IS NULL;

CREATE TRIGGER hamtdaa_pair_member_insert_guard BEFORE INSERT ON hamtdaa_pair_members
WHEN NOT EXISTS (
    SELECT 1 FROM hamtdaa_pairs p JOIN hamtdaa_pair_invitations i ON i.id=p.invitation_id
    JOIN hamtdaa_profiles u ON u.user_id=NEW.user_id JOIN "user" a ON a.id=u.user_id
    WHERE p.id=NEW.pair_id AND p.state='forming' AND u.account_state='active' AND a.emailVerified=1
      AND i.state='awaiting_creator' AND i.expires_at>CAST(strftime('%s','now') AS INTEGER)
      AND ((NEW.slot=1 AND NEW.user_id=i.creator_id) OR (NEW.slot=2 AND NEW.user_id=i.requester_id))
  )
BEGIN
  SELECT RAISE(ABORT,'pair_membership_guard');
END;
CREATE TRIGGER hamtdaa_pair_activate_guard BEFORE UPDATE OF state ON hamtdaa_pairs
WHEN NEW.state='active' AND (OLD.state<>'forming' OR (
    SELECT count(*) FROM hamtdaa_pair_members WHERE pair_id=NEW.id AND revoked_at IS NULL
  )<>2)
BEGIN
  SELECT RAISE(ABORT,'pair_activation_guard');
END;
CREATE TRIGGER hamtdaa_pair_no_reactivate BEFORE UPDATE OF state ON hamtdaa_pairs
WHEN OLD.state='unlinked' AND NEW.state<>'unlinked'
BEGIN
  SELECT RAISE(ABORT,'pair_unlinked');
END;
CREATE TRIGGER hamtdaa_pair_no_member_restore BEFORE UPDATE OF revoked_at ON hamtdaa_pair_members
WHEN OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS NULL
BEGIN
  SELECT RAISE(ABORT,'pair_member_revoked');
END;

-- Receipts contain hashes and entity IDs, never invitation secrets or partner
-- projections. A replay rebuilds its result using the current access rules.
CREATE TABLE hamtdaa_pair_receipts (
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL,
  payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64),
  outcome TEXT NOT NULL CHECK(json_valid(outcome)),
  created_at INTEGER NOT NULL,
  PRIMARY KEY(user_id,command_id)
);
CREATE TABLE hamtdaa_pair_rate_limits (
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  action TEXT NOT NULL CHECK(action IN ('preview','create','request','mutation')),
  window_start INTEGER NOT NULL,
  attempts INTEGER NOT NULL CHECK(attempts>0),
  PRIMARY KEY(user_id,action)
);
-- A failed predicate aborts the WHOLE D1 batch, including its receipt. Guards
-- are deleted in the same batch, so no permanent per-request rows accumulate.
CREATE TABLE hamtdaa_pair_transition_guards (
  id TEXT PRIMARY KEY,
  allowed INTEGER NOT NULL CHECK(allowed=1)
);
