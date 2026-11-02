-- Tax per item on multi-item fund requests (Ruth, 2 November), between
-- Amount and Category. Total before tax and sales tax add up each item's
-- own tax; the request's Tax shows the first item's.

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
           'category', nullif(btrim(e ->> 'category'), ''),
           'customer', nullif(btrim(e ->> 'customer'), ''),
           'tax_code', nullif(btrim(e ->> 'tax_code'), '')
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
    category = case when jsonb_array_length(v_lines) > 0 then v_lines -> 0 ->> 'category' else category end,
    tax_code = case when jsonb_array_length(v_lines) > 0 and not tax_locked then v_lines -> 0 ->> 'tax_code' else tax_code end,
    tax_rate = case when jsonb_array_length(v_lines) > 0 and not tax_locked
                    then (select rate from lookups where list = 'tax_code' and label = v_lines -> 0 ->> 'tax_code')
                    else tax_rate end
  where id = f.id;
end $$;

create or replace function compute_fr_amounts() returns trigger
language plpgsql as $$
declare
  v_rate numeric;
  v_missing boolean;
begin
  if new.currency = 'PHP' then
    new.exchange_rate := 1;
    new.rate_date := null;
  end if;
  v_rate := new.exchange_rate;
  if new.original_amount is null or v_rate is null then
    new.amount_php := null;
  else
    new.amount_php := round(new.original_amount * v_rate, 2);
  end if;

  if new.amount_php is not null and jsonb_array_length(coalesce(new.lines, '[]')) > 0
     and exists (select 1 from jsonb_array_elements(new.lines) e where e ->> 'tax_code' is not null) then
    -- Each item's own tax.
    select bool_or(l.rate is null) into v_missing
      from jsonb_array_elements(new.lines) e
      left join lookups l on l.list = 'tax_code' and l.label = e ->> 'tax_code';
    if v_missing then
      new.total_before_tax := null;
      new.sales_tax := null;
    else
      select sum(round(coalesce((e ->> 'amount')::numeric, 0) * v_rate / (1 + l.rate), 2))
        into new.total_before_tax
        from jsonb_array_elements(new.lines) e
        join lookups l on l.list = 'tax_code' and l.label = e ->> 'tax_code';
      new.sales_tax := new.amount_php - new.total_before_tax;
    end if;
  elsif new.amount_php is null or new.tax_rate is null then
    new.total_before_tax := null;
    new.sales_tax := null;
  else
    new.total_before_tax := round(new.amount_php / (1 + new.tax_rate), 2);
    new.sales_tax := new.amount_php - new.total_before_tax;
  end if;
  return new;
end $$;

create or replace function check_fund_lines() returns trigger
language plpgsql as $$
begin
  if new.status = 'pending_fund_approval' and old.status is distinct from new.status
     and exists (select 1 from jsonb_array_elements(new.lines) e
                 where coalesce(e ->> 'description', '') = '' or e ->> 'category' is null
                    or (e ->> 'tax_code' is null and not new.tax_locked)
                    or coalesce((e ->> 'amount')::numeric, 0) <= 0) then
    raise exception 'Every item needs a description, an amount above 0, a tax and a category.';
  end if;
  return new;
end $$;
