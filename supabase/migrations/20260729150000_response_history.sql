-- Keep a timeline of past responses. Every time save_response replaces the
-- current answer, a before-update trigger appends the OLD response into
-- response_history so the owner dashboard can show what changed and when.

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

notify pgrst, 'reload schema';
