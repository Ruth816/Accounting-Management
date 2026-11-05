-- Correction (Ruth, 5 November): only Admins and Fund Approvers may approve
-- their own requests. A Payment Approver cannot approve their own payment
-- request, and cannot also be a Payment Requestor.


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
  elsif r.approver_id = r.requestor_id and not user_has_role(r.requestor_id, 'admin') then
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
  -- Only an Admin may approve their own payment request.
  if r.requestor_id = uid and not has_role('admin') then raise exception 'You cannot approve your own request.'; end if;
  perform check_payment_approver(r, uid);

  -- VisMin: approver 1 passes it to approver 2. An Admin's approval is final.
  v_next := route_approver(r.region, r.approval_level + 1);
  if v_next is not null and v_next <> r.requestor_id and not has_role('admin') then
    update payment_requests set approval_level = r.approval_level + 1, approver_id = v_next,
      first_approver_id = uid, first_approved_on = now()
    where id = r.id;
    perform log_event(r.id, null, format('Approved by approver %s', r.approval_level), r.status, r.status,
      case when r.requestor_id = uid then 'Self-approved: the Admin approved their own request' end);
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

-- A Payment Approver can't also be a Payment Requestor. Checked when roles
-- change, so existing accounts keep working until an Admin edits their roles.
create or replace function check_role_combination() returns trigger
language plpgsql as $$
begin
  if 'payment_approver' = any (new.roles) and 'payment_requestor' = any (new.roles)
     and (tg_op = 'INSERT' or new.roles is distinct from old.roles) then
    raise exception 'A Payment Approver cannot also be a Payment Requestor. Choose one of the two roles.';
  end if;
  return new;
end $$;

drop trigger if exists check_role_combination on profiles;
create trigger check_role_combination before insert or update of roles on profiles
  for each row execute function check_role_combination();

