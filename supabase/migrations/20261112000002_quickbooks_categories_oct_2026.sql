-- Categories follow Aspencom's QuickBooks account list as of October 2026 (Ruth, 12 November).
-- Expense accounts are unchanged. In QuickBooks the PROJ project-cost accounts are now all
-- sub-accounts of "Cost of sales", so their full names change (e.g. "PROJ SUBCON" becomes
-- "Cost of sales:PROJ SUBCON"). The locked parents AMORTIZATION EXPENSES and
-- TRANSPORTATION EXPENSES- ADMIN stay out, so only their sub-accounts can be picked (spec 10).

create temp table category_renames (old_label text primary key, new_label text not null);
insert into category_renames values
  ('PROJ Commissions & Fees', 'Cost of sales:PROJ Commissions & Fees'),
  ('PROJ Mobilization Expenses', 'Cost of sales:PROJ Mobilization Expenses'),
  ('PROJ Mobilization Expenses:PROJ Permitting & Safety Expenses', 'Cost of sales:PROJ Permitting & Safety Expenses'),
  ('PROJ Mobilization Expenses:PROJ Tools/Equipment Repairs', 'Cost of sales:PROJ Tools/Equipment Repairs'),
  ('PROJ Mobilization Expenses:PROJ Vehicles Expenses', 'Cost of sales:PROJ Vehicles Expenses'),
  ('PROJ SUBCON', 'Cost of sales:PROJ SUBCON'),
  ('PROJ Supplies & Materials', 'Cost of sales:PROJ Supplies & Materials'),
  ('PROJ Supplies & Materials:PROJ Freight and delivery Fees', 'Cost of sales:PROJ Freight and delivery Fees');

-- Requests not yet exported to QuickBooks move to the new names, so their export matches.
update fund_requests f set category = r.new_label
  from category_renames r
 where f.category = r.old_label and not f.locked;

update fund_requests f
   set lines = (
     select coalesce(jsonb_agg(
              case when r.new_label is not null then jsonb_set(e, '{category}', to_jsonb(r.new_label)) else e end
              order by i), '[]'::jsonb)
       from jsonb_array_elements(f.lines) with ordinality as t(e, i)
       left join category_renames r on r.old_label = e ->> 'category')
 where not f.locked
   and exists (select 1 from jsonb_array_elements(f.lines) e join category_renames r on r.old_label = e ->> 'category');

