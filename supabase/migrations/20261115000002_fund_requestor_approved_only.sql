-- A Fund Requestor sees only approved payment requests (Ruth, 15 November).
-- Drafts, pending, returned, expired and cancelled requests are for the
-- requestor and the Payment Approver. Someone who also holds another role
-- (for example a Payment Requestor) still sees what that role allows, such
-- as their own requests.

drop policy if exists "visible payment requests" on payment_requests;
create policy "visible payment requests" on payment_requests for select to authenticated
  using (requestor_id = auth.uid()
         or approver_id = auth.uid()
         or (has_role('payment_approver') and status <> 'draft' and approver_region_ok(region))
         or (has_role('fund_requestor') and region_ok(region)
             and status in ('approved_awaiting_funding', 'in_funding_preparation', 'pending_fund_approval',
                            'returned_to_fund_requestor', 'approved_ready_for_qb', 'approved_posted_to_qb',
                            'sync_failed'))
         or has_role('admin'));

-- Same rule for a payment request's items, attachments, history and notifications.
create or replace function can_see_pr(pr_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from payment_requests p
    where p.id = pr_id
      and (p.requestor_id = auth.uid()
           or p.approver_id = auth.uid()
           or (has_role('payment_approver') and p.status <> 'draft' and approver_region_ok(p.region))
           or (has_role('fund_requestor') and region_ok(p.region)
               and p.status in ('approved_awaiting_funding', 'in_funding_preparation', 'pending_fund_approval',
                                'returned_to_fund_requestor', 'approved_ready_for_qb', 'approved_posted_to_qb',
                                'sync_failed'))
           or has_role('admin'))
  );
$$;
