import { QB_CONFIRM } from '@/components/PostQbForm'
import { fmtDateTime } from '@/lib/format'
import Link from 'next/link'
import { BackButton } from '@/components/BackButton'
import { canSubmitApprove, frEditMode } from '@/lib/labels'
import { EditButton } from '@/components/EditButton'
import { notFound } from 'next/navigation'
import { getDirectory, getMe } from '@/lib/auth'
import { FundRequestForm, type ChequeOption } from '@/components/FundRequestForm'
import { FRView } from '@/components/FRView'
import { PRView } from '@/components/PRView'
import { FRStatusBadge } from '@/components/StatusBadge'
import { Tracker } from '@/components/Tracker'
import { Attachments } from '@/components/Attachments'
import { ActionForm, Submit } from '@/components/ActionForm'
import { requestAction } from '@/app/actions'
import type { Attachment, AuditEntry, FundRequest, Lookup, PaymentRequest } from '@/lib/types'

export default async function FundRequestPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ edit?: string }>
}) {
  const { id } = await params
  const { edit } = await searchParams
  const { supabase, me, is } = await getMe()
  const { people, name } = await getDirectory()

  const { data } = await supabase.from('fund_requests').select('*').eq('id', id).maybeSingle()
  if (!data) notFound()
  const fr = data as FundRequest

  const [{ data: pr }, { data: files }, { data: audit }, { data: cheque }, { data: chequeTotal }] = await Promise.all([
    fr.payment_request_id
      ? supabase.from('payment_requests').select('*').eq('id', fr.payment_request_id).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase.from('attachments').select('*').eq('fund_request_id', id).order('created_at'),
    supabase.from('audit_log').select('*').eq('fund_request_id', id).order('created_at'),
    fr.cheque_id ? supabase.from('cheques').select('id, cheque_no').eq('id', fr.cheque_id).maybeSingle() : Promise.resolve({ data: null }),
    fr.cheque_id ? supabase.rpc('cheque_total', { p_cheque: fr.cheque_id }) : Promise.resolve({ data: null }),
  ])

  const isApprover = is('fund_approver') && (fr.fund_approver_id === me.id || fr.fund_requestor_id === me.id || is('admin')) && fr.status === 'pending_fund_approval'
  const approved = ['approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed'].includes(fr.status)
  // Its Fund Requestor edits it until it is funded; an Admin or a Fund Approver
  // edits every request at any stage, until it is exported to QuickBooks (Ruth, 10 November).
  // Once sent, edits keep the status and need remarks. Approved requests can't be deleted.
  const postedToQb = fr.status === 'approved_posted_to_qb'
  const editMode = frEditMode(fr, is, me.id)
  const canEditInPlace = editMode === 'in_place'
  const afterApproval = canEditInPlace && edit === '1'
  const editable = editMode === 'prep' || afterApproval

  let formData: { lookups: Lookup[]; cheques: ChequeOption[] } | null = null
  if (editable) {
    const [{ data: lookups }, { data: available }] = await Promise.all([
      supabase.from('lookups').select('*').order('sort'),
      supabase.rpc('available_cheques'),
    ])
    const cheques = ((available ?? []) as ChequeOption[]).map((c) => ({ ...c, total: Number(c.total) }))
    if (cheque && !cheques.some((c) => c.id === cheque.id)) {
      cheques.unshift({ id: cheque.id, cheque_no: cheque.cheque_no, total: Number(chequeTotal ?? 0) })
    }
    formData = { lookups: (lookups ?? []) as Lookup[], cheques }
  }
  const approvers = people.filter(
    (p) => p.active && (p.roles.includes('fund_approver') || p.roles.includes('admin')),
  )

  return (
    <div className="stack">
      <BackButton
        fallback={
          !(is('fund_requestor') || is('fund_approver') || is('admin'))
            ? '/'
            : '/fund-requests'
        }
      />
      <div className="page-head">
        <div>
          <h1>Fund request {fr.ref_no ?? ''}</h1>
          <div className="row status-actions">
            <FRStatusBadge f={fr} />
            {canEditInPlace && !afterApproval && (
              <Link className="btn secondary small" href={`/fund-requests/${fr.id}?edit=1`}>
                Edit
              </Link>
            )}
            {editMode === 'withdraw' && <EditButton href={`/fund-requests/${fr.id}`} withdrawOp="withdraw_fr" />}
            {canSubmitApprove(fr, is, me.id) && (
              <ActionForm action={requestAction} hidden={{ op: 'submit_approve_fr', id: fr.id }} confirm="Submit and approve this fund request? Save any changes below first. It goes to Ready for funding.">
                <Submit className="btn small">Submit &amp; approve</Submit>
              </ActionForm>
            )}
            {is('fund_approver') && fr.funded_at && (fr.status === 'approved_ready_for_qb' || fr.status === 'sync_failed') && (
              <ActionForm action={requestAction} hidden={{ op: 'post_qb', id: fr.id }} confirm={QB_CONFIRM}>
                <Submit className="btn small">Export to QuickBooks</Submit>
              </ActionForm>
            )}
          </div>
        </div>
        <div className="row">
          {pr && (
            <Link href={`/payment-requests/${pr.id}`} className="btn secondary small">
              Payment request {pr.req_no}
            </Link>
          )}
          {approved && (
            <Link href={`/fund-requests/${fr.id}/voucher`} className="btn small">
              Voucher
            </Link>
          )}
        </div>
      </div>

      {fr.status === 'returned_to_fund_requestor' && fr.disapproval_reason && (
        <div className="msg warn">
          <strong>Returned by {name(fr.fund_approver_id)}:</strong> {fr.disapproval_reason}
        </div>
      )}

      {pr && (
        <details className="card carried" open={editable}>
          <summary>
            <strong>From payment request {(pr as PaymentRequest).req_no}</strong>{' '}
            <span className="muted small">Everything encoded on the payment request, carried over</span>
          </summary>
          <div className="stack">
            <PRView pr={pr as PaymentRequest} name={(id) => name(id)} />
          </div>
        </details>
      )}

      {editable && formData ? (
        <>
          <FundRequestForm fr={fr} lookups={formData.lookups} approvers={approvers} cheques={formData.cheques} afterApproval={afterApproval} />
          {afterApproval && (
            <Link className="btn secondary" href={`/fund-requests/${fr.id}`}>
              Done editing
            </Link>
          )}
          <section className="card">
            <h2>Attachments</h2>
            <Attachments files={(files ?? []) as Attachment[]} frId={fr.id} canEdit userId={me.id} />
          </section>
          {fr.status === 'returned_to_fund_requestor' && fr.payment_request_id && (
            <section className="card">
              <h2>Return to payment approver</h2>
              <p className="small muted">
                This cancels the fund request and takes it off its cheque. The payment request goes back to its approver,
                and once re-approved it is received again as a new fund request.
              </p>
              <ActionForm action={requestAction} hidden={{ op: 'return_to_approver', id: fr.id }} className="stack" confirm="Cancel this fund request and send the payment request back?">
                <label className="field">
                  <span className="label">Reason *</span>
                  <textarea name="reason" rows={2} required />
                </label>
                <Submit className="btn danger secondary">Return to payment approver</Submit>
              </ActionForm>
            </section>
          )}
        </>
      ) : (
        <>
          {canEditInPlace && (
            <p className="muted small">
              {approved ? 'Approved' : 'Waiting for approval'}: it can still be corrected (Edit, with remarks)
 until it is exported to QuickBooks.
              {approved && <> It can&apos;t be deleted.</>}
            </p>
          )}
          {approved && !postedToQb && !canEditInPlace && (
            <p className="muted small">Approved: only an Admin or a Fund Approver can correct it now.</p>
          )}
          {postedToQb && <p className="muted small">Exported to QuickBooks: locked, no more edits or deletion.</p>}
          {(() => {
            const last = [...((audit ?? []) as AuditEntry[])]
              .reverse()
              .find((e) => e.action === 'Edited after approval' || e.action === 'Edited while pending approval')
            return last ? (
              <p className="muted small">
                Last {last.action.toLowerCase()} on {fmtDateTime(last.created_at)} by {name(last.actor_id)}.
              </p>
            ) : null
          })()}
          <FRView
            fr={fr}
            chequeNo={cheque?.cheque_no}
            chequeTotal={chequeTotal === null ? null : Number(chequeTotal)}
            approverName={name(fr.fund_approver_id)}
          />
          <section className="card">
            <h2>Attachments</h2>
            <Attachments files={(files ?? []) as Attachment[]} frId={fr.id} canEdit={false} userId={me.id} />
          </section>
        </>
      )}

      {isApprover && (
        <section className="card">
          <h2>Your decision</h2>
          <div className="decision">
            <ActionForm action={requestAction} hidden={{ op: 'approve_fr', id: fr.id }} confirm="You reviewed this fund request and approve it for funding? It goes to Ready for funding.">
              <Submit>Approve for funding</Submit>
            </ActionForm>
            <ActionForm action={requestAction} hidden={{ op: 'disapprove_fr', id: fr.id }} className="stack">
              <label className="field">
                <span className="label">Reason for disapproving *</span>
                <textarea name="reason" rows={2} required />
              </label>
              <Submit className="btn danger">
                Disapprove
              </Submit>
            </ActionForm>
          </div>
        </section>
      )}

      <section className="card">
        <h2>Status tracker</h2>
        <Tracker entries={(audit ?? []) as AuditEntry[]} name={name} />
      </section>
    </div>
  )
}
