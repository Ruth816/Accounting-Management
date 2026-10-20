import Link from 'next/link'
import { getMe } from '@/lib/auth'
import { ActionForm, Submit } from '@/components/ActionForm'
import { requestAction } from '@/app/actions'
import { fmtDateTime } from '@/lib/format'
import type { Notification } from '@/lib/types'

export default async function NotificationsPage() {
  const { supabase, me } = await getMe()
  const { data } = await supabase
    .from('notifications')
    .select('*')
    .eq('recipient_id', me.id)
    .order('created_at', { ascending: false })
    .limit(100)
  const rows = (data ?? []) as Notification[]

  return (
    <div className="stack">
      <div className="page-head">
        <h1>Notifications</h1>
        {rows.some((n) => !n.read) && (
          <ActionForm action={requestAction} hidden={{ op: 'mark_read' }}>
            <Submit className="btn secondary small">Mark all as read</Submit>
          </ActionForm>
        )}
      </div>
      {rows.length === 0 && <p className="muted">No notifications yet.</p>}
      <ul className="notifications">
        {rows.map((n) => {
          const href = n.fund_request_id && !n.payment_request_id
            ? `/fund-requests/${n.fund_request_id}`
            : n.payment_request_id
              ? `/payment-requests/${n.payment_request_id}`
              : n.fund_request_id
                ? `/fund-requests/${n.fund_request_id}`
                : null
          return (
            <li key={n.id} className={n.read ? 'read' : 'unread'}>
              <div>{href ? <Link href={href}>{n.message}</Link> : n.message}</div>
              <div className="small muted">
                {fmtDateTime(n.created_at)} · SMS: {n.sms_status}
              </div>
              {!n.read && (
                <ActionForm action={requestAction} hidden={{ op: 'mark_read', id: n.id }}>
                  <Submit className="link small">Mark read</Submit>
                </ActionForm>
              )}
            </li>
          )
        })}
      </ul>
    </div>
  )
}
