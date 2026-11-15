-- Category offers only Expenses, Cost of Sales and the Directors Advances account
-- (Ruth, 15 November: "expenses, director cash advance and cost of sales only"),
-- from the October 2026 QuickBooks account list: 78 accounts. The other accounts
-- are switched off rather than deleted, so Admin can switch any back on.

update lookups
   set active = (qb_type in ('Expenses', 'Cost of Sales') or label = 'ADVANCES:Directors Advances')
 where list = 'category';
