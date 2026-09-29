-- Same code + same invite id returns the already-created invite after a lost response.
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
       and coalesce(p_config->>'apologyPaper', '') not in ('soft', 'dotted', 'grid', 'handmade', 'linen', 'clean') then
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
  if code_row.used then
    if code_row.used_for_invite_id = p_invite_id then
      return query select i.id, i.owner_token, i.created_at from public.invites i where i.id = p_invite_id;
      if found then return; end if;
    end if;
    raise exception 'Access code already used';
  end if;

  insert into public.invites(id, owner_token, config, private_config, created_at)
    values (
      p_invite_id,
      new_owner,
      p_config,
      p_private_config,
      now_ts
    );

  update public.access_codes
    set used = true, used_at = now_ts, used_for_invite_id = p_invite_id
    where code = p_access_code;

  return query select p_invite_id, new_owner, now_ts;
end;
$$;


revoke all on function public.create_invite_with_code(text, jsonb, text, jsonb) from public, authenticated;
grant execute on function public.create_invite_with_code(text, jsonb, text, jsonb) to anon;
notify pgrst, 'reload schema';
