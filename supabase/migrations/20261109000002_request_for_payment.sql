-- New payment request type "Request for payment" (Ruth, 9 November).
-- Same route as the other payment requests: the Payment Requestor files it,
-- their Payment Approver approves it, and approval creates a fund request for
-- the region's Fund Requestor, who edits it, types the fund request Ref no.
-- and fills in the remaining QuickBooks Expense fields. It is not
-- reimbursable or an auto debit, so its fund request is type 2 (NCR) or
-- 3 (VisMin). Safe to run more than once.

alter table payment_requests drop constraint if exists payment_requests_request_kind_check;
alter table payment_requests add constraint payment_requests_request_kind_check
  check (request_kind in ('regular', 'auto_debit', 'reimbursable', 'request_for_payment'));

-- Fund request (cash/check), auto debit and reimbursable are the Fund
-- Requestor's to choose (Ruth, 9 November): on a fund request that came from
-- a payment request, while it is being prepared, the Fund Requestor sets the
-- type. The Ref no. prefix must then match it. Types of the other region are
-- refused, because the region comes from the payment request.
create or replace function set_fund_request_type(p_id uuid, p_type smallint) returns void
language plpgsql security definer set search_path = public as $$
declare
  f fund_requests;
begin
  perform require_role('fund_requestor');
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if p_type is null or p_type = f.request_type then return; end if;
  if f.payment_request_id is null then
    raise exception 'The type of an auto debit or check payment request cannot be changed.';
  end if;
  if f.locked or f.status not in ('in_funding_preparation', 'returned_to_fund_requestor') then
    raise exception 'The request type can only be changed while the fund request is being prepared.';
  end if;
  if p_type not in (1, 2, 3, 4, 5)
     or (coalesce(f.region, 'NCR') = 'NCR' and p_type in (3, 5))
     or (f.region = 'VisMin' and p_type in (2, 4)) then
    raise exception 'That request type does not match the % region of this request.', coalesce(f.region, 'NCR');
  end if;
  update fund_requests set request_type = p_type where id = f.id;
  perform log_event(f.payment_request_id, f.id,
    format('Request type changed from %s to %s', f.request_type, p_type), f.status, f.status);
end $$;

revoke execute on function set_fund_request_type(uuid, smallint) from public, anon;
grant execute on function set_fund_request_type(uuid, smallint) to authenticated;

-- "Other notes" on the payment request (Ruth, 9 November): anything else the
-- requestor wants the approver and Fund Requestor to know that has no field
-- of its own. Same as the 5 November save_payment_request, plus other_notes.
alter table payment_requests add column if not exists other_notes text;

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
