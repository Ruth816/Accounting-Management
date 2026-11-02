-- Cheque number and cheque amount on every item of a Check fund request
-- (Ruth, 2 November). The request-level cheque section becomes a summary
-- of the cheques issued: subtotal to fund is the sum of the cheque amounts
-- and the memo lists each cheque number with its amount.

create or replace function save_fund_lines(p_id uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  f fund_requests;
  v_lines jsonb;
  v_check boolean;
  v_cheques int;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.payment_request_id is not null then raise exception 'Items come from the payment request.'; end if;
  if f.locked or f.status not in ('in_funding_preparation', 'returned_to_fund_requestor') then
    raise exception 'This fund request can no longer be edited.';
  end if;
  v_check := f.payment_method = 'Check';

  select coalesce(jsonb_agg(jsonb_build_object(
           'description', coalesce(btrim(e ->> 'description'), ''),
           'amount', round(nullif(btrim(replace(e ->> 'amount', ',', '')), '')::numeric, 2),
           'category', nullif(btrim(e ->> 'category'), ''),
           'customer', nullif(btrim(e ->> 'customer'), ''),
           'tax_code', nullif(btrim(e ->> 'tax_code'), ''),
           'cheque_no', case when v_check then nullif(btrim(e ->> 'cheque_no'), '') end,
           'cheque_amount', case when v_check then coalesce(
              round(nullif(btrim(replace(e ->> 'cheque_amount', ',', '')), '')::numeric, 2),
              case when nullif(btrim(e ->> 'cheque_no'), '') is not null
                   then round(nullif(btrim(replace(e ->> 'amount', ',', '')), '')::numeric, 2) end) end
         ) order by i), '[]'::jsonb)
    into v_lines
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, i)
   where coalesce(btrim(e ->> 'description'), '') <> ''
      or nullif(btrim(e ->> 'amount'), '') is not null
      or nullif(btrim(e ->> 'category'), '') is not null
      or nullif(btrim(e ->> 'cheque_no'), '') is not null;

  select count(*) into v_cheques from jsonb_array_elements(v_lines) e where e ->> 'cheque_no' is not null;

  update fund_requests set
    lines = v_lines,
    original_amount = case when jsonb_array_length(v_lines) > 0
                           then (select sum((e ->> 'amount')::numeric) from jsonb_array_elements(v_lines) e)
                           else original_amount end,
    description = case
      when jsonb_array_length(v_lines) = 1 then v_lines -> 0 ->> 'description'
      when jsonb_array_length(v_lines) > 1 then
        (select string_agg(format('%s. %s', i, e ->> 'description'), E'\n' order by i)
           from jsonb_array_elements(v_lines) with ordinality as t(e, i))
      else description end,
    category = case when jsonb_array_length(v_lines) > 0 then v_lines -> 0 ->> 'category' else category end,
    tax_code = case when jsonb_array_length(v_lines) > 0 and not tax_locked then v_lines -> 0 ->> 'tax_code' else tax_code end,
    tax_rate = case when jsonb_array_length(v_lines) > 0 and not tax_locked
                    then (select rate from lookups where list = 'tax_code' and label = v_lines -> 0 ->> 'tax_code')
                    else tax_rate end,
    -- Cheques on the items replace the request-level cheque.
    cheque_id = case when v_cheques > 0 then null else cheque_id end,
    subtotal_to_fund = case when v_cheques > 0
      then (select sum(coalesce((e ->> 'cheque_amount')::numeric, 0)) from jsonb_array_elements(v_lines) e)
      else subtotal_to_fund end,
    memo = case when v_cheques > 0 and not memo_edited then
      (select string_agg(format('Check No. %s PHP %s', c.no, money_txt(c.total)), ' | ' order by c.first)
         from (select e ->> 'cheque_no' as no, sum(coalesce((e ->> 'cheque_amount')::numeric, 0)) as total, min(i) as first
                 from jsonb_array_elements(v_lines) with ordinality as t(e, i)
                where e ->> 'cheque_no' is not null group by e ->> 'cheque_no') c)
      else memo end
  where id = f.id;
end $$;

create or replace function check_fund_lines() returns trigger
language plpgsql as $$
begin
  if new.status = 'pending_fund_approval' and old.status is distinct from new.status then
    if exists (select 1 from jsonb_array_elements(new.lines) e
               where coalesce(e ->> 'description', '') = '' or e ->> 'category' is null
                  or (e ->> 'tax_code' is null and not new.tax_locked)
                  or coalesce((e ->> 'amount')::numeric, 0) <= 0) then
      raise exception 'Every item needs a description, an amount above 0, a tax and a category.';
    end if;
    if new.payment_method = 'Check' and new.cheque_id is null
       and exists (select 1 from jsonb_array_elements(new.lines) e
                   where e ->> 'cheque_no' is null or coalesce((e ->> 'cheque_amount')::numeric, 0) <= 0) then
      raise exception 'Every item needs a cheque number and a cheque amount above 0.';
    end if;
  end if;
  return new;
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
  -- A Check request needs a cheque, or a cheque number on its items.
  if f.payment_method = 'Check' and f.cheque_id is null
     and not (jsonb_array_length(coalesce(f.lines, '[]')) > 0
              and not exists (select 1 from jsonb_array_elements(f.lines) e where e ->> 'cheque_no' is null)) then
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

