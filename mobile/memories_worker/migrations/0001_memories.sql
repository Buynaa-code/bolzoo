-- Additive memories schema. Existing authentication and pair tables are shared.
-- All timestamps in these tables are milliseconds since the Unix epoch.
CREATE TABLE hamtdaa_memories (
  id TEXT NOT NULL PRIMARY KEY CHECK(
    length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-'
    AND substr(id,19,1)='-' AND substr(id,24,1)='-'
    AND length(replace(id,'-',''))=32
    AND replace(id,'-','') NOT GLOB '*[^0-9a-f]*'
  ),
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  creator_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  day TEXT NOT NULL CHECK(
    day GLOB '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
    AND date(day,'+0 days') IS NOT NULL AND date(day,'+0 days')=day
  ),
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 80),
  note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=2000),
  sticker TEXT NOT NULL CHECK(sticker IN ('rounded','polaroid')),
  state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','ready')),
  photo_key TEXT NOT NULL UNIQUE CHECK(length(photo_key) BETWEEN 1 AND 512),
  thumbnail_key TEXT NOT NULL UNIQUE CHECK(length(thumbnail_key) BETWEEN 1 AND 512),
  photo_bytes INTEGER NOT NULL CHECK(typeof(photo_bytes)='integer' AND photo_bytes>0),
  thumb_bytes INTEGER NOT NULL CHECK(typeof(thumb_bytes)='integer' AND thumb_bytes>0),
  payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64 AND payload_hash NOT GLOB '*[^0-9a-f]*'),
  command_id TEXT NOT NULL CHECK(length(command_id)=36),
  version INTEGER NOT NULL DEFAULT 1 CHECK(typeof(version)='integer' AND version>0),
  created_at INTEGER NOT NULL CHECK(typeof(created_at)='integer' AND created_at>0),
  upload_deadline INTEGER NOT NULL CHECK(typeof(upload_deadline)='integer' AND upload_deadline>created_at),
  UNIQUE(creator_id,command_id),
  CHECK(photo_key<>thumbnail_key)
);
CREATE INDEX hamtdaa_memories_pair_day ON hamtdaa_memories(pair_id,state,day DESC,id DESC);
CREATE INDEX hamtdaa_memories_creator ON hamtdaa_memories(creator_id);
CREATE INDEX hamtdaa_memories_pending_deadline ON hamtdaa_memories(upload_deadline) WHERE state='pending';

CREATE TABLE hamtdaa_memory_receipts (
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL CHECK(length(command_id)=36),
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  operation TEXT NOT NULL CHECK(operation IN ('create','delete')),
  payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64 AND payload_hash NOT GLOB '*[^0-9a-f]*'),
  -- Kept after content deletion so an idempotent delete can still be recognized.
  memory_id TEXT,
  created_at INTEGER NOT NULL CHECK(typeof(created_at)='integer' AND created_at>0),
  PRIMARY KEY(user_id,command_id)
);
CREATE INDEX hamtdaa_memory_receipts_pair ON hamtdaa_memory_receipts(pair_id);

CREATE TABLE hamtdaa_memory_quotas (
  user_id TEXT NOT NULL PRIMARY KEY REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  day TEXT NOT NULL CHECK(
    day GLOB '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
    AND date(day,'+0 days') IS NOT NULL AND date(day,'+0 days')=day
  ),
  creates INTEGER NOT NULL CHECK(typeof(creates)='integer' AND creates BETWEEN 1 AND 10)
);
CREATE TABLE hamtdaa_memory_guards (
  id TEXT NOT NULL PRIMARY KEY,
  allowed INTEGER NOT NULL CHECK(allowed=1)
);

-- No content/account FK: cleanup must survive removal of its originating row.
-- Keys remain tombstoned after successful deletion to catch late in-flight PUTs.
CREATE TABLE hamtdaa_memory_gc (
  object_key TEXT NOT NULL PRIMARY KEY CHECK(length(object_key) BETWEEN 1 AND 512),
  due_at INTEGER NOT NULL CHECK(typeof(due_at)='integer' AND due_at>0),
  retain_until INTEGER NOT NULL CHECK(typeof(retain_until)='integer' AND retain_until>=due_at),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK(typeof(attempts)='integer' AND attempts>=0)
);
CREATE INDEX hamtdaa_memory_gc_due ON hamtdaa_memory_gc(due_at);
CREATE TABLE hamtdaa_memory_gc_state (
  name TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
);

-- The two key columns share one object namespace. A key is never repurposed,
-- including while a deletion tombstone is retained for late upload cleanup.
CREATE TRIGGER hamtdaa_memory_key_guard BEFORE INSERT ON hamtdaa_memories
WHEN EXISTS(SELECT 1 FROM hamtdaa_memories m
    WHERE m.photo_key IN (NEW.photo_key,NEW.thumbnail_key)
       OR m.thumbnail_key IN (NEW.photo_key,NEW.thumbnail_key))
  OR EXISTS(SELECT 1 FROM hamtdaa_memory_gc g
    WHERE g.object_key IN (NEW.photo_key,NEW.thumbnail_key))
BEGIN SELECT RAISE(ABORT,'memory_object_key_used'); END;

