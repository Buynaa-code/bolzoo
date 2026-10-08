-- Additive wish board. Existing auth, pair and calendar schema are unchanged.
-- Every mutation is committed with live pair and optimistic-version guards.
CREATE TABLE hamtdaa_wishes (
  id TEXT NOT NULL PRIMARY KEY CHECK(length(id)=36 AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^0-9a-f]*'),
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  creator_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 80),
  note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=500),
  location TEXT NOT NULL DEFAULT '' CHECK(length(location)<=120),
  category TEXT NOT NULL CHECK(category IN ('home','outdoor','food','travel','other')),
  budget TEXT NOT NULL CHECK(budget IN ('free','low','medium','high')),
  status TEXT NOT NULL DEFAULT 'idea' CHECK(status IN ('idea','planned','done')),
  event_id TEXT UNIQUE REFERENCES hamtdaa_calendar_events(id) ON DELETE SET NULL,
  version INTEGER NOT NULL DEFAULT 1 CHECK(typeof(version)='integer' AND version>0),
  created_at INTEGER NOT NULL CHECK(typeof(created_at)='integer' AND created_at>0),
  updated_at INTEGER NOT NULL CHECK(typeof(updated_at)='integer' AND updated_at>=created_at),
  CHECK((status='idea' AND event_id IS NULL) OR (status='planned' AND event_id IS NOT NULL) OR status='done')
);
CREATE INDEX hamtdaa_wishes_pair ON hamtdaa_wishes(pair_id,created_at DESC,id);
CREATE INDEX hamtdaa_wishes_creator ON hamtdaa_wishes(creator_id);
CREATE TABLE hamtdaa_wish_likes (
  wish_id TEXT NOT NULL REFERENCES hamtdaa_wishes(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  created_at INTEGER NOT NULL CHECK(typeof(created_at)='integer' AND created_at>0),
  PRIMARY KEY(wish_id,user_id)
);
CREATE INDEX hamtdaa_wish_likes_user ON hamtdaa_wish_likes(user_id);
CREATE TABLE hamtdaa_wish_receipts (
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL CHECK(length(command_id)=36),
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  operation TEXT NOT NULL CHECK(operation IN ('create','like','delete','plan','complete')),
  payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64 AND payload_hash NOT GLOB '*[^0-9a-f]*'),
  -- Tombstones intentionally survive wish and calendar deletion to prevent replay resurrection.
  wish_id TEXT NOT NULL,
  event_id TEXT,
  created_at INTEGER NOT NULL CHECK(typeof(created_at)='integer' AND created_at>0),
  PRIMARY KEY(user_id,command_id)
);
CREATE INDEX hamtdaa_wish_receipts_pair ON hamtdaa_wish_receipts(pair_id);
CREATE TABLE hamtdaa_wish_quotas (
  user_id TEXT NOT NULL PRIMARY KEY REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  day TEXT NOT NULL CHECK(day GLOB '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(day,'+0 days') IS NOT NULL AND date(day,'+0 days')=day),
  mutations INTEGER NOT NULL CHECK(typeof(mutations)='integer' AND mutations BETWEEN 1 AND 100)
);
CREATE TABLE hamtdaa_wish_guards (id TEXT NOT NULL PRIMARY KEY, allowed INTEGER NOT NULL CHECK(allowed=1));

CREATE TRIGGER hamtdaa_wish_insert_guard BEFORE INSERT ON hamtdaa_wishes
WHEN NEW.status<>'idea' OR NOT EXISTS (
  SELECT 1 FROM hamtdaa_pairs p
  JOIN hamtdaa_pair_members own ON own.pair_id=p.id AND own.user_id=NEW.creator_id AND own.revoked_at IS NULL
  JOIN hamtdaa_pair_members other ON other.pair_id=p.id AND other.user_id<>own.user_id AND other.revoked_at IS NULL
  JOIN hamtdaa_profiles ap ON ap.user_id=own.user_id AND ap.account_state='active'
  JOIN hamtdaa_profiles op ON op.user_id=other.user_id AND op.account_state='active'
  JOIN "user" au ON au.id=own.user_id AND au.emailVerified=1
  JOIN "user" ou ON ou.id=other.user_id AND ou.emailVerified=1
  WHERE p.id=NEW.pair_id AND p.state='active'
  AND NOT EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts d WHERE d.user_id IN (own.user_id,other.user_id))
  AND NOT EXISTS(SELECT 1 FROM hamtdaa_blocks b WHERE (b.blocker_id=own.user_id AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=own.user_id))
)
BEGIN SELECT RAISE(ABORT,'wish_pair_guard'); END;
CREATE TRIGGER hamtdaa_wish_identity_guard BEFORE UPDATE ON hamtdaa_wishes
WHEN NEW.id IS NOT OLD.id OR NEW.pair_id IS NOT OLD.pair_id OR NEW.creator_id IS NOT OLD.creator_id
  OR NEW.title IS NOT OLD.title OR NEW.note IS NOT OLD.note OR NEW.location IS NOT OLD.location
  OR NEW.category IS NOT OLD.category OR NEW.budget IS NOT OLD.budget OR NEW.created_at IS NOT OLD.created_at
  OR NEW.version<>OLD.version+1
BEGIN SELECT RAISE(ABORT,'wish_immutable'); END;
CREATE TRIGGER hamtdaa_wish_event_guard BEFORE UPDATE OF event_id ON hamtdaa_wishes
WHEN NEW.event_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hamtdaa_calendar_events e WHERE e.id=NEW.event_id AND e.pair_id=NEW.pair_id)
BEGIN SELECT RAISE(ABORT,'wish_event_scope'); END;
CREATE TRIGGER hamtdaa_wish_like_guard BEFORE INSERT ON hamtdaa_wish_likes
WHEN NOT EXISTS(SELECT 1 FROM hamtdaa_wishes w JOIN hamtdaa_pair_members m ON m.pair_id=w.pair_id AND m.user_id=NEW.user_id AND m.revoked_at IS NULL WHERE w.id=NEW.wish_id AND w.status='idea')
BEGIN SELECT RAISE(ABORT,'wish_like_scope'); END;

-- A calendar plan remains independent when an idea is removed. If its calendar
-- event is removed, the idea becomes plan-able again while its likes are retained.
CREATE TRIGGER hamtdaa_wish_calendar_delete BEFORE DELETE ON hamtdaa_calendar_events
BEGIN
  UPDATE hamtdaa_wishes SET status=CASE WHEN status='planned' THEN 'idea' ELSE status END,
    event_id=NULL,version=version+1,updated_at=max(updated_at,CAST(strftime('%s','now') AS INTEGER)*1000)
    WHERE event_id=OLD.id;
END;
CREATE TRIGGER hamtdaa_wish_account_delete AFTER INSERT ON hamtdaa_deleted_accounts
BEGIN
  DELETE FROM hamtdaa_wishes WHERE creator_id=NEW.user_id;
  DELETE FROM hamtdaa_wish_likes WHERE user_id=NEW.user_id;
  DELETE FROM hamtdaa_wish_receipts WHERE user_id=NEW.user_id;
  DELETE FROM hamtdaa_wish_quotas WHERE user_id=NEW.user_id;
END;
CREATE TRIGGER hamtdaa_wish_pair_unlink AFTER UPDATE OF state ON hamtdaa_pairs
WHEN NEW.state='unlinked' AND OLD.state<>'unlinked'
BEGIN
  DELETE FROM hamtdaa_wishes WHERE pair_id=NEW.id;
  DELETE FROM hamtdaa_wish_receipts WHERE pair_id=NEW.id;
END;
