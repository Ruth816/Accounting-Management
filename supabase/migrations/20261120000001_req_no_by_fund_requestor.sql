-- Payment requests no longer get a REQ No. when they are created (Ruth,
-- 20 November). The field stays empty until the request is approved and
-- reaches the Fund Requestor, who types the REQ No. to match the numbering
-- already used on the approved fund requests. Requests that already have a
-- number keep it; the Fund Requestor can still correct it.

alter table payment_requests alter column req_no drop not null;

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
    insert into payment_requests (requestor_id, approver_id)
    values (uid, v_approver)
    returning * into r;
    perform log_event(r.id, null, 'Created', null, 'draft');
  else
    select * into r from payment_requests where id = p_id for update;
    if not found or r.requestor_id <> uid then
      raise exception 'Payment request not found.';
    end if;
    -- An Admin may correct details after approval (Ruth, 5 November); the status stays.
    if r.status in ('draft', 'returned_to_requestor') then
      null;
    elsif r.status = 'approved_posted_to_qb' then
      raise exception 'Posted to QuickBooks: this request can no longer be edited.';
    elsif has_role('admin') and r.status not in ('cancelled', 'expired', 'pending_payment_approval') then
      if txt(p, 'edit_remarks') is null then
        raise exception 'Add remarks: what needed to change, or what was changed.';
      end if;
      perform log_event(r.id, r.fund_request_id, 'Edited after approval', r.status, r.status, txt(p, 'edit_remarks'));
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
                                 case when (p ->> 'reimbursable')::boolean then 'reimbursable' else 'request_for_payment' end),
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
    terms_accepted    = coalesce((p ->> 'terms_accepted')::boolean, false),
    other_notes       = txt(p, 'other_notes')
  where id = r.id;

  return r.id;
end $$;

-- The Fund Requestor (or an Admin) types the REQ No. once the request is
-- approved, until its fund request is exported to QuickBooks. Empty clears it.
create or replace function set_payment_req_no(p_id uuid, p_req_no text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  r payment_requests;
  v_no text := nullif(regexp_replace(btrim(coalesce(p_req_no, '')), '\s+', ' ', 'g'), '');
begin
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  if r.status in ('draft', 'pending_payment_approval', 'returned_to_requestor', 'cancelled', 'expired') then
    raise exception 'The REQ No. is filled in once the payment request is approved.';
  end if;
  if r.status = 'approved_posted_to_qb' then
    raise exception 'Posted to QuickBooks: this request can no longer be edited.';
  end if;
  if v_no is not distinct from r.req_no then return; end if;
  if v_no is not null and exists (select 1 from payment_requests where req_no = v_no and id <> r.id) then
    raise exception 'REQ No. % is already used by another payment request.', v_no;
  end if;
  update payment_requests set req_no = v_no where id = r.id;
  perform log_event(r.id, r.fund_request_id, 'REQ No. set', r.status, r.status,
    case when r.req_no is null then coalesce(v_no, '')
         else format('%s → %s', r.req_no, coalesce(v_no, '(empty)')) end);
end $$;

revoke execute on function set_payment_req_no(uuid, text) from public, anon;
grant execute on function set_payment_req_no(uuid, text) to authenticated;

-- Messages written before a request has a REQ No. would read "payment request
-- was approved" with a gap where the number goes: name the payee there instead.
create or replace function notification_fill_req_gap() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_payee text;
begin
  if new.message ~* 'request  ' then
    select nullif(btrim(payable_to), '') into v_payee from payment_requests where id = new.payment_request_id;
    new.message := regexp_replace(new.message, '(request)  ',
      case when v_payee is null then '\1 ' else '\1 for ' || replace(v_payee, '\', '\\') || ' ' end, 'gi');
  end if;
  return new;
end $$;

drop trigger if exists notification_fill_req_gap on notifications;
create trigger notification_fill_req_gap before insert on notifications
  for each row execute function notification_fill_req_gap();

-- The audit log keeps something to recognise a request by after it is deleted.
create or replace function audit_ref_fallback() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.ref is null and new.payment_request_id is not null then
    select 'No REQ No. · ' || coalesce(nullif(btrim(payable_to), ''), 'no payee')
      into new.ref from payment_requests where id = new.payment_request_id;
  end if;
  return new;
end $$;

drop trigger if exists audit_ref_fallback on audit_log;
create trigger audit_ref_fallback before insert on audit_log
  for each row execute function audit_ref_fallback();
