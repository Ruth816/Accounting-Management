-- Approved requests are registered and can no longer be deleted (Ruth,
-- 5 November). Payment requests can be deleted until they are approved; fund
-- requests already could not be deleted once approved. Safe to run again.

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
  if r.status not in ('draft', 'pending_payment_approval', 'returned_to_requestor', 'expired') then
    raise exception 'An approved request is already registered and cannot be deleted.';
  end if;
  update payment_requests set status = 'cancelled', returned_on = null, expires_on = null where id = r.id;
  perform log_event(r.id, null, 'Deleted', r.status, 'cancelled', btrim(p_reason));
  if r.status in ('pending_payment_approval', 'approved_awaiting_funding') and r.approver_id <> uid then
    perform notify(r.approver_id, format('Payment request %s was deleted: %s', r.req_no, btrim(p_reason)), r.id);
  end if;
end $$;
