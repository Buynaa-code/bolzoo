-- Make save_response safe against stale retries and against overwriting a
-- response the guest has explicitly marked final.
--
-- Semantics:
--   * If the invite doesn't exist, error.
--   * If the existing response has {"final": true}, silently no-op — the
--     guest's committed answer wins, even if a background retry fires later.
--   * If p_client_ts is provided AND responded_at is newer than p_client_ts,
--     silently no-op — this is a stale retry from an offline queue.
--   * Otherwise, overwrite response and set responded_at = now().
--
-- p_client_ts defaults to null so existing clients that call the 2-arg form
-- keep working (last-write-wins for legacy callers, guard active for new ones).

drop function if exists public.save_response(text, jsonb);

create or replace function public.save_response(
  p_invite_id  text,
  p_response   jsonb,
  p_client_ts  timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_response jsonb;
  existing_ts       timestamptz;
begin
  if p_invite_id is null or length(p_invite_id) = 0 then
    raise exception 'Invite id required';
  end if;

  select response, responded_at
    into existing_response, existing_ts
    from public.invites
   where id = p_invite_id;

  if not found then
    raise exception 'Invite not found';
  end if;

  -- Locked final answer wins.
  if existing_response is not null
     and coalesce(existing_response->>'final', 'false') = 'true' then
    return;
  end if;

  -- Stale retry from an offline queue.
  if p_client_ts is not null
     and existing_ts is not null
     and existing_ts > p_client_ts then
    return;
  end if;

  update public.invites
     set response = p_response,
         responded_at = now()
   where id = p_invite_id;
end;
$$;

revoke execute on function public.save_response(text, jsonb, timestamptz)
  from public, authenticated;
grant execute on function public.save_response(text, jsonb, timestamptz)
  to anon;

notify pgrst, 'reload schema';