-- A memory belongs permanently to its original pair. Client-supplied pair IDs
-- are only expected-state checks; the Worker resolves its actor from auth.
CREATE TRIGGER hamtdaa_memory_insert_guard BEFORE INSERT ON hamtdaa_memories
WHEN NEW.state<>'pending' OR NOT EXISTS (
  SELECT 1 FROM hamtdaa_pairs p
  JOIN hamtdaa_pair_members own ON own.pair_id=p.id
    AND own.user_id=NEW.creator_id AND own.revoked_at IS NULL
  JOIN hamtdaa_pair_members other ON other.pair_id=p.id
    AND other.user_id<>own.user_id AND other.revoked_at IS NULL
  JOIN hamtdaa_profiles ap ON ap.user_id=own.user_id AND ap.account_state='active'
  JOIN hamtdaa_profiles op ON op.user_id=other.user_id AND op.account_state='active'
  JOIN "user" au ON au.id=own.user_id AND au.emailVerified=1
  JOIN "user" ou ON ou.id=other.user_id AND ou.emailVerified=1
  WHERE p.id=NEW.pair_id AND p.state='active'
    AND NOT EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts d
      WHERE d.user_id IN (own.user_id,other.user_id))
    AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b
      WHERE (b.blocker_id=own.user_id AND b.blocked_id=other.user_id)
         OR (b.blocker_id=other.user_id AND b.blocked_id=own.user_id))
)
BEGIN SELECT RAISE(ABORT,'memory_pair_guard'); END;

-- The only update is publication after both immutable objects are stored.
CREATE TRIGGER hamtdaa_memory_immutable BEFORE UPDATE ON hamtdaa_memories
WHEN OLD.state<>'pending' OR NEW.state<>'ready'
  OR NEW.id IS NOT OLD.id OR NEW.pair_id IS NOT OLD.pair_id
  OR NEW.creator_id IS NOT OLD.creator_id OR NEW.day IS NOT OLD.day
  OR NEW.title IS NOT OLD.title OR NEW.note IS NOT OLD.note
  OR NEW.sticker IS NOT OLD.sticker OR NEW.photo_key IS NOT OLD.photo_key
  OR NEW.thumbnail_key IS NOT OLD.thumbnail_key OR NEW.photo_bytes IS NOT OLD.photo_bytes
  OR NEW.thumb_bytes IS NOT OLD.thumb_bytes OR NEW.payload_hash IS NOT OLD.payload_hash
  OR NEW.command_id IS NOT OLD.command_id OR NEW.created_at IS NOT OLD.created_at
  OR NEW.upload_deadline IS NOT OLD.upload_deadline
  OR NEW.version NOT IN (OLD.version,OLD.version+1)
BEGIN SELECT RAISE(ABORT,'memory_immutable'); END;

CREATE TRIGGER hamtdaa_memory_ready_guard BEFORE UPDATE OF state ON hamtdaa_memories
WHEN NEW.state='ready' AND (
  NEW.upload_deadline<=CAST(strftime('%s','now') AS INTEGER)*1000
  OR NOT EXISTS (
    SELECT 1 FROM hamtdaa_pairs p
    JOIN hamtdaa_pair_members own ON own.pair_id=p.id
      AND own.user_id=NEW.creator_id AND own.revoked_at IS NULL
    JOIN hamtdaa_pair_members other ON other.pair_id=p.id
      AND other.user_id<>own.user_id AND other.revoked_at IS NULL
    JOIN hamtdaa_profiles ap ON ap.user_id=own.user_id AND ap.account_state='active'
    JOIN hamtdaa_profiles op ON op.user_id=other.user_id AND op.account_state='active'
    JOIN "user" au ON au.id=own.user_id AND au.emailVerified=1
    JOIN "user" ou ON ou.id=other.user_id AND ou.emailVerified=1
    WHERE p.id=NEW.pair_id AND p.state='active'
      AND NOT EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts d
        WHERE d.user_id IN (own.user_id,other.user_id))
      AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b
        WHERE (b.blocker_id=own.user_id AND b.blocked_id=other.user_id)
           OR (b.blocker_id=other.user_id AND b.blocked_id=own.user_id))
  )
)
BEGIN SELECT RAISE(ABORT,'memory_pair_guard'); END;

CREATE TRIGGER hamtdaa_memory_delete_gc BEFORE DELETE ON hamtdaa_memories
BEGIN
  INSERT INTO hamtdaa_memory_gc(object_key,due_at,retain_until)
    VALUES(OLD.photo_key,CAST(strftime('%s','now') AS INTEGER)*1000+300000,
      CAST(strftime('%s','now') AS INTEGER)*1000+86400000)
    ON CONFLICT(object_key) DO UPDATE SET
      due_at=max(hamtdaa_memory_gc.due_at,excluded.due_at),
      retain_until=max(hamtdaa_memory_gc.retain_until,excluded.retain_until);
  INSERT INTO hamtdaa_memory_gc(object_key,due_at,retain_until)
    VALUES(OLD.thumbnail_key,CAST(strftime('%s','now') AS INTEGER)*1000+300000,
      CAST(strftime('%s','now') AS INTEGER)*1000+86400000)
    ON CONFLICT(object_key) DO UPDATE SET
      due_at=max(hamtdaa_memory_gc.due_at,excluded.due_at),
      retain_until=max(hamtdaa_memory_gc.retain_until,excluded.retain_until);
END;

-- Existing account deletion inserts this marker before unlinking membership.
-- These operations participate in that transaction without auth Worker changes.
CREATE TRIGGER hamtdaa_memory_account_delete AFTER INSERT ON hamtdaa_deleted_accounts
BEGIN
  DELETE FROM hamtdaa_memories WHERE creator_id=NEW.user_id;
  DELETE FROM hamtdaa_memory_receipts WHERE user_id=NEW.user_id;
  DELETE FROM hamtdaa_memory_quotas WHERE user_id=NEW.user_id;
END;

CREATE TRIGGER hamtdaa_memory_pair_unlink AFTER UPDATE OF state ON hamtdaa_pairs
WHEN NEW.state='unlinked' AND OLD.state<>'unlinked'
BEGIN
  DELETE FROM hamtdaa_memories WHERE pair_id=NEW.id;
END;
