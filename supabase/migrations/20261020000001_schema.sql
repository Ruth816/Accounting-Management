-- Finance Approval Portal: tables, helpers and row-level security.
-- Clients only ever SELECT through RLS. Every write goes through the
-- SECURITY DEFINER functions in the workflow migration, so the rules in the
-- spec (who may act, in which status) live in the database, not the UI.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type app_role as enum (
  'payment_requestor',
  'payment_approver',
  'fund_requestor',
  'fund_approver',
  'admin'
);

create type request_status as enum (
  'draft',
  'pending_payment_approval',
  'returned_to_requestor',
  'expired',
  'cancelled',
  'approved_awaiting_funding',
  'in_funding_preparation',
  'pending_fund_approval',
  'returned_to_fund_requestor',
  'approved_ready_for_qb',
  'approved_posted_to_qb',
  'sync_failed'
);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  roles app_role[] not null default '{}', -- an Admin assigns roles
  mobile_no text check (mobile_no ~ '^63[0-9]{10}$'),
  default_payment_approver uuid references profiles (id) on delete set null,
  default_fund_approver uuid references profiles (id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Every new sign-in account gets a profile.
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name)
  values (new.id, coalesce(new.email, ''),
          coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, ''), '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function handle_new_user();

create function has_role(r app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles where id = auth.uid() and active and r = any (roles)
  );
$$;

create function user_has_role(uid uuid, r app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = uid and active and r = any (roles));
$$;

-- Names and roles of everyone, for approver pickers and signatures.
-- Mobile numbers and defaults stay private to the user and Admins.
create view directory as
  select id, full_name, email, roles, active from profiles;

-- ---------------------------------------------------------------------------
-- Dropdown lists (Phase 1 option sets, replaced by QuickBooks in Phase 2)
-- ---------------------------------------------------------------------------

create table lookups (
  id uuid primary key default gen_random_uuid(),
  list text not null check (list in ('payment_method', 'payment_account', 'category', 'tax_code')),
  label text not null,
  rate numeric(6, 4),
  sort int not null default 0,
  active boolean not null default true,
  unique (list, label)
);

-- ---------------------------------------------------------------------------
-- Payment requests
-- ---------------------------------------------------------------------------

create table req_counters (
  yyyymm text primary key,
  last_no int not null default 0
);

