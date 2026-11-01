-- Real QuickBooks lists (spec section 10, Ruth 31 October / 1 November).
-- Payment methods: Cash, Check, Credit Card, Direct Debit, FUND TRANSFER.
-- Categories: expense and cost-of-goods-sold accounts only; sub-accounts as "Parent:Child"
-- (QuickBooks full names); locked parents are left out so only their sub-accounts can be picked.

alter table lookups add column if not exists qb_type text;

-- Payment methods on fund requests follow QuickBooks names.
alter table fund_requests drop constraint if exists fund_requests_payment_method_check;
update fund_requests set payment_method = 'FUND TRANSFER' where payment_method = 'Bank transfer';
update fund_requests set payment_method = 'Direct Debit' where payment_method = 'Auto debit';
alter table fund_requests add constraint fund_requests_payment_method_check
  check (payment_method in ('Cash', 'Check', 'Credit Card', 'Direct Debit', 'FUND TRANSFER'));

-- Replace the sample lists.
delete from lookups where list in ('payment_method', 'payment_account', 'category');
insert into lookups (list, label, qb_type, sort) values
  ('category', 'AMORTIZATION EXPENSES:Credit Line Partial Payment', 'Expense', 1),
  ('category', 'BANK CHARGES', 'Expense', 2),
  ('category', 'BANK CHARGES:Credit line Renewal Fees', 'Expense', 3),
  ('category', 'BANK CHARGES:Interest expense', 'Expense', 4),
  ('category', 'BANK CHARGES:Transfer & MC Fees', 'Expense', 5),
  ('category', 'Bad debts', 'Expense', 6),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES', 'Expense', 7),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES:Business License & Permits- Admin', 'Expense', 8),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES:Legal and professional fees', 'Expense', 9),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES:Penalties & Late filings', 'Expense', 10),
  ('category', 'INSURANCE EXPENSES', 'Expense', 11),
  ('category', 'INSURANCE EXPENSES:Insurance - Disability', 'Expense', 12),
  ('category', 'INSURANCE EXPENSES:Insurance - General', 'Expense', 13),
  ('category', 'INSURANCE EXPENSES:Insurance - Liability', 'Expense', 14),
  ('category', 'Loss on discontinued operations, net of tax', 'Expense', 15),
  ('category', 'MEALS & ENTERTAINMENT', 'Expense', 16),
  ('category', 'MEALS & ENTERTAINMENT:Company Events & recreational', 'Expense', 17),
  ('category', 'MEALS & ENTERTAINMENT:Official Meals & Entertainment Expense', 'Expense', 18),
  ('category', 'MISCELLANEOUS', 'Expense', 19),
  ('category', 'MISCELLANEOUS:Other- Hauling Services', 'Expense', 20),
  ('category', 'MISCELLANEOUS:Other- Office Expenses', 'Expense', 21),
  ('category', 'OFFICE EXPENSES- Admin', 'Expense', 22),
  ('category', 'OFFICE EXPENSES- Admin:Office Supplies', 'Expense', 23),
  ('category', 'OFFICE EXPENSES- Admin:Office Uniform', 'Expense', 24),
  ('category', 'OFFICE EXPENSES- Admin:Office equipment rental & maintenance', 'Expense', 25),
  ('category', 'OFFICE EXPENSES- Admin:Printing & Fax', 'Expense', 26),
  ('category', 'OFFICE EXPENSES- Admin:Shipping and delivery expense', 'Expense', 27),
  ('category', 'OFFICE EXPENSES- Admin:Software/ APP Subscriptions', 'Expense', 28),
  ('category', 'OFFICE EXPENSES- Admin:Trainings & Seminar', 'Expense', 29),
  ('category', 'OFFICE EXPENSES- Admin:Utilities (light, water & Internet)', 'Expense', 30),
  ('category', 'OFFICE EXPENSES- Admin:Utilities (light, water & Internet):Mobile Allowances', 'Expense', 31),
  ('category', 'Other Types of Expenses-Advertising Expenses', 'Expense', 32),
  ('category', 'Other selling expenses', 'Expense', 33),
  ('category', 'PAYROLL EXPENSES', 'Expense', 34),
  ('category', 'PAYROLL EXPENSES:13th month & last Pay', 'Expense', 35),
  ('category', 'PAYROLL EXPENSES:Benefits HMO , Medical & Hospitalization', 'Expense', 36),
  ('category', 'PAYROLL EXPENSES:Benefits Mandatory', 'Expense', 37),
  ('category', 'PAYROLL EXPENSES:Benefits Perks & Rewards', 'Expense', 38),
  ('category', 'PAYROLL EXPENSES:Incentive & Bonuses', 'Expense', 39),
  ('category', 'Purchases', 'Expense', 40),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin', 'Expense', 41),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Assoc/ Admin dues', 'Expense', 42),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Employees Housing Expense', 'Expense', 43),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Rental Payments (Ofc/Warehouse)', 'Expense', 44),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Repairs & Improvement Expense', 'Expense', 45),
  ('category', 'SALARIES & WAGES EXPENSES', 'Expense', 46),
  ('category', 'SALARIES & WAGES EXPENSES:Cash Allowances', 'Expense', 47),
  ('category', 'SALARIES & WAGES EXPENSES:Salaries', 'Expense', 48),
  ('category', 'SPONSORSHIP & EVENTS Expenses', 'Expense', 49),
  ('category', 'SPONSORSHIP & EVENTS Expenses:Client Events Support', 'Expense', 50),
  ('category', 'SPONSORSHIP & EVENTS Expenses:Community Share', 'Expense', 51),
  ('category', 'SPONSORSHIP & EVENTS Expenses:Education Scholarship', 'Expense', 52),
  ('category', 'TAX PAID', 'Expense', 53),
  ('category', 'TAX PAID:BIR (Business Taxes)', 'Expense', 54),
  ('category', 'TAX PAID:Income tax expense', 'Expense', 55),
  ('category', 'TAX PAID:Property TAX', 'Expense', 56),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Fuel/Gasoline, Tolls, Taxi ,Parking & Angkas', 'Expense', 57),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Transpo Allowances', 'Expense', 58),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:VEHICLES Amortization', 'Expense', 59),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Vehicles (Registration& Insurance)', 'Expense', 60),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Vehicles (maintenance & repair)', 'Expense', 61),
  ('category', 'TRAVEL EXPENSES- Admin', 'Expense', 62),
  ('category', 'TRAVEL EXPENSES- Admin:Airfare, accommodation & allowances', 'Expense', 63),
  ('category', 'Unapplied Cash Bill Payment Expense', 'Expense', 64),
  ('category', 'Uncategorized Expense', 'Expense', 65),
  ('category', 'Wage expenses', 'Expense', 66),
  ('category', 'Cost of sales', 'Cost of Goods Sold', 67),
  ('category', 'PROJ Commissions & Fees', 'Cost of Goods Sold', 68),
  ('category', 'PROJ Mobilization Expenses', 'Cost of Goods Sold', 69),
  ('category', 'PROJ Mobilization Expenses:PROJ Permitting & Safety Expenses', 'Cost of Goods Sold', 70),
  ('category', 'PROJ Mobilization Expenses:PROJ Tools/Equipment Repairs', 'Cost of Goods Sold', 71),
  ('category', 'PROJ Mobilization Expenses:PROJ Vehicles Expenses', 'Cost of Goods Sold', 72),
  ('category', 'PROJ SUBCON', 'Cost of Goods Sold', 73),
  ('category', 'PROJ Supplies & Materials', 'Cost of Goods Sold', 74),
  ('category', 'PROJ Supplies & Materials:PROJ Freight and delivery Fees', 'Cost of Goods Sold', 75),
  ('payment_account', 'CREDIT Line Expenses', 'Bank', 76),
  ('payment_account', 'Cash and cash equivalents', 'Bank', 77),
  ('payment_account', 'ADVANCES', 'Other Current Asset', 78),
  ('payment_account', 'ADVANCES:Directors Advances', 'Other Current Asset', 79),
  ('payment_account', 'ADVANCES:Employees Adv/Loan', 'Other Current Asset', 80),
  ('payment_account', 'Allowance for bad debt', 'Other Current Asset', 81),
  ('payment_account', 'Available for sale assets (short-term)', 'Other Current Asset', 82),
  ('payment_account', 'Inventory', 'Other Current Asset', 83),
  ('payment_account', 'Inventory Asset', 'Other Current Asset', 84),
  ('payment_account', 'Prepaid expenses', 'Other Current Asset', 85),
  ('payment_account', 'Uncategorized Asset', 'Other Current Asset', 86),
  ('payment_account', 'Undeposited Funds', 'Other Current Asset', 87),
  ('payment_method', 'Cash', null, 88),
  ('payment_method', 'Check', null, 89),
  ('payment_method', 'Credit Card', null, 90),
  ('payment_method', 'Direct Debit', null, 91),
  ('payment_method', 'FUND TRANSFER', null, 92)
