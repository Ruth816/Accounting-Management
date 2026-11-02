-- A Payment Approver who is on the approval routing for one region only sees
-- that region (Ruth, 2 November: Jonathan, VisMin approver 1, must not see
-- NCR). Approvers on both regions' routing, or on none, and Admins still see
-- every region. Safe to run more than once.

create or replace function approver_region_of(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when count(distinct r.region) = 1 then min(r.region) end
  from approval_routes r
  join profiles p on p.id = r.approver_id
  where r.approver_id = p_user and not ('admin' = any (p.roles));
$$;

create or replace function approver_region() returns text
language sql stable security definer set search_path = public as $$
  select approver_region_of(auth.uid());
$$;

create or replace function approver_region_ok(p_region text) returns boolean
language sql stable security definer set search_path = public as $$
  select approver_region() is null or p_region is null or p_region = approver_region();
$$;

drop policy if exists "visible payment requests" on payment_requests;
create policy "visible payment requests" on payment_requests for select to authenticated
  using (requestor_id = auth.uid()
         or approver_id = auth.uid()
         or (has_role('payment_approver') and status <> 'draft' and approver_region_ok(region))
         or (has_role('fund_requestor') and region_ok(region))
         or has_role('admin'));

create or replace function can_see_pr(pr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from payment_requests p
    where p.id = pr_id
      and (p.requestor_id = auth.uid()
           or p.approver_id = auth.uid()
           or (has_role('payment_approver') and p.status <> 'draft' and approver_region_ok(p.region))
           or (has_role('fund_requestor') and region_ok(p.region))
           or has_role('admin'))
  );
$$;

-- Notifications to a role skip approvers locked to the other region.
create or replace function notify_role(p_role app_role, p_message text, p_pr uuid default null, p_fr uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_region text;
begin
  if p_fr is not null then
    select fr_region(f) into v_region from fund_requests f where f.id = p_fr;
  end if;
  if v_region is null and p_pr is not null then
    select region into v_region from payment_requests where id = p_pr;
  end if;
  for r in select id from profiles
           where active and p_role = any (roles)
             and (v_region is null or region is null or region = v_region
                  or roles && array['admin', 'payment_approver', 'fund_approver']::app_role[])
             and (v_region is null or p_role <> 'payment_approver'
                  or coalesce(approver_region_of(id), v_region) = v_region) loop
    perform notify(r.id, p_message, p_pr, p_fr);
  end loop;
end $$;

revoke execute on function notify_role(app_role, text, uuid, uuid) from public, anon, authenticated;
revoke execute on function approver_region_of(uuid) from public, anon;
grant execute on function approver_region_of(uuid), approver_region(), approver_region_ok(text) to authenticated;
