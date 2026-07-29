-- Pin search_path on _gen_code so a rogue schema in the caller's search_path
-- can't shadow built-in functions we rely on (defense in depth).

create or replace function public._gen_code()
returns text
language plpgsql
set search_path = public, pg_catalog
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

revoke execute on function public._gen_code()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
