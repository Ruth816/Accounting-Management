-- Admins can approve their own payment requests (Ruth, 5 November).
create or replace function approve_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
  v_next uuid;
  v_preparer uuid;
  v_fr uuid;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  -- An Admin may approve their own request, flagged as self-approved (Ruth, 5 November).
  if r.requestor_id = uid and not has_role('admin') then raise exception 'You cannot approve your own request.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;
  perform check_payment_approver(r, uid);

  -- VisMin: approver 1 passes it to approver 2. An Admin's approval is final.
  v_next := route_approver(r.region, r.approval_level + 1);
  if v_next is not null and v_next <> r.requestor_id and not has_role('admin') then
    update payment_requests set approval_level = r.approval_level + 1, approver_id = v_next,
      first_approver_id = uid, first_approved_on = now()
    where id = r.id;
    perform log_event(r.id, null, format('Approved by approver %s', r.approval_level), r.status, r.status);
    perform notify(v_next,
      format('Payment request %s (%s %s) was approved by %s and is waiting for your approval.',
             r.req_no, r.currency, money_txt(r.total_due), (select full_name from profiles where id = uid)),
      r.id);
    return;
  end if;

  update payment_requests set status = 'approved_awaiting_funding', approved_on = now(), approver_id = uid,
    disapproval_reason = null, return_note = null
  where id = r.id;
  perform log_event(r.id, null, 'Approved', r.status, 'approved_awaiting_funding',
    case when r.requestor_id = uid then 'Self-approved: the Admin approved their own request' end);
  perform notify(r.requestor_id, format('Your payment request %s was approved and is waiting for funding.', r.req_no), r.id);
  -- Straight to a fund request (Ruth, 2 November), prepared by the region's Fund Requestor.
  v_preparer := fund_preparer_for(r.region);
  if v_preparer is not null then
    v_fr := make_fund_request(r.id, v_preparer);
    perform notify_role('fund_requestor',
      format('Payment request %s (%s, %s %s) is approved. Its fund request is ready for you to complete.',
             r.req_no, r.payable_to, r.currency, money_txt(r.total_due)), r.id, v_fr);
  else
    perform notify_role('fund_requestor',
      format('Payment request %s (%s, %s %s) is approved and ready to receive for funding.',
             r.req_no, r.payable_to, r.currency, money_txt(r.total_due)), r.id);
  end if;
end $$;
