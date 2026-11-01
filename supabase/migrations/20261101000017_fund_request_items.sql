-- Several items on an auto debit or check payment fund request (Ruth,
-- 1 November), each with its own description, amount and category. The
-- request's description, original amount and category are filled from the
-- items: numbered descriptions, the sum, and the first item's category.

alter table fund_requests add column if not exists lines jsonb not null default '[]';

create or replace function save_fund_lines(p_id uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  f fund_requests;
  v_lines jsonb;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.payment_request_id is not null then raise exception 'Items come from the payment request.'; end if;
  if f.locked or f.status not in ('in_funding_preparation', 'returned_to_fund_requestor') then
    raise exception 'This fund request can no longer be edited.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'description', coalesce(btrim(e ->> 'description'), ''),
           'amount', round(nullif(btrim(replace(e ->> 'amount', ',', '')), '')::numeric, 2),
           'category', nullif(btrim(e ->> 'category'), '')
         ) order by i), '[]'::jsonb)
    into v_lines
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, i)
   where coalesce(btrim(e ->> 'description'), '') <> ''
      or nullif(btrim(e ->> 'amount'), '') is not null
      or nullif(btrim(e ->> 'category'), '') is not null;

  update fund_requests set
    lines = v_lines,
    original_amount = case when jsonb_array_length(v_lines) > 0
                           then (select sum((e ->> 'amount')::numeric) from jsonb_array_elements(v_lines) e)
                           else original_amount end,
    description = case
      when jsonb_array_length(v_lines) = 1 then v_lines -> 0 ->> 'description'
      when jsonb_array_length(v_lines) > 1 then
        (select string_agg(format('%s. %s', i, e ->> 'description'), E'\n' order by i)
           from jsonb_array_elements(v_lines) with ordinality as t(e, i))
      else description end,
    category = case when jsonb_array_length(v_lines) > 0 then v_lines -> 0 ->> 'category' else category end
  where id = f.id;
end $$;

-- Sending for approval needs every item complete.
create or replace function check_fund_lines() returns trigger
language plpgsql as $$
begin
  if new.status = 'pending_fund_approval' and old.status is distinct from new.status
     and exists (select 1 from jsonb_array_elements(new.lines) e
                 where coalesce(e ->> 'description', '') = '' or e ->> 'category' is null
                    or coalesce((e ->> 'amount')::numeric, 0) <= 0) then
    raise exception 'Every item needs a description, an amount above 0 and a category.';
  end if;
  return new;
end $$;

drop trigger if exists check_fund_lines on fund_requests;
create trigger check_fund_lines before update on fund_requests
  for each row execute function check_fund_lines();

revoke execute on function save_fund_lines(uuid, jsonb) from public, anon;
grant execute on function save_fund_lines(uuid, jsonb) to authenticated;