-- Replace the category list with the QuickBooks one, in QuickBooks order.
delete from lookups where list = 'category';
insert into lookups (list, label, qb_type, sort) values
  ('category', 'AMORTIZATION EXPENSES:Credit Line Partial Payment', 'Expense', 1),
  ('category', 'Bad debts', 'Expense', 2),
  ('category', 'BANK CHARGES', 'Expense', 3),
  ('category', 'BANK CHARGES:Credit line Renewal Fees', 'Expense', 4),
  ('category', 'BANK CHARGES:Interest expense', 'Expense', 5),
  ('category', 'BANK CHARGES:Transfer & MC Fees', 'Expense', 6),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES', 'Expense', 7),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES:Business License & Permits- Admin', 'Expense', 8),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES:Legal and professional fees', 'Expense', 9),
  ('category', 'GOVERMENT LICENSES & PROFESSIONAL FEES:Penalties & Late filings', 'Expense', 10),
  ('category', 'INSURANCE EXPENSES', 'Expense', 11),
  ('category', 'INSURANCE EXPENSES:Insurance - Disability', 'Expense', 12),
  ('category', 'INSURANCE EXPENSES:Insurance - General', 'Expense', 13),
  ('category', 'INSURANCE EXPENSES:Insurance - Liability', 'Expense', 14),
  ('category', 'Loss on discontinued operations, net of tax', 'Expense', 15),
  ('category', 'MEALS & ENTERTAINMENT', 'Expense', 16),
  ('category', 'MEALS & ENTERTAINMENT:Company Events & recreational', 'Expense', 17),
  ('category', 'MEALS & ENTERTAINMENT:Official Meals & Entertainment Expense', 'Expense', 18),
  ('category', 'MISCELLANEOUS', 'Expense', 19),
  ('category', 'MISCELLANEOUS:Other- Hauling Services', 'Expense', 20),
  ('category', 'MISCELLANEOUS:Other- Office Expenses', 'Expense', 21),
  ('category', 'OFFICE EXPENSES- Admin', 'Expense', 22),
  ('category', 'OFFICE EXPENSES- Admin:Office equipment rental & maintenance', 'Expense', 23),
  ('category', 'OFFICE EXPENSES- Admin:Office Supplies', 'Expense', 24),
  ('category', 'OFFICE EXPENSES- Admin:Office Uniform', 'Expense', 25),
  ('category', 'OFFICE EXPENSES- Admin:Printing & Fax', 'Expense', 26),
  ('category', 'OFFICE EXPENSES- Admin:Shipping and delivery expense', 'Expense', 27),
  ('category', 'OFFICE EXPENSES- Admin:Software/ APP Subscriptions', 'Expense', 28),
  ('category', 'OFFICE EXPENSES- Admin:Trainings & Seminar', 'Expense', 29),
  ('category', 'OFFICE EXPENSES- Admin:Utilities (light, water & Internet)', 'Expense', 30),
  ('category', 'OFFICE EXPENSES- Admin:Utilities (light, water & Internet):Mobile Allowances', 'Expense', 31),
  ('category', 'Other selling expenses', 'Expense', 32),
  ('category', 'Other Types of Expenses-Advertising Expenses', 'Expense', 33),
  ('category', 'PAYROLL EXPENSES', 'Expense', 34),
  ('category', 'PAYROLL EXPENSES:13th month & last Pay', 'Expense', 35),
  ('category', 'PAYROLL EXPENSES:Benefits HMO , Medical & Hospitalization', 'Expense', 36),
  ('category', 'PAYROLL EXPENSES:Benefits Mandatory', 'Expense', 37),
  ('category', 'PAYROLL EXPENSES:Benefits Perks & Rewards', 'Expense', 38),
  ('category', 'PAYROLL EXPENSES:Incentive & Bonuses', 'Expense', 39),
  ('category', 'Purchases', 'Expense', 40),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin', 'Expense', 41),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Assoc/ Admin dues', 'Expense', 42),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Employees Housing Expense', 'Expense', 43),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Rental Payments (Ofc/Warehouse)', 'Expense', 44),
  ('category', 'RENTAL/ LEASE EXPENSES- Admin:Repairs & Improvement Expense', 'Expense', 45),
  ('category', 'SALARIES & WAGES EXPENSES', 'Expense', 46),
  ('category', 'SALARIES & WAGES EXPENSES:Cash Allowances', 'Expense', 47),
  ('category', 'SALARIES & WAGES EXPENSES:Salaries', 'Expense', 48),
  ('category', 'SPONSORSHIP & EVENTS Expenses', 'Expense', 49),
  ('category', 'SPONSORSHIP & EVENTS Expenses:Client Events Support', 'Expense', 50),
  ('category', 'SPONSORSHIP & EVENTS Expenses:Community Share', 'Expense', 51),
  ('category', 'SPONSORSHIP & EVENTS Expenses:Education Scholarship', 'Expense', 52),
  ('category', 'TAX PAID', 'Expense', 53),
  ('category', 'TAX PAID:BIR (Business Taxes)', 'Expense', 54),
  ('category', 'TAX PAID:Income tax expense', 'Expense', 55),
  ('category', 'TAX PAID:Property TAX', 'Expense', 56),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Fuel/Gasoline, Tolls, Taxi ,Parking & Angkas', 'Expense', 57),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Transpo Allowances', 'Expense', 58),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Vehicles (maintenance & repair)', 'Expense', 59),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:Vehicles (Registration& Insurance)', 'Expense', 60),
  ('category', 'TRANSPORTATION EXPENSES- ADMIN:VEHICLES Amortization', 'Expense', 61),
  ('category', 'TRAVEL EXPENSES- Admin', 'Expense', 62),
  ('category', 'TRAVEL EXPENSES- Admin:Airfare, accommodation & allowances', 'Expense', 63),
  ('category', 'Unapplied Cash Bill Payment Expense', 'Expense', 64),
  ('category', 'Uncategorized Expense', 'Expense', 65),
  ('category', 'Wage expenses', 'Expense', 66),
  ('category', 'Cost of sales', 'Cost of Goods Sold', 67),
  ('category', 'Cost of sales:PROJ Commissions & Fees', 'Cost of Goods Sold', 68),
  ('category', 'Cost of sales:PROJ Freight and delivery Fees', 'Cost of Goods Sold', 69),
  ('category', 'Cost of sales:PROJ Mobilization Expenses', 'Cost of Goods Sold', 70),
  ('category', 'Cost of sales:PROJ Permitting & Safety Expenses', 'Cost of Goods Sold', 71),
  ('category', 'Cost of sales:PROJ SUBCON', 'Cost of Goods Sold', 72),
  ('category', 'Cost of sales:PROJ Supplies & Materials', 'Cost of Goods Sold', 73),
  ('category', 'Cost of sales:PROJ Tools/Equipment Repairs', 'Cost of Goods Sold', 74),
  ('category', 'Cost of sales:PROJ Vehicles Expenses', 'Cost of Goods Sold', 75)
on conflict (list, label) do update set qb_type = excluded.qb_type, sort = excluded.sort, active = true;

drop table category_renames;
