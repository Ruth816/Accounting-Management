-- "Direct Debit" as a Type of payment on payment requests (Ruth, 1 November).
-- When received for funding, the fund request's payment method is Direct Debit.
alter table payment_requests drop constraint if exists payment_requests_payment_type_check;
alter table payment_requests add constraint payment_requests_payment_type_check
  check (payment_type in ('Cash', 'Cheque', 'Bank deposit', 'Direct Debit'));

create or replace function direct_debit_method() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.payment_request_id is not null
     and (select payment_type from payment_requests where id = new.payment_request_id) = 'Direct Debit' then
    new.payment_method := 'Direct Debit';
  end if;
  return new;
end $$;

drop trigger if exists direct_debit_method on fund_requests;
create trigger direct_debit_method before insert on fund_requests
  for each row execute function direct_debit_method();

revoke execute on function direct_debit_method() from public, anon, authenticated;
