-- Category shows only the QuickBooks expense accounts again (Ruth, 15 November:
-- "update categories expenses to quickbooks expenses list"): types Expenses and
-- Cost of Sales from the October 2026 account list, 77 accounts. The other
-- accounts are switched off rather than deleted, so Admin can switch any back on.

update lookups set active = (qb_type in ('Expenses', 'Cost of Sales'))
 where list = 'category';
