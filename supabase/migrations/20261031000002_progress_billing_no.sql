-- Mode of payment: progress billing carries its number, stored as 'PB 1', 'PB 2', ...
alter table public.payment_requests drop constraint if exists payment_requests_po_mode_check;
alter table public.payment_requests add constraint payment_requests_po_mode_check
  check (po_mode ~ '^(D/P|FB|FP|PB( [1-9][0-9]*)?)$');
