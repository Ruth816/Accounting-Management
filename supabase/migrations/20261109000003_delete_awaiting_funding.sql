-- Delete after approval (Ruth, 9 November): only an Admin who is both the
-- requestor and the approver of a payment request may delete it after it is
-- approved (not a requestor only, not an approver only), up to the approved stage, that is until its fund request is
-- approved. A fund request still being prepared for it is cancelled with it.
-- Everyone else keeps the 5 November rule: a request can be deleted only
-- until it is approved. Deleted requests are marked Cancelled and stay in the
-- audit log. Safe to run again.

create or replace function delete_payment_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r payment_requests;
  f fund_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required.'; end if;
  select * into r from payment_requests where id = p_id for update;
  if not found or (r.requestor_id <> uid and not has_role('admin')) then
    raise exception 'Only the requestor or an Admin can delete this request.';
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
