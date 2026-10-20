-- Phase 1 dropdown values (spec section 10). Placeholders until the real
-- QuickBooks lists are connected.
insert into lookups (list, label, rate, sort) values
  ('payment_method', 'Check', null, 1),
  ('payment_method', 'Auto debit', null, 2),
  ('payment_method', 'Bank transfer', null, 3),
  ('payment_method', 'Cash', null, 4),
  ('payment_account', 'BDO Current Account', null, 1),
  ('payment_account', 'BPI Savings Account', null, 2),
  ('payment_account', 'Petty Cash Fund', null, 3),
  ('category', 'Utilities', null, 1),
  ('category', 'Telephone and Internet', null, 2),
  ('category', 'Office Supplies', null, 3),
  ('category', 'Software and Subscriptions', null, 4),
  ('category', 'Loan Payable', null, 5),
  ('category', 'Professional Fees', null, 6),
  ('category', 'Rent', null, 7),
  ('tax_code', '12% S - Goods', 0.12, 1),
  ('tax_code', '12% S - Services', 0.12, 2),
  ('tax_code', 'No VAT (0%)', 0, 3)
on conflict (list, label) do nothing;
