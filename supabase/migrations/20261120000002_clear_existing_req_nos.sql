-- Clear the REQ Nos. the portal gave automatically, so the Fund Requestor types
-- them to match the approved fund requests (Ruth, 20 November). Requests already
-- exported to QuickBooks keep theirs. The old numbers are kept in
-- payment_req_no_backup and in each request's status tracker, so they can be
-- put back if needed:
--   update payment_requests p set req_no = b.req_no from payment_req_no_backup b
--   where b.payment_request_id = p.id and p.req_no is null;

create table if not exists payment_req_no_backup (
  payment_request_id uuid primary key,
  req_no text not null,
  status text not null,
  cleared_at timestamptz not null default now()
);
alter table payment_req_no_backup enable row level security;
revoke all on payment_req_no_backup from anon, authenticated;

insert into payment_req_no_backup (payment_request_id, req_no, status)
select id, req_no, status::text from payment_requests
 where req_no is not null and status <> 'approved_posted_to_qb'
on conflict (payment_request_id) do nothing;

insert into audit_log (payment_request_id, fund_request_id, ref, action, actor_id, old_status, new_status, note)
select p.id, p.fund_request_id, p.req_no, 'REQ No. cleared', null, p.status, p.status,
       format('Automatic number %s cleared; the Fund Requestor fills in the REQ No.', p.req_no)
  from payment_requests p
 where p.req_no is not null and p.status <> 'approved_posted_to_qb';

update payment_requests set req_no = null
 where req_no is not null and status <> 'approved_posted_to_qb';
