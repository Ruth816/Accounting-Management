import Link from 'next/link'
import { AUTO_DEBIT_HELP, CHECK_PAYMENT_HELP } from '@/lib/labels'
import { getDirectory, getMe } from '@/lib/auth'
import { FRTable, PRTable } from '@/components/Tables'
import { todayManila } from '@/lib/summary'
import { ActionForm, Submit } from '@/components/ActionForm'
import { requestAction } from '@/app/actions'
import type { FundRequest, PaymentRequest } from '@/lib/types'

const WORKFLOW_ROLES = ['payment_requestor', 'payment_approver', 'fund_requestor', 'fund_approver'] as const

export default async function Dashboard() {
  const { supabase, me, is } = await getMe()
  const { name } = await getDirectory()

  const headCount = (status: string[]) =>
    supabase.from('payment_requests').select('id', { count: 'exact', head: true }).in('status', status)
  const [mine, toApprove, toReceive, preparing, toFundApprove, recent, coPending, coFunding, coFundApproval, coApproved] = await Promise.all([
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
    is('admin') ? headCount(['pending_payment_approval']) : null,
    is('admin') ? headCount(['approved_awaiting_funding', 'in_funding_preparation', 'returned_to_fund_requestor']) : null,
    is('admin') ? headCount(['pending_fund_approval']) : null,
    is('admin') ? headCount(['approved_ready_for_qb', 'approved_posted_to_qb']) : null,
  ])
  const my = (mine?.data ?? []) as PaymentRequest[]
  const count = (pred: (r: PaymentRequest) => boolean) => my.filter(pred).length
  const frPreparing = (preparing?.data ?? []) as FundRequest[]

  // Stat cards, grouped like the HRM dashboard. Only the roles the user holds add cards.
  const action: StatCard[] = []
  const progress: StatCard[] = []
  const done: StatCard[] = []
  if (is('payment_approver')) action.push({ value: toApprove?.data?.length ?? 0, label: 'payment requests awaiting your approval', href: '#approve-pr' })
  if (is('fund_approver')) action.push({ value: toFundApprove?.data?.length ?? 0, label: 'fund requests awaiting your approval', href: '#approve-fr' })
  if (is('fund_requestor')) {
    action.push({ value: toReceive?.data?.length ?? 0, label: 'approved requests to receive for funding', href: '#receive' })
    action.push({ value: frPreparing.filter((f) => f.status === 'returned_to_fund_requestor').length, label: 'fund requests returned to you', href: '#preparing' })
    progress.push({ value: frPreparing.filter((f) => f.status === 'in_funding_preparation').length, label: 'fund requests in preparation', href: '#preparing' })
  }
  if (is('payment_requestor')) {
    action.push({ value: count((r) => r.status === 'returned_to_requestor'), label: 'of your requests returned to you', href: '#mine' })
    progress.push({ value: count((r) => ['pending_payment_approval', 'approved_awaiting_funding', 'in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor'].includes(r.status)), label: 'of your requests in approval', href: '#mine' })
    progress.push({ value: count((r) => r.status === 'draft'), label: 'drafts not yet submitted', href: '#mine' })
    done.push({ value: count((r) => r.status.startsWith('approved_ready') || r.status.startsWith('approved_posted')), label: 'of your requests fully approved', href: '#mine' })
  }
  // Today's approvals, linking to the approval summaries.
  const todayStart = `${todayManila()}T00:00:00+08:00`
  if (is('fund_approver')) {
    const { count: n } = await supabase.from('fund_requests').select('id', { count: 'exact', head: true })
      .eq('approved_by', me.id).gte('approved_on', todayStart).neq('status', 'cancelled')
    done.push({ value: n ?? 0, label: 'fund requests you approved today · open the summary list for funding', href: '/summary/funding' })
  }
  if (is('payment_approver')) {
    const { count: n } = await supabase.from('payment_requests').select('id', { count: 'exact', head: true })
      .eq('approver_id', me.id).gte('approved_on', todayStart).neq('status', 'cancelled')
    done.push({ value: n ?? 0, label: 'payment requests you approved today · open the summary', href: '/summary/payments' })
  }
  const company: StatCard[] = is('admin')
    ? [
        { value: coPending?.count ?? 0, label: 'waiting for payment approval' },
        { value: coFunding?.count ?? 0, label: 'approved, being funded' },
        { value: coFundApproval?.count ?? 0, label: 'waiting for fund approval' },
        { value: coApproved?.count ?? 0, label: 'fully approved', tone: 'good' },
      ]
    : []

  return (
    <div className="stack">
      <div>
        <h1 className="page-title">Dashboard</h1>
        <p className="page-sub">Hello, {me.full_name.split(' ')[0]}. Here is what needs your attention.</p>
      </div>

      <StatGroup title="Needs action today" cards={action} tone="action" />
      <StatGroup title="In progress" cards={progress} tone="progress" />
      <StatGroup title="Completed" cards={done} tone="good" />
      <StatGroup title="Company overview" cards={company} tone="progress" />

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
        <Queue id="approve-pr" title="Waiting for your approval" count={toApprove?.data?.length}>
          <PRTable rows={(toApprove?.data ?? []) as PaymentRequest[]} name={name} empty="No requests waiting for you." />
        </Queue>
      )}

      {is('fund_approver') && (
        <Queue id="approve-fr" title="Fund requests waiting for your approval" count={toFundApprove?.data?.length}>
          <FRTable rows={(toFundApprove?.data ?? []) as FundRequest[]} empty="No fund requests waiting for you." />
        </Queue>
      )}

      {is('fund_requestor') && (
        <>
          <Queue id="receive" title="Approved, ready to receive for funding" count={toReceive?.data?.length}>
            <PRTable rows={(toReceive?.data ?? []) as PaymentRequest[]} name={name} empty="No approved requests waiting." />
          </Queue>
          <Queue
            id="preparing"
            title="Fund requests you are preparing"
            count={preparing?.data?.length}
            action={
              <ActionForm action={requestAction} className="row">
                <select name="op" aria-label="Fund request type" defaultValue="new_auto_debit">
                  <option value="new_auto_debit">1 · Auto debit request</option>
                  <option value="new_check_payment">2 · Check payment request</option>
                </select>
                <Submit className="btn small">New fund request</Submit>
              </ActionForm>
            }
          >
            <ul className="small muted plain type-help">
              <li>
                <strong>Auto debit request:</strong> {AUTO_DEBIT_HELP}
              </li>
              <li>
                <strong>Check payment request:</strong> {CHECK_PAYMENT_HELP}
              </li>
            </ul>
            <FRTable rows={frPreparing} empty="Nothing in preparation." />
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
          id="mine"
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

type StatCard = { value: number; label: string; href?: string; tone?: string }

// A titled row of big-number cards. A non-zero number takes the group's colour.
function StatGroup({ title, cards, tone }: { title: string; cards: StatCard[]; tone: string }) {
  if (!cards.length) return null
  return (
    <section>
      <h2 className="group-title">{title}</h2>
      <div className="stat-grid">
        {cards.map((c) => {
          const cls = `stat-card${c.value ? ` ${c.tone ?? tone}` : ''}`
          const body = (
            <>
              <div className="stat-value">{c.value}</div>
              <div className="stat-label">{c.label}</div>
            </>
          )
          return c.href ? (
            <a key={c.label} href={c.href} className={cls}>
              {body}
            </a>
          ) : (
            <div key={c.label} className={cls}>
              {body}
            </div>
          )
        })}
      </div>
    </section>
  )
}

function Queue({
  id,
  title,
  count,
  action,
  children,
}: {
  id?: string
  title: string
  count?: number
  action?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <section className="card" id={id}>
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
