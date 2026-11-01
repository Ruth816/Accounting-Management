-- Every Payment Approver sees and can act on every Payment Requestor's
-- submitted requests, not only the ones assigned to them (Ruth, 1 November).
-- The approver who acts is recorded as the request's approver, so the
-- Approved payments summary shows who approved what. Drafts stay private.

drop policy if exists "visible payment requests" on payment_requests;
create policy "visible payment requests" on payment_requests for select to authenticated
  using (requestor_id = auth.uid()
         or approver_id = auth.uid()
         or (has_role('payment_approver') and status <> 'draft')
         or has_role('fund_requestor')
         or has_role('admin'));

create or replace function can_see_pr(pr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from payment_requests p
    where p.id = pr_id
      and (p.requestor_id = auth.uid()
           or p.approver_id = auth.uid()
           or (has_role('payment_approver') and p.status <> 'draft')
           or has_role('fund_requestor')
           or has_role('admin'))
  );
$$;

create or replace function approve_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  if r.requestor_id = uid then raise exception 'You cannot approve your own request.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;

  update payment_requests set status = 'approved_awaiting_funding', approved_on = now(), approver_id = uid,
    disapproval_reason = null, return_note = null
  where id = r.id;
  perform log_event(r.id, null, 'Approved', r.status, 'approved_awaiting_funding');
  perform notify(r.requestor_id, format('Your payment request %s was approved and is waiting for funding.', r.req_no), r.id);
  perform notify_role('fund_requestor',
    format('Payment request %s (%s, %s %s) is approved and ready to receive for funding.',
           r.req_no, r.payable_to, r.currency, money_txt(r.total_due)), r.id);
end $$;

create or replace function disapprove_payment_request(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'A reason is required to disapprove.'; end if;
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  if r.requestor_id = uid then raise exception 'You cannot disapprove your own request.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;

  insert into payment_request_versions (payment_request_id, version, snapshot, reason, returned_by)
  values (r.id, r.version, to_jsonb(r), btrim(p_reason), uid);

  update payment_requests set
    status = 'returned_to_requestor',
    approver_id = uid,
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
