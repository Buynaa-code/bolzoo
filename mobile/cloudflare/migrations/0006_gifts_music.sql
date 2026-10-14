-- A gift is private to one immutable, mutually accepted pair. Unlinking never
-- grants a new partner access. Names are joined live rather than copied here.
CREATE TABLE hamtdaa_flower_gifts (
  id TEXT PRIMARY KEY,
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  sender_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  recipient_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  template_id TEXT NOT NULL CHECK(template_id IN ('letter','garden','bloom')),
  color_id TEXT NOT NULL CHECK(color_id IN ('rose','sage','peach')),
  occasion TEXT NOT NULL CHECK(occasion IN ('Зүгээр л','Төрсөн өдөр','Баярлалаа')),
  message TEXT NOT NULL CHECK(length(trim(message)) BETWEEN 1 AND 500),
  created_at INTEGER NOT NULL,
  CHECK(sender_id<>recipient_id)
);
CREATE INDEX hamtdaa_flower_gifts_page ON hamtdaa_flower_gifts(pair_id,created_at DESC,id DESC);
CREATE TABLE hamtdaa_gift_receipts (
  user_id TEXT NOT NULL REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL,
  pair_id TEXT NOT NULL REFERENCES hamtdaa_pairs(id) ON DELETE RESTRICT,
  gift_id TEXT NOT NULL,
  payload_hash TEXT NOT NULL CHECK(length(payload_hash)=64),
  operation TEXT NOT NULL CHECK(operation IN ('send','delete')),
  day TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(user_id,command_id)
);
CREATE INDEX hamtdaa_gift_receipts_daily ON hamtdaa_gift_receipts(user_id,day,operation);
CREATE TABLE hamtdaa_gift_quotas (
  user_id TEXT PRIMARY KEY REFERENCES hamtdaa_profiles(user_id) ON DELETE RESTRICT,
  day TEXT NOT NULL,
  mutations INTEGER NOT NULL CHECK(mutations BETWEEN 1 AND 60)
);
CREATE TABLE hamtdaa_gift_guards (
  id TEXT PRIMARY KEY,
  allowed INTEGER NOT NULL CHECK(allowed=1)
);
-- Only public YouTube metadata is stored; never audio, arbitrary URLs, or tokens.
ALTER TABLE hamtdaa_calendar_events ADD COLUMN music_json TEXT
 CHECK(music_json IS NULL OR (json_valid(music_json) AND length(music_json)<=2000));
CREATE TABLE hamtdaa_music_limits (
  scope TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  attempts INTEGER NOT NULL CHECK(attempts>0)
);
