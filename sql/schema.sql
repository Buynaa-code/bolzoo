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
  id            text primary key,           -- short public ID, e.g. "aB3xK9zQ"
  owner_token   uuid not null default gen_random_uuid(),
  config        jsonb not null,             -- recipient name, sender, videoId, theme, etc
  response      jsonb,                      -- filled when recipient answers
  opened_at     timestamptz,                -- first time recipient opened link
  responded_at  timestamptz,
  created_at    timestamptz not null default now()
);

create index if not exists invites_created_at_idx on public.invites (created_at desc);

alter table public.invites enable row level security;

-- Anon cannot insert invites directly anymore — they must go through create_invite_with_code RPC.
drop policy if exists "anon can insert invites" on public.invites;

-- Anyone (anon) can SELECT config by id
drop policy if exists "anon can select invites" on public.invites;
create policy "anon can select invites"
  on public.invites for select
  to anon
  using (true);

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

-- Багц: 'basic' (9,900₮) | 'premium' (14,900₮).
-- Аль хэдийн зарагдсан хуучин кодыг доошлуулахгүйн тулд default нь 'premium'.
-- Багцын агуулгыг assets/bolzoo-plans.js-тэй ЗЭРЭГ шинэчилж байх ёстой.
alter table public.access_codes
  add column if not exists plan text not null default 'premium';

alter table public.access_codes drop constraint if exists access_codes_plan_check;
alter table public.access_codes
  add constraint access_codes_plan_check check (plan in ('basic','premium'));

create index if not exists access_codes_created_at_idx on public.access_codes (created_at desc);
create index if not exists access_codes_used_idx on public.access_codes (used);

alter table public.access_codes enable row level security;

-- Anon can SELECT to validate a code before submitting (client checks used=false, code=X)
drop policy if exists "anon can select access codes" on public.access_codes;
create policy "anon can select access codes"
  on public.access_codes for select
  to anon
  using (true);

-- No anon insert/update/delete — those go through RPCs (admin_* + create_invite_with_code)

/* ---------- Helpers ---------- */

create or replace function public._check_admin_pw(admin_pw text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  correct_pw text;
begin
  select value into correct_pw from public.admin_settings where key = 'admin_password';
  if correct_pw is null then
    raise exception 'Admin password not set. Run: insert into admin_settings(key,value) values (''admin_password'',''your-secret'') on conflict (key) do update set value = excluded.value;';
  end if;
  if admin_pw is null or admin_pw <> correct_pw then
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

/* ---------- Багцын хязгаар ---------- */

-- Тухайн багцад зөвшөөрөгдөөгүй талбаруудыг config-оос таслана.
-- Энэ бол ЖИНХЭНЭ хамгаалалт: create.html дээрх хаалтыг тойрч болно ч
-- урилга энд дамжин орох тул премиум агуулга Энгийн кодоор хадгалагдахгүй.
create or replace function public._apply_plan_limits(cfg jsonb, plan_ text)
returns jsonb
language plpgsql
immutable
as $$
declare
  out_cfg jsonb := coalesce(cfg, '{}'::jsonb);
  trimmed jsonb;
  letter_max int;
  promise_max int;
begin
  out_cfg := jsonb_set(out_cfg, '{plan}', to_jsonb(plan_));

  if plan_ = 'basic' then
    letter_max := 300;
    promise_max := 0;
    -- Энгийн багцад байхгүй талбарууд
    out_cfg := out_cfg - 'locationName' - 'locationUrl' - 'specialLetter' - 'promises';
    -- Зөвшөөрөгдсөн цаас / стикер
    if out_cfg ? 'paper' and not (out_cfg->>'paper' = any (array['cream','blush','ruled'])) then
      out_cfg := jsonb_set(out_cfg, '{paper}', to_jsonb('cream'::text));
    end if;
    if out_cfg ? 'sticker' and not (out_cfg->>'sticker' = any (array['draw','none'])) then
      out_cfg := jsonb_set(out_cfg, '{sticker}', to_jsonb('draw'::text));
    end if;
  else
    letter_max := 600;
    promise_max := 5;
  end if;

  if out_cfg ? 'sorryLetter' then
    out_cfg := jsonb_set(out_cfg, '{sorryLetter}', to_jsonb(left(out_cfg->>'sorryLetter', letter_max)));
  end if;

  if promise_max > 0 and jsonb_typeof(out_cfg->'promises') = 'array'
     and jsonb_array_length(out_cfg->'promises') > promise_max then
    select coalesce(jsonb_agg(elem order by ord), '[]'::jsonb)
      into trimmed
      from jsonb_array_elements(out_cfg->'promises') with ordinality as t(elem, ord)
     where ord <= promise_max;
    out_cfg := jsonb_set(out_cfg, '{promises}', trimmed);
  end if;

  return out_cfg;
end;
$$;

/* ---------- RPCs ---------- */

-- Redeem a code and create an invite in one atomic step.
-- Called from create.html when the buyer submits their invite form.
create or replace function public.create_invite_with_code(
  p_invite_id     text,
  p_config        jsonb,
  p_access_code   text
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
  if p_invite_id is null or length(p_invite_id) < 4 then raise exception 'Invalid invite id'; end if;
  if p_access_code is null or length(p_access_code) = 0 then raise exception 'Access code required'; end if;

  select * into code_row from public.access_codes where code = p_access_code for update;
  if not found then raise exception 'Invalid access code'; end if;
  if code_row.used then raise exception 'Access code already used'; end if;

  insert into public.invites(id, owner_token, config, created_at)
    values (p_invite_id, new_owner,
            public._apply_plan_limits(p_config, code_row.plan), now_ts);

  update public.access_codes
    set used = true, used_at = now_ts, used_for_invite_id = p_invite_id
    where code = p_access_code;

  return query select p_invite_id, new_owner, now_ts;
end;
$$;

grant execute on function public.create_invite_with_code(text, jsonb, text) to anon;

-- Recipient: хариугаа хадгална. Зөвхөн response + responded_at-г өөрчилнө.
create or replace function public.save_response(
  p_invite_id text,
  p_response  jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invite_id is null or length(p_invite_id) = 0 then raise exception 'Invite id required'; end if;
  update public.invites
    set response = p_response,
        responded_at = now()
    where id = p_invite_id;
  if not found then raise exception 'Invite not found'; end if;
end;
$$;

grant execute on function public.save_response(text, jsonb) to anon;

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
-- plan_ нэмэгдсэн тул хуучин 3 аргументтай хувилбарыг эхлээд устгана
-- (үгүй бол default-тай шинэ функцтэй давхцаж "ambiguous" алдаа өгнө).
drop function if exists public.admin_create_codes(text, int, text);

create or replace function public.admin_create_codes(
  admin_pw text,
  qty      int,
  note_    text default null,
  plan_    text default 'premium'
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
  if plan_ is null or plan_ not in ('basic','premium') then raise exception 'plan must be basic or premium'; end if;

  for i in 1..qty loop
    -- retry in the unlikely event of collision
    loop
      new_code := public._gen_code();
      begin
        insert into public.access_codes(code, note, plan) values (new_code, note_, plan_);
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

grant execute on function public.admin_create_codes(text, int, text, text) to anon;

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

-- Force PostgREST to reload its schema cache so new tables/functions are picked up immediately.
NOTIFY pgrst, 'reload schema';
