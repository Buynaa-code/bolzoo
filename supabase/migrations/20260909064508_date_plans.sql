-- HamtDaa plans are private aggregates. The Node API authenticates the owner or
-- participant, validates state transitions, and filters private fields before
-- responding. Never return this document directly from a public invite RPC.
create table if not exists public.date_plans (
  id          uuid primary key,
  invite_id   text not null unique references public.invites(id) on delete cascade,
  version     integer not null default 1,
  document    jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint date_plans_positive_version check (version > 0),
  constraint date_plans_document_object check (jsonb_typeof(document) = 'object'),
  constraint date_plans_document_size check (octet_length(document::text) <= 131072)
);

-- The unique invite_id constraint also indexes invite lookup and FK cascades.
comment on column public.date_plans.document is
  'Private application aggregate: participant token hashes, plan revisions, progress, memories and bounded request receipts. Server access only.';

alter table public.date_plans enable row level security;

-- Explicit grants are required on new Supabase projects. The service role is
-- trusted server infrastructure; browser roles have neither grants nor policies.
revoke all on table public.date_plans from public, anon, authenticated, service_role;
grant usage on schema public to service_role;
grant select, insert on table public.date_plans to service_role;
grant update (version, document, updated_at) on table public.date_plans to service_role;
drop policy if exists date_plans_service_access on public.date_plans;
create policy date_plans_service_access on public.date_plans
  for all to service_role using (true) with check (true);

-- Lost create responses are retryable. A second create for the same invite
-- returns its original plan and never replaces its document, id or version.
create or replace function public.create_date_plan(
  p_id uuid,
  p_invite_id text,
  p_document jsonb
)
returns setof public.date_plans
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return query
    insert into public.date_plans (id, invite_id, document)
    values (p_id, p_invite_id, p_document)
    on conflict (invite_id) do nothing
    returning *;
  if found then return; end if;

  -- A separate statement observes the committed winner of a concurrent insert
  -- at READ COMMITTED. A one-statement CTE can miss that newly committed row.
  return query select p.* from public.date_plans p where p.invite_id = p_invite_id;
end;
$$;

-- Compare and swap is a single UPDATE: a stale writer gets zero rows, and must
-- reload before applying a new intent. The expected version must never be
-- replaced by a read performed inside this function.
create or replace function public.commit_date_plan(
  p_id uuid,
  p_expected_version integer,
  p_document jsonb
)
returns setof public.date_plans
language sql
security invoker
set search_path = ''
as $$
  update public.date_plans as p
  set document = p_document,
      version = p.version + 1,
      updated_at = clock_timestamp()
  where p.id = p_id and p.version = p_expected_version
  returning p.*;
$$;

revoke all on function public.create_date_plan(uuid, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.commit_date_plan(uuid, integer, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.create_date_plan(uuid, text, jsonb) to service_role;
grant execute on function public.commit_date_plan(uuid, integer, jsonb) to service_role;

notify pgrst, 'reload schema';
