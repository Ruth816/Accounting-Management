-- QuickBooks imported summary (Ruth, 5 November): approved fund requests already
-- exported to QuickBooks, dated by the export. Open to Payment Approvers, Fund
-- Approvers and Admins; an approver limited to one region sees only that region.
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
    and (has_role('admin') or has_role('payment_approver') or has_role('fund_approver'))
    and (has_role('admin') or approver_region_ok(fr_region(f)))
  order by x.exported_at;
$$;

revoke execute on function qb_imported_summary(timestamptz, timestamptz) from public, anon;
grant execute on function qb_imported_summary(timestamptz, timestamptz) to authenticated;
