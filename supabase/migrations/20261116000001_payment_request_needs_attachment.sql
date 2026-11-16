-- Every payment request needs at least one attached document before it can be
-- submitted (or resubmitted) for approval (Ruth, 16 November). Drafts can still
-- be saved without one.

create or replace function pr_requires_attachment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending_payment_approval'
     and old.status in ('draft', 'returned_to_requestor')
     and not exists (select 1 from attachments where payment_request_id = new.id) then
    raise exception 'Attach at least one document in the Memo section before submitting for approval.';
  end if;
  return new;
end $$;

drop trigger if exists pr_requires_attachment on payment_requests;
create trigger pr_requires_attachment before update of status on payment_requests
  for each row execute function pr_requires_attachment();
