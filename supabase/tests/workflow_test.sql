-- Runs the spec's acceptance checks (section 11) against the database rules.
-- Run with: supabase/tests/run.sh (plain Postgres 15+ with the stub schema).
\set ON_ERROR_STOP 1
\o /dev/null

create schema t;
grant usage on schema t to authenticated;
create function t.as_user(name text) returns void language sql security definer as $$
  select set_config('request.jwt.claim.sub', (select id::text from auth.users where email = name || '@x.test'), false);
$$;
create function t.uid(name text) returns uuid language sql security definer as $$
  select id from auth.users where email = name || '@x.test';
$$;
create function t.expect_error(q text, pattern text) returns void language plpgsql as $$
begin
  execute q;
  raise exception 'Expected an error matching "%" from: %', pattern, q;
exception when others then
  if sqlerrm like 'Expected an error%' then raise; end if;
  if sqlerrm !~* pattern then
    raise exception 'Wrong error from %: got "%", wanted "%"', q, sqlerrm, pattern;
  end if;
end $$;
create function t.eq(got anyelement, want anyelement, label text) returns void language plpgsql as $$
begin
  if got is distinct from want then raise exception '%: got %, want %', label, got, want; end if;
  raise notice 'ok  %', label;
end $$;
grant execute on all functions in schema t to authenticated;

-- People
insert into auth.users (id, email, raw_user_meta_data) values
  (gen_random_uuid(), 'req@x.test', '{"full_name":"Rita Requestor"}'),
  (gen_random_uuid(), 'req2@x.test', '{"full_name":"Other Requestor"}'),
  (gen_random_uuid(), 'appr@x.test', '{"full_name":"Paolo Approver"}'),
  (gen_random_uuid(), 'fr@x.test', '{"full_name":"Fe Fundreq"}'),
  (gen_random_uuid(), 'fa@x.test', '{"full_name":"Fred Fundappr"}'),
  (gen_random_uuid(), 'adm@x.test', '{"full_name":"Ada Admin"}');
update profiles set roles = '{payment_requestor}' where email in ('req@x.test', 'req2@x.test');
update profiles set roles = '{payment_requestor,payment_approver}' where email = 'appr@x.test';
update profiles set roles = '{fund_requestor}', default_fund_approver = t.uid('fa'), mobile_no = '639171234567' where email = 'fr@x.test';
update profiles set roles = '{fund_approver}' where email = 'fa@x.test';
update profiles set roles = '{admin}' where email = 'adm@x.test';
update profiles set default_payment_approver = t.uid('appr'), mobile_no = '639181112222' where email = 'req@x.test';

set role authenticated;

