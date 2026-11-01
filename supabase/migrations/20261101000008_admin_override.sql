-- Admin can cover every role (Ruth, 1 November): an Admin counts as Payment
-- Requestor, Payment Approver, Fund Requestor and Fund Approver, sees every
-- request, and can act on requests assigned to someone else. Nobody, Admin
-- included, approves a request they made or prepared themselves.
-- admin_hand_over moves one person's open work to another, for when someone
-- leaves on short notice. Safe to run more than once.

create or replace function has_role(r app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles where id = auth.uid() and active and (r = any (roles) or 'admin' = any (roles))
  );
$$;

create or replace function set_fund_reviewed(p_id uuid, p_reviewed boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found or (f.fund_approver_id <> uid and not has_role('admin')) then raise exception 'Fund request not found.'; end if;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  update fund_requests set reviewed = coalesce(p_reviewed, false) where id = f.id;
  if p_reviewed then
    perform log_event(f.payment_request_id, f.id, 'Marked reviewed', null, null);
  end if;
end $$;

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
    if r.status not in ('draft', 'returned_to_requestor') then
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

create or replace function submit_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
  resubmit boolean;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or (r.requestor_id <> uid and not has_role('admin')) then raise exception 'Payment request not found.'; end if;
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

create or replace function cancel_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r payment_requests;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or (r.requestor_id <> uid and not has_role('admin')) then raise exception 'Payment request not found.'; end if;
  if r.status not in ('draft', 'returned_to_requestor') then
    raise exception 'Only a draft or returned request can be cancelled.';
  end if;
  update payment_requests set status = 'cancelled', returned_on = null, expires_on = null where id = r.id;
  perform log_event(r.id, null, 'Cancelled', r.status, 'cancelled');
end $$;

create or replace function liquidate_payment_request(
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
  if not found or (r.requestor_id <> uid and not has_role('admin')) then raise exception 'Payment request not found.'; end if;
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

create or replace function disapprove_fund_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required to disapprove.'; end if;
  select * into f from fund_requests where id = p_id for update;
  if not found or (f.fund_approver_id <> uid and not has_role('admin')) then raise exception 'Fund request not found.'; end if;
  if f.status <> 'pending_fund_approval' then raise exception 'This fund request is not waiting for approval.'; end if;
  if not f.reviewed then raise exception 'Tick Reviewed before disapproving.'; end if;

  update fund_requests set status = 'returned_to_fund_requestor', disapproval_reason = btrim(p_reason), reviewed = false
  where id = f.id;
  perform log_event(f.payment_request_id, f.id, 'Fund disapproved', f.status, 'returned_to_fund_requestor', btrim(p_reason));
  perform notify(f.fund_requestor_id, format('Fund request %s was returned: %s', f.ref_no, btrim(p_reason)),
                 f.payment_request_id, f.id);
end $$;

create or replace function withdraw_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or (r.requestor_id <> uid and not has_role('admin')) then raise exception 'Payment request not found.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'Only a request waiting for approval can be taken back.'; end if;
  update payment_requests set status = 'draft' where id = r.id;
  perform log_event(r.id, null, 'Taken back for editing', r.status, 'draft');
  perform notify(r.approver_id, format('Payment request %s was taken back by the requestor for editing.', r.req_no), r.id);
end $$;

create or replace function admin_hand_over(p_from uuid, p_to uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  n_defaults int; n_pr int; n_fa int; n_fr int;
  v_from text; v_to text;
begin
  if p_from is null or p_to is null or p_from = p_to then raise exception 'Choose two different people.'; end if;
  select full_name into v_from from profiles where id = p_from;
  select full_name into v_to from profiles where id = p_to and active;
  if v_to is null then raise exception 'The person taking over must be an active user.'; end if;

  update profiles set default_payment_approver = p_to where default_payment_approver = p_from;
  get diagnostics n_defaults = row_count;
  update profiles set default_fund_approver = p_to where default_fund_approver = p_from;

  update payment_requests set approver_id = p_to
   where approver_id = p_from and status in ('draft', 'pending_payment_approval', 'returned_to_requestor');
  get diagnostics n_pr = row_count;
  update fund_requests set fund_approver_id = p_to
   where fund_approver_id = p_from and not locked
     and status in ('in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor');
  get diagnostics n_fa = row_count;
  update fund_requests set fund_requestor_id = p_to
   where fund_requestor_id = p_from and not locked
     and status in ('in_funding_preparation', 'returned_to_fund_requestor');
  get diagnostics n_fr = row_count;

  insert into audit_log (action, actor_id, note)
  values ('Handed over', uid, format('%s to %s: %s payment approvals, %s fund approvals, %s fund requests in preparation',
                                     v_from, v_to, n_pr, n_fa, n_fr));
  perform notify(p_to, format('%s''s open work was handed over to you: %s payment requests to approve, %s fund requests to approve, %s fund requests to prepare.',
                              v_from, n_pr, n_fa, n_fr));
  return jsonb_build_object('payment_approvals', n_pr, 'fund_approvals', n_fa, 'fund_requests', n_fr);
end $$;

revoke execute on function admin_hand_over(uuid, uuid) from public, anon;
grant execute on function admin_hand_over(uuid, uuid) to authenticated;
