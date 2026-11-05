-- REQ No. of the payment request behind each fund request, for the Ready for
-- funding list (Ruth, 5 November). A Fund Approver can't read payment requests
-- directly, so this returns only the number, for fund requests the caller can see.
create or replace function fr_req_nos(p_frs uuid[])
returns table (fund_request_id uuid, req_no text)
language sql stable security definer set search_path = public as $$
  select f.id, p.req_no
  from fund_requests f
  join payment_requests p on p.id = f.payment_request_id
  where f.id = any (p_frs) and can_see_fr(f.id);
$$;

revoke execute on function fr_req_nos(uuid[]) from public, anon;
grant execute on function fr_req_nos(uuid[]) to authenticated;
