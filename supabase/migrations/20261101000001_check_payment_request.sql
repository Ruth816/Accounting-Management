-- Fund request type 6: Check payment request. Like an auto debit request it is
-- started by a Fund Requestor with no payment request stage, but it is paid by
-- cheque. Ref no. prefix 6.
alter table public.fund_requests drop constraint if exists fund_requests_request_type_check;
alter table public.fund_requests add constraint fund_requests_request_type_check
  check (request_type between 1 and 6);

create or replace function create_check_payment_request() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  v_fr uuid;
  v_approver uuid;
begin
  select default_fund_approver into v_approver from profiles where id = uid;
  if v_approver = uid then v_approver := null; end if;
  insert into fund_requests (request_type, fund_requestor_id, fund_approver_id, payment_method)
  values (6, uid, v_approver, 'Check')
  returning id into v_fr;
  perform log_event(null, v_fr, 'Check payment request created', null, 'in_funding_preparation');
  return v_fr;
end $$;

revoke execute on function create_check_payment_request() from public, anon;
grant execute on function create_check_payment_request() to authenticated;

create or replace function validate_fund_request(f fund_requests, p_preparer uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare
  errs text[] := '{}';
  pr_requestor uuid;
begin
  if f.ref_no is null then
    errs := array_append(errs, 'Ref no. is required');
  elsif f.ref_no !~ '^[1-6]- 20[0-9]{2} (0[1-9]|1[0-2]) [0-9]{4}$' then
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
  if f.payment_method = 'Bank transfer' and (f.bank_account_name is null or f.bank_account_no is null) then
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
  elsif f.fund_approver_id = p_preparer or f.fund_approver_id = pr_requestor then
    errs := array_append(errs, 'The fund approver cannot be the person who prepared or requested it');
  elsif not user_has_role(f.fund_approver_id, 'fund_approver') then
    errs := array_append(errs, 'The chosen fund approver is not an active Fund Approver');
  end if;

  if array_length(errs, 1) > 0 then
    raise exception '%.', array_to_string(errs, '. ');
  end if;
end $$;
