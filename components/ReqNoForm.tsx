import { requestAction } from '@/app/actions'
import { ActionForm, Submit } from './ActionForm'
import type { PaymentRequest } from '@/lib/types'

// Payment requests are saved without a REQ No.; the Fund Requestor types it
// once the request is approved, to match the numbering on the approved fund
// requests (Ruth, 20 November). Until the request is exported to QuickBooks.
const NUMBERING_STATUSES = [
  'approved_awaiting_funding',
  'in_funding_preparation',
  'pending_fund_approval',
  'returned_to_fund_requestor',
  'approved_ready_for_qb',
  'sync_failed',
]

export function canSetReqNo(pr: Pick<PaymentRequest, 'status'>, isFundRequestor: boolean) {
  return isFundRequestor && NUMBERING_STATUSES.includes(pr.status)
}

export function ReqNoForm({ pr }: { pr: Pick<PaymentRequest, 'id' | 'req_no'> }) {
  return (
    <section className="card">
      <h2>Payment REQ No.</h2>
      <ActionForm action={requestAction} hidden={{ op: 'set_req_no', id: pr.id }} className="row">
        <label className="field">
          <span className="label">REQ No.{!pr.req_no && ' (not filled in yet)'}</span>
          <input name="req_no" defaultValue={pr.req_no ?? ''} placeholder="e.g. 2026 11 0024" />
          <span className="hint">Type it to match the numbering on the approved fund requests.</span>
        </label>
        <Submit className="btn secondary">Save REQ No.</Submit>
      </ActionForm>
    </section>
  )
}