on conflict (list, label) do update set qb_type = excluded.qb_type, sort = excluded.sort, active = true;

create or replace function receive_payment_request(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  r payment_requests;
  v_fr uuid;
  v_type smallint;
  v_approver uuid;
  v_desc text;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  if r.status <> 'approved_awaiting_funding' then raise exception 'This request is not waiting for funding.'; end if;

  v_type := case
    when r.region = 'NCR' and not r.reimbursable then 2
    when r.region = 'VisMin' and not r.reimbursable then 3
    when r.region = 'NCR' and r.reimbursable then 4
    else 5 end;

  select default_fund_approver into v_approver from profiles where id = uid;
  if v_approver = uid then v_approver := null; end if;

  select r.purpose || coalesce(E'\n' || string_agg(format('%s. %s', i, e ->> 'description'), E'\n' order by i), '')
    into v_desc
    from jsonb_array_elements(r.items) with ordinality as t(e, i);

  insert into fund_requests (
    request_type, payment_request_id, fund_requestor_id, fund_approver_id, status,
    payee, item_no, description, currency, original_amount,
    payment_method, tax_code, tax_rate, tax_locked, wtax_note
  ) values (
    v_type, r.id, uid, v_approver, 'in_funding_preparation',
    r.payable_to, r.item_no, v_desc, r.currency, r.total_vat_in,
    case r.payment_type when 'Cash' then 'Cash' when 'Cheque' then 'Check' else 'FUND TRANSFER' end,
    case when r.billing_type <> 'VAT' then 'No VAT (0%)' end,
    case when r.billing_type <> 'VAT' then 0 end,
    r.billing_type <> 'VAT',
    case when r.wtax_rate > 0 then
      format('Less W-tax %s%%: %s %s. Total amount due: %s %s.',
             (r.wtax_rate * 100)::int, r.currency, money_txt(r.wtax_amount), r.currency, money_txt(r.total_due))
    end
  ) returning id into v_fr;

  insert into attachments (fund_request_id, storage_path, file_name, uploaded_by)
  select v_fr, storage_path, file_name, uploaded_by from attachments where payment_request_id = r.id;

  perform log_event(r.id, v_fr, 'Received for funding', r.status, 'in_funding_preparation');
  return v_fr;
end $$;

create or replace function create_auto_debit_request() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  v_fr uuid;
  v_approver uuid;
begin
  select default_fund_approver into v_approver from profiles where id = uid;
  if v_approver = uid then v_approver := null; end if;
  insert into fund_requests (request_type, fund_requestor_id, fund_approver_id, payment_method)
  values (1, uid, v_approver, 'Direct Debit')
  returning id into v_fr;
  perform log_event(null, v_fr, 'Auto debit request created', null, 'in_funding_preparation');
  return v_fr;
end $$;

create or replace function save_fund_request(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  f fund_requests;
  v_method text;
  v_tax text;
  v_cheque uuid;
  v_mode text := coalesce(txt(p, 'cheque_mode'), 'none');
  v_cheque_no text := txt(p, 'cheque_no');
  v_memo text := txt(p, 'memo');
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.locked or f.status not in ('in_funding_preparation', 'returned_to_fund_requestor') then
    raise exception 'This fund request can no longer be edited.';
  end if;

  v_method := txt(p, 'payment_method');
  if f.request_type = 1 and v_method is null then v_method := 'Direct Debit'; end if;

  -- Cheque (spec 5.5): only for Check.
  if v_method = 'Check' and v_mode = 'new' and v_cheque_no is not null then
    select id into v_cheque from cheques where cheque_no = v_cheque_no;
    if found then
      if v_cheque is distinct from f.cheque_id then
        raise exception 'Cheque number % already exists. Select it from the existing cheques instead.', v_cheque_no;
      end if;
    else
      insert into cheques (cheque_no, created_by) values (v_cheque_no, uid) returning id into v_cheque;
    end if;
  elsif v_method = 'Check' and v_mode = 'existing' then
    v_cheque := txt(p, 'cheque_id')::uuid;
    if v_cheque is not null and v_cheque is distinct from f.cheque_id
       and exists (select 1 from fund_requests where cheque_id = v_cheque and locked) then
      raise exception 'That cheque already has an approved request and cannot take more.';
    end if;
  else
    v_cheque := null;
  end if;

  v_tax := case when f.tax_locked then f.tax_code else txt(p, 'tax_code') end;

  begin
  update fund_requests set
    ref_no            = txt(p, 'ref_no'),
    payee             = case when payment_request_id is null then txt(p, 'payee') else payee end,
    item_no           = case when payment_request_id is null then txt(p, 'item_no') else item_no end,
    description       = case when payment_request_id is null then txt(p, 'description') else description end,
    currency          = case when payment_request_id is null then coalesce(txt(p, 'currency'), 'PHP') else currency end,
    original_amount   = case when payment_request_id is null then num(p, 'original_amount') else original_amount end,
    exchange_rate     = case when num(p, 'exchange_rate') is null then null
                             else round(replace(p ->> 'exchange_rate', ',', '')::numeric, 4) end,
    rate_date         = txt(p, 'rate_date')::date,
    payment_date      = txt(p, 'payment_date')::date,
    payment_method    = v_method,
    cash_received_by  = case when v_method = 'Cash' then txt(p, 'cash_received_by') end,
    bank_account_name = case when v_method in ('FUND TRANSFER', 'Direct Debit') then txt(p, 'bank_account_name') end,
    bank_account_no   = case when v_method in ('FUND TRANSFER', 'Direct Debit') then txt(p, 'bank_account_no') end,
    tax_code          = v_tax,
    tax_rate          = case when tax_locked then tax_rate
                             else (select rate from lookups where list = 'tax_code' and label = v_tax) end,
    payment_account   = txt(p, 'payment_account'),
    category          = txt(p, 'category'),
    fund_approver_id  = txt(p, 'fund_approver_id')::uuid,
    cheque_id         = v_cheque,
    subtotal_to_fund  = case when v_cheque is not null then num(p, 'subtotal_to_fund') end,
    -- An emptied memo goes back to the automatic pre-fill.
    memo_edited       = case when v_memo is null then false
                             else memo_edited or v_memo is distinct from memo end,
    memo              = v_memo
  where id = f.id;
  exception when unique_violation then
    raise exception 'Ref no. % is already used by another fund request.', txt(p, 'ref_no');
  end;

  perform refresh_cheque_memos(v_cheque);
  if f.cheque_id is distinct from v_cheque then
    perform refresh_cheque_memos(f.cheque_id);
    update fund_requests set memo = null where id = f.id and v_cheque is null and not memo_edited;
  end if;
end $$;

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
  elsif f.fund_approver_id = p_preparer or f.fund_approver_id = pr_requestor then
    errs := array_append(errs, 'The fund approver cannot be the person who prepared or requested it');
  elsif not user_has_role(f.fund_approver_id, 'fund_approver') then
    errs := array_append(errs, 'The chosen fund approver is not an active Fund Approver');
  end if;

  if array_length(errs, 1) > 0 then
    raise exception '%.', array_to_string(errs, '. ');
  end if;
end $$;

