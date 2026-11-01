-- The next Payment REQ No., shown on the New payment request form before it
-- is saved (Ruth, 1 November). Numbers stay first come, first served across
-- Admins and requestors: the real number is still taken when the request is
-- first saved, so two people saving at once never get the same number.
create or replace function peek_next_req_no() returns text
language sql stable security definer set search_path = public as $$
  select substr(ym, 1, 4) || ' ' || substr(ym, 5, 2) || ' ' ||
         lpad((coalesce((select last_no from req_counters where yyyymm = ym), 0) + 1)::text, 4, '0')
  from (select to_char(now() at time zone 'Asia/Manila', 'YYYYMM') as ym) t;
$$;

revoke execute on function peek_next_req_no() from public, anon;
grant execute on function peek_next_req_no() to authenticated;
