-- Payment request "Request type" replaces "Reimbursable?" (Ruth, 1 November):
--   regular       Regular fund request (check payment & cash)  -> fund type 2 NCR / 3 VisMin
--   auto_debit    Auto debit (direct debit & MC)               -> fund type 1
--   reimbursable  Reimbursable fund request                    -> fund type 4 NCR / 5 VisMin
-- reimbursable stays as a column, kept in step by a trigger. Fund requests
-- now carry the region of their payment request, so auto debits group by region.
-- Safe to run more than once.

alter table payment_requests add column if not exists request_kind text not null default 'regular';
alter table payment_requests drop constraint if exists payment_requests_request_kind_check;
alter table payment_requests add constraint payment_requests_request_kind_check
  check (request_kind in ('regular', 'auto_debit', 'reimbursable'));
update payment_requests set request_kind = 'reimbursable' where reimbursable and request_kind = 'regular';

create or replace function sync_reimbursable() returns trigger
language plpgsql as $$
begin
  new.reimbursable := new.request_kind = 'reimbursable';
  return new;
end $$;
drop trigger if exists payment_requests_kind on payment_requests;
create trigger payment_requests_kind before insert or update on payment_requests
for each row execute function sync_reimbursable();

alter table fund_requests add column if not exists region text check (region in ('NCR', 'VisMin'));
update fund_requests f set region = p.region
  from payment_requests p where p.id = f.payment_request_id and f.region is null;

create or replace function save_payment_request(p_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('payment_requestor');
  r payment_requests;
  v_items jsonb;
  v_approver uuid;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'description', coalesce(btrim(e ->> 'description'), ''),
           'amount', round(nullif(btrim(replace(e ->> 'amount', ',', '')), '')::numeric, 2)
         ) order by i), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(p -> 'items', '[]'::jsonb)) with ordinality as t(e, i)
   where coalesce(btrim(e ->> 'description'), '') <> ''
      or nullif(btrim(e ->> 'amount'), '') is not null;

  v_approver := txt(p, 'approver_id')::uuid;

  if p_id is null then
    if v_approver is null then
      select default_payment_approver into v_approver from profiles where id = uid;
    end if;
    insert into payment_requests (req_no, requestor_id, approver_id)
    values (next_req_no(), uid, v_approver)
    returning * into r;
    perform log_event(r.id, null, 'Created', null, 'draft');
  else
    select * into r from payment_requests where id = p_id for update;
    if not found or r.requestor_id <> uid then
      raise exception 'Payment request not found.';
    end if;
    if r.status not in ('draft', 'returned_to_requestor') then
      raise exception 'Only a draft or returned request can be edited.';
    end if;
    -- The approver is locked once the request has been returned.
    if r.status = 'draft' then
      update payment_requests set approver_id = v_approver where id = r.id;
    end if;
  end if;

  update payment_requests set
    request_kind      = coalesce(txt(p, 'request_kind'),
                                 case when (p ->> 'reimbursable')::boolean then 'reimbursable' else 'regular' end),
    region            = coalesce(txt(p, 'region'), 'NCR'),
    project_name      = txt(p, 'project_name'),
    project_type      = txt(p, 'project_type'),
    job_order_no      = txt(p, 'job_order_no'),
    addendum_no       = txt(p, 'addendum_no'),
    work_order_no     = txt(p, 'work_order_no'),
    date_required     = txt(p, 'date_required')::date,
    payable_to        = txt(p, 'payable_to'),
    payment_type      = coalesce(txt(p, 'payment_type'), 'Cheque'),
    billing_type      = coalesce(txt(p, 'billing_type'), 'VAT'),
    currency          = coalesce(txt(p, 'currency'), 'PHP'),
    purpose           = txt(p, 'purpose'),
    items             = v_items,
    po_num            = txt(p, 'po_num'),
    po_date           = txt(p, 'po_date')::date,
    po_amount         = num(p, 'po_amount'),
    po_mode           = txt(p, 'po_mode'),
    last_payment_ref  = txt(p, 'last_payment_ref'),
    wtax_rate         = coalesce(num(p, 'wtax_rate'), 0),
    bank_transfer_fee = num(p, 'bank_transfer_fee'),
    terms_accepted    = coalesce((p ->> 'terms_accepted')::boolean, false)
  where id = r.id;

  return r.id;
end $$;

create or replace function receive_payment_request(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_requestor');
  r payment_requests;
  v_fr uuid;
  v_type smallint;
  v_approver uuid;
  v_desc text;
begin
  select * into r from payment_requests where id = p_id for update;
  if not found then raise exception 'Payment request not found.'; end if;
  if r.status <> 'approved_awaiting_funding' then raise exception 'This request is not waiting for funding.'; end if;

  v_type := case
    when r.request_kind = 'auto_debit' then 1
    when r.region = 'NCR' and not r.reimbursable then 2
    when r.region = 'VisMin' and not r.reimbursable then 3
    when r.region = 'NCR' and r.reimbursable then 4
    else 5 end;

  select default_fund_approver into v_approver from profiles where id = uid;
  if v_approver = uid then v_approver := null; end if;

  select r.purpose || coalesce(E'\n' || string_agg(format('%s. %s', i, e ->> 'description'), E'\n' order by i), '')
    into v_desc
    from jsonb_array_elements(r.items) with ordinality as t(e, i);

  insert into fund_requests (
    request_type, region, payment_request_id, fund_requestor_id, fund_approver_id, status,
    payee, item_no, description, currency, original_amount,
    payment_method, tax_code, tax_rate, tax_locked, wtax_note
  ) values (
    v_type, r.region, r.id, uid, v_approver, 'in_funding_preparation',
    r.payable_to, r.item_no, v_desc, r.currency, r.total_vat_in,
    case when r.request_kind = 'auto_debit' then 'Direct Debit'
         else case r.payment_type when 'Cash' then 'Cash' when 'Cheque' then 'Check' else 'FUND TRANSFER' end end,
    case when r.billing_type <> 'VAT' then 'No VAT (0%)' end,
    case when r.billing_type <> 'VAT' then 0 end,
    r.billing_type <> 'VAT',
    case when r.wtax_rate > 0 then
      format('Less W-tax %s%%: %s %s. Total amount due: %s %s.',
             (r.wtax_rate * 100)::int, r.currency, money_txt(r.wtax_amount), r.currency, money_txt(r.total_due))
    end
  ) returning id into v_fr;

  insert into attachments (fund_request_id, storage_path, file_name, uploaded_by)
  select v_fr, storage_path, file_name, uploaded_by from attachments where payment_request_id = r.id;

  perform log_event(r.id, v_fr, 'Received for funding', r.status, 'in_funding_preparation');
  return v_fr;
end $$;
