-- Employee ID on each user (Ruth, 1 November). The ID prefix shows the
-- region: NO and NFS (field staff) are NCR, VO and VFS (field staff) are
-- VisMin. When no region is chosen, it comes from the prefix.

alter table profiles add column if not exists employee_id text;

create or replace function admin_update_user(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('admin');
  v_roles app_role[];
  v_active boolean := coalesce((p ->> 'active')::boolean, true);
  v_pa uuid := txt(p, 'default_payment_approver')::uuid;
  v_fa uuid := txt(p, 'default_fund_approver')::uuid;
  v_region text := txt(p, 'region');
  v_emp text := upper(txt(p, 'employee_id'));
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
  if v_region is null then
    v_region := case when v_emp ~ '^(NO|NFS)' then 'NCR' when v_emp ~ '^(VO|VFS)' then 'VisMin' end;
  end if;

  update profiles set
    full_name = coalesce(txt(p, 'full_name'), full_name),
    roles = v_roles,
    mobile_no = normalize_mobile(p ->> 'mobile_no'),
    default_payment_approver = v_pa,
    default_fund_approver = v_fa,
    region = case when p ? 'region' or v_region is not null then v_region else region end,
    employee_id = case when p ? 'employee_id' then v_emp else employee_id end,
    active = v_active
  where id = p_id;
  if not found then raise exception 'User not found.'; end if;

  if not exists (select 1 from profiles where active and 'admin' = any (roles)) then
    raise exception 'At least one active Admin must remain.';
  end if;
end $$;