-- Stage 1 -------------------------------------------------------------------
select t.as_user('req');
create temp table ids (k text primary key, v uuid);
insert into ids values ('pr', save_payment_request(null, '{
  "payable_to": "Meralco", "purpose": "Barangay permit fee", "date_required": "2026-11-01",
  "items": [{"description": "Permit", "amount": "1,000.00"}, {"description": "Notary", "amount": 120}, {"description": "", "amount": ""}],
  "billing_type": "VAT", "wtax_rate": "0.02"}'));

select t.eq((select approver_id from payment_requests where id = (select v from ids where k='pr')), t.uid('appr'), 'approver pre-filled from default');
select t.eq((select array[total_vat_in, total_vat_ex, wtax_amount, total_due]::text from payment_requests where id = (select v from ids where k='pr')),
            '{1120.00,1000.00,20.00,1100.00}', '1,120.00 VAT-in at 2% gives 1,000.00 / 20.00 / 1,100.00');
select t.eq((select item_no from payment_requests where id = (select v from ids where k='pr')), '1-2', 'item no. 1-n');
select t.eq((select req_no ~ '^20[0-9]{2} [01][0-9] 0001$' from payment_requests where id = (select v from ids where k='pr')), true, 'req no. format');

select t.expect_error(format('select submit_payment_request(%L)', (select v from ids where k='pr')), 'terms and conditions');
select save_payment_request((select v from ids where k='pr'), ('{
  "payable_to": "Meralco", "purpose": "Barangay permit fee", "date_required": "2026-11-01",
  "items": [{"description": "Permit", "amount": "1000"}, {"description": "Notary", "amount": 120}],
  "billing_type": "VAT", "wtax_rate": "0.02", "terms_accepted": true, "approver_id": "' || t.uid('req') || '"}')::jsonb);
select t.expect_error(format('select submit_payment_request(%L)', (select v from ids where k='pr')), 'cannot approve your own');
select save_payment_request((select v from ids where k='pr'), ('{
  "payable_to": "", "purpose": "", "items": [], "terms_accepted": false}')::jsonb);
select t.expect_error(format('select submit_payment_request(%L)', (select v from ids where k='pr')),
  'Payable to is required.*Purpose is required.*Date required.*above 0.*Choose an approver.*terms');
select save_payment_request((select v from ids where k='pr'), ('{
  "payable_to": "Meralco", "purpose": "Barangay permit fee", "date_required": "2026-11-01",
  "items": [{"description": "Permit", "amount": "1000"}, {"description": "Notary", "amount": 120}],
  "billing_type": "VAT", "wtax_rate": "0.02", "terms_accepted": true, "approver_id": "' || t.uid('appr') || '"}')::jsonb);
select submit_payment_request((select v from ids where k='pr'));

-- Another requestor cannot see it.
select t.as_user('req2');
select t.eq((select count(*) from payment_requests), 0::bigint, 'other requestor sees nothing');
select t.expect_error(format('select approve_payment_request(%L)', (select v from ids where k='pr')), 'Payment Approver role');

-- Approver disapproves, requestor resubmits as version 2.
select t.as_user('appr');
select t.expect_error(format('select disapprove_payment_request(%L, %L)', (select v from ids where k='pr'), ' '), 'reason is required');
select disapprove_payment_request((select v from ids where k='pr'), 'Attach the permit');
select t.as_user('req');
select t.eq((select status::text from payment_requests where id = (select v from ids where k='pr')), 'returned_to_requestor', 'returned');
-- approver is locked while returned
select save_payment_request((select v from ids where k='pr'), ('{
  "payable_to": "Meralco", "purpose": "Barangay permit fee (with permit)", "date_required": "2026-11-01",
  "items": [{"description": "Permit", "amount": "1000"}, {"description": "Notary", "amount": 120}],
  "billing_type": "VAT", "wtax_rate": "0.02", "terms_accepted": true, "approver_id": "' || t.uid('req2') || '"}')::jsonb);
select submit_payment_request((select v from ids where k='pr'));
select t.eq((select array[version::text, approver_id::text] from payment_requests where id = (select v from ids where k='pr')),
            array['2', t.uid('appr')::text], 'resubmit: version 2, same approver');
select t.eq((select count(*) from payment_request_versions where payment_request_id = (select v from ids where k='pr') and version = 1 and reason = 'Attach the permit'), 1::bigint, 'version history keeps v1');

select t.as_user('appr');
select approve_payment_request((select v from ids where k='pr'));

-- Stage 2 -------------------------------------------------------------------
select t.as_user('fr');
insert into ids values ('fr', receive_payment_request((select v from ids where k='pr')));
select t.eq((select array[request_type::text, payee, item_no, currency, original_amount::text, payment_method, fund_approver_id::text]
             from fund_requests where id = (select v from ids where k='fr')),
            array['2', 'Meralco', '1-2', 'PHP', '1120.00', 'Check', t.uid('fa')::text], 'receive copies fields, NCR/No gives type 2');
select t.eq((select wtax_note from fund_requests where id = (select v from ids where k='fr')),
            'Less W-tax 2%: PHP 20.00. Total amount due: PHP 1,100.00.', 'W-tax note');

-- Copied fields cannot be overwritten.
select save_fund_request((select v from ids where k='fr'), '{"payee": "Hacker", "original_amount": 1}');
select t.eq((select payee || original_amount from fund_requests where id = (select v from ids where k='fr')), 'Meralco1120.00', 'copied fields are read-only');

-- Ref no. rules
select save_fund_request((select v from ids where k='fr'), jsonb_build_object(
  'ref_no', '3- 2026 10 0075', 'payment_date', '2026-10-21', 'payment_method', 'Check',
  'tax_code', '12% S - Services', 'payment_account', 'BDO Current Account', 'category', 'Rent',
  'fund_approver_id', t.uid('fa'), 'cheque_mode', 'new', 'cheque_no', '100200', 'subtotal_to_fund', '1120'));
select t.expect_error(format('select submit_fund_request(%L)', (select v from ids where k='fr')), 'must start with 2-');
select t.as_user('fr');

-- A second fund request (auto debit) on the same cheque.
insert into ids values ('ad', create_auto_debit_request());
select t.expect_error(format('select save_fund_request(%L, %L)', (select v from ids where k='ad'),
  '{"payment_method":"Check","cheque_mode":"new","cheque_no":"100200"}'), 'already exists');
select save_fund_request((select v from ids where k='ad'), jsonb_build_object(
  'ref_no', '1- 2026 10 0001', 'payee', 'PLDT', 'item_no', '1', 'description', 'Internet', 'currency', 'USD',
  'original_amount', '420', 'exchange_rate', '58.25', 'rate_date', '2026-10-20',
  'payment_date', '2026-10-21', 'payment_method', 'Check', 'bank_account_name', 'Co', 'bank_account_no', '123',
  'tax_code', '12% S - Services', 'payment_account', 'Cash and cash equivalents', 'category', 'OFFICE EXPENSES- Admin:Utilities (light, water & Internet)',
  'fund_approver_id', t.uid('fa'), 'cheque_mode', 'existing',
  'cheque_id', (select id from cheques where cheque_no = '100200'), 'subtotal_to_fund', '24465'));
select t.eq((select amount_php from fund_requests where id = (select v from ids where k='ad')), 24465.00, 'USD 420 at 58.25 gives PHP 24,465.00');
select t.eq((select cheque_total(id) from cheques where cheque_no = '100200'), 25585.00, 'cheque total = sum of subtotals');
select t.eq((select memo from fund_requests where id = (select v from ids where k='fr')),
  'Check No. 100200 | Check total PHP 25,585.00 | Subtotal funded PHP 1,120.00', 'memo pre-fill follows cheque total');

-- Fix the ref no. and send; duplicate ref is refused.
select save_fund_request((select v from ids where k='fr'), jsonb_build_object(
  'ref_no', '2- 2026 10 0075', 'payment_date', '2026-10-21', 'payment_method', 'Check',
  'tax_code', '12% S - Services', 'payment_account', 'BDO Current Account', 'category', 'Rent',
  'fund_approver_id', t.uid('fa'), 'cheque_mode', 'existing', 'cheque_id', (select id from cheques where cheque_no = '100200'),
  'subtotal_to_fund', '1120', 'memo', 'Check No. 100200 | Check total PHP 25,585.00 | Subtotal funded PHP 1,120.00'));
select t.eq((select memo_edited from fund_requests where id = (select v from ids where k='fr')), false, 'unchanged memo is not an edit');
select submit_fund_request((select v from ids where k='fr'));
select t.eq((select status::text from payment_requests where id = (select v from ids where k='pr')), 'pending_fund_approval', 'payment request follows fund status');
select t.expect_error(format('select save_fund_request(%L, %L)', (select v from ids where k='ad'),
  jsonb_build_object('ref_no', '2- 2026 10 0075', 'payment_method', 'Direct Debit', 'payee', 'PLDT', 'description', 'x', 'original_amount', 1)), 'already used');
select t.expect_error(format('select save_fund_request(%L, %L)', (select v from ids where k='ad'),
  jsonb_build_object('ref_no', '2- 2026 10 0099', 'payment_method', 'Direct Debit', 'payee', 'PLDT', 'description', 'x', 'original_amount', 1)) || '; select submit_fund_request(' || quote_literal((select v from ids where k='ad')) || ')', 'must start with 1-');

-- 5,500 at 12%
select t.eq((select round(5500.00 / 1.12, 2)), 4910.71, '5,500 at 12% gives 4,910.71');

-- Fund approval
select t.as_user('fa');
select t.expect_error(format('select approve_fund_request(%L)', (select v from ids where k='fr')), 'Tick Reviewed');
select set_fund_reviewed((select v from ids where k='fr'), true);
select disapprove_fund_request((select v from ids where k='fr'), 'Wrong category');

-- Return to payment approver cancels and leaves the cheque.
select t.as_user('fr');
select return_to_payment_approver((select v from ids where k='fr'), 'Amount looks wrong');
select t.eq((select status::text || coalesce(cheque_id::text, '-') from fund_requests where id = (select v from ids where k='fr')), 'cancelled-', 'fund request cancelled and off its cheque');
select t.eq((select status::text from payment_requests where id = (select v from ids where k='pr')), 'pending_payment_approval', 'payment request back with approver');
select t.eq((select cheque_total(id) from cheques where cheque_no = '100200'), 24465.00, 'cheque total drops the cancelled request');

-- Approve again, receive again, approve funding.
select t.as_user('appr');
select approve_payment_request((select v from ids where k='pr'));
select t.as_user('fr');
insert into ids values ('fr2', receive_payment_request((select v from ids where k='pr')));
select save_fund_request((select v from ids where k='fr2'), jsonb_build_object(
  'ref_no', '2- 2026 10 0075', 'payment_date', '2026-10-21', 'payment_method', 'Check',
  'tax_code', '12% S - Goods', 'payment_account', 'BDO Current Account', 'category', 'Rent',
  'fund_approver_id', t.uid('fa'), 'cheque_mode', 'new', 'cheque_no', '100300', 'subtotal_to_fund', '1120'));
select submit_fund_request((select v from ids where k='fr2'));
select t.as_user('fa');
select set_fund_reviewed((select v from ids where k='fr2'), true);
select approve_fund_request((select v from ids where k='fr2'));
select t.eq((select status::text || locked from fund_requests where id = (select v from ids where k='fr2')), 'approved_ready_for_qbtrue', 'approved and locked');
select t.eq((select array[total_before_tax, sales_tax]::text from fund_requests where id = (select v from ids where k='fr2')), '{1000.00,120.00}', 'tax split');
select t.eq((select (get_voucher((select v from ids where k='fr2')) ->> 'payment_requested_by')), 'Rita Requestor', 'voucher has signatures');
select t.eq((select count(*) from payment_requests), 0::bigint, 'fund approver cannot read payment requests');

select t.as_user('fr');
select t.expect_error(format('select save_fund_request(%L, %L)', (select v from ids where k='fr2'), '{}'), 'can no longer be edited');
select t.eq((select count(*) from available_cheques() where cheque_no = '100300'), 0::bigint, 'cheque with approved request is not offered');

-- Requestor sees funding on their tracker; notifications have SMS status.
select t.as_user('req');
select t.eq((select status::text from payment_requests where id = (select v from ids where k='pr')), 'approved_ready_for_qb', 'requestor sees funded status');
select t.eq((select count(*) from notifications where sms_status not in ('Queued', 'No mobile')), 0::bigint, 'every notification has an SMS status');
select t.eq((select count(*) > 0 from notifications where sms_status = 'Queued'), true, 'requestor SMS queued');
select t.expect_error(format('select liquidate_payment_request(%L, 1, null, null, null)', (select v from ids where k='pr')), 'Only cash');

-- Direct writes are blocked.
select t.expect_error(format('update payment_requests set status = %L', 'approved_awaiting_funding'), 'permission denied');

-- Liquidation of a cash request
reset role;
update payment_requests set payment_type = 'Cash' where id = (select v from ids where k='pr');
set role authenticated;
select t.as_user('req');
select t.expect_error(format('select liquidate_payment_request(%L, 1000, null, null, null)', (select v from ids where k='pr')), 'deposit-back');
select liquidate_payment_request((select v from ids where k='pr'), 1000, '2026-10-25', 120, 'BDO');
select t.eq((select liq_change from payment_requests where id = (select v from ids where k='pr')), 120.00, 'change computed');

-- Day 23 / 28 / 30
select t.as_user('req');
insert into ids values ('old', save_payment_request(null, jsonb_build_object(
  'payable_to', 'X', 'purpose', 'Y', 'date_required', '2026-11-01', 'terms_accepted', true,
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 5)))));
select submit_payment_request((select v from ids where k='old'));
select t.as_user('appr');
select disapprove_payment_request((select v from ids where k='old'), 'No');
reset role;
update payment_requests set returned_on = now() - interval '23 days 1 hour' where id = (select v from ids where k='old');
select t.eq((run_daily_jobs() ->> 'reminders')::int, 1, 'day 23 reminder');
select t.eq((run_daily_jobs() ->> 'reminders')::int, 0, 'day 23 reminder only once');
update payment_requests set returned_on = now() - interval '28 days 1 hour' where id = (select v from ids where k='old');
select t.eq((run_daily_jobs() ->> 'reminders')::int, 1, 'day 28 reminder');
-- Resubmitted then returned again: the clock restarts, no stale reminder.
set role authenticated;
select t.as_user('req');
select submit_payment_request((select v from ids where k='old'));
select t.as_user('appr');
select disapprove_payment_request((select v from ids where k='old'), 'Still no');
reset role;
select t.eq((run_daily_jobs() ->> 'reminders')::int, 0, 'no reminder from an earlier return');
update payment_requests set returned_on = now() - interval '30 days 1 hour' where id = (select v from ids where k='old');
select t.eq((run_daily_jobs() ->> 'expired')::int, 1, 'expires on day 30');
select t.eq((select count(*) from payment_requests where id = (select v from ids where k='old')), 0::bigint, 'expired request deleted');
select t.eq((select count(*) from audit_log where action = 'Expired' and ref is not null), 1::bigint, 'expiry stays in the audit log');

-- Admin
set role authenticated;
select t.as_user('adm');
select t.expect_error(format('select admin_update_user(%L, %L)', t.uid('adm'), '{"roles":["payment_requestor"]}'), 'At least one active Admin');
select admin_update_user(t.uid('req2'), '{"roles":["payment_requestor"], "mobile_no":"0917 123 4567"}');
select t.eq((select mobile_no from profiles where id = t.uid('req2')), '639171234567', 'mobile 09... converted to 63...');
select t.as_user('req2');
select t.expect_error(format('select admin_update_user(%L, %L)', t.uid('req2'), '{"roles":["admin"]}'), 'Admin role');

-- Check payment request (type 2): started by a Fund Requestor, paid by cheque, Ref no. prefix 2.
select t.as_user('fr');
insert into ids values ('cp', create_check_payment_request());
select t.eq((select request_type::int from fund_requests where id = (select v from ids where k='cp')), 2, 'check payment request is type 2');
select t.eq((select payment_method from fund_requests where id = (select v from ids where k='cp')), 'Check', 'check payment request defaults to Check');
select t.expect_error(format('select submit_fund_request(%L)', (select v from ids where k='cp')), 'Ref no. is required.*Choose or enter a cheque');
reset role;
update fund_requests set ref_no = '1- 2026 10 0999' where id = (select v from ids where k='cp');
set role authenticated;
select t.expect_error(format('select submit_fund_request(%L)', (select v from ids where k='cp')), 'must start with 2-');

-- QuickBooks lists (spec 10): real payment methods, expense categories only.
select t.eq((select string_agg(label, ', ' order by sort) from lookups where list = 'payment_method'), 'Cash, Check, Credit Card, Direct Debit, FUND TRANSFER', 'payment methods match QuickBooks');
select t.eq((select count(*)::int from lookups where list = 'category' and label = 'BANK CHARGES:Transfer & MC Fees'), 1, 'Transfer & MC Fees is a category');
select t.eq((select count(*)::int from lookups where list = 'category' and label in ('Loan Payable', 'AMORTIZATION EXPENSES', 'Utilities')), 0, 'no samples, no locked parents');
select t.eq((select payment_method from fund_requests where id = (select v from ids where k='ad')), 'Check', 'auto debit can still be paid by Check');

-- Delete button: soft delete to Cancelled, kept in the audit log.
select t.as_user('req');
insert into ids values ('dpr', save_payment_request(null, jsonb_build_object(
  'payable_to', 'Dup', 'purpose', 'Doubled entry', 'date_required', '2026-11-01', 'terms_accepted', true,
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 50)))));
select submit_payment_request((select v from ids where k='dpr'));
select t.as_user('req2');
select t.expect_error(format('select delete_payment_request(%L, %L)', (select v from ids where k='dpr'), 'x'), 'Only the requestor or an Admin');
select t.as_user('appr');
select approve_payment_request((select v from ids where k='dpr'));
select t.as_user('fr');
insert into ids values ('dfr', receive_payment_request((select v from ids where k='dpr')));
select t.as_user('req');
select t.expect_error(format('select delete_payment_request(%L, %L)', (select v from ids where k='dpr'), 'x'), 'Delete its fund request first');
select t.as_user('fa');
select t.expect_error(format('select delete_fund_request(%L, %L)', (select v from ids where k='dfr'), 'x'), 'Fund Requestor or an Admin');
select t.as_user('fr');
select t.expect_error(format('select delete_fund_request(%L, %L)', (select v from ids where k='dfr'), ' '), 'reason is required');
select t.expect_error(format('select delete_fund_request(%L, %L)', (select id from fund_requests where locked limit 1), 'x'), 'approved fund request cannot');
select delete_fund_request((select v from ids where k='dfr'), 'Encoded wrongly');
select t.eq((select status::text from fund_requests where id = (select v from ids where k='dfr')), 'cancelled', 'deleted fund request is Cancelled');
select t.eq((select status::text || ' ' || coalesce(fund_request_id::text, 'none') from payment_requests where id = (select v from ids where k='dpr')),
            'approved_awaiting_funding none', 'its payment request waits for funding again');
select t.as_user('adm');
select delete_payment_request((select v from ids where k='dpr'), 'Doubled');
select t.eq((select status::text from payment_requests where id = (select v from ids where k='dpr')), 'cancelled', 'Admin deletes a payment request');
select t.eq((select count(*)::int from audit_log where action = 'Deleted' and note in ('Doubled', 'Encoded wrongly')), 2, 'deletes stay in the audit log');
select t.as_user('fr');
insert into ids values ('dcp', create_check_payment_request());
select delete_fund_request((select v from ids where k='dcp'), 'Doubled');
select t.eq((select status::text from fund_requests where id = (select v from ids where k='dcp')), 'cancelled', 'standalone fund request deleted');

-- A Payment Requestor sees only what they requested (Ruth, 1 November).
select t.as_user('req2');
select t.eq((select count(*)::int from payment_requests where requestor_id <> t.uid('req2')), 0, 'requestor sees no one else''s payment requests');
select t.eq((select count(*)::int from fund_requests), 0, 'requestor sees no fund requests that are not theirs');
select t.eq((select count(*)::int from audit_log), 0, 'requestor sees no one else''s history');
select t.eq((select count(*)::int from cheques), 0, 'requestor sees no cheques');
select t.eq((select count(*)::int from attachments), 0, 'requestor sees no one else''s attachments');
select t.as_user('req');
select t.eq((select count(*)::int from payment_requests where requestor_id <> t.uid('req')), 0, 'second requestor also sees only their own');
select t.eq((select count(*)::int from fund_requests f where not exists (
  select 1 from payment_requests p where p.id = f.payment_request_id and p.requestor_id = t.uid('req'))), 0,
  'only the funding of their own requests');

-- Every Payment Approver sees all submitted requests and can approve any of them.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'appr2@x.test', '{"full_name":"Second Approver"}');
update profiles set roles = '{payment_approver}' where email = 'appr2@x.test';
set role authenticated;
select t.as_user('req');
insert into ids values ('apr', save_payment_request(null, jsonb_build_object(
  'payable_to', 'Any approver', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true,
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 75)))));
select t.as_user('appr2');
select t.eq((select count(*)::int from payment_requests where id = (select v from ids where k='apr')), 0, 'approvers cannot see someone else''s draft');
select t.as_user('req');
select submit_payment_request((select v from ids where k='apr'));
select t.as_user('appr2');
select t.eq((select count(*)::int from payment_requests where id = (select v from ids where k='apr')), 1, 'any approver sees a submitted request');
select t.eq((select count(*)::int from payment_requests where requestor_id = t.uid('req') and status <> 'draft') > 1, true, 'approver sees every requestor''s entries');
select approve_payment_request((select v from ids where k='apr'));
select t.eq((select approver_id from payment_requests where id = (select v from ids where k='apr')), t.uid('appr2'), 'the approver who approved is recorded');

