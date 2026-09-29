-- Paper texture is an allowlisted public presentation choice. Readiness is
-- recipient-entered feedback, never an inferred score. Keep both inside the
-- existing JSONB payloads and validate at the narrow RPC boundary.

create or replace function public.create_invite_with_code(
  p_invite_id       text,
  p_config          jsonb,
  p_access_code     text,
  p_private_config  jsonb default '{}'::jsonb
)
returns table (id text, owner_token uuid, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  code_row public.access_codes%rowtype;
  new_owner uuid := gen_random_uuid();
  now_ts timestamptz := now();
  expiry_ts timestamptz;
begin
  if p_invite_id is null or length(p_invite_id) < 8 then raise exception 'Invalid invite id'; end if;
  if p_access_code is null or length(p_access_code) = 0 then raise exception 'Access code required'; end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object' or octet_length(p_config::text) > 32768 then
    raise exception 'Invalid invite config';
  end if;
  if p_private_config is null or jsonb_typeof(p_private_config) <> 'object' or octet_length(p_private_config::text) > 16384 then
    raise exception 'Invalid private config';
  end if;

  if p_config->>'experienceType' = 'apology' then
    if coalesce(p_config->>'apologyIssue', '') not in
       ('harsh_words', 'forgot', 'neglected', 'cancelled', 'jealousy', 'other') then
      raise exception 'Invalid apology issue';
    end if;
    if coalesce(p_config->>'apologyTone', '') not in ('short', 'gentle', 'serious') then
      raise exception 'Invalid apology tone';
    end if;
    if p_config ? 'apologyPaper'
       and coalesce(p_config->>'apologyPaper', '') not in
         ('soft', 'dotted', 'grid', 'handmade', 'linen', 'clean') then
      raise exception 'Invalid apology paper';
    end if;
    if length(trim(coalesce(p_config->>'apologyLetter', ''))) = 0
       or length(p_config->>'apologyLetter') > 5000 then
      raise exception 'Invalid apology letter';
    end if;
    begin
      expiry_ts := nullif(p_config->>'expiresAt', '')::timestamptz;
    exception when others then
      raise exception 'Invalid apology expiry';
    end;
    if expiry_ts is null or expiry_ts <= now_ts or expiry_ts > now_ts + interval '31 days' then
      raise exception 'Invalid apology expiry';
    end if;
  end if;

  select * into code_row from public.access_codes where code = p_access_code for update;
  if not found then raise exception 'Invalid access code'; end if;
  if code_row.used then raise exception 'Access code already used'; end if;

  insert into public.invites(id, owner_token, config, private_config, created_at)
    values (p_invite_id, new_owner, p_config, p_private_config, now_ts);

  update public.access_codes
    set used = true, used_at = now_ts, used_for_invite_id = p_invite_id
    where code = p_access_code;

  return query select p_invite_id, new_owner, now_ts;
end;
$$;

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
  invite_config     jsonb;
  existing_response jsonb;
  existing_ts       timestamptz;
  expiry_ts         timestamptz;
  readiness_percent integer;
begin
  if p_invite_id is null or length(p_invite_id) = 0 then raise exception 'Invite id required'; end if;
  if p_response is null or jsonb_typeof(p_response) <> 'object' or octet_length(p_response::text) > 16384 then
    raise exception 'Invalid response';
  end if;

  select config, response, responded_at
    into invite_config, existing_response, existing_ts
    from public.invites
   where id = p_invite_id;
  if not found then raise exception 'Invite not found'; end if;

  if invite_config->>'experienceType' = 'apology' then
    begin
      expiry_ts := nullif(invite_config->>'expiresAt', '')::timestamptz;
    exception when others then
      raise exception 'Invalid apology expiry';
    end;
    if expiry_ts is null or expiry_ts <= now() then raise exception 'Invite expired'; end if;
    if p_response->>'type' <> 'apology'
       or coalesce(p_response->>'status', '') not in ('needs_space', 'read', 'message', 'meet', 'stop') then
      raise exception 'Invalid apology response';
    end if;
    if p_response ? 'readinessPercent' then
      if jsonb_typeof(p_response->'readinessPercent') <> 'number'
         or coalesce(p_response->>'readinessPercent', '') !~ '^(0|[1-9][0-9]?|100)$' then
        raise exception 'Invalid apology readiness';
      end if;
      readiness_percent := (p_response->>'readinessPercent')::integer;
      if mod(readiness_percent, 10) <> 0 then raise exception 'Invalid apology readiness'; end if;
      if p_response->>'status' = 'stop' and readiness_percent <> 0 then
        raise exception 'Stop readiness must be zero';
      end if;
    end if;
    if coalesce(p_response->>'final', 'false') = 'true' and p_response->>'status' <> 'stop' then
      raise exception 'Only stop may be final';
    end if;
  end if;

  if existing_response is not null and coalesce(existing_response->>'final', 'false') = 'true' then return; end if;
  if p_client_ts is not null and existing_ts is not null and existing_ts > p_client_ts then return; end if;

  update public.invites
     set response = p_response,
         responded_at = now()
   where id = p_invite_id;
end;
$$;

revoke execute on function public.create_invite_with_code(text, jsonb, text, jsonb)
  from public, authenticated, service_role;
revoke execute on function public.save_response(text, jsonb, timestamptz)
  from public, authenticated, service_role;
grant execute on function public.create_invite_with_code(text, jsonb, text, jsonb) to anon;
grant execute on function public.save_response(text, jsonb, timestamptz) to anon;

notify pgrst, 'reload schema';
