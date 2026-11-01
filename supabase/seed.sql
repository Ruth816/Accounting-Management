-- Tax codes (spec section 10). Payment methods, payment accounts and categories
-- are the QuickBooks lists loaded by migration 20261101000003_quickbooks_lists.sql.
insert into lookups (list, label, rate, sort) values
  ('tax_code', '12% S - Goods', 0.12, 1),
  ('tax_code', '12% S - Services', 0.12, 2),
  ('tax_code', 'No VAT (0%)', 0, 3)
on conflict (list, label) do nothing;
