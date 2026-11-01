-- A fund request received from a payment request starts with the payment
-- request's Date required as its Payment date (Ruth, 1 November), on top of
-- the payee, description, item no., currency, amount, payment method and tax
-- already carried over. The fund request page also shows every payment
-- request detail.
create or replace function carry_from_payment_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.payment_request_id is not null and new.payment_date is null then
    new.payment_date := (select date_required from payment_requests where id = new.payment_request_id);
  end if;
  return new;
end $$;

drop trigger if exists carry_from_payment_request on fund_requests;
create trigger carry_from_payment_request before insert on fund_requests
  for each row execute function carry_from_payment_request();

revoke execute on function carry_from_payment_request() from public, anon, authenticated;