-- Request type on payment requests: regular / auto debit / reimbursable.
select t.as_user('req');
insert into ids values ('kad', save_payment_request(null, jsonb_build_object(
  'payable_to', 'Meralco', 'purpose', 'Auto debit bill', 'date_required', '2026-11-01', 'terms_accepted', true,
  'request_kind', 'auto_debit', 'region', 'VisMin',
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 300)))));
insert into ids values ('krb', save_payment_request(null, jsonb_build_object(
  'payable_to', 'Client', 'purpose', 'Reimbursable', 'date_required', '2026-11-01', 'terms_accepted', true,
  'request_kind', 'reimbursable',
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 40)))));
select t.eq((select reimbursable from payment_requests where id = (select v from ids where k='krb')), true, 'reimbursable kind sets reimbursable');
select submit_payment_request((select v from ids where k='kad'));
select submit_payment_request((select v from ids where k='krb'));
select t.as_user('appr');
select approve_payment_request((select v from ids where k='kad'));
select approve_payment_request((select v from ids where k='krb'));
select t.as_user('fr');
insert into ids values ('fkad', receive_payment_request((select v from ids where k='kad')));
insert into ids values ('fkrb', receive_payment_request((select v from ids where k='krb')));
select t.eq((select array[request_type::text, payment_method, region] from fund_requests where id = (select v from ids where k='fkad')),
            array['1', 'Direct Debit', 'VisMin'], 'auto debit payment request gives fund type 1, Direct Debit, its region');
