-- An approved payment request goes straight to a fund request (Ruth,
-- 2 November): no Receive click. The fund request is prepared by the
-- region's Fund Requestor (one set to that region, else one with no region,
-- else an Admin); any Fund Requestor of the region can complete it and send
-- it to the Fund Approver. Receive stays for requests whose fund request was
-- deleted. Safe to run more than once.

create or replace function fund_preparer_for(p_region text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from profiles
  where active and ('fund_requestor' = any (roles) or 'admin' = any (roles))
    and (region is null or region = p_region or 'admin' = any (roles))
  order by ('fund_requestor' = any (roles)) desc,
           (region is not distinct from p_region) desc,
           (region is null) desc,
           created_at
  limit 1;
$$;

create or replace function make_fund_request(p_id uuid, uid uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
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
    when r.request_kind = 'auto_debit' then 1
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
    request_type, region, payment_request_id, fund_requestor_id, fund_approver_id, status,
    payee, item_no, description, currency, original_amount,
    payment_method, tax_code, tax_rate, tax_locked, wtax_note
  ) values (
    v_type, r.region, r.id, uid, v_approver, 'in_funding_preparation',
    r.payable_to, r.item_no, v_desc, r.currency, r.total_vat_in,
    case when r.request_kind = 'auto_debit' then 'Direct Debit'
         else case r.payment_type when 'Cash' then 'Cash' when 'Cheque' then 'Check' else 'FUND TRANSFER' end end,
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

create or replace function receive_payment_request(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  return make_fund_request(p_id, require_role('fund_requestor'));
end $$;

create or replace function approve_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
  v_next uuid;
  v_preparer uuid;
  v_fr uuid;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  if r.requestor_id = uid then raise exception 'You cannot approve your own request.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;
  perform check_payment_approver(r, uid);

  -- VisMin: approver 1 passes it to approver 2. An Admin's approval is final.
  v_next := route_approver(r.region, r.approval_level + 1);
  if v_next is not null and v_next <> r.requestor_id and not has_role('admin') then
    update payment_requests set approval_level = r.approval_level + 1, approver_id = v_next,
      first_approver_id = uid, first_approved_on = now()
    where id = r.id;
    perform log_event(r.id, null, format('Approved by approver %s', r.approval_level), r.status, r.status);
    perform notify(v_next,
      format('Payment request %s (%s %s) was approved by %s and is waiting for your approval.',
             r.req_no, r.currency, money_txt(r.total_due), (select full_name from profiles where id = uid)),
      r.id);
    return;
  end if;

  update payment_requests set status = 'approved_awaiting_funding', approved_on = now(), approver_id = uid,
    disapproval_reason = null, return_note = null
  where id = r.id;
  perform log_event(r.id, null, 'Approved', r.status, 'approved_awaiting_funding');
  perform notify(r.requestor_id, format('Your payment request %s was approved and is waiting for funding.', r.req_no), r.id);
  -- Straight to a fund request (Ruth, 2 November), prepared by the region's Fund Requestor.
  v_preparer := fund_preparer_for(r.region);
  if v_preparer is not null then
    v_fr := make_fund_request(r.id, v_preparer);
    perform notify_role('fund_requestor',
      format('Payment request %s (%s, %s %s) is approved. Its fund request is ready for you to complete.',
             r.req_no, r.payable_to, r.currency, money_txt(r.total_due)), r.id, v_fr);
  else
    perform notify_role('fund_requestor',
      format('Payment request %s (%s, %s %s) is approved and ready to receive for funding.',
             r.req_no, r.payable_to, r.currency, money_txt(r.total_due)), r.id);
  end if;
end $$;

revoke execute on function make_fund_request(uuid, uuid), fund_preparer_for(text) from public, anon, authenticated;
