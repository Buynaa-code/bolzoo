-- Apply before deploying the payment API. Existing amount remains whole MNT;
-- amount_minor is the exact Wire amount (1 MNT = 100 minor units).
begin;
alter table public.payments add column if not exists amount_minor integer;
alter table public.payments add column if not exists checkout_token_hash text;
alter table public.payments add column if not exists return_to_create boolean not null default false;
alter table public.payments add column if not exists return_origin text;
alter table public.payments add column if not exists payment_description text;
alter table public.payments add column if not exists livemode boolean;
update public.payments set amount_minor = amount * 100 where amount_minor is null;
update public.payments set provider_intent_id = id where provider = 'wire' and provider_intent_id is null;
alter table public.payments alter column amount_minor set not null;
alter table public.payments drop constraint if exists payments_positive_minor;
alter table public.payments add constraint payments_positive_minor check (amount_minor > 0);
create unique index if not exists payments_checkout_token_unique on public.payments(checkout_token_hash) where checkout_token_hash is not null;
create unique index if not exists payments_provider_intent_unique on public.payments(provider_intent_id) where provider_intent_id is not null;

create or replace function public.reconcile_wire_payment(p_id text, p_remote jsonb)
returns setof public.payments
language plpgsql security invoker set search_path = ''
as $$
declare
  p public.payments%rowtype;
  remote_status text := p_remote->>'status';
  issued_code text;
  candidate text;
  random_hex text;
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  attempt integer;
  i integer;
begin
  select * into p from public.payments where id = p_id for update;
  if not found then raise exception 'Payment not found'; end if;
  if p.provider <> 'wire'
     or (p_remote->>'id') is distinct from coalesce(p.provider_intent_id, p.id)
     or (p_remote->>'currency') is distinct from p.currency
     or jsonb_typeof(p_remote->'amount') is distinct from 'number'
     or (p_remote->>'amount')::numeric is distinct from p.amount_minor::numeric
     or (p.livemode is not null and (p_remote->>'livemode')::boolean is distinct from p.livemode)
     or remote_status is null
     or remote_status not in ('new','requires_payment_method','requires_action','requires_capture','processing','succeeded','canceled') then
    raise exception 'Payment verification mismatch';
  end if;

  -- Success is irreversible here; a stale poll/charge failure cannot revoke it.
  -- Cancellation also cannot be overwritten by an older pending snapshot.
  if p.status = 'succeeded' then remote_status := 'succeeded';
  elsif p.status = 'canceled' and remote_status <> 'succeeded' then remote_status := 'canceled';
  end if;

  if remote_status = 'succeeded' then
    select code into issued_code from public.access_codes where payment_id = p.id;
    if issued_code is null then
      for attempt in 1..10 loop
        -- UUID v4 supplies cryptographic randomness, unlike SQL random().
        random_hex := replace(gen_random_uuid()::text, '-', '');
        candidate := 'LOV-';
        for i in 0..5 loop
          candidate := candidate || substr(chars, 1 + (get_byte(decode(substr(random_hex, i * 2 + 1, 2), 'hex'), 0) % length(chars)), 1);
        end loop;
        insert into public.access_codes(code, used, source, payment_id, note)
          values(candidate, false, 'self_service', p.id, 'self-serve ' || p.id)
          on conflict do nothing returning code into issued_code;
        if issued_code is not null then exit; end if;
        select code into issued_code from public.access_codes where payment_id = p.id;
        if issued_code is not null then exit; end if;
      end loop;
      if issued_code is null then raise exception 'Access code allocation failed'; end if;
    end if;
  end if;

  update public.payments set
    status = remote_status,
    code = coalesce(issued_code, code),
    next_action = case when remote_status in ('succeeded','canceled') then null
                       when p_remote ? 'next_action' then p_remote->'next_action' else next_action end,
    expires_at = case when p_remote->>'expires_at' is not null then to_timestamp((p_remote->>'expires_at')::double precision) else expires_at end,
    updated_at = now()
    where id = p.id;
  return query select * from public.payments where id = p.id;
end;
$$;
revoke all on function public.reconcile_wire_payment(text, jsonb) from public, anon, authenticated;
grant execute on function public.reconcile_wire_payment(text, jsonb) to service_role;
-- Old event payloads must never write payment status directly.
revoke all on function public.process_wire_event(text, text, text, jsonb) from public, anon, authenticated, service_role;
notify pgrst, 'reload schema';
commit;
