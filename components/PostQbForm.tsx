'use client'

import { Message, Submit, useSubmit } from './ActionForm'
import { markPostedToQb } from '@/app/actions'

export const POST_QB_FORM = 'post-qb'

// The form behind the "Posted to QuickBooks" buttons and tick boxes in the
// funding summary. Row inputs join it with form="post-qb".
export function PostQbForm({ count }: { count: number }) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(markPostedToQb)
  if (count === 0) return <Message state={state} />
  return (
    <form id={POST_QB_FORM} onSubmit={onSubmit} className="row no-print post-qb">
      <PendingProvider value={pending}>
        <label className="check small">
          <input
            type="checkbox"
            onChange={(e) =>
              document
                .querySelectorAll<HTMLInputElement>(`input[form="${POST_QB_FORM}"][name="ids"]`)
                .forEach((i) => (i.checked = e.target.checked))
            }
          />{' '}
          Tick all ready for QuickBooks ({count})
        </label>
        <Submit className="btn small">Mark ticked as posted to QuickBooks</Submit>
        <Message state={state} />
      </PendingProvider>
    </form>
  )
}
