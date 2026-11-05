-- Approvers and Admins may approve their own requests, flagged as self-approved
-- (Ruth, 5 November): payment requests, fund requests and auto debit alike.


create or replace function validate_payment_request(r payment_requests) returns void
language plpgsql stable security definer set search_path = public as $$
declare
  errs text[] := '{}';
begin
  if r.payable_to is null then errs := array_append(errs, 'Payable to is required'); end if;
  if r.purpose is null then errs := array_append(errs, 'Purpose is required'); end if;
  if r.date_required is null then errs := array_append(errs, 'Date required is required'); end if;
  if not exists (select 1 from jsonb_array_elements(r.items) e where (e ->> 'amount')::numeric > 0) then
    errs := array_append(errs, 'At least one item needs an amount above 0');
  end if;
  if exists (select 1 from jsonb_array_elements(r.items) e
             where (e ->> 'description' = '') <> (e ->> 'amount' is null)) then
    errs := array_append(errs, 'Every item needs both a description and an amount');
  end if;
  if exists (select 1 from jsonb_array_elements(r.items) e where (e ->> 'amount')::numeric < 0) then
    errs := array_append(errs, 'Item amounts cannot be negative');
  end if;
  if r.approver_id is null then
    errs := array_append(errs, 'Choose an approver');
  elsif r.approver_id = r.requestor_id and not user_has_role(r.requestor_id, 'payment_approver') then
    errs := array_append(errs, 'You cannot approve your own request, so choose another approver');
  elsif not user_has_role(r.approver_id, 'payment_approver') then
    errs := array_append(errs, 'The chosen approver is not an active Payment Approver');
  end if;
  if not r.terms_accepted then
    errs := array_append(errs, 'Tick that you have read and understood the terms and conditions');
  end if;
  if array_length(errs, 1) > 0 then
    raise exception '%.', array_to_string(errs, '. ');
  end if;
end $$;

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

  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;
  -- The requestor, being an approver, may approve their own request.
  if r.requestor_id is distinct from uid then perform check_payment_approver(r, uid); end if;

  -- VisMin: approver 1 passes it to approver 2. An Admin's approval is final.
  v_next := route_approver(r.region, r.approval_level + 1);
  if v_next is not null and v_next <> r.requestor_id and not has_role('admin') then
    update payment_requests set approval_level = r.approval_level + 1, approver_id = v_next,
      first_approver_id = uid, first_approved_on = now()
    where id = r.id;
    perform log_event(r.id, null, format('Approved by approver %s', r.approval_level), r.status, r.status,
      case when r.requestor_id = uid then 'Self-approved: the approver approved their own request' end);
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
    case when r.requestor_id = uid then 'Self-approved: the approver approved their own request' end);
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
    format('Your payment request %s is funded (Ref no. %s).',
           (select req_no from payment_requests where id = f.payment_request_id), f.ref_no),
    f.payment_request_id, f.id);
end $$;

create or replace function set_fund_reviewed(p_id uuid, p_reviewed boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found or (f.fund_approver_id <> uid and f.fund_requestor_id <> uid and not has_role('admin')) then raise exception 'Fund request not found.'; end if;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  update fund_requests set reviewed = coalesce(p_reviewed, false) where id = f.id;
  if p_reviewed then
    perform log_event(f.payment_request_id, f.id, 'Marked reviewed', null, null);
  end if;
end $$;
