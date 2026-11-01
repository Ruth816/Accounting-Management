-- Fund requests only (Ruth, 1 November): an Admin, or a Fund Requestor who
-- is also a Fund Approver, may prepare a fund request and approve it
-- themselves, so funding goes on when the encoder or approver is absent,
-- resigned or AWOL. The history marks it "Self-approved". Payment requests
-- keep the rule that you cannot approve your own request.

create or replace function validate_fund_request(f fund_requests, p_preparer uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare
  errs text[] := '{}';
  pr_requestor uuid;
begin
  if f.ref_no is null then
    errs := array_append(errs, 'Ref no. is required');
  elsif f.ref_no !~ '^[1-5]- 20[0-9]{2} (0[1-9]|1[0-2]) [0-9]{4}$' then
    errs := array_append(errs, 'Ref no. must look like "2- 2026 10 0075"');
  elsif left(f.ref_no, 1)::int <> f.request_type then
    errs := array_append(errs, format('Ref no. must start with %s- for this request type', f.request_type));
  elsif exists (select 1 from fund_requests where ref_no = f.ref_no and id <> f.id and status <> 'cancelled') then
    errs := array_append(errs, format('Ref no. %s is already used', f.ref_no));
  end if;
  if f.payee is null then errs := array_append(errs, 'Payee is required'); end if;
  if f.description is null then errs := array_append(errs, 'Description is required'); end if;
  if coalesce(f.original_amount, 0) <= 0 then errs := array_append(errs, 'Amount must be above 0'); end if;
  if f.payment_date is null then errs := array_append(errs, 'Payment date is required'); end if;
  if f.payment_method is null then errs := array_append(errs, 'Payment method is required'); end if;
  if f.currency = 'USD' and (coalesce(f.exchange_rate, 0) <= 0 or f.rate_date is null) then
    errs := array_append(errs, 'Enter the exchange rate and rate date for a USD request');
  end if;
  if f.payment_method = 'FUND TRANSFER' and (f.bank_account_name is null or f.bank_account_no is null) then
    errs := array_append(errs, 'Bank account name and number are required for a bank transfer');
  end if;
  if f.payment_method = 'Check' and f.cheque_id is null then
    errs := array_append(errs, 'Choose or enter a cheque');
  end if;
  if f.cheque_id is not null and coalesce(f.subtotal_to_fund, 0) <= 0 then
    errs := array_append(errs, 'Subtotal to fund is required');
  end if;
  if f.tax_code is null or f.tax_rate is null then errs := array_append(errs, 'Tax is required'); end if;
  if f.payment_account is null then errs := array_append(errs, 'Payment account is required'); end if;
  if f.category is null then errs := array_append(errs, 'Category is required'); end if;

  select requestor_id into pr_requestor from payment_requests where id = f.payment_request_id;
  if f.fund_approver_id is null then
    errs := array_append(errs, 'Choose a fund approver');
  elsif not (user_has_role(f.fund_approver_id, 'fund_approver') or user_has_role(f.fund_approver_id, 'admin')) then
    errs := array_append(errs, 'The chosen fund approver is not an active Fund Approver');
  end if;

  if array_length(errs, 1) > 0 then
    raise exception '%.', array_to_string(errs, '. ');
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
  if not found or (f.fund_approver_id <> uid and not has_role('admin')) then raise exception 'Fund request not found.'; end if;
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
