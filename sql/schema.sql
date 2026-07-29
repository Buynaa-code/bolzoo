-- Bolzoo Supabase schema
-- Run this in Supabase SQL editor: https://supabase.com/dashboard/project/_/sql/new
--
-- After running this file:
--   1. Set your admin password:
--        insert into public.admin_settings(key, value) values ('admin_password', 'YOUR-SECRET-HERE')
--        on conflict (key) do update set value = excluded.value;
--   2. Open admin.html, log in with that password, generate codes.
--   3. Give a code to each customer who pays via bank transfer.

create extension if not exists "pgcrypto";

/* ---------- invites ---------- */

create table if not exists public.invites (
  id             text primary key,           -- short public ID, e.g. "aB3xK9zQ"
  owner_token    uuid not null default gen_random_uuid(),
  config         jsonb not null,             -- PUBLIC: recipient name, sender, videoId, theme, etc
  private_config jsonb not null default '{}'::jsonb, -- OWNER-ONLY: responseEmail, notes, etc
  response       jsonb,                      -- filled when recipient answers
  opened_at      timestamptz,                -- first time recipient opened link
  responded_at   timestamptz,
  created_at     timestamptz not null default now()
);

-- Existing installs upgrade path.
alter table public.invites
  add column if not exists private_config jsonb not null default '{}'::jsonb;

create index if not exists invites_created_at_idx on public.invites (created_at desc);

alter table public.invites enable row level security;

-- Anon cannot insert invites directly anymore — they must go through create_invite_with_code RPC.
drop policy if exists "anon can insert invites" on public.invites;

-- Direct table reads are blocked. Public config is returned by /api/invite.
drop policy if exists "anon can select invites" on public.invites;

-- Anon UPDATE-ыг зөвшөөрөхгүй — хариу болон нээсэн тэмдгийг save_response / mark_opened RPC дамжуулна.
drop policy if exists "anon can update response" on public.invites;

-- Anon DELETE-ыг зөвшөөрөхгүй — устгал delete_own_invite RPC дамжуулна.
drop policy if exists "anon can delete own invites" on public.invites;

/* ---------- admin_settings (private) ---------- */

create table if not exists public.admin_settings (
  key   text primary key,
  value text
);
alter table public.admin_settings enable row level security;
-- No policies for anon = totally hidden from public

/* ---------- access_codes ---------- */

create table if not exists public.access_codes (
  code                text primary key,           -- e.g. "LOV-8K3M2P"
  used                boolean not null default false,
  used_at             timestamptz,
  used_for_invite_id  text references public.invites(id) on delete set null,
  note                text,                       -- admin note: buyer name, contact, amount, etc
  created_at          timestamptz not null default now()
);

create index if not exists access_codes_created_at_idx on public.access_codes (created_at desc);
create index if not exists access_codes_used_idx on public.access_codes (used);

alter table public.access_codes enable row level security;

-- Direct table reads are blocked. Exact-code validation uses /api/validate-code.
drop policy if exists "anon can select access codes" on public.access_codes;

-- No anon insert/update/delete — those go through RPCs (admin_* + create_invite_with_code)

/* ---------- Helpers ---------- */

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

create or replace function public._gen_code()
returns text
language plpgsql
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no I, O, 0, 1
  out_code text := 'LOV-';
  i int;
begin
  for i in 1..6 loop
    out_code := out_code || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return out_code;
end;
$$;

/* ---------- RPCs ---------- */

-- Redeem a code and create an invite in one atomic step.
-- Called from create.html when the buyer submits their invite form.
-- p_private_config carries owner-only fields (e.g. responseEmail) so they never
-- reach the public /api/invite GET response.
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
  now_ts timestamptz := now();
begin
  if p_invite_id is null or length(p_invite_id) < 8 then raise exception 'Invalid invite id'; end if;
  if p_access_code is null or length(p_access_code) = 0 then raise exception 'Access code required'; end if;

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
    set used = true, used_at = now_ts, used_for_invite_id = p_invite_id
    where code = p_access_code;

  return query select p_invite_id, new_owner, now_ts;
end;
$$;

grant execute on function public.create_invite_with_code(text, jsonb, text, jsonb) to anon;

