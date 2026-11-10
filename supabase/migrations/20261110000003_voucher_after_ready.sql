-- Vouchers for Fund Requestors (Ruth, 10 November). Every fund request a
-- Fund Requestor can see gets its voucher once it is ready for funding (then
-- funded, then exported to QuickBooks): they can view, save as PDF and print
-- it. Admins and Fund Approvers keep seeing it from fund approval, as before.
-- Anyone else who can see the request (its Payment Requestor) also waits
-- until it is ready for funding.

create or replace function can_see_voucher(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select can_see_fr(p_id) and exists (
    select 1 from fund_requests f
    where f.id = p_id and f.locked
      and f.status in ('approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed')
      and (has_role('admin') or has_role('fund_approver')
           or f.ready_for_funding_at is not null or f.funded_at is not null
           or f.status = 'approved_posted_to_qb')
  );
$$;

create or replace function get_voucher(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f fund_requests;
  r payment_requests;
begin
  if not can_see_fr(p_id) then raise exception 'Fund request not found.'; end if;
  if not can_see_voucher(p_id) then
    raise exception 'The voucher is available once the fund request is ready for funding.';
  end if;
  select * into f from fund_requests where id = p_id;
  select * into r from payment_requests where id = f.payment_request_id;
  return jsonb_build_object(
    'fund_request', to_jsonb(f),
    'cheque_no', (select cheque_no from cheques where id = f.cheque_id),
    'cheque_total', case when f.cheque_id is not null then cheque_total(f.cheque_id) end,
    'req_no', r.req_no,
    'payment_requested_by', (select full_name from profiles where id = r.requestor_id),
    'payment_requested_on', r.submitted_on,
    'payment_approved_by', (select full_name from profiles where id = r.approver_id),
    'payment_approved_on', (select max(created_at) from audit_log
                            where payment_request_id = r.id and action = 'Approved'),
    'fund_prepared_by', (select full_name from profiles where id = f.fund_requestor_id),
    'fund_prepared_on', f.submitted_on,
    'fund_approved_by', (select full_name from profiles where id = f.approved_by),
    'fund_approved_on', f.approved_on
  );
end $$;

revoke execute on function can_see_voucher(uuid), get_voucher(uuid) from public, anon;
grant execute on function can_see_voucher(uuid), get_voucher(uuid) to authenticated;
