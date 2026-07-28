-- One paid PaymentIntent may issue at most one access code.
create unique index if not exists access_codes_payment_id_unique_idx
  on public.access_codes (payment_id)
  where payment_id is not null;

-- Claim a Wire event and update the matching payment in one transaction.
-- Invoked only by the server-side service role after HMAC verification.
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

revoke all on function public.process_wire_event(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.process_wire_event(text, text, text, jsonb)
  to service_role;

notify pgrst, 'reload schema';
