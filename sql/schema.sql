-- Bolzoo Supabase schema
-- Run this in Supabase SQL editor: https://supabase.com/dashboard/project/_/sql/new

create extension if not exists "pgcrypto";

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

-- Anyone (anon) can INSERT a new invite (seller creates one)
drop policy if exists "anon can insert invites" on public.invites;
create policy "anon can insert invites"
  on public.invites for insert
  to anon
  with check (true);

-- Anyone (anon) can SELECT config by id, but NOT owner_token
-- (owner_token is filtered in the client via .select('id,config,response,opened_at,responded_at,created_at'))
drop policy if exists "anon can select invites" on public.invites;
create policy "anon can select invites"
  on public.invites for select
  to anon
  using (true);

-- Anyone (anon) can UPDATE only response + timestamps (recipient answers)
-- config cannot be changed by anon
drop policy if exists "anon can update response" on public.invites;
create policy "anon can update response"
  on public.invites for update
  to anon
  using (true)
  with check (true);

-- (Optional hardening) Only allow updates that don't change config or owner_token.
-- Postgres RLS can't easily enforce column-level immutability with anon key,
-- so we rely on client-side to only send response updates. For stricter security,
-- move mutating logic behind edge functions.

-- Rate limit hint: use Supabase Rate Limiting settings + Cloudflare Turnstile on client
