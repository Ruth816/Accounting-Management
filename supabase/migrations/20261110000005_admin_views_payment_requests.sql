-- Admins view payment requests, they don't approve or edit them (Ruth,
-- 10 November). Approving and disapproving payment requests belongs to the
-- Payment Approver only; an Admin sees every region's payment requests and
-- may still delete one (Ruth, 9 November), but can't approve, disapprove or
-- edit someone else's. Fund approval is unchanged.

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active and 'admin' = any (roles));
$$;

-- Guards every approval path (approve, disapprove, routing to approver 2).
create or replace function pr_no_admin_approval() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'pending_payment_approval' and is_admin()
     and (new.status in ('approved_awaiting_funding', 'returned_to_requestor')
          or new.approval_level is distinct from old.approval_level) then
    raise exception 'Payment requests are approved by a Payment Approver. An Admin can view them only.';
  end if;
  return new;
end $$;

drop trigger if exists pr_no_admin_approval on payment_requests;
create trigger pr_no_admin_approval before update on payment_requests
  for each row execute function pr_no_admin_approval();

-- An Admin edits only their own payment requests.
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

-- An Admin deletes only their own payment requests; the requestor keeps Delete (Ruth, 10 November).
create or replace function delete_payment_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r payment_requests;
  f fund_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required.'; end if;
  select * into r from payment_requests where id = p_id for update;
  if not found or r.requestor_id <> uid then
    raise exception 'Only its requestor can delete this request.';
  end if;

  if r.status not in ('draft', 'pending_payment_approval', 'returned_to_requestor', 'expired') then
    if not (has_role('admin') and r.requestor_id = uid and r.approver_id = uid
            and r.status in ('approved_awaiting_funding', 'in_funding_preparation',
                             'pending_fund_approval', 'returned_to_fund_requestor')) then
      raise exception 'An approved request is already registered and cannot be deleted. Only an Admin who both requested and approved it can delete it, until its fund request is approved.';
    end if;
    -- Cancel the fund request still being prepared for it, as Delete on a fund request does.
    for f in select * from fund_requests
              where payment_request_id = r.id and status <> 'cancelled' for update loop
      if f.locked or f.status not in ('in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor') then
        raise exception 'Its fund request is already approved, so this request cannot be deleted.';
      end if;
      update fund_requests set status = 'cancelled', cheque_id = null where id = f.id;
      perform refresh_cheque_memos(f.cheque_id);
      perform log_event(r.id, f.id, 'Deleted', f.status, 'cancelled', btrim(p_reason));
      if f.status = 'pending_fund_approval' and f.fund_approver_id <> uid then
        perform notify(f.fund_approver_id,
          format('Fund request %s was deleted with payment request %s: %s',
                 coalesce(f.ref_no, '(no Ref no.)'), r.req_no, btrim(p_reason)), r.id, f.id);
      end if;
    end loop;
  end if;

  update payment_requests set status = 'cancelled', returned_on = null, expires_on = null where id = r.id;
  perform log_event(r.id, null, 'Deleted', r.status, 'cancelled', btrim(p_reason));
  if r.status = 'pending_payment_approval' and r.approver_id <> uid then
    perform notify(r.approver_id, format('Payment request %s was deleted: %s', r.req_no, btrim(p_reason)), r.id);
  end if;
end $$;
