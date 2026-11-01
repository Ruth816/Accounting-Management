import Link from 'next/link'
import { BackButton } from '@/components/BackButton'
import { PR_OPEN_STATUSES } from '@/lib/labels'
import { notFound } from 'next/navigation'
import { getDirectory, getMe } from '@/lib/auth'
import { PaymentRequestForm } from '@/components/PaymentRequestForm'
import { PRView } from '@/components/PRView'
import { StatusBadge } from '@/components/StatusBadge'
import { Tracker } from '@/components/Tracker'
import { Attachments } from '@/components/Attachments'
import { ActionForm, Submit } from '@/components/ActionForm'
import { requestAction } from '@/app/actions'
import { fmtDate, fmtDateTime, money } from '@/lib/format'
import type { Attachment, AuditEntry, FundRequest, PaymentRequest, Version } from '@/lib/types'

export default async function PaymentRequestPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ error?: string }>
}) {
  const { id } = await params
  const { error } = await searchParams
  const { supabase, me, is } = await getMe()
  const { people, name } = await getDirectory()

  const { data } = await supabase.from('payment_requests').select('*').eq('id', id).maybeSingle()
  if (!data) notFound()
  const pr = data as PaymentRequest

  const [{ data: frs }, { data: files }, { data: versions }] = await Promise.all([
    supabase.from('fund_requests').select('*').eq('payment_request_id', id).order('created_at'),
    supabase.from('attachments').select('*').eq('payment_request_id', id).order('created_at'),
    supabase.from('payment_request_versions').select('*').eq('payment_request_id', id).order('version', { ascending: false }),
  ])
  const fundRequests = (frs ?? []) as FundRequest[]
  const frIds = fundRequests.map((f) => f.id)
  const { data: audit } = await supabase
    .from('audit_log')
    .select('*')
    .or(frIds.length ? `payment_request_id.eq.${id},fund_request_id.in.(${frIds.join(',')})` : `payment_request_id.eq.${id}`)
    .order('created_at')
  const entries = [...new Map(((audit ?? []) as AuditEntry[]).map((e) => [e.id, e])).values()]

  const fr = fundRequests.find((f) => f.id === pr.fund_request_id) ?? null
  let cheque: { cheque_no: string; total: number } | null = null
  if (fr?.cheque_id) {
    const [{ data: c }, { data: total }] = await Promise.all([
      supabase.from('cheques').select('cheque_no').eq('id', fr.cheque_id).maybeSingle(),
      supabase.rpc('cheque_total', { p_cheque: fr.cheque_id }),
    ])
    if (c) cheque = { cheque_no: c.cheque_no, total: Number(total ?? 0) }
  }

  const mine = pr.requestor_id === me.id
  const editable = mine && (pr.status === 'draft' || pr.status === 'returned_to_requestor')
  const canApprove = is('payment_approver') && !mine && pr.status === 'pending_payment_approval'
  const canReceive = is('fund_requestor') && pr.status === 'approved_awaiting_funding'
  const funded = fr && ['approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed'].includes(fr.status)
  const canLiquidate = mine && pr.payment_type === 'Cash' && funded && !pr.liquidated_on
  const approvers = people.filter((p) => p.active && p.roles.includes('payment_approver') && p.id !== pr.requestor_id)

  return (
    <div className="stack">
      <BackButton fallback={PR_OPEN_STATUSES.includes(pr.status) ? '/payment-requests' : '/payment-requests/approved'} />
      <div className="page-head">
        <div>
          <h1>Payment request {pr.req_no}</h1>
          <StatusBadge status={pr.status} />
        </div>
        {fr && (
          <Link href={`/fund-requests/${fr.id}`} className="btn secondary small">
            Open fund request
          </Link>
        )}
      </div>

      {pr.status === 'returned_to_requestor' && (
        <div className="msg warn">
          <strong>Returned:</strong> {pr.disapproval_reason}
          <br />
          Resubmit by {fmtDate(pr.expires_on)} or the request will be deleted.
        </div>
      )}
      {pr.return_note && pr.status === 'pending_payment_approval' && (
        <div className="msg warn">
          <strong>Sent back by funding:</strong> {pr.return_note}
        </div>
      )}

      {editable ? (
        <>
          <PaymentRequestForm
            pr={pr}
            approvers={approvers}
            defaultApprover={me.default_payment_approver}
            requestorName={name(pr.requestor_id)}
            initialError={error}
          />
          <section className="card">
            <h2>Attachments</h2>
            <Attachments files={(files ?? []) as Attachment[]} prId={pr.id} canEdit userId={me.id} />
          </section>
          <ActionForm action={requestAction} hidden={{ op: 'cancel_pr', id: pr.id }} confirm="Cancel this request? It stays in the audit log.">
            <Submit className="btn danger secondary">Cancel request</Submit>
          </ActionForm>
        </>
      ) : (
        <>
          <PRView pr={pr} name={name} />
          <section className="card">
            <h2>Attachments</h2>
            <Attachments files={(files ?? []) as Attachment[]} prId={pr.id} canEdit={false} userId={me.id} />
          </section>
        </>
      )}

      {canApprove && (
        <section className="card">
          <h2>Your decision</h2>
          <div className="decision">
            <ActionForm action={requestAction} hidden={{ op: 'approve_pr', id: pr.id }}>
              <Submit>Approve</Submit>
            </ActionForm>
            <ActionForm action={requestAction} hidden={{ op: 'disapprove_pr', id: pr.id }} className="stack">
              <label className="field">
                <span className="label">Reason for disapproving *</span>
                <textarea name="reason" rows={2} required />
              </label>
              <Submit className="btn danger">Disapprove</Submit>
            </ActionForm>
          </div>
        </section>
      )}

      {canReceive && (
        <section className="card">
          <h2>Funding</h2>
          <ActionForm action={requestAction} hidden={{ op: 'receive', id: pr.id }}>
            <Submit>Receive and prepare fund request</Submit>
          </ActionForm>
        </section>
      )}

      {fr && (
        <section className="card">
          <h2>Payment details</h2>
          <dl className="details">
            <div>
              <dt>Part of fund request #</dt>
              <dd>{fr.ref_no || '–'}</dd>
            </div>
            <div>
              <dt>Issued date</dt>
              <dd>{fmtDate(fr.approved_on) || '–'}</dd>
            </div>
            {fr.payment_method === 'Cash' && (
              <>
                <div>
                  <dt>Received by</dt>
                  <dd>{fr.cash_received_by || '–'}</dd>
                </div>
                <div>
                  <dt>Date</dt>
                  <dd>{fmtDate(fr.payment_date) || '–'}</dd>
                </div>
                <div>
                  <dt>Amount</dt>
                  <dd>PHP {money(fr.amount_php)}</dd>
                </div>
              </>
            )}
            {(fr.payment_method === 'FUND TRANSFER' || fr.payment_method === 'Direct Debit') && (
              <>
                <div>
                  <dt>Account name</dt>
                  <dd>{fr.bank_account_name || '–'}</dd>
                </div>
                <div>
                  <dt>Bank account</dt>
                  <dd>{fr.bank_account_no || '–'}</dd>
                </div>
                <div>
                  <dt>Amount</dt>
                  <dd>PHP {money(fr.amount_php)}</dd>
                </div>
              </>
            )}
            {cheque && (
              <>
                <div>
                  <dt>Cheque number</dt>
                  <dd>{cheque.cheque_no}</dd>
                </div>
                <div>
                  <dt>Dated</dt>
                  <dd>{fmtDate(fr.payment_date) || '–'}</dd>
                </div>
                <div>
                  <dt>Amount (this request)</dt>
                  <dd>PHP {money(fr.subtotal_to_fund)}</dd>
                </div>
                <div>
                  <dt>Total amount per cheque</dt>
                  <dd>PHP {money(cheque.total)}</dd>
                </div>
              </>
            )}
          </dl>
        </section>
      )}

      {pr.payment_type === 'Cash' && fr && (canLiquidate || pr.liquidated_on) && (
        <section className="card">
          <h2>Liquidation</h2>
          <dl className="amounts">
            <dt>Issued amount</dt>
            <dd>PHP {money(fr.amount_php)}</dd>
          </dl>
          {pr.liquidated_on ? (
            <dl className="amounts">
              <dt>Actual used</dt>
              <dd>{money(pr.liq_actual_used)}</dd>
              <dt>Change / excess</dt>
              <dd>{money(pr.liq_change)}</dd>
              <dt>Deposited back</dt>
              <dd>
                {pr.liq_deposit_amount !== null
                  ? `${money(pr.liq_deposit_amount)} on ${fmtDate(pr.liq_deposit_date)} at ${pr.liq_deposit_bank}`
                  : '–'}
              </dd>
              <dt>Liquidated</dt>
              <dd>{fmtDateTime(pr.liquidated_on)}</dd>
            </dl>
          ) : (
            <ActionForm action={requestAction} hidden={{ op: 'liquidate', id: pr.id }} className="stack">
              <div className="grid">
                <label className="field">
                  <span className="label">Actual used (PHP) *</span>
                  <input name="actual_used" inputMode="decimal" className="num" required />
                </label>
                <label className="field">
                  <span className="label">Deposit-back date</span>
                  <input type="date" name="deposit_date" />
                </label>
                <label className="field">
                  <span className="label">Deposit-back amount</span>
                  <input name="deposit_amount" inputMode="decimal" className="num" />
                </label>
                <label className="field">
                  <span className="label">Bank</span>
                  <input name="deposit_bank" />
                </label>
              </div>
              <p className="small muted">The deposit-back fields are required when there is change left over.</p>
              <Submit>Save liquidation</Submit>
            </ActionForm>
          )}
        </section>
      )}

      {(versions ?? []).length > 0 && (
        <section className="card">
          <h2>Version history</h2>
          <ul className="versions">
            {((versions ?? []) as Version[]).map((v) => (
              <li key={v.id}>
                <details>
                  <summary>
                    Version {v.version} returned {fmtDateTime(v.created_at)} by {name(v.returned_by)}: {v.reason}
                  </summary>
                  <PRView pr={v.snapshot} name={name} />
                </details>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="card">
        <h2>Status tracker</h2>
        <Tracker entries={entries} name={name} />
      </section>
    </div>
  )
}
