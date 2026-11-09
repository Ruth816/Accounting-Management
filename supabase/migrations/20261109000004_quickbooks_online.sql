-- QuickBooks Online connection (spec section 8, Phases 2 and 3; Ruth, 9 November).
--   Phase 2: an Admin connects the company once; the dropdown lists then sync
--            from QuickBooks daily and on demand.
--   Phase 3: "Export to QuickBooks" creates the Expense in QuickBooks, stores
--            its ID and locks the request. On an error the request goes to
--            Sync Failed and can be exported again without a duplicate.
-- Safe to run again.

-- One row: the connected company. Tokens are encrypted by the app
-- (QBO_TOKEN_KEY). Only the server (service role) can read or change it.
create table if not exists qb_connection (
  id boolean primary key default true check (id),
  environment text not null check (environment in ('sandbox', 'production')),
  realm_id text not null,
  company_name text,
  access_token text not null,
  refresh_token text not null,
  access_expires_at timestamptz not null,
  refresh_expires_at timestamptz,
  connected_by uuid references profiles (id) on delete set null,
  connected_at timestamptz not null default now(),
  last_sync_at timestamptz,
  last_sync_error text
);
alter table qb_connection enable row level security;
revoke all on qb_connection from anon, authenticated;

-- The QuickBooks ID of each dropdown value, filled by the sync.
alter table lookups add column if not exists qb_id text;

-- Replace the synced lists with what QuickBooks returned. Values QuickBooks no
-- longer has are hidden (not deleted: older requests still show them).
-- p_lists: {"category": [{"label", "qb_id", "qb_type", "rate"}], ...}
create or replace function qb_apply_lists(p_lists jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_list text;
  v_rows jsonb;
  v_counts jsonb := '{}';
begin
  for v_list, v_rows in select key, value from jsonb_each(coalesce(p_lists, '{}')) loop
    if v_list not in ('payment_method', 'payment_account', 'category', 'tax_code') then continue; end if;
    -- An empty answer from QuickBooks never empties a list.
    if jsonb_array_length(v_rows) = 0 then continue; end if;

    insert into lookups (list, label, qb_id, qb_type, rate, sort, active)
    select v_list, e ->> 'label', e ->> 'qb_id', e ->> 'qb_type', (e ->> 'rate')::numeric, i, true
      from jsonb_array_elements(v_rows) with ordinality as t(e, i)
    on conflict (list, label) do update set
      qb_id = excluded.qb_id, qb_type = excluded.qb_type,
      rate = coalesce(excluded.rate, lookups.rate), sort = excluded.sort, active = true;

    update lookups set active = false
     where list = v_list and active
       and label not in (select e ->> 'label' from jsonb_array_elements(v_rows) e);

    v_counts := v_counts || jsonb_build_object(v_list, jsonb_array_length(v_rows));
  end loop;
  return v_counts;
end $$;

revoke execute on function qb_apply_lists(jsonb) from public, anon, authenticated;
grant execute on function qb_apply_lists(jsonb) to service_role;

-- The result of posting one fund request to QuickBooks, recorded as the Fund
-- Approver who clicked Export so the history shows who did it.
create or replace function record_qb_result(p_id uuid, p_txn_id text, p_error text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_role('fund_approver');
  f fund_requests;
begin
  select * into f from fund_requests where id = p_id for update;
  if not found then raise exception 'Fund request not found.'; end if;
  if f.status = 'approved_posted_to_qb' then return; end if;
  if f.status not in ('approved_ready_for_qb', 'sync_failed') then
    raise exception 'This fund request is not ready for QuickBooks.';
  end if;

  if p_txn_id is not null then
    update fund_requests set status = 'approved_posted_to_qb', qb_txn_id = p_txn_id, qb_sync_error = null
     where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'Posted to QuickBooks', f.status, 'approved_posted_to_qb',
      format('QuickBooks Expense ID %s', p_txn_id) || coalesce('. ' || nullif(btrim(p_error), ''), ''));
  else
    update fund_requests set status = 'sync_failed', qb_sync_error = left(coalesce(p_error, 'Unknown error'), 1000)
     where id = f.id;
    perform log_event(f.payment_request_id, f.id, 'QuickBooks sync failed', f.status, 'sync_failed',
      left(coalesce(p_error, 'Unknown error'), 1000));
    if f.status <> 'sync_failed' then
      perform notify(f.fund_approver_id,
        format('Fund request %s could not be posted to QuickBooks: %s', f.ref_no, left(coalesce(p_error, ''), 200)),
        f.payment_request_id, f.id);
      perform notify_role('admin',
        format('QuickBooks sync failed for fund request %s.', f.ref_no), f.payment_request_id, f.id);
    end if;
  end if;
end $$;

revoke execute on function record_qb_result(uuid, text, text) from public, anon;
grant execute on function record_qb_result(uuid, text, text) to authenticated;