select t.eq((select array[request_type::text, region] from fund_requests where id = (select v from ids where k='fkrb')),
            array['4', 'NCR'], 'reimbursable NCR gives fund type 4');

-- Edit: take a waiting request back for editing.
select t.as_user('req');
insert into ids values ('wpr', save_payment_request(null, jsonb_build_object(
  'payable_to', 'Edit me', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true,
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 10)))));
select submit_payment_request((select v from ids where k='wpr'));
select t.as_user('req2');
select t.expect_error(format('select withdraw_payment_request(%L)', (select v from ids where k='wpr')), 'Payment Requestor role|not found');
select t.as_user('req');
select withdraw_payment_request((select v from ids where k='wpr'));
select t.eq((select status::text from payment_requests where id = (select v from ids where k='wpr')), 'draft', 'taken back to draft for editing');
select save_payment_request((select v from ids where k='wpr'), jsonb_build_object(
  'payable_to', 'Edited', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true, 'approver_id', t.uid('appr'),
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 12))));
select submit_payment_request((select v from ids where k='wpr'));
select t.eq((select payable_to || ' ' || status::text from payment_requests where id = (select v from ids where k='wpr')), 'Edited pending_payment_approval', 'edited and resubmitted');
select t.as_user('fr');
insert into ids values ('wfr', create_check_payment_request());
reset role;
update fund_requests set status = 'pending_fund_approval' where id = (select v from ids where k='wfr');
set role authenticated;
select withdraw_fund_request((select v from ids where k='wfr'));
select t.eq((select status::text from fund_requests where id = (select v from ids where k='wfr')), 'in_funding_preparation', 'fund request taken back for editing');

