-- Editing fund requests until funded (Ruth, 10 November):
--   * a Fund Requestor may edit their own fund request (all its details)
--     until it is funded: while it is being prepared, after it is sent (by
--     taking it back first, as before), and after approval while it is still
--     waiting to be funded;
--   * an Admin or a Fund Approver may edit every fund request at any stage.
-- Two locks stay: a cancelled request, and one exported to QuickBooks
-- (Ruth, 5 November). Edits made once a request is sent keep its status and
-- need remarks, logged with who and when; its Fund Approver is notified.
-- While it is being prepared, any Fund Requestor may still complete it
-- (Ruth, 2 November). Safe to run again.

-- How the caller may edit this fund request:
--   'prep'     being prepared: edit, then send for approval;
--   'in_place' already sent or approved: save changes, the status stays;
--   null       not allowed.
create or replace function fund_request_edit_mode(f fund_requests) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_staff boolean := has_role('admin') or has_role('fund_approver');
begin
  if uid is null or f.status in ('cancelled', 'approved_posted_to_qb') then return null; end if;
  if not f.locked and f.status in ('in_funding_preparation', 'returned_to_fund_requestor') then
    return case when v_staff or has_role('fund_requestor') then 'prep' end;
  end if;
  if f.status in ('pending_fund_approval', 'approved_ready_for_qb', 'sync_failed') then
    if v_staff then return 'in_place'; end if;
    -- Their own request, until it is funded. While it waits for approval the
    -- requestor takes it back first (withdraw_fund_request) and sends it again.
    if has_role('fund_requestor') and f.fund_requestor_id = uid
       and f.status <> 'pending_fund_approval' and f.funded_at is null then
      return 'in_place';
    end if;
  end if;
  return null;
end $$;

create or replace function fund_request_edit_refusal(f fund_requests) returns text
language sql stable as $$
  select case
    when f.status = 'approved_posted_to_qb' then 'Posted to QuickBooks: this request can no longer be edited.'
    when f.status = 'cancelled' then 'This fund request is cancelled.'
    when f.funded_at is not null then 'This fund request is already funded. Only an Admin or a Fund Approver can edit it now.'
    when f.status = 'pending_fund_approval' then 'This fund request is waiting for approval. Take it back for editing first.'
    else 'Only its Fund Requestor, an Admin or a Fund Approver can edit this fund request.'
  end;
$$;

revoke execute on function fund_request_edit_mode(fund_requests) from public, anon;
grant execute on function fund_request_edit_mode(fund_requests) to authenticated;

create or replace function save_fund_request(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  v_edit text;
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
  v_edit := fund_request_edit_mode(f);
  if v_edit is null then raise exception '%', fund_request_edit_refusal(f); end if;
  if v_edit = 'in_place' then
    if txt(p, 'edit_remarks') is null then
      raise exception 'Add remarks: what needed to change, or what was changed.';
    end if;
    perform log_event(f.payment_request_id, f.id,
      case when f.status = 'pending_fund_approval' then 'Edited while pending approval' else 'Edited after approval' end,
      f.status, f.status, txt(p, 'edit_remarks'));
    -- The Fund Approver hears about changes made by someone else.
    if f.fund_approver_id is not null and f.fund_approver_id <> uid then
      perform notify(f.fund_approver_id,
        format('Fund request %s was edited: %s', coalesce(f.ref_no, '(no Ref no.)'), txt(p, 'edit_remarks')),
        f.payment_request_id, f.id);
    end if;
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
  uid uuid := require_user();
  f fund_requests;
  v_lines jsonb;
  v_check boolean;
  v_cheques int;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.payment_request_id is not null then raise exception 'Items come from the payment request.'; end if;
  if fund_request_edit_mode(f) is null then raise exception '%', fund_request_edit_refusal(f); end if;
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


create or replace function set_fund_request_type(p_id uuid, p_type smallint) returns void
language plpgsql security definer set search_path = public as $$
declare
  f fund_requests;
begin
  perform require_user();
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if p_type is null or p_type = f.request_type then return; end if;
  if f.payment_request_id is null then
    raise exception 'The type of an auto debit or check payment request cannot be changed.';
  end if;
  if fund_request_edit_mode(f) is null then raise exception '%', fund_request_edit_refusal(f); end if;
  if p_type not in (1, 2, 3, 4, 5)
     or (coalesce(f.region, 'NCR') = 'NCR' and p_type in (3, 5))
     or (f.region = 'VisMin' and p_type in (2, 4)) then
    raise exception 'That request type does not match the % region of this request.', coalesce(f.region, 'NCR');
  end if;
  update fund_requests set request_type = p_type where id = f.id;
  perform log_event(f.payment_request_id, f.id,
    format('Request type changed from %s to %s', f.request_type, p_type), f.status, f.status);
end $$;

-- Attachments follow the same rule as the other details.
create or replace function add_attachment(p_pr uuid, p_fr uuid, p_path text, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  f fund_requests;
begin
  if split_part(p_path, '/', 1) <> uid::text then raise exception 'Invalid file path.'; end if;
  if p_pr is not null then
    if not exists (select 1 from payment_requests where id = p_pr and requestor_id = uid
                   and status in ('draft', 'returned_to_requestor')) then
      raise exception 'Files can be added only to your own draft or returned request.';
    end if;
  elsif p_fr is not null then
    select * into f from fund_requests where id = p_fr;
    if not found or fund_request_edit_mode(f) is null then
      raise exception 'Files can be added only while you can edit the fund request.';
    end if;
  else
    raise exception 'Attach the file to a request.';
  end if;
  insert into attachments (payment_request_id, fund_request_id, storage_path, file_name, uploaded_by)
  values (p_pr, p_fr, p_path, p_name, uid);
end $$;

create or replace function remove_attachment(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  a attachments;
  f fund_requests;
begin
  select * into a from attachments where id = p_id;
  if not found or a.uploaded_by <> uid then raise exception 'Attachment not found.'; end if;
  if a.payment_request_id is not null and not exists (
       select 1 from payment_requests where id = a.payment_request_id and status in ('draft', 'returned_to_requestor')) then
    raise exception 'This request can no longer be changed.';
  end if;
  if a.fund_request_id is not null then
    select * into f from fund_requests where id = a.fund_request_id;
    if fund_request_edit_mode(f) is null then raise exception 'This fund request can no longer be changed.'; end if;
  end if;
  delete from attachments where id = a.id;
  -- Tell the caller whether the file itself is now unused.
  if exists (select 1 from attachments where storage_path = a.storage_path) then return null; end if;
  return a.storage_path;
end $$;
