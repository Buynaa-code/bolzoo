-- Store the admin password as a bcrypt hash instead of plaintext, and compare
-- with a constant-time crypt() check. pgcrypto is already enabled in schema.sql.
--
-- Backfill: any existing admin_settings.value that is NOT already a bcrypt hash
-- ($2a$/$2b$/$2y$…) is treated as plaintext and rehashed in place. Running this
-- migration a second time is a no-op because rehashing an already-bcrypt string
-- would not match the pattern.

update public.admin_settings
   set value = crypt(value, gen_salt('bf', 10))
 where key = 'admin_password'
   and value is not null
   and value !~ '^\$2[aby]\$';

create or replace function public._check_admin_pw(admin_pw text)
returns void
language plpgsql
security definer
set search_path = public
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

revoke execute on function public._check_admin_pw(text)
  from public, anon, authenticated;

notify pgrst, 'reload schema';
