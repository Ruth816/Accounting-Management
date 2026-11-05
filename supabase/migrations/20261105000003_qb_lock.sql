-- Once a request is posted to QuickBooks it is locked: no more edits and no
-- deletion (Ruth, 5 November). Edits made after approval and before posting
-- stay time-stamped in the history ("Edited after approval", with who and when).
-- Safe to run again.

create or replace function save_payment_request(p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
  v_items jsonb;
  v_approver uuid;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'description', coalesce(btrim(e ->> 'description'), ''),
           'amount', round(nullif(btrim(replace(e ->> 'amount', ',', '')), '')::numeric, 2)
         ) order by i), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(p -> 'items', '[]'::jsonb)) with ordinality as t(e, i)
   where coalesce(btrim(e ->> 'description'), '') <> ''
      or nullif(btrim(e ->> 'amount'), '') is not null;

  v_approver := txt(p, 'approver_id')::uuid;

  if p_id is null then
    if v_approver is null then
      select default_payment_approver into v_approver from profiles where id = uid;
    end if;
    insert into payment_requests (req_no, requestor_id, approver_id)
    values (next_req_no(), uid, v_approver)
    returning * into r;
    perform log_event(r.id, null, 'Created', null, 'draft');
  else
    select * into r from payment_requests where id = p_id for update;
    if not found or (r.requestor_id <> uid and not has_role('admin')) then
      raise exception 'Payment request not found.';
    end if;
    -- An Admin may correct details after approval (Ruth, 5 November); the status stays.
    if r.status in ('draft', 'returned_to_requestor') then
      null;
    elsif r.status = 'approved_posted_to_qb' then
      raise exception 'Posted to QuickBooks: this request can no longer be edited.';
    elsif has_role('admin') and r.status not in ('cancelled', 'expired', 'pending_payment_approval') then
      perform log_event(r.id, r.fund_request_id, 'Edited after approval', r.status, r.status);
    else
      raise exception 'Only a draft or returned request can be edited.';
    end if;
    -- The approver is locked once the request has been returned.
    if r.status = 'draft' then
      update payment_requests set approver_id = v_approver where id = r.id;
    end if;
  end if;

  update payment_requests set
    request_kind      = coalesce(txt(p, 'request_kind'),
                                 case when (p ->> 'reimbursable')::boolean then 'reimbursable' else 'regular' end),
    region            = coalesce(txt(p, 'region'), 'NCR'),
    project_name      = txt(p, 'project_name'),
    project_type      = txt(p, 'project_type'),
    job_order_no      = txt(p, 'job_order_no'),
    addendum_no       = txt(p, 'addendum_no'),
    work_order_no     = txt(p, 'work_order_no'),
    date_required     = txt(p, 'date_required')::date,
    payable_to        = txt(p, 'payable_to'),
    payment_type      = coalesce(txt(p, 'payment_type'), 'Cheque'),
    billing_type      = coalesce(txt(p, 'billing_type'), 'VAT'),
    currency          = coalesce(txt(p, 'currency'), 'PHP'),
    purpose           = txt(p, 'purpose'),
    items             = v_items,
    po_num            = txt(p, 'po_num'),
    po_date           = txt(p, 'po_date')::date,
    po_amount         = num(p, 'po_amount'),
    po_mode           = txt(p, 'po_mode'),
    last_payment_ref  = txt(p, 'last_payment_ref'),
    wtax_rate         = coalesce(num(p, 'wtax_rate'), 0),
    bank_transfer_fee = num(p, 'bank_transfer_fee'),
    terms_accepted    = coalesce((p ->> 'terms_accepted')::boolean, false)
  where id = r.id;

  return r.id;
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
  if not f.locked and f.status in ('in_funding_preparation', 'returned_to_fund_requestor') then
    null;
  elsif f.status = 'approved_posted_to_qb' then
    raise exception 'Posted to QuickBooks: this request can no longer be edited.';
  elsif has_role('admin') and f.status in ('approved_ready_for_qb', 'sync_failed') then
    perform log_event(f.payment_request_id, f.id, 'Edited after approval', f.status, f.status);
  else
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
  if not (not f.locked and f.status in ('in_funding_preparation', 'returned_to_fund_requestor'))
     and not (has_role('admin') and f.status in ('approved_ready_for_qb', 'sync_failed')) then
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
