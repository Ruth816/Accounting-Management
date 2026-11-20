'use client'

import { useRouter } from 'next/navigation'
import { useTransition } from 'react'

// Shown on every portal page (Ruth, 20 November). Re-fetches the page's data
// from the database without a full reload, so lists, counts and statuses are
// current and anything already typed into a form is kept.
export function RefreshButton() {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  return (
    <button
      type="button"
      className="btn secondary small refresh-btn no-print"
      onClick={() => startTransition(() => router.refresh())}
      disabled={pending}
      aria-busy={pending}
      title="Load the latest data for this page"
    >
      <span className={pending ? 'refresh-icon spin' : 'refresh-icon'} aria-hidden="true">
        ↻
      </span>
      {pending ? 'Refreshing…' : 'Refresh'}
    </button>
  )
}
