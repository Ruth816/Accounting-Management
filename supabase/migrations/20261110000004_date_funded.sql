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
    perform notify(f.fund_requestor_id,
      format('Fund request %s was funded on %s.', f.ref_no, to_char(p_date, 'Mon FMDD, YYYY')),
      f.payment_request_id, f.id);
    -- The payment requestor can now collect it (Ruth, 10 November).
    perform notify((select requestor_id from payment_requests where id = f.payment_request_id),
      format('Your payment request %s is now available. Please go to the Finance office.',
             (select req_no from payment_requests where id = f.payment_request_id)),
      f.payment_request_id, f.id);
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

-- Approved for funding goes straight to Ready for funding (Ruth, 10 November):
-- the separate Fund approved list is gone, and Ready for funding is where every
-- approved request waits until the Fund Approver ticks it Funded. The trigger
-- covers every way a request is approved (Approve, Submit & approve, the
-- Admin override).
create or replace function fr_ready_on_approval() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved_ready_for_qb' and old.status is distinct from new.status
     and old.status not in ('approved_ready_for_qb', 'sync_failed', 'approved_posted_to_qb')
     and new.ready_for_funding_at is null then
    new.ready_for_funding_at := now();
    new.ready_for_funding_by := coalesce(new.approved_by, auth.uid());
  end if;
  return new;
end $$;

drop trigger if exists fr_ready_on_approval on fund_requests;
create trigger fr_ready_on_approval before update of status on fund_requests
  for each row execute function fr_ready_on_approval();

-- Requests already approved but not yet on Ready for funding join it on the
-- day they were approved.
update fund_requests
   set ready_for_funding_at = coalesce(approved_on, now()), ready_for_funding_by = approved_by
 where status in ('approved_ready_for_qb', 'sync_failed') and ready_for_funding_at is null;

-- Approval no longer tells the payment requestor it is funded: that message
-- now comes when the Fund Approver ticks Funded (Ruth, 10 November).
create or replace function approve_fund_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
  pr_requestor uuid;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found or (f.fund_approver_id <> uid and f.fund_requestor_id <> uid and not has_role('admin')) then raise exception 'Fund request not found.'; end if;
  select requestor_id into pr_requestor from payment_requests where id = f.payment_request_id;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  if not f.reviewed then raise exception 'Tick Reviewed before approving.'; end if;

  update fund_requests set status = 'approved_ready_for_qb', approved_by = uid, approved_on = now(),
    locked = true, disapproval_reason = null
  where id = f.id;
  perform log_event(f.payment_request_id, f.id, 'Fund approved', f.status, 'approved_ready_for_qb',
    case when uid = f.fund_requestor_id or uid = pr_requestor
         then 'Self-approved: the approver also prepared or requested this fund request' end);
  perform notify(f.fund_requestor_id, format('Fund request %s was approved.', f.ref_no), f.payment_request_id, f.id);
  perform notify(pr_requestor,
    format('Your payment request %s was approved for funding (Ref no. %s).',
           (select req_no from payment_requests where id = f.payment_request_id), f.ref_no),
    f.payment_request_id, f.id);
end $$;


-- Fund Requestors edit until approval, not until funded (Ruth, 10 November):
-- once approved, only the Fund Approver (or an Admin) corrects it.
create or replace function fund_request_edit_mode(f fund_requests) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_staff boolean := has_role('admin') or has_role('fund_approver');
begin
  if uid is null or f.status in ('cancelled', 'approved_posted_to_qb') then return null; end if;
  if not f.locked and f.status in ('in_funding_preparation', 'returned_to_fund_requestor') then
    return case when v_staff or has_role('fund_requestor') then 'prep' end;
  end if;
  -- Sent or approved: staff save in place; a requestor takes theirs back
  -- first while it waits for approval (withdraw_fund_request).
  if f.status in ('pending_fund_approval', 'approved_ready_for_qb', 'sync_failed') and v_staff then
    return 'in_place';
  end if;
  return null;
end $$;

create or replace function fund_request_edit_refusal(f fund_requests) returns text
language sql stable as $$
  select case
    when f.status = 'approved_posted_to_qb' then 'Posted to QuickBooks: this request can no longer be edited.'
    when f.status = 'cancelled' then 'This fund request is cancelled.'
    when f.status in ('approved_ready_for_qb', 'sync_failed') then 'This fund request is already approved. Only an Admin or a Fund Approver can edit it now.'
    when f.status = 'pending_fund_approval' then 'This fund request is waiting for approval. Take it back for editing first.'
    else 'Only its Fund Requestor, an Admin or a Fund Approver can edit this fund request.'
  end;
$$;
