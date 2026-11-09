-- Merge a duplicate account into the right one (Ruth, 9 November): every
-- request, approval and history line that names the old account is moved to
-- the new one, so the old sign-in can then be deleted. Rows that are deleted
-- with the account anyway (notifications, approval routing) are left alone.
create or replace function admin_merge_user(p_from uuid, p_to uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  r record;
  n int;
  total int := 0;
begin
  if p_from is null or p_to is null or p_from = p_to then raise exception 'Choose two different people.'; end if;
  if p_from = uid then raise exception 'You cannot merge away your own account.'; end if;
  if not exists (select 1 from profiles where id = p_from) then raise exception 'The old account was not found.'; end if;
  if not exists (select 1 from profiles where id = p_to and active) then raise exception 'The account to keep must be an active user.'; end if;

  for r in
    select c.conrelid::regclass as tbl, a.attname as col
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f'
       and c.confrelid = 'public.profiles'::regclass
       and array_length(c.conkey, 1) = 1
       and c.confdeltype <> 'c'
  loop
    execute format('update %s set %I = $1 where %I = $2', r.tbl, r.col, r.col) using p_to, p_from;
    get diagnostics n = row_count;
    total := total + n;
  end loop;

  update profiles set active = false where id = p_from;
  return total;
end $$;

revoke all on function admin_merge_user(uuid, uuid) from public;
grant execute on function admin_merge_user(uuid, uuid) to authenticated;
