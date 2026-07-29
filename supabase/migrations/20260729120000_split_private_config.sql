-- Split owner-only fields (e.g. responseEmail) out of the public `config` JSONB
-- so /api/invite public GET can never leak them. Also tightens the min invite id
-- length inside create_invite_with_code from 4 to 8 to make brute-force guessing
-- of invite URLs practically infeasible.

alter table public.invites
  add column if not exists private_config jsonb not null default '{}'::jsonb;

-- One-shot backfill: move responseEmail out of public config into private_config.
-- Idempotent: only touches rows where responseEmail still exists in `config`.
update public.invites
   set private_config = coalesce(private_config, '{}'::jsonb)
                          || jsonb_build_object('responseEmail', config->>'responseEmail'),
       config = config - 'responseEmail'
 where config ? 'responseEmail'
   and coalesce(nullif(trim(config->>'responseEmail'), ''), '') <> '';

-- Also drop the key without copying if it's present but empty (garbage cleanup).
update public.invites
   set config = config - 'responseEmail'
 where config ? 'responseEmail';

-- Replace create_invite_with_code with a 4-arg version that accepts private_config.
-- The 4th arg defaults to '{}' so existing PostgREST clients that send only three
-- named arguments still resolve to this function.
drop function if exists public.create_invite_with_code(text, jsonb, text);

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
  now_ts    timestamptz := now();
begin
  if p_invite_id is null or length(p_invite_id) < 8 then
    raise exception 'Invalid invite id';
  end if;
  if p_access_code is null or length(p_access_code) = 0 then
    raise exception 'Access code required';
  end if;

  select * into code_row from public.access_codes where code = p_access_code for update;
  if not found then raise exception 'Invalid access code'; end if;
  if code_row.used then raise exception 'Access code already used'; end if;

  insert into public.invites(id, owner_token, config, private_config, created_at)
    values (
      p_invite_id,
      new_owner,
      coalesce(p_config, '{}'::jsonb),
      coalesce(p_private_config, '{}'::jsonb),
      now_ts
    );

  update public.access_codes
     set used = true,
         used_at = now_ts,
         used_for_invite_id = p_invite_id
   where code = p_access_code;

  return query select p_invite_id, new_owner, now_ts;
end;
$$;

revoke execute on function public.create_invite_with_code(text, jsonb, text, jsonb)
  from public, authenticated;
grant execute on function public.create_invite_with_code(text, jsonb, text, jsonb)
  to anon;

notify pgrst, 'reload schema';