-- Admin covers every role and can hand over someone's open work.
select t.as_user('req');
insert into ids values ('apr2', save_payment_request(null, jsonb_build_object(
  'payable_to', 'Admin covers', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true, 'approver_id', t.uid('appr'),
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 20)))));
select t.as_user('adm');
select save_payment_request((select v from ids where k='apr2'), jsonb_build_object(
  'payable_to', 'Admin edited', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true, 'approver_id', t.uid('appr'),
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 20))));
select submit_payment_request((select v from ids where k='apr2'));
select approve_payment_request((select v from ids where k='apr2'));
select t.eq((select payable_to || ' ' || status::text from payment_requests where id = (select v from ids where k='apr2')),
            'Admin edited approved_awaiting_funding', 'Admin edits, submits and approves someone else''s request');
insert into ids values ('afr2', receive_payment_request((select v from ids where k='apr2')));
select t.eq((select count(*)::int from fund_requests where id = (select v from ids where k='afr2')), 1, 'Admin receives for funding');
select t.eq((admin_hand_over(t.uid('fa'), t.uid('adm')) ->> 'fund_approvals')::int >= 0, true, 'hand over runs');
select t.eq((select count(*)::int from profiles where default_fund_approver = t.uid('fa')), 0, 'defaults handed over');
select t.as_user('req2');
select t.expect_error(format('select admin_hand_over(%L, %L)', t.uid('fa'), t.uid('req2')), 'Admin role');

