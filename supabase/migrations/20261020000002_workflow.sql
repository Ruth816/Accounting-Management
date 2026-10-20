-- Finance Approval Portal: workflow functions.
-- Each button in the portal calls one of these. They check who the caller
-- is, the request's status and the spec's rules, then write the change, the
-- audit log entry and any notifications in one transaction.

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

create function require_user() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not exists (select 1 from profiles where id = uid and active) then
    raise exception 'You are not signed in, or your account is inactive.';
  end if;
  return uid;
end $$;

create function require_role(r app_role) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := require_user();
begin
  if not has_role(r) then
    raise exception 'This needs the % role.', initcap(replace(r::text, '_', ' '));
  end if;
  return uid;
end $$;

create function txt(p jsonb, k text) returns text
language sql immutable as $$
  select nullif(btrim(p ->> k), '');
$$;

create function num(p jsonb, k text) returns numeric
language plpgsql immutable as $$
declare v text := nullif(btrim(replace(p ->> k, ',', '')), '');
begin
  if v is null then return null; end if;
  return round(v::numeric, 2);
exception when others then
  raise exception 'Enter a number for %.', k;
end $$;

create function money_txt(v numeric) returns text
language sql immutable as $$
  select to_char(coalesce(v, 0), 'FM999,999,999,990.00');
$$;

