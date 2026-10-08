-- Billing belongs to the purchasing identity. Partner access is derived from
-- current active memberships at read time, never copied to the partner.
CREATE TABLE hamtdaa_billing_orders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES "user"(id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL,
  plan TEXT NOT NULL CHECK(plan IN ('monthly','yearly')),
  duration_seconds INTEGER NOT NULL CHECK(duration_seconds IN (2592000,31536000)),
  amount_minor INTEGER NOT NULL CHECK(amount_minor IN (990000,7990000)),
  currency TEXT NOT NULL DEFAULT 'MNT' CHECK(currency='MNT'),
  livemode INTEGER NOT NULL CHECK(livemode IN (0,1)),
  return_url TEXT NOT NULL,
  description TEXT NOT NULL,
  provider_id TEXT UNIQUE,
  state TEXT NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','new','requires_payment_method','requires_action','requires_capture','processing','succeeded','canceled','refunded')),
  next_action TEXT CHECK(next_action IS NULL OR json_valid(next_action)),
  expires_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(user_id,command_id)
);
CREATE INDEX hamtdaa_billing_orders_owner ON hamtdaa_billing_orders(user_id,created_at);

CREATE TABLE hamtdaa_billing_grants (
  provider TEXT NOT NULL CHECK(provider IN ('wire','apple','google')),
  source_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES "user"(id) ON DELETE RESTRICT,
  transaction_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  starts_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL CHECK(expires_at>starts_at),
  revoked_at INTEGER,
  auto_renew INTEGER NOT NULL DEFAULT 0 CHECK(auto_renew IN (0,1)),
  observed_at INTEGER NOT NULL,
  PRIMARY KEY(provider,source_id)
);
CREATE INDEX hamtdaa_billing_grants_owner ON hamtdaa_billing_grants(user_id,expires_at);
CREATE TABLE hamtdaa_billing_transactions (
  provider TEXT NOT NULL CHECK(provider IN ('apple','google')),
  transaction_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES "user"(id) ON DELETE RESTRICT,
  PRIMARY KEY(provider,transaction_id)
);
CREATE TABLE hamtdaa_billing_events (
  provider TEXT NOT NULL CHECK(provider='wire'),
  event_id TEXT NOT NULL,
  order_id TEXT NOT NULL REFERENCES hamtdaa_billing_orders(id) ON DELETE RESTRICT,
  processed_at INTEGER NOT NULL,
  PRIMARY KEY(provider,event_id)
);
CREATE TABLE hamtdaa_billing_guards (
  id TEXT PRIMARY KEY,
  allowed INTEGER NOT NULL CHECK(allowed=1)
);
-- Frozen provider-create parameters cannot drift across retries or deploys.
CREATE TRIGGER hamtdaa_billing_order_immutable BEFORE UPDATE ON hamtdaa_billing_orders
WHEN NEW.user_id<>OLD.user_id OR NEW.command_id<>OLD.command_id OR NEW.plan<>OLD.plan
  OR NEW.duration_seconds<>OLD.duration_seconds OR NEW.amount_minor<>OLD.amount_minor
  OR NEW.currency<>OLD.currency OR NEW.livemode<>OLD.livemode
  OR NEW.return_url<>OLD.return_url OR NEW.description<>OLD.description
  OR NEW.created_at<>OLD.created_at
  OR (OLD.provider_id IS NOT NULL AND NEW.provider_id IS NOT OLD.provider_id)
BEGIN SELECT RAISE(ABORT,'billing_order_immutable'); END;
CREATE TRIGGER hamtdaa_billing_grant_owner_immutable BEFORE UPDATE ON hamtdaa_billing_grants
WHEN NEW.user_id<>OLD.user_id OR NEW.provider<>OLD.provider OR NEW.source_id<>OLD.source_id
BEGIN SELECT RAISE(ABORT,'billing_grant_owner_immutable'); END;
