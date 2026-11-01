-- Edit button on the request lists (Ruth, 1 November). A request waiting for
-- approval is taken back for editing first, so the approver never approves a
-- version that is still changing; it is then submitted again.

-- Payment request: its requestor, while Pending Payment Approval -> Draft.
create or replace function withdraw_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or r.requestor_id <> uid then raise exception 'Payment request not found.'; end if;
  if r.status <> 'pending_payment_approval' then raise exception 'Only a request waiting for approval can be taken back.'; end if;
  update payment_requests set status = 'draft' where id = r.id;
  perform log_event(r.id, null, 'Taken back for editing', r.status, 'draft');
  perform notify(r.approver_id, format('Payment request %s was taken back by the requestor for editing.', r.req_no), r.id);
end $$;

-- Fund request: a Fund Requestor, while Pending Fund Approval -> In Funding Preparation.
create or replace function withdraw_fund_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  f fund_requests;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.locked or f.status <> 'pending_fund_approval' then raise exception 'Only a fund request waiting for approval can be taken back.'; end if;
  update fund_requests set status = 'in_funding_preparation' where id = f.id;
  perform log_event(f.payment_request_id, f.id, 'Taken back for editing', f.status, 'in_funding_preparation');
  if f.fund_approver_id <> uid then
    perform notify(f.fund_approver_id,
      format('Fund request %s was taken back for editing.', coalesce(f.ref_no, '(no Ref no.)')), f.payment_request_id, f.id);
  end if;
end $$;

revoke execute on function withdraw_payment_request(uuid), withdraw_fund_request(uuid) from public, anon;
grant execute on function withdraw_payment_request(uuid), withdraw_fund_request(uuid) to authenticated;
