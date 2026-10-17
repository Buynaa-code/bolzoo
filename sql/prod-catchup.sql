-- =============================================================================
-- BOLZOO PROD DB CATCH-UP MIGRATION
-- Target project: chmxjljudmwttwhemdri
-- Generated:     bolzoo qpay-integration branch
--
-- Тайлбар:
-- Prod дээр applied биш байгаа 5 migration-ийг нэгтгэсэн. Supabase Dashboard →
-- SQL Editor → New query цонхонд бүхлээр нь paste хийж Run. Бүх statement
-- idempotent (`if not exists`, `create or replace`, etc.) тул давхар ажиллуулж
-- болно.
--
-- Applied болсны дараа:
--   • public.invites-д private_config, response_history багана нэмэгдэнэ
--   • save_response(p_invite_id, p_response, p_client_ts) 3-arg overload үүснэ
--   • public.notifications хүснэгт үүснэ
--   • response history trigger идэвхжинэ
--   • _gen_code search_path pinned болно
-- =============================================================================


-- ── 1. 20260729120000_split_private_config.sql ───────────────────────────────
alter table public.invites
  add column if not exists private_config jsonb not null default '{}'::jsonb;

update public.invites
   set private_config = coalesce(private_config, '{}'::jsonb)
                          || jsonb_build_object('responseEmail', config->>'responseEmail'),
       config = config - 'responseEmail'
 where config ? 'responseEmail'
   and coalesce(nullif(trim(config->>'responseEmail'), ''), '') <> '';

update public.invites
   set config = config - 'responseEmail'
 where config ? 'responseEmail';

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


-- ── 2. 20260729130000_save_response_guard.sql ────────────────────────────────
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

  if existing_response is not null
     and coalesce(existing_response->>'final', 'false') = 'true' then
    return;
  end if;

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


-- ── 3. 20260729140000_notifications_table.sql ────────────────────────────────
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  invite_id   text not null references public.invites(id) on delete cascade,
  kind        text not null,
  to_email    text not null,
  sent_at     timestamptz,
  error       text,
  created_at  timestamptz not null default now(),
  unique (invite_id, kind)
);

create index if not exists notifications_invite_id_idx on public.notifications(invite_id);
create index if not exists notifications_pending_idx  on public.notifications(created_at)
  where sent_at is null;

alter table public.notifications enable row level security;

revoke all on table public.notifications from public, anon, authenticated;
grant select, insert, update, delete on table public.notifications to service_role;


-- ── 4. 20260729150000_response_history.sql ───────────────────────────────────
alter table public.invites
  add column if not exists response_history jsonb not null default '[]'::jsonb;

create or replace function public._append_response_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if OLD.response is not null and OLD.response is distinct from NEW.response then
    NEW.response_history := coalesce(OLD.response_history, '[]'::jsonb)
      || jsonb_build_array(
        jsonb_build_object(
          'response',     OLD.response,
          'responded_at', OLD.responded_at
        )
      );
  end if;
  return NEW;
end;
$$;

drop trigger if exists invites_response_history on public.invites;
create trigger invites_response_history
  before update of response on public.invites
  for each row
  execute function public._append_response_history();

revoke execute on function public._append_response_history()
  from public, anon, authenticated;


-- ── 5. 20260729160000_gen_code_search_path.sql ───────────────────────────────
create or replace function public._gen_code()
returns text
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  out_code text := 'LOV-';
  i int;
begin
  for i in 1..6 loop
    out_code := out_code || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return out_code;
end;
$$;

revoke execute on function public._gen_code()
  from public, anon, authenticated;


-- ── Final: PostgREST schema reload ──────────────────────────────────────────
notify pgrst, 'reload schema';