create table payment_requests (
  id uuid primary key default gen_random_uuid(),
  req_no text unique not null,
  requestor_id uuid not null references profiles (id),
  approver_id uuid references profiles (id),
  status request_status not null default 'draft',
  version int not null default 1,

  reimbursable boolean not null default false,
  region text not null default 'NCR' check (region in ('NCR', 'VisMin')),
  project_name text,
  project_type text,
  job_order_no text,
  addendum_no text,
  work_order_no text,
  date_required date,
  payable_to text,
  payment_type text not null default 'Cheque' check (payment_type in ('Cash', 'Cheque', 'Bank deposit')),
  billing_type text not null default 'VAT' check (billing_type in ('VAT', 'Non-VAT', 'Ack/R', 'Pakyaw')),
  currency text not null default 'PHP' check (currency in ('PHP', 'USD')),

  purpose text,
  items jsonb not null default '[]'::jsonb, -- [{ "description": text, "amount": number }]
  item_no text,

  po_num text,
  po_date date,
  po_amount numeric(14, 2),
  po_mode text check (po_mode in ('D/P', 'PB', 'FB')),
  last_payment_ref text,

  wtax_rate numeric(4, 2) not null default 0 check (wtax_rate in (0, 0.01, 0.02, 0.05)),
  bank_transfer_fee numeric(14, 2),
  total_vat_in numeric(14, 2) not null default 0,
  total_vat_ex numeric(14, 2) not null default 0,
  wtax_amount numeric(14, 2) not null default 0,
  total_due numeric(14, 2) not null default 0,

  terms_accepted boolean not null default false,

  disapproval_reason text,
  return_note text, -- reason given when a Fund Requestor sends it back
  returned_on timestamptz,
  expires_on timestamptz,
  reminder_23_sent boolean not null default false,
  reminder_28_sent boolean not null default false,
  submitted_on timestamptz,
  approved_on timestamptz,
  fund_request_id uuid,

  liq_actual_used numeric(14, 2),
  liq_change numeric(14, 2),
  liq_deposit_date date,
  liq_deposit_amount numeric(14, 2),
  liq_deposit_bank text,
  liquidated_on timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index on payment_requests (requestor_id);
create index on payment_requests (approver_id);
create index on payment_requests (status);

create table payment_request_versions (
  id uuid primary key default gen_random_uuid(),
  payment_request_id uuid not null references payment_requests (id) on delete cascade,
  version int not null,
  snapshot jsonb not null,
  reason text not null,
  returned_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Fund requests and cheques
-- ---------------------------------------------------------------------------

create table cheques (
  id uuid primary key default gen_random_uuid(),
  cheque_no text not null unique,
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table fund_requests (
  id uuid primary key default gen_random_uuid(),
  request_type smallint not null check (request_type between 1 and 5),
  payment_request_id uuid references payment_requests (id) on delete set null,
  fund_requestor_id uuid not null references profiles (id),
  fund_approver_id uuid references profiles (id),
  status request_status not null default 'in_funding_preparation',

  ref_no text,
  payee text,
  item_no text,
  description text,
  currency text not null default 'PHP' check (currency in ('PHP', 'USD')),
  original_amount numeric(14, 2),
  exchange_rate numeric(12, 4),
  rate_date date,
  payment_date date,
  payment_method text check (payment_method in ('Check', 'Auto debit', 'Bank transfer', 'Cash')),
  cash_received_by text,
  bank_account_name text,
  bank_account_no text,
  amount_php numeric(14, 2),
  tax_code text,
  tax_rate numeric(6, 4),
  total_before_tax numeric(14, 2),
  sales_tax numeric(14, 2),
  payment_account text,
  category text,
  memo text,
  memo_edited boolean not null default false,
  wtax_note text,
  tax_locked boolean not null default false, -- true when the payment request is not VAT

  cheque_id uuid references cheques (id),
  subtotal_to_fund numeric(14, 2),

  reviewed boolean not null default false,
  disapproval_reason text,
  submitted_on timestamptz,
  approved_by uuid references profiles (id),
  approved_on timestamptz,
  locked boolean not null default false,
  qb_txn_id text,
  qb_sync_error text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A Ref no. can be reused only by a cancelled fund request.
create unique index fund_requests_ref_no_key on fund_requests (ref_no)
  where ref_no is not null and status <> 'cancelled';
create index on fund_requests (fund_approver_id);
create index on fund_requests (payment_request_id);
create index on fund_requests (cheque_id);
create index on fund_requests (status);

alter table payment_requests
  add constraint payment_requests_fund_request_fk
  foreign key (fund_request_id) references fund_requests (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Attachments, audit log, notifications
-- ---------------------------------------------------------------------------

create table attachments (
  id uuid primary key default gen_random_uuid(),
  payment_request_id uuid references payment_requests (id) on delete cascade,
  fund_request_id uuid references fund_requests (id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  uploaded_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  check (payment_request_id is not null or fund_request_id is not null)
);

create table audit_log (
  id bigint generated always as identity primary key,
  payment_request_id uuid references payment_requests (id) on delete set null,
  fund_request_id uuid references fund_requests (id) on delete set null,
  ref text, -- Payment REQ No. or Ref no. at the time, kept after deletion
  action text not null,
  actor_id uuid references profiles (id),
  old_status request_status,
  new_status request_status,
  note text,
  created_at timestamptz not null default now()
);
create index on audit_log (payment_request_id);
create index on audit_log (fund_request_id);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references profiles (id) on delete cascade,
  message text not null,
  payment_request_id uuid references payment_requests (id) on delete set null,
  fund_request_id uuid references fund_requests (id) on delete set null,
  read boolean not null default false,
  sms_status text not null default 'Queued' check (sms_status in ('Queued', 'Sending', 'Sent', 'Failed', 'No mobile')),
  sms_mobile_no text,
  sms_message_id text,
  sms_error text,
  sms_attempted_on timestamptz,
  created_at timestamptz not null default now()
);
create index on notifications (recipient_id, read);
create index on notifications (sms_status) where sms_status = 'Queued';

-- ---------------------------------------------------------------------------
-- Visibility helpers (SECURITY DEFINER so policies don't recurse)
-- ---------------------------------------------------------------------------

create function can_see_pr(pr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from payment_requests p
    where p.id = pr_id
      and (p.requestor_id = auth.uid()
           or p.approver_id = auth.uid()
           or has_role('fund_requestor')
           or has_role('admin'))
  );
$$;

create function can_see_fr(fr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fund_requests f
    left join payment_requests p on p.id = f.payment_request_id
    where f.id = fr_id
      and (has_role('fund_requestor')
           or has_role('admin')
           or f.fund_approver_id = auth.uid()
           or p.requestor_id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Row-level security: read-only for clients
-- ---------------------------------------------------------------------------

alter table profiles enable row level security;
alter table lookups enable row level security;
alter table req_counters enable row level security;
alter table payment_requests enable row level security;
alter table payment_request_versions enable row level security;
alter table cheques enable row level security;
alter table fund_requests enable row level security;
alter table attachments enable row level security;
alter table audit_log enable row level security;
alter table notifications enable row level security;

create policy "own profile or admin" on profiles for select to authenticated
  using (id = auth.uid() or has_role('admin'));

create policy "everyone reads lists" on lookups for select to authenticated using (true);
create policy "admins manage lists" on lookups for all to authenticated
  using (has_role('admin')) with check (has_role('admin'));

create policy "visible payment requests" on payment_requests for select to authenticated
  using (requestor_id = auth.uid()
         or approver_id = auth.uid()
         or has_role('fund_requestor')
         or has_role('admin'));

create policy "versions follow request" on payment_request_versions for select to authenticated
  using (can_see_pr(payment_request_id));

create policy "visible fund requests" on fund_requests for select to authenticated
  using (has_role('fund_requestor')
         or has_role('admin')
         or fund_approver_id = auth.uid()
         or exists (select 1 from payment_requests p
                    where p.id = payment_request_id and p.requestor_id = auth.uid()));

create policy "cheques of visible fund requests" on cheques for select to authenticated
  using (has_role('fund_requestor') or has_role('admin')
         or exists (select 1 from fund_requests f where f.cheque_id = cheques.id));

create policy "attachments follow request" on attachments for select to authenticated
  using ((payment_request_id is not null and can_see_pr(payment_request_id))
         or (fund_request_id is not null and can_see_fr(fund_request_id)));

create policy "audit follows request" on audit_log for select to authenticated
  using (has_role('admin')
         or (payment_request_id is not null and can_see_pr(payment_request_id))
         or (fund_request_id is not null and can_see_fr(fund_request_id)));

create policy "own notifications" on notifications for select to authenticated
  using (recipient_id = auth.uid() or has_role('admin'));

-- Grant reads explicitly rather than relying on the project's default privileges.
grant usage on schema public to authenticated, service_role;
grant select on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;

-- The directory view runs as its owner, so it can list names without
-- exposing the rest of each profile.
revoke all on directory from anon;
grant select on directory to authenticated;
revoke all on req_counters from anon, authenticated;

-- Nothing is writable directly except the Admin's dropdown lists.
revoke insert, update, delete on all tables in schema public from anon, authenticated;
grant insert, update, delete on lookups to authenticated;
