-- Delete button on the request lists. A deleted request is marked Cancelled
-- (spec section 3), so it leaves every list but stays in the audit log with
-- the reason given.

-- Payment request: its requestor or an Admin, any time before funding starts.
create or replace function delete_payment_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r payment_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required.'; end if;
  select * into r from payment_requests where id = p_id for update;
  if not found or (r.requestor_id <> uid and not has_role('admin')) then
    raise exception 'Only the requestor or an Admin can delete this request.';
  end if;
  if r.status not in ('draft', 'pending_payment_approval', 'returned_to_requestor', 'expired', 'approved_awaiting_funding') then
    raise exception 'This request is already being funded. Delete its fund request first.';
  end if;
  update payment_requests set status = 'cancelled', returned_on = null, expires_on = null where id = r.id;
  perform log_event(r.id, null, 'Deleted', r.status, 'cancelled', btrim(p_reason));
  if r.status in ('pending_payment_approval', 'approved_awaiting_funding') and r.approver_id <> uid then
    perform notify(r.approver_id, format('Payment request %s was deleted: %s', r.req_no, btrim(p_reason)), r.id);
  end if;
end $$;

-- Fund request: a Fund Requestor or an Admin, any time before fund approval.
-- A linked payment request goes back to Approved – Awaiting Funding so it can
-- be received again.
create or replace function delete_fund_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  f fund_requests;
begin
  if not (has_role('fund_requestor') or has_role('admin')) then
    raise exception 'Only a Fund Requestor or an Admin can delete a fund request.';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required.'; end if;
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.locked or f.status not in ('in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor') then
    raise exception 'An approved fund request cannot be deleted.';
  end if;

  update fund_requests set status = 'cancelled', cheque_id = null where id = f.id;
  perform refresh_cheque_memos(f.cheque_id);
  perform log_event(f.payment_request_id, f.id, 'Deleted', f.status, 'cancelled', btrim(p_reason));

  if f.payment_request_id is not null then
    update payment_requests set status = 'approved_awaiting_funding', fund_request_id = null
     where id = f.payment_request_id;
    perform log_event(f.payment_request_id, null, 'Back to awaiting funding', f.status, 'approved_awaiting_funding',
                      btrim(p_reason));
  end if;
  if f.status = 'pending_fund_approval' and f.fund_approver_id <> uid then
    perform notify(f.fund_approver_id,
      format('Fund request %s was deleted: %s', coalesce(f.ref_no, '(no Ref no.)'), btrim(p_reason)),
      f.payment_request_id, f.id);
  end if;
end $$;

revoke execute on function delete_payment_request(uuid, text), delete_fund_request(uuid, text) from public, anon;
grant execute on function delete_payment_request(uuid, text) to authenticated;
grant execute on function delete_fund_request(uuid, text) to authenticated;
