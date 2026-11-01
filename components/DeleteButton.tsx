'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { requestAction } from '@/app/actions'

// Delete on a list row. Asks for a reason; the request is marked Cancelled
// and stays in the audit log.
export function DeleteButton({ op, id, label }: { op: 'delete_pr' | 'delete_fr'; id: string; label: string }) {
  const [pending, start] = useTransition()
  const router = useRouter()
  const onClick = () => {
    const reason = window.prompt(
      `Delete ${label}?\n\nIt will be marked Cancelled and removed from the lists. Type the reason (for example: doubled entry, encoded wrongly, cancelled).`,
    )
    if (reason === null) return
    if (!reason.trim()) {
      window.alert('A reason is required. Nothing was deleted.')
      return
    }
    const fd = new FormData()
    fd.set('op', op)
    fd.set('id', id)
    fd.set('reason', reason.trim())
    start(async () => {
      const res = await requestAction(null, fd)
      if (res?.error) window.alert(res.error)
      router.refresh()
    })
  }
  return (
    <button type="button" className="btn small danger secondary" onClick={onClick} disabled={pending}>
      {pending ? 'Deleting…' : 'Delete'}
    </button>
  )
}
