-- PREPARED ONLY: applying this migration begins NEW measurement coverage.
-- payments has no historical paid_at. Never reconstruct it from created_at or
-- updated_at and never backfill old succeeded rows. paid_at below means the
-- database's first observed successful transition, NOT provider settlement time.
-- Requires the separately reviewed payment_integrity migration's livemode field.
begin;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'public.payments'::regclass and attname = 'livemode'
      and atttypid = 'boolean'::regtype and not attisdropped
  ) then
    raise exception 'Required payment schema unavailable';
  end if;
end;
$$;

-- Establish the coverage start only after in-flight payment writes complete.
-- Hold the same lock through trigger installation so no success can commit in
-- the gap between sampling started_at and enabling capture.
lock table public.payments in share row exclusive mode;

create table if not exists public.moch_learning_coverage (
  singleton boolean primary key default true check (singleton),
  started_at timestamptz not null,
  capture_complete boolean not null default true
);
create table if not exists public.moch_learning_payment_facts (
  payment_id text primary key,
  paid_at timestamptz not null,
  amount_mnt bigint,
  currency text,
  provider text,
  livemode boolean
);
create index if not exists moch_learning_payment_facts_paid_at_idx
  on public.moch_learning_payment_facts(paid_at);

alter table public.moch_learning_coverage enable row level security;
alter table public.moch_learning_payment_facts enable row level security;
revoke all on table public.moch_learning_coverage, public.moch_learning_payment_facts
  from public, anon, authenticated, service_role;
grant select on table public.moch_learning_coverage, public.moch_learning_payment_facts to service_role;
drop policy if exists learning_coverage_service_read on public.moch_learning_coverage;
create policy learning_coverage_service_read on public.moch_learning_coverage
  for select to service_role using (true);
drop policy if exists learning_facts_service_read on public.moch_learning_payment_facts;
create policy learning_facts_service_read on public.moch_learning_payment_facts
  for select to service_role using (true);

-- Rerunning must not reset the coverage start or clear a recorded capture gap.
insert into public.moch_learning_coverage(singleton, started_at, capture_complete)
values (true, clock_timestamp(), true) on conflict (singleton) do nothing;

create or replace function public._capture_moch_learning_success()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status <> 'succeeded' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'succeeded' then return new; end if;
  begin
    insert into public.moch_learning_payment_facts(payment_id, paid_at, amount_mnt, currency, provider, livemode)
    values (new.id, clock_timestamp(), new.amount, new.currency, new.provider, new.livemode)
    on conflict (payment_id) do nothing;
  exception when others then
    -- Analytics must not fail an otherwise valid payment write. Remember gaps
    -- durably when possible; the reader then refuses ALL apparently complete
    -- totals. Do not store the database error (it may contain private values).
    begin
      update public.moch_learning_coverage set capture_complete = false where singleton;
    exception when others then
      -- If even the gap marker cannot be written, fail-open means durable gap
      -- detection cannot be guaranteed. This limit requires operational review;
      -- never claim this ledger is independent bank/provider reconciliation.
      null;
    end;
  end;
  return new;
end;
$$;
revoke all on function public._capture_moch_learning_success() from public, anon, authenticated, service_role;
drop trigger if exists moch_learning_capture_success on public.payments;
create trigger moch_learning_capture_success
  after insert or update of status on public.payments
  for each row when (new.status = 'succeeded')
  execute function public._capture_moch_learning_success();

create or replace function public.moch_learning_overview(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare
  read_at timestamptz := statement_timestamp();
  coverage_start timestamptz;
  coverage_complete boolean;
  unavailable boolean;
  recorded_count bigint;
  recorded_amount bigint;
begin
  if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to)
     or p_from >= p_to or p_to > read_at
     or extract(epoch from (p_to - p_from)) > 31 * 86400 then
    raise exception 'Invalid reporting period' using errcode = '22023';
  end if;
  select c.started_at, c.capture_complete into coverage_start, coverage_complete
  from public.moch_learning_coverage c where c.singleton;
  unavailable := coverage_start is null or not coalesce(coverage_complete, false) or p_from < coverage_start
    or not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.payments'::regclass
        and t.tgname = 'moch_learning_capture_success' and t.tgenabled in ('O', 'A')
        and t.tgfoid = 'public._capture_moch_learning_success()'::regprocedure
    );

  if not unavailable then
    select
      coalesce(bool_or(
        f.provider is null or f.provider not in ('wire', 'mock', 'manual', 'demo', 'test')
        or (f.provider = 'wire' and (
          f.livemode is null or (f.livemode and (
            f.currency is distinct from 'MNT' or f.amount_mnt is null or f.amount_mnt <= 0
          ))
        ))
      ), false),
      count(*) filter (where f.provider = 'wire' and f.livemode and f.currency = 'MNT' and f.amount_mnt > 0),
      coalesce(sum(f.amount_mnt) filter (where f.provider = 'wire' and f.livemode and f.currency = 'MNT' and f.amount_mnt > 0), 0)
    into unavailable, recorded_count, recorded_amount
    from public.moch_learning_payment_facts f where f.paid_at >= p_from and f.paid_at < p_to;
  end if;
  return jsonb_build_object(
    'read_at', to_char(read_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'measurement_available', not unavailable,
    'recorded_count', case when unavailable then null else recorded_count end,
    'recorded_amount_mnt', case when unavailable then null else recorded_amount end
  );
end;
$$;
revoke all on function public.moch_learning_overview(timestamptz, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.moch_learning_overview(timestamptz, timestamptz) to service_role;
notify pgrst, 'reload schema';
commit;