create function normalize_mobile(raw text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g');
begin
  if d = '' then return null; end if;
  if d ~ '^09[0-9]{9}$' then return '63' || substr(d, 2); end if;
  if d ~ '^9[0-9]{9}$' then return '63' || d; end if;
  if d ~ '^63[0-9]{10}$' then return d; end if;
  raise exception 'Mobile number % is not a valid Philippine mobile number (09XXXXXXXXX or 63XXXXXXXXXX).', raw;
end $$;

create function log_event(
  p_pr uuid, p_fr uuid, p_action text,
  p_old request_status, p_new request_status, p_note text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_ref text;
begin
  select coalesce(
    (select ref_no from fund_requests where id = p_fr),
    (select req_no from payment_requests where id = p_pr)
  ) into v_ref;
  insert into audit_log (payment_request_id, fund_request_id, ref, action, actor_id, old_status, new_status, note)
  values (p_pr, p_fr, v_ref, p_action, auth.uid(), p_old, p_new, p_note);
end $$;

create function notify(p_to uuid, p_message text, p_pr uuid default null, p_fr uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
declare v_mobile text;
begin
  if p_to is null then return; end if;
  select mobile_no into v_mobile from profiles where id = p_to and active;
  if not found then return; end if;
  insert into notifications (recipient_id, message, payment_request_id, fund_request_id, sms_status, sms_mobile_no)
  values (p_to, p_message, p_pr, p_fr,
          case when v_mobile is null then 'No mobile' else 'Queued' end, v_mobile);
end $$;

create function notify_role(p_role app_role, p_message text, p_pr uuid default null, p_fr uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from profiles where active and p_role = any (roles) loop
    perform notify(r.id, p_message, p_pr, p_fr);
  end loop;
end $$;

create function touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger payment_requests_touch before update on payment_requests
for each row execute function touch_updated_at();
create trigger fund_requests_touch before update on fund_requests
for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- Payment request numbering and amounts
-- ---------------------------------------------------------------------------

-- "2026 10 0077": year, month, running number for that month (Manila time).
create function next_req_no() returns text
language plpgsql security definer set search_path = public as $$
declare
  ym text := to_char(now() at time zone 'Asia/Manila', 'YYYYMM');
  n int;
begin
  insert into req_counters (yyyymm, last_no) values (ym, 1)
  on conflict (yyyymm) do update set last_no = req_counters.last_no + 1
  returning last_no into n;
  return substr(ym, 1, 4) || ' ' || substr(ym, 5, 2) || ' ' || lpad(n::text, 4, '0');
end $$;

-- Spec 4.2 and 4.4.
create function compute_pr_amounts() returns trigger
language plpgsql as $$
declare
  priced int;
begin
  select coalesce(round(sum((e ->> 'amount')::numeric), 2), 0),
         count(*) filter (where (e ->> 'amount')::numeric > 0)
    into new.total_vat_in, priced
    from jsonb_array_elements(new.items) e
   where nullif(e ->> 'amount', '') is not null;

  new.total_vat_ex := case when new.billing_type = 'VAT'
                           then round(new.total_vat_in / 1.12, 2)
                           else new.total_vat_in end;
  new.wtax_amount := round(new.total_vat_ex * new.wtax_rate, 2);
  new.total_due := new.total_vat_in - new.wtax_amount;
  new.item_no := case when jsonb_array_length(new.items) <= 1 then '1'
                      else '1-' || jsonb_array_length(new.items) end;
  return new;
end $$;

create trigger payment_requests_amounts before insert or update on payment_requests
for each row execute function compute_pr_amounts();

-- Once a payment request has a fund request, it shows the fund request's
-- status (spec section 3), except Cancelled.
create function mirror_fund_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.payment_request_id is not null and new.status <> 'cancelled' then
    update payment_requests
       set status = new.status, fund_request_id = new.id
     where id = new.payment_request_id
       and (status is distinct from new.status or fund_request_id is distinct from new.id);
  end if;
  return new;
end $$;

create trigger fund_requests_mirror after insert or update of status on fund_requests
for each row execute function mirror_fund_status();

-- ---------------------------------------------------------------------------
-- Stage 1: payment requests
-- ---------------------------------------------------------------------------

-- Save as draft (new or existing). No checks beyond types.
create function save_payment_request(p_id uuid, p jsonb) returns uuid
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
    if not found or r.requestor_id <> uid then
      raise exception 'Payment request not found.';
    end if;
    if r.status not in ('draft', 'returned_to_requestor') then
      raise exception 'Only a draft or returned request can be edited.';
    end if;
    -- The approver is locked once the request has been returned.
    if r.status = 'draft' then
      update payment_requests set approver_id = v_approver where id = r.id;
    end if;
  end if;

  update payment_requests set
    reimbursable      = coalesce((p ->> 'reimbursable')::boolean, false),
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

create function validate_payment_request(r payment_requests) returns void
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
  elsif r.approver_id = r.requestor_id then
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

-- Submit (from Draft) or Resubmit (from Returned: same approver, version + 1).
create function submit_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
  resubmit boolean;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or r.requestor_id <> uid then raise exception 'Payment request not found.'; end if;
  if r.status not in ('draft', 'returned_to_requestor') then
    raise exception 'This request has already been submitted.';
  end if;
  perform validate_payment_request(r);
  resubmit := r.status = 'returned_to_requestor';

  update payment_requests set
    status = 'pending_payment_approval',
    version = version + case when resubmit then 1 else 0 end,
    returned_on = null, expires_on = null,
    reminder_23_sent = false, reminder_28_sent = false,
    submitted_on = now()
  where id = r.id;

  perform log_event(r.id, null, case when resubmit then 'Resubmitted' else 'Submitted' end,
                    r.status, 'pending_payment_approval',
                    case when resubmit then 'Version ' || (r.version + 1) end);
  perform notify(r.approver_id,
    format('Payment request %s from %s (%s %s) is waiting for your approval.',
           r.req_no, (select full_name from profiles where id = uid), r.currency, money_txt(r.total_due)),
    r.id);
end $$;

create function cancel_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r payment_requests;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or r.requestor_id <> uid then raise exception 'Payment request not found.'; end if;
  if r.status not in ('draft', 'returned_to_requestor') then
    raise exception 'Only a draft or returned request can be cancelled.';
  end if;
  update payment_requests set status = 'cancelled', returned_on = null, expires_on = null where id = r.id;
  perform log_event(r.id, null, 'Cancelled', r.status, 'cancelled');
end $$;

create function approve_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or r.approver_id <> uid then raise exception 'Payment request not found.'; end if;
  if r.requestor_id = uid then raise exception 'You cannot approve your own request.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;

  update payment_requests set status = 'approved_awaiting_funding', approved_on = now(),
    disapproval_reason = null, return_note = null
  where id = r.id;
  perform log_event(r.id, null, 'Approved', r.status, 'approved_awaiting_funding');
  perform notify(r.requestor_id, format('Your payment request %s was approved and is waiting for funding.', r.req_no), r.id);
  perform notify_role('fund_requestor',
    format('Payment request %s (%s, %s %s) is approved and ready to receive for funding.',
           r.req_no, r.payable_to, r.currency, money_txt(r.total_due)), r.id);
end $$;

create function disapprove_payment_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required to disapprove.'; end if;
  select * into r from payment_requests where id = p_id for update;
  if not found or r.approver_id <> uid then raise exception 'Payment request not found.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;

  insert into payment_request_versions (payment_request_id, version, snapshot, reason, returned_by)
  values (r.id, r.version, to_jsonb(r), btrim(p_reason), uid);

  update payment_requests set
    status = 'returned_to_requestor',
    disapproval_reason = btrim(p_reason),
    returned_on = now(),
    expires_on = now() + interval '30 days',
    reminder_23_sent = false, reminder_28_sent = false
  where id = r.id;
  perform log_event(r.id, null, 'Disapproved', r.status, 'returned_to_requestor', btrim(p_reason));
  perform notify(r.requestor_id,
    format('Payment request %s was returned: %s. Resubmit within 30 days or it will be deleted.', r.req_no, btrim(p_reason)),
    r.id);
end $$;

-- Spec 4.9: liquidation of a funded cash request.
create function liquidate_payment_request(
  p_id uuid, p_actual_used numeric, p_deposit_date date, p_deposit_amount numeric, p_deposit_bank text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r payment_requests;
  f fund_requests;
  v_change numeric;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or r.requestor_id <> uid then raise exception 'Payment request not found.'; end if;
  if r.payment_type <> 'Cash' then raise exception 'Only cash requests are liquidated.'; end if;
  if r.liquidated_on is not null then raise exception 'This request is already liquidated.'; end if;
  select * into f from fund_requests where id = r.fund_request_id;
  if not found or f.status not in ('approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed') then
    raise exception 'You can liquidate once the fund request is approved.';
  end if;
  if p_actual_used is null or p_actual_used < 0 then raise exception 'Enter the actual amount used.'; end if;

  v_change := coalesce(f.amount_php, 0) - round(p_actual_used, 2);
  if v_change > 0 and (p_deposit_date is null or p_deposit_amount is null or nullif(btrim(p_deposit_bank), '') is null) then
    raise exception 'There is change of PHP %. Enter the deposit-back date, amount and bank.', money_txt(v_change);
  end if;

  update payment_requests set
    liq_actual_used = round(p_actual_used, 2),
    liq_change = v_change,
    liq_deposit_date = p_deposit_date,
    liq_deposit_amount = round(p_deposit_amount, 2),
    liq_deposit_bank = nullif(btrim(p_deposit_bank), ''),
    liquidated_on = now()
  where id = r.id;
  perform log_event(r.id, f.id, 'Liquidated', null, null,
    format('Used PHP %s, change PHP %s', money_txt(p_actual_used), money_txt(v_change)));
  perform notify_role('fund_requestor',
    format('Payment request %s was liquidated: used PHP %s, change PHP %s.', r.req_no, money_txt(p_actual_used), money_txt(v_change)),
    r.id, f.id);
end $$;

-- ---------------------------------------------------------------------------
-- Stage 2: fund requests
-- ---------------------------------------------------------------------------

create function cheque_total(p_cheque uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(subtotal_to_fund), 0) from fund_requests
  where cheque_id = p_cheque and status <> 'cancelled';
$$;

-- Cheques that can still take requests: none of their requests is approved.
create function available_cheques()
returns table (id uuid, cheque_no text, total numeric)
language sql stable security definer set search_path = public as $$
  select c.id, c.cheque_no, cheque_total(c.id)
  from cheques c
  where has_role('fund_requestor')
    and not exists (select 1 from fund_requests f where f.cheque_id = c.id and f.locked)
  order by c.created_at desc;
$$;

-- Spec 5.5 memo pre-fill, for every unlocked, unedited request on a cheque.
create function refresh_cheque_memos(p_cheque uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_no text; v_total numeric;
begin
  if p_cheque is null then return; end if;
  select cheque_no into v_no from cheques where id = p_cheque;
  v_total := cheque_total(p_cheque);
  update fund_requests set memo = format('Check No. %s | Check total PHP %s | Subtotal funded PHP %s',
                                         v_no, money_txt(v_total), money_txt(subtotal_to_fund))
   where cheque_id = p_cheque and not locked and not memo_edited and status <> 'cancelled';
end $$;

create function compute_fr_amounts() returns trigger
language plpgsql as $$
declare v_rate numeric;
begin
  if new.currency = 'PHP' then
    new.exchange_rate := 1;
    new.rate_date := null;
  end if;
  v_rate := new.exchange_rate;
  if new.original_amount is null or v_rate is null then
    new.amount_php := null;
  else
    new.amount_php := round(new.original_amount * v_rate, 2);
  end if;
  if new.amount_php is null or new.tax_rate is null then
    new.total_before_tax := null;
    new.sales_tax := null;
  else
    new.total_before_tax := round(new.amount_php / (1 + new.tax_rate), 2);
    new.sales_tax := new.amount_php - new.total_before_tax;
  end if;
  return new;
end $$;

create trigger fund_requests_amounts before insert or update on fund_requests
for each row execute function compute_fr_amounts();

-- Spec 5.1: Receive an approved payment request.
create function receive_payment_request(p_id uuid) returns uuid
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
    case r.payment_type when 'Cash' then 'Cash' when 'Cheque' then 'Check' else 'Bank transfer' end,
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

-- Spec 5.7: New auto debit request (no payment request stage).
create function create_auto_debit_request() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  v_fr uuid;
  v_approver uuid;
begin
  select default_fund_approver into v_approver from profiles where id = uid;
  if v_approver = uid then v_approver := null; end if;
  insert into fund_requests (request_type, fund_requestor_id, fund_approver_id, payment_method)
  values (1, uid, v_approver, 'Auto debit')
  returning id into v_fr;
  perform log_event(null, v_fr, 'Auto debit request created', null, 'in_funding_preparation');
  return v_fr;
end $$;

-- Save as draft. Only checks that a new cheque number is not taken.
create function save_fund_request(p_id uuid, p jsonb) returns void
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
  if f.request_type = 1 and v_method is null then v_method := 'Auto debit'; end if;

  -- Cheque (spec 5.5): used for Check, optional for Auto debit.
  if v_method in ('Check', 'Auto debit') and v_mode = 'new' and v_cheque_no is not null then
    select id into v_cheque from cheques where cheque_no = v_cheque_no;
    if found then
      if v_cheque is distinct from f.cheque_id then
        raise exception 'Cheque number % already exists. Select it from the existing cheques instead.', v_cheque_no;
      end if;
    else
      insert into cheques (cheque_no, created_by) values (v_cheque_no, uid) returning id into v_cheque;
    end if;
  elsif v_method in ('Check', 'Auto debit') and v_mode = 'existing' then
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
    bank_account_name = case when v_method in ('Bank transfer', 'Auto debit') then txt(p, 'bank_account_name') end,
    bank_account_no   = case when v_method in ('Bank transfer', 'Auto debit') then txt(p, 'bank_account_no') end,
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

create function validate_fund_request(f fund_requests, p_preparer uuid) returns void
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

-- Send for fund approval / Resubmit.
create function submit_fund_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  f fund_requests;
  resubmit boolean;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.status not in ('in_funding_preparation', 'returned_to_fund_requestor') then
    raise exception 'This fund request has already been sent.';
  end if;
  perform validate_fund_request(f, uid);
  resubmit := f.status = 'returned_to_fund_requestor';

  update fund_requests set status = 'pending_fund_approval', reviewed = false,
    fund_requestor_id = uid, submitted_on = now()
  where id = f.id;
  perform log_event(f.payment_request_id, f.id,
    case when resubmit then 'Resubmitted for fund approval' else 'Sent for fund approval' end,
    f.status, 'pending_fund_approval');
  perform notify(f.fund_approver_id,
    format('Fund request %s (%s, PHP %s) is waiting for your approval.', f.ref_no, f.payee, money_txt(f.amount_php)),
    f.payment_request_id, f.id);
end $$;

create function set_fund_reviewed(p_id uuid, p_reviewed boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found or f.fund_approver_id <> uid then raise exception 'Fund request not found.'; end if;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  update fund_requests set reviewed = coalesce(p_reviewed, false) where id = f.id;
  if p_reviewed then
    perform log_event(f.payment_request_id, f.id, 'Marked reviewed', null, null);
  end if;
end $$;

create function approve_fund_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
  pr_requestor uuid;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found or f.fund_approver_id <> uid then raise exception 'Fund request not found.'; end if;
  select requestor_id into pr_requestor from payment_requests where id = f.payment_request_id;
  if uid = f.fund_requestor_id or uid = pr_requestor then
    raise exception 'You cannot approve a request you prepared or requested.';
  end if;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  if not f.reviewed then raise exception 'Tick Reviewed before approving.'; end if;

  update fund_requests set status = 'approved_ready_for_qb', approved_by = uid, approved_on = now(),
    locked = true, disapproval_reason = null
  where id = f.id;
  perform log_event(f.payment_request_id, f.id, 'Fund approved', f.status, 'approved_ready_for_qb');
  perform notify(f.fund_requestor_id, format('Fund request %s was approved.', f.ref_no), f.payment_request_id, f.id);
  perform notify(pr_requestor,
    format('Your payment request %s is funded (Ref no. %s).',
           (select req_no from payment_requests where id = f.payment_request_id), f.ref_no),
    f.payment_request_id, f.id);
end $$;

create function disapprove_fund_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required to disapprove.'; end if;
  select * into f from fund_requests where id = p_id for update;
  if not found or f.fund_approver_id <> uid then raise exception 'Fund request not found.'; end if;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  if not f.reviewed then raise exception 'Tick Reviewed before disapproving.'; end if;

  update fund_requests set status = 'returned_to_fund_requestor', disapproval_reason = btrim(p_reason), reviewed = false
  where id = f.id;
  perform log_event(f.payment_request_id, f.id, 'Fund disapproved', f.status, 'returned_to_fund_requestor', btrim(p_reason));
  perform notify(f.fund_requestor_id, format('Fund request %s was returned: %s', f.ref_no, btrim(p_reason)),
                 f.payment_request_id, f.id);
end $$;

-- Spec 5.6: Return to payment approver.
create function return_to_payment_approver(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  f fund_requests;
  r payment_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required.'; end if;
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.status <> 'returned_to_fund_requestor' or f.payment_request_id is null then
    raise exception 'Only a returned fund request linked to a payment request can go back to its approver.';
  end if;
  select * into r from payment_requests where id = f.payment_request_id for update;

  update fund_requests set status = 'cancelled', cheque_id = null where id = f.id;
  perform refresh_cheque_memos(f.cheque_id);

  update payment_requests set status = 'pending_payment_approval', fund_request_id = null,
    approved_on = null, return_note = btrim(p_reason)
  where id = r.id;

  perform log_event(r.id, f.id, 'Returned to payment approver', f.status, 'cancelled', btrim(p_reason));
  perform log_event(r.id, null, 'Back for payment approval', r.status, 'pending_payment_approval', btrim(p_reason));
  perform notify(r.approver_id,
    format('Payment request %s was sent back by funding: %s. Please review it again.', r.req_no, btrim(p_reason)),
    r.id);
end $$;

-- Data for the approval voucher (spec 5.8), including names the fund
-- approver could not otherwise read.
create function get_voucher(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f fund_requests;
  r payment_requests;
begin
  if not can_see_fr(p_id) then raise exception 'Fund request not found.'; end if;
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

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------

create function mark_notifications_read(p_ids uuid[] default null) returns void
language sql security definer set search_path = public as $$
  update notifications set read = true
  where recipient_id = auth.uid() and (p_ids is null or id = any (p_ids));
$$;

-- Called by the server with the service role only.
create function claim_sms_batch(p_limit int default 50)
returns table (id uuid, mobile_no text, message text)
language sql security definer set search_path = public as $$
  update notifications n set sms_status = 'Sending', sms_attempted_on = now()
  where n.id in (select q.id from notifications q where q.sms_status = 'Queued'
                 order by q.created_at limit p_limit for update skip locked)
  returning n.id, n.sms_mobile_no, n.message;
$$;

create function record_sms_result(p_id uuid, p_ok boolean, p_message_id text, p_error text) returns void
language sql security definer set search_path = public as $$
  update notifications set sms_status = case when p_ok then 'Sent' else 'Failed' end,
    sms_message_id = p_message_id, sms_error = p_error
  where id = p_id;
$$;

-- ---------------------------------------------------------------------------
-- Daily job (spec 4.7): reminders on day 23 and 28, expiry on day 30.
-- Sweeping on the current return's date means an earlier return can never
-- fire after a resubmit. Returns storage paths whose files should be removed.
-- ---------------------------------------------------------------------------

create function run_daily_jobs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r payment_requests;
  n_remind int := 0;
  n_expired int := 0;
  paths text[] := '{}';
begin
  for r in select * from payment_requests where status = 'returned_to_requestor' and returned_on is not null for update loop
    if now() >= r.returned_on + interval '30 days' then
      perform log_event(r.id, null, 'Expired', r.status, 'expired', 'Not resubmitted within 30 days; deleted');
      perform notify(r.requestor_id,
        format('Payment request %s was not resubmitted within 30 days and has been deleted.', r.req_no));
      paths := paths || coalesce((select array_agg(storage_path) from attachments a
                                  where a.payment_request_id = r.id
                                    and not exists (select 1 from attachments b
                                                    where b.storage_path = a.storage_path
                                                      and b.payment_request_id is distinct from r.id)), '{}');
      delete from payment_requests where id = r.id;
      n_expired := n_expired + 1;
    elsif now() >= r.returned_on + interval '28 days' and not r.reminder_28_sent then
      perform notify(r.requestor_id, format('Reminder: payment request %s will be deleted in 2 days unless you resubmit it.', r.req_no), r.id);
      update payment_requests set reminder_28_sent = true, reminder_23_sent = true where id = r.id;
      n_remind := n_remind + 1;
    elsif now() >= r.returned_on + interval '23 days' and not r.reminder_23_sent then
      perform notify(r.requestor_id, format('Reminder: payment request %s will be deleted in 7 days unless you resubmit it.', r.req_no), r.id);
      update payment_requests set reminder_23_sent = true where id = r.id;
      n_remind := n_remind + 1;
    end if;
  end loop;
  return jsonb_build_object('reminders', n_remind, 'expired', n_expired, 'storage_paths', to_jsonb(paths));
end $$;

-- ---------------------------------------------------------------------------
-- Attachments and admin
-- ---------------------------------------------------------------------------

-- The file is uploaded first to "<user id>/..." in the attachments bucket.
create function add_attachment(p_pr uuid, p_fr uuid, p_path text, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user();
begin
  if split_part(p_path, '/', 1) <> uid::text then raise exception 'Invalid file path.'; end if;
  if p_pr is not null then
    if not exists (select 1 from payment_requests where id = p_pr and requestor_id = uid
                   and status in ('draft', 'returned_to_requestor')) then
      raise exception 'Files can be added only to your own draft or returned request.';
    end if;
  elsif p_fr is not null then
    if not has_role('fund_requestor') or not exists (
      select 1 from fund_requests where id = p_fr and not locked
        and status in ('in_funding_preparation', 'returned_to_fund_requestor')) then
      raise exception 'Files can be added only while the fund request is being prepared.';
    end if;
  else
    raise exception 'Attach the file to a request.';
  end if;
  insert into attachments (payment_request_id, fund_request_id, storage_path, file_name, uploaded_by)
  values (p_pr, p_fr, p_path, p_name, uid);
end $$;

create function remove_attachment(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  a attachments;
begin
  select * into a from attachments where id = p_id;
  if not found or a.uploaded_by <> uid then raise exception 'Attachment not found.'; end if;
  if a.payment_request_id is not null and not exists (
       select 1 from payment_requests where id = a.payment_request_id and status in ('draft', 'returned_to_requestor')) then
    raise exception 'This request can no longer be changed.';
  end if;
  if a.fund_request_id is not null and exists (select 1 from fund_requests where id = a.fund_request_id and locked) then
    raise exception 'This fund request is locked.';
  end if;
  delete from attachments where id = a.id;
  -- Tell the caller whether the file itself is now unused.
  if exists (select 1 from attachments where storage_path = a.storage_path) then return null; end if;
  return a.storage_path;
end $$;

create function admin_update_user(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  v_roles app_role[];
  v_active boolean := coalesce((p ->> 'active')::boolean, true);
  v_pa uuid := txt(p, 'default_payment_approver')::uuid;
  v_fa uuid := txt(p, 'default_fund_approver')::uuid;
begin
  select coalesce(array_agg(distinct x::app_role), '{}') into v_roles
  from jsonb_array_elements_text(coalesce(p -> 'roles', '[]'::jsonb)) x;

  if v_pa = p_id or (v_pa is not null and not user_has_role(v_pa, 'payment_approver')) then
    raise exception 'The default payment approver must be another active Payment Approver.';
  end if;
  if v_fa = p_id or (v_fa is not null and not user_has_role(v_fa, 'fund_approver')) then
    raise exception 'The default fund approver must be another active Fund Approver.';
  end if;

  update profiles set
    full_name = coalesce(txt(p, 'full_name'), full_name),
    roles = v_roles,
    mobile_no = normalize_mobile(p ->> 'mobile_no'),
    default_payment_approver = v_pa,
    default_fund_approver = v_fa,
    active = v_active
  where id = p_id;
  if not found then raise exception 'User not found.'; end if;

  if not exists (select 1 from profiles where active and 'admin' = any (roles)) then
    raise exception 'At least one active Admin must remain.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Permissions on functions
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function claim_sms_batch(int), record_sms_result(uuid, boolean, text, text),
  run_daily_jobs(), log_event(uuid, uuid, text, request_status, request_status, text),
  notify(uuid, text, uuid, uuid), notify_role(app_role, text, uuid, uuid),
  refresh_cheque_memos(uuid), next_req_no()
  from authenticated;
grant execute on function claim_sms_batch(int), record_sms_result(uuid, boolean, text, text), run_daily_jobs()
  to service_role;
