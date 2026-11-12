'use client'

import { Message, Submit, useSubmit } from './ActionForm'
import { approvePaymentRequests } from '@/app/actions'

export const BULK_APPROVE_FORM = 'bulk-approve-pr'

// The Payment Approver's "Approve ticked" bar on Payment requests (Ruth, 12 November).
// Row tick boxes join this form with form="bulk-approve-pr".
export function BulkApproveForm({ count }: { count: number }) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(approvePaymentRequests, null, 'Approve all the ticked payment requests?')
  if (count === 0) return <Message state={state} />
  return (
    <form id={BULK_APPROVE_FORM} onSubmit={onSubmit} className="card row bulk-approve">
      <PendingProvider value={pending}>
        <label className="check">
          <input
            type="checkbox"
            onChange={(e) =>
              document
                .querySelectorAll<HTMLInputElement>(`input[form="${BULK_APPROVE_FORM}"][name="ids"]`)
                .forEach((i) => (i.checked = e.target.checked))
            }
          />{' '}
          Tick all waiting for your approval ({count})
        </label>
        <Submit className="btn">Approve ticked</Submit>
        <Message state={state} />
      </PendingProvider>
    </form>
  )
}
