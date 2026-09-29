-- After payment_integrity: let an old in-flight checkout insert its row while
-- the new API is promoted. Keep the same expected amount as the integrity
-- backfill; this does not approve legacy underpayments or change existing rows.
create or replace function public._fill_payment_amount_minor()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.amount_minor is null then
    new.amount_minor := new.amount * 100;
  end if;
  return new;
end;
$$;

-- Trigger execution needs no new browser or server RPC permission. The existing
-- table privileges and positive/non-null amount constraints remain in force.
revoke all on function public._fill_payment_amount_minor()
  from public, anon, authenticated, service_role;

drop trigger if exists payments_fill_amount_minor on public.payments;
create trigger payments_fill_amount_minor
  before insert on public.payments
  for each row
  execute function public._fill_payment_amount_minor();