-- Recipient: хариугаа хадгална. p_client_ts дамжуулж илгээвэл хожуу stale retry
-- эсвэл response.final = true болсон хариуг дарж бичихгүй.
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

grant execute on function public.save_response(text, jsonb, timestamptz) to anon;

-- Recipient: анх удаа нээхэд opened_at тэмдэглэнэ (дахин дарж бичихгүй).
create or replace function public.mark_opened(p_invite_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invite_id is null or length(p_invite_id) = 0 then return; end if;
  update public.invites
    set opened_at = now()
    where id = p_invite_id and opened_at is null;
end;
$$;

grant execute on function public.mark_opened(text) to anon;

-- Owner (dashboard): өөрийн урилгыг owner_token дамжуулан устгана.
create or replace function public.delete_own_invite(
  p_invite_id   text,
  p_owner_token uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invite_id is null or p_owner_token is null then raise exception 'invite id and owner token required'; end if;
  delete from public.invites
    where id = p_invite_id and owner_token = p_owner_token;
  if not found then raise exception 'Invite not found or wrong owner token'; end if;
end;
$$;

grant execute on function public.delete_own_invite(text, uuid) to anon;

-- Admin: create N new codes at once.
create or replace function public.admin_create_codes(
  admin_pw text,
  qty      int,
  note_    text default null
)
returns setof public.access_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  i int;
  new_code text;
  created_codes text[] := '{}';
begin
  perform public._check_admin_pw(admin_pw);
  if qty is null or qty < 1 or qty > 100 then raise exception 'qty must be between 1 and 100'; end if;

  for i in 1..qty loop
    -- retry in the unlikely event of collision
    loop
      new_code := public._gen_code();
      begin
        insert into public.access_codes(code, note) values (new_code, note_);
        exit;
      exception when unique_violation then
        -- try again
      end;
    end loop;
    created_codes := created_codes || new_code;
  end loop;

  return query select * from public.access_codes where code = any(created_codes) order by created_at desc;
end;
$$;

grant execute on function public.admin_create_codes(text, int, text) to anon;

-- Admin: list all codes.
create or replace function public.admin_list_codes(admin_pw text)
returns setof public.access_codes
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._check_admin_pw(admin_pw);
  return query select * from public.access_codes order by created_at desc;
end;
$$;

grant execute on function public.admin_list_codes(text) to anon;

-- Admin: delete an unused code (used codes stay for audit).
create or replace function public.admin_delete_code(admin_pw text, p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._check_admin_pw(admin_pw);
  delete from public.access_codes where code = p_code and used = false;
  if not found then raise exception 'Code not found or already used'; end if;
end;
$$;

grant execute on function public.admin_delete_code(text, text) to anon;

/* ---------- payments (self-serve QPay via wire.mn) ---------- */

create table if not exists public.payments (
  id                  text primary key,               -- wire.mn payment_intent id (жишээ: obj_1a2b3c)
  status              text not null default 'pending',-- new | requires_action | processing | succeeded | canceled | failed
  amount              integer not null,               -- MNT ₮ (minor units)
  currency            text not null default 'MNT',
  provider            text not null default 'wire',   -- 'wire' | 'mock'
  provider_intent_id  text,                           -- wire.mn intent id (id-тай ижил)
  client_secret       text,
  next_action         jsonb,                          -- QR / deeplink payload
  code                text references public.access_codes(code) on delete set null,
  email               text,
  raw_event           jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  expires_at          timestamptz
);

create index if not exists payments_status_idx     on public.payments (status);
create index if not exists payments_created_at_idx on public.payments (created_at desc);

alter table public.payments enable row level security;

-- Payment polling uses /api/payment-status with the server-side service role.
drop policy if exists "anon can select payments" on public.payments;

-- No anon insert/update/delete — backend endpoint-ууд (server.js эсвэл Vercel function) service_role-оор гүйцэтгэнэ.

/* ---------- webhook_events (idempotency) ---------- */

create table if not exists public.webhook_events (
  id            text primary key,   -- wire.mn event id
  type          text not null,
  intent_id     text,
  raw           jsonb,
  processed_at  timestamptz not null default now()
);

alter table public.webhook_events enable row level security;
-- Backend only (service_role). Anon-д ямар ч policy байхгүй.

/* ---------- notifications (email outbox) ---------- */

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  invite_id   text not null references public.invites(id) on delete cascade,
  kind        text not null,             -- 'response' | future kinds
  to_email    text not null,
  sent_at     timestamptz,
  error       text,
  created_at  timestamptz not null default now(),
  unique (invite_id, kind)                -- idempotency: one email per (invite, kind)
);

create index if not exists notifications_invite_id_idx on public.notifications(invite_id);
create index if not exists notifications_pending_idx  on public.notifications(created_at)
  where sent_at is null;

alter table public.notifications enable row level security;
-- Backend only (service_role). Never queryable by anon.

/* ---------- access_codes нэмэлт талбар (self-serve tracking) ---------- */

alter table public.access_codes add column if not exists source     text;    -- 'admin' | 'self_service'
alter table public.access_codes add column if not exists payment_id text references public.payments(id) on delete set null;

create unique index if not exists access_codes_payment_id_unique_idx
  on public.access_codes (payment_id)
  where payment_id is not null;

/* ---------- Verified webhook processing ---------- */

create or replace function public.process_wire_event(
  p_event_id  text,
  p_type      text,
  p_intent_id text,
  p_raw       jsonb
)
returns table (
  processed     boolean,
  payment_found boolean,
  new_status    text
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_inserted integer := 0;
  v_updated integer := 0;
  v_status text;
begin
  if p_event_id is null or length(p_event_id) = 0 then
    raise exception 'event id required';
  end if;

  insert into public.webhook_events(id, type, intent_id, raw)
  values (p_event_id, coalesce(p_type, ''), p_intent_id, p_raw)
  on conflict (id) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    return query select false, true, null::text;
    return;
  end if;

  v_status := case p_type
    when 'payment_intent.succeeded' then 'succeeded'
    when 'charge.succeeded' then 'succeeded'
    when 'payment_intent.canceled' then 'canceled'
    when 'payment_intent.payment_failed' then 'failed'
    when 'charge.failed' then 'failed'
    else null
  end;

  if v_status is null or p_intent_id is null then
    return query select true, false, null::text;
    return;
  end if;

  update public.payments
  set status = v_status,
      raw_event = p_raw,
      updated_at = now()
  where id = p_intent_id;
  get diagnostics v_updated = row_count;

  return query select true, (v_updated = 1), v_status;
end;
$$;

/* ---------- Least-privilege Data API grants ---------- */

revoke all on table public.invites from public, anon, authenticated;
revoke all on table public.access_codes from public, anon, authenticated;
revoke all on table public.payments from public, anon, authenticated;
revoke all on table public.admin_settings from public, anon, authenticated;
revoke all on table public.webhook_events from public, anon, authenticated;
revoke all on table public.notifications from public, anon, authenticated;

grant select, insert, update, delete
  on table public.invites,
           public.access_codes,
           public.payments,
           public.admin_settings,
           public.webhook_events,
           public.notifications
  to service_role;

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences
  from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions
  from public, anon, authenticated, service_role;

revoke execute on function public._check_admin_pw(text)
  from public, anon, authenticated;
revoke execute on function public._gen_code()
  from public, anon, authenticated;
revoke execute on function public.create_invite_with_code(text, jsonb, text, jsonb)
  from public, authenticated;
revoke execute on function public.save_response(text, jsonb, timestamptz)
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
revoke all on function public.process_wire_event(text, text, text, jsonb)
  from public, anon, authenticated;

grant usage on schema public to anon, service_role;
grant execute on function public.create_invite_with_code(text, jsonb, text, jsonb) to anon;
grant execute on function public.save_response(text, jsonb, timestamptz) to anon;
grant execute on function public.mark_opened(text) to anon;
grant execute on function public.delete_own_invite(text, uuid) to anon;
grant execute on function public.admin_create_codes(text, int, text) to anon;
grant execute on function public.admin_list_codes(text) to anon;
grant execute on function public.admin_delete_code(text, text) to anon;
grant execute on function public.process_wire_event(text, text, text, jsonb) to service_role;

-- Force PostgREST to reload its schema cache so new tables/functions are picked up immediately.
NOTIFY pgrst, 'reload schema';
