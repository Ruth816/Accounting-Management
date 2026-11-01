-- Requestors see only their own region (Ruth, 1 November):
-- an NCR Payment Requestor or Fund Requestor sees and files only NCR
-- requests, a VisMin one only VisMin. The Admin sets each person's region
-- on the Users table. No region means both regions. Approvers and Admins
-- always see every region.

alter table profiles add column if not exists region text check (region in ('NCR', 'VisMin'));

-- The region the signed-in person is limited to, or null when they are not
-- limited (no region set, or they are an Admin or an approver).
create or replace function my_region() returns text
language sql stable security definer set search_path = public as $$
  select region from profiles
  where id = auth.uid()
    and not (roles && array['admin', 'payment_approver', 'fund_approver']::app_role[]);
$$;

create or replace function region_ok(p_region text) returns boolean
language sql stable security definer set search_path = public as $$
  select my_region() is null or p_region is null or p_region = my_region();
$$;

-- A fund request's region, for older rows that were made before fund
-- requests carried one: types 2 and 4 are NCR, 3 and 5 are VisMin.
create or replace function fr_region(f fund_requests) returns text
language sql immutable as $$
  select coalesce(f.region, case f.request_type when 2 then 'NCR' when 4 then 'NCR'
                                                when 3 then 'VisMin' when 5 then 'VisMin' end);
$$;

drop policy if exists "visible payment requests" on payment_requests;
create policy "visible payment requests" on payment_requests for select to authenticated
  using (requestor_id = auth.uid()
         or approver_id = auth.uid()
         or (has_role('payment_approver') and status <> 'draft')
         or (has_role('fund_requestor') and region_ok(region))
         or has_role('admin'));

create or replace function can_see_pr(pr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from payment_requests p
    where p.id = pr_id
      and (p.requestor_id = auth.uid()
           or p.approver_id = auth.uid()
           or (has_role('payment_approver') and p.status <> 'draft')
           or (has_role('fund_requestor') and region_ok(p.region))
           or has_role('admin'))
  );
$$;

drop policy if exists "visible fund requests" on fund_requests;
create policy "visible fund requests" on fund_requests for select to authenticated
  using ((has_role('fund_requestor') and region_ok(fr_region(fund_requests)))
         or has_role('admin')
         or fund_approver_id = auth.uid()
         or exists (select 1 from payment_requests p
                    where p.id = payment_request_id and p.requestor_id = auth.uid()));

create or replace function can_see_fr(fr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fund_requests f
    left join payment_requests p on p.id = f.payment_request_id
    where f.id = fr_id
      and ((has_role('fund_requestor') and region_ok(fr_region(f)))
           or has_role('admin')
           or f.fund_approver_id = auth.uid()
           or p.requestor_id = auth.uid())
  );
$$;

-- A limited Payment Requestor's requests are always in their region.
create or replace function lock_pr_region() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v text := my_region();
begin
  if v is not null and new.requestor_id = auth.uid()
     and (tg_op = 'INSERT' or new.region is distinct from old.region) then
    new.region := v;
  end if;
  return new;
end $$;

drop trigger if exists lock_pr_region on payment_requests;
create trigger lock_pr_region before insert or update on payment_requests
  for each row execute function lock_pr_region();

-- A limited Fund Requestor can't receive, edit or send a fund request of the
-- other region. Auto debits they create take their region.
create or replace function lock_fr_region() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v text := my_region();
begin
  if v is null then return new; end if;
  if tg_op = 'INSERT' and new.region is null and new.payment_request_id is null then
    new.region := v;
  end if;
  if fr_region(new) is distinct from v and fr_region(new) is not null then
    raise exception 'This request belongs to another region.';
  end if;
  return new;
end $$;

drop trigger if exists lock_fr_region on fund_requests;
create trigger lock_fr_region before insert or update on fund_requests
  for each row execute function lock_fr_region();

create or replace function admin_update_user(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  v_roles app_role[];
  v_active boolean := coalesce((p ->> 'active')::boolean, true);
  v_pa uuid := txt(p, 'default_payment_approver')::uuid;
  v_fa uuid := txt(p, 'default_fund_approver')::uuid;
  v_region text := txt(p, 'region');
begin
  select coalesce(array_agg(distinct x::app_role), '{}') into v_roles
  from jsonb_array_elements_text(coalesce(p -> 'roles', '[]'::jsonb)) x;

  if v_pa = p_id or (v_pa is not null and not user_has_role(v_pa, 'payment_approver')) then
    raise exception 'The default payment approver must be another active Payment Approver.';
  end if;
  if v_fa = p_id or (v_fa is not null and not user_has_role(v_fa, 'fund_approver')) then
    raise exception 'The default fund approver must be another active Fund Approver.';
  end if;
  if v_region is not null and v_region not in ('NCR', 'VisMin') then
    raise exception 'Region must be NCR or VisMin.';
  end if;

  update profiles set
    full_name = coalesce(txt(p, 'full_name'), full_name),
    roles = v_roles,
    mobile_no = normalize_mobile(p ->> 'mobile_no'),
    default_payment_approver = v_pa,
    default_fund_approver = v_fa,
    region = case when p ? 'region' then v_region else region end,
    active = v_active
  where id = p_id;
  if not found then raise exception 'User not found.'; end if;

  if not exists (select 1 from profiles where active and 'admin' = any (roles)) then
    raise exception 'At least one active Admin must remain.';
  end if;
end $$;

-- Messages to everyone in a role skip requestors of the other region.
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
                  or roles && array['admin', 'payment_approver', 'fund_approver']::app_role[]) loop
    perform notify(r.id, p_message, p_pr, p_fr);
  end loop;
end $$;

revoke execute on function notify_role(app_role, text, uuid, uuid) from public, anon, authenticated;
revoke execute on function lock_pr_region(), lock_fr_region() from public, anon, authenticated;
