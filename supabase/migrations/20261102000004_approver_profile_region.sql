-- A Payment Approver's Region on the Admin page also limits what they see
-- (Ruth, 2 November). An approver routed for both regions still sees both,
-- and Admins see everything. Safe to run more than once.

create or replace function approver_region_of(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when 'admin' = any (p.roles) then null
    when (select count(distinct r.region) from approval_routes r where r.approver_id = p.id) > 1 then null
    else coalesce(p.region, (select min(r.region) from approval_routes r where r.approver_id = p.id))
  end
  from profiles p
  where p.id = p_user;
$$;
