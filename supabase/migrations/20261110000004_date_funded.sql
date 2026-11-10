-- Tick each request as funded, with the date it was truly funded (Ruth, 10 November).
-- A request can be funded earlier than it is encoded and approved, so the
-- Fund Approver types the date funded; it can be any date up to today and can
-- be corrected later, until the request is imported to QuickBooks.
alter table fund_requests add column if not exists funded_on date;

update fund_requests
   set funded_on = (funded_at at time zone 'Asia/Manila')::date
 where funded_at is not null and funded_on is null;

create or replace function set_funded(p_id uuid, p_funded boolean, p_date date default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.status = 'approved_posted_to_qb' then
    raise exception 'Imported to QuickBooks: the funding can no longer be changed.';
  end if;
  if f.status not in ('approved_ready_for_qb', 'sync_failed') or f.ready_for_funding_at is null then
    raise exception 'Only a request on the Ready for funding list can be marked as funded.';
  end if;

  if not coalesce(p_funded, false) then
    if f.funded_at is null then return; end if;
    update fund_requests set funded_at = null, funded_by = null, funded_on = null where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Funded tick cleared', f.status, f.status);
    return;
  end if;

  if p_date is null then raise exception 'Enter the date funded.'; end if;
  if p_date > v_today then raise exception 'The date funded cannot be later than today.'; end if;

  if f.funded_at is null then
    update fund_requests set funded_at = now(), funded_by = uid, funded_on = p_date where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Funded', f.status, f.status,
      'Date funded ' || to_char(p_date, 'Mon FMDD, YYYY'));
  elsif f.funded_on is distinct from p_date then
    update fund_requests set funded_on = p_date where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Date funded changed', f.status, f.status,
      coalesce(to_char(f.funded_on, 'Mon FMDD, YYYY'), 'none') || ' to ' || to_char(p_date, 'Mon FMDD, YYYY'));
  end if;
end $$;

revoke execute on function set_funded(uuid, boolean, date) from public, anon;
grant execute on function set_funded(uuid, boolean, date) to authenticated;

-- The day's bulk "Mark as funded" now records today as the date funded.
create or replace function mark_funded(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
  n int := 0;
begin
  for f in select * from fund_requests
           where id = any (coalesce(p_ids, '{}'))
             and status in ('approved_ready_for_qb', 'sync_failed')
             and ready_for_funding_at is not null and funded_at is null
           for update loop
    update fund_requests
       set funded_at = now(), funded_by = uid, funded_on = (now() at time zone 'Asia/Manila')::date
     where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Funded', f.status, f.status);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Nothing on this day is waiting to be marked as funded.'; end if;
  return n;
end $$;
