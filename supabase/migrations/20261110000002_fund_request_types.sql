-- New fund request: the Fund Requestor picks one of the five types (Ruth, 10 November):
--   1 Auto debit request, 2 NCR fund request, 3 VisMin fund request,
--   4 NCR reimbursable fund request, 5 VisMin reimbursable fund request.
-- Types 2 to 5 take the region of their type and start as Check, like the old
-- Check payment request (type 2, NCR), which is now listed as NCR fund request.
-- A Fund Requestor limited to one region can't start the other region's types
-- (lock_fr_region raises "This request belongs to another region.").
create or replace function create_fund_request(p_type smallint) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  v_fr uuid;
  v_approver uuid;
begin
  if p_type is null or p_type not between 1 and 5 then
    raise exception 'Pick a request type from 1 to 5.';
  end if;
  select default_fund_approver into v_approver from profiles where id = uid;
  if v_approver = uid then v_approver := null; end if;
  insert into fund_requests (request_type, region, fund_requestor_id, fund_approver_id, payment_method)
  values (
    p_type,
    case p_type when 2 then 'NCR' when 4 then 'NCR' when 3 then 'VisMin' when 5 then 'VisMin' end,
    uid, v_approver,
    case when p_type = 1 then 'Direct Debit' else 'Check' end
  )
  returning id into v_fr;
  perform log_event(null, v_fr,
    case p_type
      when 1 then 'Auto debit request created'
      when 2 then 'NCR fund request created'
      when 3 then 'VisMin fund request created'
      when 4 then 'NCR reimbursable fund request created'
      else 'VisMin reimbursable fund request created'
    end, null, 'in_funding_preparation');
  return v_fr;
end $$;

revoke execute on function create_fund_request(smallint) from public, anon;
grant execute on function create_fund_request(smallint) to authenticated;
