-- The browser now reads through narrow server-side endpoints.
drop policy if exists "anon can select invites" on public.invites;
drop policy if exists "anon can select access codes" on public.access_codes;
drop policy if exists "anon can select payments" on public.payments;

revoke all on table public.invites from public, anon, authenticated;
revoke all on table public.access_codes from public, anon, authenticated;
revoke all on table public.payments from public, anon, authenticated;
revoke all on table public.admin_settings from public, anon, authenticated;
revoke all on table public.webhook_events from public, anon, authenticated;

grant select, insert, update, delete
  on table public.invites,
           public.access_codes,
           public.payments,
           public.admin_settings,
           public.webhook_events
  to service_role;

-- Stop future public objects from becoming reachable accidentally.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions
  from public, anon, authenticated, service_role;

-- Remove PostgreSQL's default PUBLIC execute privilege from every RPC.
revoke execute on function public._check_admin_pw(text)
  from public, anon, authenticated;
revoke execute on function public._gen_code()
  from public, anon, authenticated;

revoke execute on function public.create_invite_with_code(text, jsonb, text)
  from public, authenticated;
revoke execute on function public.save_response(text, jsonb)
  from public, authenticated;
revoke execute on function public.mark_opened(text)
  from public, authenticated;
revoke execute on function public.delete_own_invite(text, uuid)
  from public, authenticated;
revoke execute on function public.admin_create_codes(text, int, text)
  from public, authenticated;
revoke execute on function public.admin_list_codes(text)
  from public, authenticated;
revoke execute on function public.admin_delete_code(text, text)
  from public, authenticated;

grant usage on schema public to anon, service_role;
grant execute on function public.create_invite_with_code(text, jsonb, text) to anon;
grant execute on function public.save_response(text, jsonb) to anon;
grant execute on function public.mark_opened(text) to anon;
grant execute on function public.delete_own_invite(text, uuid) to anon;
grant execute on function public.admin_create_codes(text, int, text) to anon;
grant execute on function public.admin_list_codes(text) to anon;
grant execute on function public.admin_delete_code(text, text) to anon;
grant execute on function public.process_wire_event(text, text, text, jsonb) to service_role;

notify pgrst, 'reload schema';
