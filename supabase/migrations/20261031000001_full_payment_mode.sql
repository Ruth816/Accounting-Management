-- Mode of payment: add FP (full payment, 100%).
alter table public.payment_requests drop constraint if exists payment_requests_po_mode_check;
alter table public.payment_requests add constraint payment_requests_po_mode_check
  check (po_mode in ('D/P', 'PB', 'FB', 'FP'));
