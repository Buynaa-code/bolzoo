-- Fix: admin login failed with `42883 function crypt(text, text) does not exist`.
--
-- Supabase installs pgcrypto into the `extensions` schema, not `public`. Pinning
-- this function to `set search_path = public` therefore hid crypt() from its own
-- body, and every admin_* RPC that gates on _check_admin_pw returned 42883.
-- `create extension if not exists "pgcrypto"` does not help — the extension is
-- already installed, just in another schema, so the statement is a no-op.
--
-- gen_random_uuid() is core Postgres (pg_catalog), not pgcrypto, which is why
-- invite creation kept working and only the admin surface broke.
--
-- Keeping `public` first preserves the existing unqualified table references.

create or replace function public._check_admin_pw(admin_pw text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  stored_pw text;
begin
  select value into stored_pw from public.admin_settings where key = 'admin_password';
  if stored_pw is null then
    raise exception 'Admin password not set. Run: insert into admin_settings(key,value) values (''admin_password'', crypt(''your-secret'', gen_salt(''bf'',10))) on conflict (key) do update set value = excluded.value;';
  end if;
  if admin_pw is null or crypt(admin_pw, stored_pw) <> stored_pw then
    raise exception 'Invalid admin password';
  end if;
end;
$$;

notify pgrst, 'reload schema';
