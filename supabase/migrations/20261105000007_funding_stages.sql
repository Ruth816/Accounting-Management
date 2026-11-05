-- Funding in stages (Ruth, 5 November). Fund approval is a pre-approval; then
--   1. the Fund Approver clicks "Ready for funding" on an approved request,
--      which puts it on the Ready for funding list for that day;
--   2. once the day's funds are sent, "Mark as funded" on the day's total;
--   3. then "Ready to import to QuickBooks" exports and locks them.
alter table fund_requests
  add column if not exists ready_for_funding_at timestamptz,
  add column if not exists ready_for_funding_by uuid references profiles (id),
  add column if not exists funded_at timestamptz,
  add column if not exists funded_by uuid references profiles (id);

create or replace function mark_ready_for_funding(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.status not in ('approved_ready_for_qb', 'sync_failed') then
    raise exception 'Only an approved fund request can be made ready for funding.';
  end if;
  if f.ready_for_funding_at is not null then raise exception 'It is already ready for funding.'; end if;
  if f.fund_approver_id is distinct from uid and not has_role('admin') then
    raise exception 'Only its Fund Approver can make it ready for funding.';
  end if;
  update fund_requests set ready_for_funding_at = now(), ready_for_funding_by = uid where id = p_id;
  perform log_event(f.payment_request_id, f.id, 'Ready for funding', f.status, f.status);
end $$;

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
    update fund_requests set funded_at = now(), funded_by = uid where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Funded', f.status, f.status);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Nothing on this day is waiting to be marked as funded.'; end if;
  return n;
end $$;

-- Only funded requests can be exported to QuickBooks now.
create or replace function mark_posted_to_qb(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
  n int := 0;
begin
  if exists (select 1 from fund_requests
             where id = any (coalesce(p_ids, '{}'))
               and status in ('approved_ready_for_qb', 'sync_failed') and funded_at is null) then
    raise exception 'Mark it as funded on Ready for funding before exporting to QuickBooks.';
  end if;
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

revoke execute on function mark_ready_for_funding(uuid), mark_funded(uuid[]), mark_posted_to_qb(uuid[]) from public, anon;
grant execute on function mark_ready_for_funding(uuid), mark_funded(uuid[]), mark_posted_to_qb(uuid[]) to authenticated;

-- The summaries are for Admins and Fund Approvers only (Ruth, 5 November).
create or replace function qb_imported_summary(p_from timestamptz, p_to timestamptz)
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(f) || jsonb_build_object('exported_at', x.exported_at, 'cheque_no', c.cheque_no)
  from fund_requests f
  cross join lateral (
    select coalesce(max(a.created_at), f.approved_on, f.updated_at) as exported_at
    from audit_log a
    where a.fund_request_id = f.id and a.action = 'Posted to QuickBooks'
  ) x
  left join cheques c on c.id = f.cheque_id
  where f.status = 'approved_posted_to_qb'
    and x.exported_at >= p_from and x.exported_at < p_to
    and (has_role('admin') or has_role('fund_approver'))
  order by x.exported_at;
$$;
