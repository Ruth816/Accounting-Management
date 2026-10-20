import Link from 'next/link'
import { getDirectory, getMe } from '@/lib/auth'
import { FRTable, PRTable } from '@/components/Tables'
import { ActionForm, Submit } from '@/components/ActionForm'
import { requestAction } from '@/app/actions'
import type { FundRequest, PaymentRequest } from '@/lib/types'

const WORKFLOW_ROLES = ['payment_requestor', 'payment_approver', 'fund_requestor', 'fund_approver'] as const

export default async function Dashboard() {
  const { supabase, me, is } = await getMe()
  const { name } = await getDirectory()

  const [mine, toApprove, toReceive, preparing, toFundApprove, recent] = await Promise.all([
    is('payment_requestor')
      ? supabase.from('payment_requests').select('*').eq('requestor_id', me.id).neq('status', 'cancelled').order('updated_at', { ascending: false }).limit(50)
      : null,
    is('payment_approver')
      ? supabase.from('payment_requests').select('*').eq('approver_id', me.id).eq('status', 'pending_payment_approval').order('submitted_on')
      : null,
    is('fund_requestor')
      ? supabase.from('payment_requests').select('*').eq('status', 'approved_awaiting_funding').order('approved_on')
      : null,
    is('fund_requestor')
      ? supabase.from('fund_requests').select('*').in('status', ['in_funding_preparation', 'returned_to_fund_requestor']).order('updated_at', { ascending: false })
      : null,
    is('fund_approver')
      ? supabase.from('fund_requests').select('*').eq('fund_approver_id', me.id).eq('status', 'pending_fund_approval').order('submitted_on')
      : null,
    is('admin')
      ? supabase.from('payment_requests').select('*').not('status', 'in', '(draft,cancelled)').order('updated_at', { ascending: false }).limit(20)
      : null,
  ])
  const my = (mine?.data ?? []) as PaymentRequest[]
  const count = (pred: (r: PaymentRequest) => boolean) => my.filter(pred).length

  return (
    <div className="stack">
      <h1>Hello, {me.full_name.split(' ')[0]}</h1>

      {is('payment_requestor') && (
        <div className="stats">
          <Stat label="Pending" value={count((r) => ['pending_payment_approval', 'approved_awaiting_funding', 'in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor'].includes(r.status))} />
          <Stat label="Returned" value={count((r) => r.status === 'returned_to_requestor')} tone="warn" />
          <Stat label="Approved" value={count((r) => r.status.startsWith('approved_ready') || r.status.startsWith('approved_posted'))} tone="good" />
          <Stat label="Drafts" value={count((r) => r.status === 'draft')} />
        </div>
      )}

      {!WORKFLOW_ROLES.some(is) &&
        (is('admin') ? (
          <section className="card">
            <h2>Get started</h2>
            <p>
              Your account is Admin only, so you have no request queues yet. Queues and the New payment request button appear
              once a user has a workflow role.
            </p>
            <ol>
              <li>
                Open <Link href="/admin">Admin</Link> and add each person under <strong>Add a user</strong>.
              </li>
              <li>Tick their roles (Payment Requestor, Payment Approver, Fund Requestor, Fund Approver) and click Save.</li>
              <li>Set each requestor&apos;s default payment approver and default fund approver.</li>
            </ol>
            <p className="small muted">
              To try the flow yourself, tick Payment Requestor on your own user. Someone else must approve, so add at least one
              other user as the approver.
            </p>
            <Link className="btn small" href="/admin">
              Go to Admin
            </Link>
          </section>
        ) : (
          <p className="msg">You have no roles yet. Ask an Admin to give you one.</p>
        ))}

      {is('payment_approver') && (
        <Queue title="Waiting for your approval" count={toApprove?.data?.length}>
          <PRTable rows={(toApprove?.data ?? []) as PaymentRequest[]} name={name} empty="No requests waiting for you." />
        </Queue>
      )}

      {is('fund_approver') && (
        <Queue title="Fund requests waiting for your approval" count={toFundApprove?.data?.length}>
          <FRTable rows={(toFundApprove?.data ?? []) as FundRequest[]} empty="No fund requests waiting for you." />
        </Queue>
      )}

      {is('fund_requestor') && (
        <>
          <Queue title="Approved, ready to receive for funding" count={toReceive?.data?.length}>
            <PRTable rows={(toReceive?.data ?? []) as PaymentRequest[]} name={name} empty="No approved requests waiting." />
          </Queue>
          <Queue
            title="Fund requests you are preparing"
            count={preparing?.data?.length}
            action={
              <ActionForm action={requestAction} hidden={{ op: 'new_auto_debit' }}>
                <Submit className="btn small">New auto debit request</Submit>
              </ActionForm>
            }
          >
            <FRTable rows={(preparing?.data ?? []) as FundRequest[]} empty="Nothing in preparation." />
          </Queue>
        </>
      )}

      {is('admin') && (
        <Queue title="Latest requests across the company">
          <PRTable rows={(recent?.data ?? []) as PaymentRequest[]} name={name} empty="No requests have been submitted yet." />
        </Queue>
      )}

      {is('payment_requestor') && (
        <Queue
          title="Your payment requests"
          action={
            <Link className="btn small" href="/payment-requests/new">
              New payment request
            </Link>
          }
        >
          <PRTable rows={my} name={name} empty="You have no requests yet." />
        </Queue>
      )}
    </div>
  )
}

function Stat({ label, value, tone }: { label: string; value: number; tone?: string }) {
  return (
    <div className={`stat ${tone ?? ''}`}>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  )
}

function Queue({
  title,
  count,
  action,
  children,
}: {
  title: string
  count?: number
  action?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <section className="card">
      <div className="card-head">
        <h2>
          {title}
          {count ? <span className="count">{count}</span> : null}
        </h2>
        {action}
      </div>
      {children}
    </section>
  )
}