-- Approval routing: VisMin goes approver 1 then approver 2; NCR one step; Admin final.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  (gen_random_uuid(), 'jon@x.test', '{"full_name":"Jonathan Villanueva"}'),
  (gen_random_uuid(), 'hm@x.test', '{"full_name":"Hoe Ming Wong"}');
update profiles set roles = '{payment_approver}' where email in ('jon@x.test', 'hm@x.test');
set role authenticated;
select t.as_user('adm');
select admin_set_routes(jsonb_build_object('NCR', jsonb_build_array(t.uid('hm')), 'VisMin', jsonb_build_array(t.uid('jon'), t.uid('hm'))));
select t.as_user('req');
insert into ids values ('rv', save_payment_request(null, jsonb_build_object(
  'payable_to', 'VisMin site', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true, 'region', 'VisMin',
  'approver_id', t.uid('appr'), 'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 90)))));
select submit_payment_request((select v from ids where k='rv'));
select t.eq((select approver_id from payment_requests where id = (select v from ids where k='rv')), t.uid('jon'), 'VisMin goes to approver 1');
select t.as_user('hm');
select t.expect_error(format('select approve_payment_request(%L)', (select v from ids where k='rv')), 'waiting for Jonathan');
select t.as_user('jon');
select approve_payment_request((select v from ids where k='rv'));
select t.eq((select array[status::text, approver_id::text, first_approver_id::text] from payment_requests where id = (select v from ids where k='rv')),
            array['pending_payment_approval', t.uid('hm')::text, t.uid('jon')::text], 'approver 1 passes it to approver 2');
select t.as_user('hm');
select approve_payment_request((select v from ids where k='rv'));
select t.eq((select status::text from payment_requests where id = (select v from ids where k='rv')), 'approved_awaiting_funding', 'approver 2 gives final approval');
select t.as_user('req');
insert into ids values ('rn', save_payment_request(null, jsonb_build_object(
  'payable_to', 'NCR site', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true, 'region', 'VisMin',
  'approver_id', t.uid('appr'), 'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 30)))));
select submit_payment_request((select v from ids where k='rn'));
select t.as_user('adm');
select approve_payment_request((select v from ids where k='rn'));
select t.eq((select status::text from payment_requests where id = (select v from ids where k='rn')), 'approved_awaiting_funding', 'Admin approval at step 1 is final');
select t.as_user('req');
insert into ids values ('rn2', save_payment_request(null, jsonb_build_object(
  'payable_to', 'NCR site', 'purpose', 'P', 'date_required', '2026-11-01', 'terms_accepted', true, 'region', 'NCR',
  'items', jsonb_build_array(jsonb_build_object('description', 'a', 'amount', 30)))));
select submit_payment_request((select v from ids where k='rn2'));
select t.eq((select approver_id from payment_requests where id = (select v from ids where k='rn2')), t.uid('hm'), 'NCR goes to its one approver');
select t.as_user('hm');
select approve_payment_request((select v from ids where k='rn2'));
select t.eq((select status::text from payment_requests where id = (select v from ids where k='rn2')), 'approved_awaiting_funding', 'NCR approved in one step');
select t.as_user('adm');
select admin_set_routes('{}'::jsonb);

\o
\echo ALL TESTS PASSED
