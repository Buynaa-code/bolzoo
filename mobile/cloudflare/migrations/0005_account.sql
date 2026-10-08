-- Only opaque ownership markers survive personal-data deletion, so a previous
-- store receipt cannot be claimed by a new account using the same email.
CREATE TABLE hamtdaa_deleted_accounts (
  user_id TEXT PRIMARY KEY REFERENCES "user"(id) ON DELETE RESTRICT,
  deleted_at INTEGER NOT NULL
);
CREATE TABLE hamtdaa_account_guards (
  id TEXT PRIMARY KEY,
  allowed INTEGER NOT NULL CHECK(allowed=1)
);
CREATE TABLE hamtdaa_account_export_limits (
  user_id TEXT PRIMARY KEY REFERENCES "user"(id) ON DELETE RESTRICT,
  window_start INTEGER NOT NULL,
  attempts INTEGER NOT NULL CHECK(attempts>0)
);

-- An auth request already in flight must not recreate access after deletion.
CREATE TRIGGER hamtdaa_deleted_session_insert BEFORE INSERT ON "session"
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.userId)
BEGIN SELECT RAISE(ABORT,'account_deleted'); END;
CREATE TRIGGER hamtdaa_deleted_session_update BEFORE UPDATE ON "session"
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.userId)
BEGIN SELECT RAISE(ABORT,'account_deleted'); END;
CREATE TRIGGER hamtdaa_deleted_auth_account_insert BEFORE INSERT ON "account"
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.userId)
BEGIN SELECT RAISE(ABORT,'account_deleted'); END;
CREATE TRIGGER hamtdaa_deleted_auth_account_update BEFORE UPDATE ON "account"
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.userId)
BEGIN SELECT RAISE(ABORT,'account_deleted'); END;
CREATE TRIGGER hamtdaa_deleted_user_update BEFORE UPDATE ON "user"
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.id)
  AND (NEW.emailVerified<>0 OR NEW.image IS NOT NULL OR NEW.name<>'Deleted account'
    OR NEW.email NOT GLOB 'deleted-*@deleted.invalid')
BEGIN SELECT RAISE(ABORT,'account_deleted'); END;
CREATE TRIGGER hamtdaa_deleted_profile_update BEFORE UPDATE ON hamtdaa_profiles
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.user_id)
  AND (NEW.account_state<>'disabled' OR NEW.display_name<>'Устгасан бүртгэл')
BEGIN SELECT RAISE(ABORT,'account_deleted'); END;

-- Delayed verified receipts may still update audit/refund records, but cannot
-- restore stored provider secrets or active entitlement to a deleted owner.
CREATE TRIGGER hamtdaa_deleted_grant_insert AFTER INSERT ON hamtdaa_billing_grants
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.user_id)
  AND (NEW.refresh_cipher IS NOT NULL OR NEW.is_active<>0)
BEGIN UPDATE hamtdaa_billing_grants SET refresh_cipher=NULL,is_active=0
  WHERE provider=NEW.provider AND source_id=NEW.source_id; END;
CREATE TRIGGER hamtdaa_deleted_grant_update AFTER UPDATE ON hamtdaa_billing_grants
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.user_id)
  AND (NEW.refresh_cipher IS NOT NULL OR NEW.is_active<>0)
BEGIN UPDATE hamtdaa_billing_grants SET refresh_cipher=NULL,is_active=0
  WHERE provider=NEW.provider AND source_id=NEW.source_id; END;

-- Checkout bearer URLs must be erased without weakening frozen charge data.
DROP TRIGGER hamtdaa_billing_order_immutable;
CREATE TRIGGER hamtdaa_billing_order_immutable BEFORE UPDATE ON hamtdaa_billing_orders
WHEN NEW.user_id<>OLD.user_id OR NEW.command_id<>OLD.command_id OR NEW.plan<>OLD.plan
  OR NEW.duration_seconds<>OLD.duration_seconds OR NEW.amount_minor<>OLD.amount_minor
  OR NEW.currency<>OLD.currency OR NEW.livemode<>OLD.livemode
  OR NEW.return_url<>OLD.return_url OR NEW.description<>OLD.description
  OR NEW.created_at<>OLD.created_at
  OR (OLD.provider_id IS NOT NULL AND NEW.provider_id IS NOT OLD.provider_id)
  OR (OLD.checkout_url IS NOT NULL AND NEW.checkout_url IS NOT OLD.checkout_url
    AND NOT (NEW.checkout_url IS NULL AND EXISTS(
      SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.user_id)))
BEGIN SELECT RAISE(ABORT,'billing_order_immutable'); END;
CREATE TRIGGER hamtdaa_deleted_order_insert AFTER INSERT ON hamtdaa_billing_orders
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.user_id)
  AND (NEW.checkout_url IS NOT NULL OR NEW.next_action IS NOT NULL)
BEGIN UPDATE hamtdaa_billing_orders SET checkout_url=NULL,next_action=NULL WHERE id=NEW.id; END;
CREATE TRIGGER hamtdaa_deleted_order_update AFTER UPDATE ON hamtdaa_billing_orders
WHEN EXISTS(SELECT 1 FROM hamtdaa_deleted_accounts WHERE user_id=NEW.user_id)
  AND (NEW.checkout_url IS NOT NULL OR NEW.next_action IS NOT NULL)
BEGIN UPDATE hamtdaa_billing_orders SET checkout_url=NULL,next_action=NULL WHERE id=NEW.id; END;
