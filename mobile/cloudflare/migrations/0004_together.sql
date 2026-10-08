-- Shared records belong to one immutable pair; access always checks live membership.
CREATE TABLE hamtdaa_calendar_events (
  id TEXT PRIMARY KEY,
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  creator_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 120),
  note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=2000),
  location TEXT NOT NULL DEFAULT '' CHECK(length(location)<=200),
  starts_at INTEGER NOT NULL,
  ends_at INTEGER CHECK(ends_at IS NULL OR (ends_at>starts_at AND ends_at-starts_at<=2678400000)),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','declined')),
  version INTEGER NOT NULL DEFAULT 1 CHECK(version>0),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX hamtdaa_calendar_pair_start ON hamtdaa_calendar_events(pair_id,starts_at,id);

CREATE TABLE hamtdaa_daily_answers (
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  day TEXT NOT NULL CHECK(length(day)=10),
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  question_id TEXT NOT NULL,
  answer TEXT NOT NULL CHECK(length(trim(answer)) BETWEEN 1 AND 2000),
  created_at INTEGER NOT NULL,
  PRIMARY KEY(pair_id,day,user_id)
);
-- Answer changes would let someone inspect their partner's answer then rewrite.
CREATE TRIGGER hamtdaa_daily_answers_immutable BEFORE UPDATE ON hamtdaa_daily_answers
BEGIN SELECT RAISE(ABORT,'daily_answer_immutable'); END;

CREATE TABLE hamtdaa_together_receipts (
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL,
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64),
  operation TEXT NOT NULL,
  day TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(user_id,command_id)
);
CREATE INDEX hamtdaa_together_receipts_daily ON hamtdaa_together_receipts(user_id,day,operation);
CREATE TABLE hamtdaa_together_quotas (
  user_id TEXT PRIMARY KEY REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  day TEXT NOT NULL,
  mutations INTEGER NOT NULL CHECK(mutations BETWEEN 1 AND 100)
);
CREATE TABLE hamtdaa_together_guards (
  id TEXT PRIMARY KEY,
  allowed INTEGER NOT NULL CHECK(allowed=1)
);
