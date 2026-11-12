-- VisMin payment requests need two different approvers (Ruth, 12 November):
-- Jonathan Villanueva approves first, then Hoe Ming Wong. Approver 2 can only
-- approve after approver 1, and the request reaches Payment approved only
-- after approver 2. Some VisMin requests were approved by Hoe Ming alone, so:
--   1. one person can no longer be both approver 1 and approver 2, on the
--      route or on a request;
--   2. the VisMin route is set back to Jonathan, then Hoe Ming;
--   3. VisMin requests still waiting go back to the right step.
-- Requests already approved are left as they are. Safe to run more than once.

create or replace function admin_set_routes(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  reg text; lvl int; v uuid;
begin
  foreach reg in array array['NCR', 'VisMin'] loop
    for lvl in 1..2 loop
      v := nullif(p -> reg ->> (lvl - 1), '')::uuid;
      if v is null then
        delete from approval_routes where region = reg and level = lvl;
      else
        if not user_has_role(v, 'payment_approver') and not user_has_role(v, 'admin') then
          raise exception '% is not a Payment Approver.', (select full_name from profiles where id = v);
        end if;
        insert into approval_routes (region, level, approver_id) values (reg, lvl, v)
        on conflict (region, level) do update set approver_id = excluded.approver_id;
      end if;
    end loop;
  end loop;
  if exists (select 1 from approval_routes a where level = 2 and not exists
             (select 1 from approval_routes b where b.region = a.region and b.level = 1)) then
    raise exception 'Set approver 1 before approver 2.';
  end if;
  if exists (select 1 from approval_routes a join approval_routes b
               on b.region = a.region and a.level = 1 and b.level = 2 and a.approver_id = b.approver_id) then
    raise exception 'Approver 1 and approver 2 must be different people.';
  end if;
  insert into audit_log (action, actor_id, note) values ('Approval routing changed', uid, p::text);
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

  if r.status <> 'pending_payment_approval' then raise exception 'This request is not waiting for approval.'; end if;
  -- Only an Admin may approve their own payment request.
  if r.requestor_id = uid and not has_role('admin') then raise exception 'You cannot approve your own request.'; end if;
  perform check_payment_approver(r, uid);
  -- Approver 2 must be someone other than approver 1 (Ruth, 12 November).
  if r.approval_level > 1 and r.first_approver_id = uid then
    raise exception 'You already approved this request as approver 1. Approver 2 must be someone else.';
  end if;

  -- VisMin: approver 1 passes it to approver 2. An Admin's approval is final.
  v_next := route_approver(r.region, r.approval_level + 1);
  if v_next is not null and v_next <> r.requestor_id and not has_role('admin') then
    update payment_requests set approval_level = r.approval_level + 1, approver_id = v_next,
      first_approver_id = uid, first_approved_on = now()
    where id = r.id;
    perform log_event(r.id, null, format('Approved by approver %s', r.approval_level), r.status, r.status,
      case when r.requestor_id = uid then 'Self-approved: the Admin approved their own request' end);
    perform notify(v_next,
      format('Payment request %s (%s %s) was approved by %s and is waiting for your approval.',
             r.req_no, r.currency, money_txt(r.total_due), (select full_name from profiles where id = uid)),
      r.id);
    return;
  end if;

  -- VisMin is never approved by one person alone, even if its route is missing (Ruth, 12 November).
  if r.region = 'VisMin' and not has_role('admin') and (r.approval_level < 2 or r.first_approver_id is null or r.first_approver_id = uid) then
    raise exception 'VisMin requests need approver 1 and then approver 2. Ask an Admin to set both VisMin approvers in Users & settings.';
  end if;
  update payment_requests set status = 'approved_awaiting_funding', approved_on = now(), approver_id = uid,
    disapproval_reason = null, return_note = null
  where id = r.id;
  perform log_event(r.id, null, 'Approved', r.status, 'approved_awaiting_funding',
    case when r.requestor_id = uid then 'Self-approved: the Admin approved their own request' end);
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

-- The VisMin route: Jonathan, then Hoe Ming, when both accounts exist.
do $$
declare
  v_jon uuid := (select id from profiles where full_name ilike '%jonathan%villanueva%' and active order by created_at limit 1);
  v_hm uuid := (select id from profiles where full_name ilike '%hoe ming%' and active order by created_at limit 1);
  r payment_requests;
begin
  if v_jon is null or v_hm is null then
    raise notice 'Jonathan Villanueva or Hoe Ming Wong not found: VisMin route left as it is.';
    return;
  end if;
  insert into approval_routes (region, level, approver_id) values ('VisMin', 1, v_jon), ('VisMin', 2, v_hm)
  on conflict (region, level) do update set approver_id = excluded.approver_id;

  -- Waiting VisMin requests that skipped Jonathan go back to him as approver 1.
  for r in select * from payment_requests
            where region = 'VisMin' and status = 'pending_payment_approval'
              and requestor_id <> v_jon
              and not (approval_level = 1 and approver_id = v_jon)
              and not (approval_level = 2 and approver_id = v_hm and first_approver_id = v_jon)
            for update loop
    update payment_requests set approval_level = 1, approver_id = v_jon,
      first_approver_id = null, first_approved_on = null
    where id = r.id;
    perform log_event(r.id, null, 'Sent to approver 1', r.status, r.status,
      'VisMin requests are approved by Jonathan Villanueva first, then Hoe Ming Wong');
    perform notify(v_jon, format('Payment request %s is waiting for your approval.', r.req_no), r.id);
  end loop;
end $$;
