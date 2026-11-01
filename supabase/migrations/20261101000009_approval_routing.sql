-- Payment approval routing by region (Ruth, 1 November):
--   NCR:    Hoe Ming Wong.
--   VisMin: Jonathan Villanueva (approver 1), then Hoe Ming Wong (approver 2).
-- The Admin page sets who is on each step. When a region has a route, only
-- that step's approver (or an Admin) can approve or disapprove; an Admin's
-- approval is final at any step. Regions without a route keep the old rule.
-- Safe to run more than once.

create table if not exists approval_routes (
  region text not null check (region in ('NCR', 'VisMin')),
  level smallint not null check (level in (1, 2)),
  approver_id uuid not null references profiles (id) on delete cascade,
  primary key (region, level)
);
alter table approval_routes enable row level security;
drop policy if exists "everyone reads routes" on approval_routes;
create policy "everyone reads routes" on approval_routes for select to authenticated using (true);
grant select on approval_routes to authenticated;

alter table payment_requests add column if not exists approval_level smallint not null default 1;
alter table payment_requests add column if not exists first_approver_id uuid references profiles (id);
alter table payment_requests add column if not exists first_approved_on timestamptz;

-- Start with the people Ruth named, if their accounts exist.
insert into approval_routes (region, level, approver_id)
select v.region, v.level, p.id
from (values ('NCR', 1, '%hoe ming%'), ('VisMin', 1, '%jonathan%'), ('VisMin', 2, '%hoe ming%')) as v(region, level, pat)
join lateral (select id from profiles where full_name ilike v.pat and active order by created_at limit 1) p on true
on conflict (region, level) do nothing;

create or replace function route_approver(p_region text, p_level int) returns uuid
language sql stable security definer set search_path = public as $$
  select approver_id from approval_routes where region = p_region and level = p_level;
$$;

-- With a route for the region, only the step's approver or an Admin may act.
create or replace function check_payment_approver(r payment_requests, uid uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from approval_routes where region = r.region)
     and r.approver_id is distinct from uid and not has_role('admin') then
    raise exception 'This request is waiting for %.', coalesce((select full_name from profiles where id = r.approver_id), 'another approver');
  end if;
end $$;

-- Admin: set the route. p is {"NCR": [id], "VisMin": [id1, id2]}; empty clears a step.
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
  insert into audit_log (action, actor_id, note) values ('Approval routing changed', uid, p::text);
end $$;

create or replace function submit_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
  resubmit boolean;
  v_route uuid;
  v_level smallint;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found or (r.requestor_id <> uid and not has_role('admin')) then raise exception 'Payment request not found.'; end if;
  if r.status not in ('draft', 'returned_to_requestor') then
    raise exception 'This request has already been submitted.';
  end if;
  -- Approval routing by region: the first approver comes from the route,
  -- skipping a step whose approver is the requestor.
  v_level := 1;
  v_route := route_approver(r.region, 1);
  if v_route = r.requestor_id then
    v_level := 2;
    v_route := route_approver(r.region, 2);
  end if;
  if v_route is not null then
    r.approver_id := v_route;
  else
    v_level := 1;
  end if;
  perform validate_payment_request(r);
  resubmit := r.status = 'returned_to_requestor';

  update payment_requests set
    status = 'pending_payment_approval',
    version = version + case when resubmit then 1 else 0 end,
    returned_on = null, expires_on = null,
    reminder_23_sent = false, reminder_28_sent = false,
    submitted_on = now(),
    approver_id = r.approver_id,
    approval_level = v_level,
    first_approver_id = null, first_approved_on = null
  where id = r.id;

  perform log_event(r.id, null, case when resubmit then 'Resubmitted' else 'Submitted' end,
                    r.status, 'pending_payment_approval',
                    case when resubmit then 'Version ' || (r.version + 1) end);
  perform notify(r.approver_id,
    format('Payment request %s from %s (%s %s) is waiting for your approval.',
           r.req_no, (select full_name from profiles where id = uid), r.currency, money_txt(r.total_due)),
    r.id);
end $$;

create or replace function approve_payment_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_approver');
  r payment_requests;
  v_next uuid;
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
  perform check_payment_approver(r, uid);

  insert into payment_request_versions (payment_request_id, version, snapshot, reason, returned_by)
  values (r.id, r.version, to_jsonb(r), btrim(p_reason), uid);

  update payment_requests set
    status = 'returned_to_requestor',
    approver_id = uid,
    approval_level = 1, first_approver_id = null, first_approved_on = null,
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

create or replace function admin_hand_over(p_from uuid, p_to uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  n_defaults int; n_pr int; n_fa int; n_fr int;
  v_from text; v_to text;
begin
  if p_from is null or p_to is null or p_from = p_to then raise exception 'Choose two different people.'; end if;
  select full_name into v_from from profiles where id = p_from;
  select full_name into v_to from profiles where id = p_to and active;
  if v_to is null then raise exception 'The person taking over must be an active user.'; end if;

  update profiles set default_payment_approver = p_to where default_payment_approver = p_from;
  get diagnostics n_defaults = row_count;
  update profiles set default_fund_approver = p_to where default_fund_approver = p_from;
  update approval_routes set approver_id = p_to where approver_id = p_from;

  update payment_requests set approver_id = p_to
   where approver_id = p_from and status in ('draft', 'pending_payment_approval', 'returned_to_requestor');
  get diagnostics n_pr = row_count;
  update fund_requests set fund_approver_id = p_to
   where fund_approver_id = p_from and not locked
     and status in ('in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor');
  get diagnostics n_fa = row_count;
  update fund_requests set fund_requestor_id = p_to
   where fund_requestor_id = p_from and not locked
     and status in ('in_funding_preparation', 'returned_to_fund_requestor');
  get diagnostics n_fr = row_count;

  insert into audit_log (action, actor_id, note)
  values ('Handed over', uid, format('%s to %s: %s payment approvals, %s fund approvals, %s fund requests in preparation',
                                     v_from, v_to, n_pr, n_fa, n_fr));
  perform notify(p_to, format('%s''s open work was handed over to you: %s payment requests to approve, %s fund requests to approve, %s fund requests to prepare.',
                              v_from, n_pr, n_fa, n_fr));
  return jsonb_build_object('payment_approvals', n_pr, 'fund_approvals', n_fa, 'fund_requests', n_fr);
end $$;

revoke execute on function admin_set_routes(jsonb), check_payment_approver(payment_requests, uuid) from public, anon;
grant execute on function admin_set_routes(jsonb), route_approver(text, int) to authenticated;
