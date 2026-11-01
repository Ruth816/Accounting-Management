'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { requestAction } from '@/app/actions'

// Edit on a list row. A request waiting for approval is first taken back
// (payment request to Draft, fund request to In Funding Preparation), then
// the request opens for editing and is submitted again from there.
export function EditButton({ href, withdrawOp }: { href: string; withdrawOp?: 'withdraw_pr' | 'withdraw_fr' }) {
  const [pending, start] = useTransition()
  const router = useRouter()
  const onClick = () => {
    if (!withdrawOp) {
      router.push(href)
      return
    }
    if (!window.confirm('This request is waiting for approval. Editing takes it back from the approver; submit it again when you are done. Continue?')) return
    const id = href.split('/').pop()!
    const fd = new FormData()
    fd.set('op', withdrawOp)
    fd.set('id', id)
    start(async () => {
      const res = await requestAction(null, fd)
      if (res?.error) window.alert(res.error)
      else router.push(href)
    })
  }
  return (
    <button type="button" className="btn small secondary" onClick={onClick} disabled={pending}>
      {pending ? 'Opening…' : 'Edit'}
    </button>
  )
}
