-- Mark fund requests as posted to QuickBooks from the funding summary list,
-- one row or several ticked at once (Ruth, 1 November).
create or replace function mark_posted_to_qb(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
  n int := 0;
begin
  for f in select * from fund_requests
           where id = any (coalesce(p_ids, '{}'))
             and status in ('approved_ready_for_qb', 'sync_failed')
           for update loop
    update fund_requests set status = 'approved_posted_to_qb', qb_sync_error = null where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Posted to QuickBooks', f.status, 'approved_posted_to_qb');
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Tick at least one request that is ready for QuickBooks.'; end if;
  return n;
end $$;

revoke execute on function mark_posted_to_qb(uuid[]) from public, anon;
grant execute on function mark_posted_to_qb(uuid[]) to authenticated;
