import Link from 'next/link'
import { FRStatusBadge, StatusBadge } from './StatusBadge'
import { ActionForm, Submit } from './ActionForm'
import { requestAction } from '@/app/actions'
import { DeleteButton } from './DeleteButton'
import { EditButton } from './EditButton'
import { fmtDate, money } from '@/lib/format'
import { type FREditMode, frRegionOf, frTypeLabel, prKindLabel } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

export function PRTable({
  rows,
  name,
  empty = 'Nothing here.',
  canDelete,
  canEdit,
  canApprove,
}: {
  rows: PaymentRequest[]
  name: (id: string | null) => string
  empty?: string
  canDelete?: (r: PaymentRequest) => boolean
  canEdit?: (r: PaymentRequest) => boolean
  canApprove?: (r: PaymentRequest) => boolean
}) {
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table className="stack-mobile">
        <thead>
          <tr>
            <th>REQ No.</th>
            <th>Type</th>
            <th>Region</th>
            <th>Payable to</th>
            <th>Items</th>
            <th>Requested by</th>
            <th className="num">Amount due</th>
            <th>Required</th>
            <th>Status</th>
            {(canDelete || canEdit || canApprove) && <th aria-label="Actions" />}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td data-label="REQ No.">
                <Link href={`/payment-requests/${r.id}`}>{r.req_no}</Link>
              </td>
              <td data-label="Type">{prKindLabel(r)}</td>
              <td data-label="Region">{r.region}</td>
              <td data-label="Payable to">{r.payable_to}</td>
              <td data-label="Items">
                <ItemList items={(r.items ?? []).map((i) => i.description)} />
              </td>
              <td data-label="Requested by">{name(r.requestor_id)}</td>
              <td className="num" data-label="Amount due">
                {r.currency} {money(r.total_due)}
              </td>
              <td data-label="Required">{fmtDate(r.date_required)}</td>
              <td data-label="Status">
                <StatusBadge status={r.status} />
              </td>
              {(canDelete || canEdit || canApprove) && (
                <td data-label="">
                  <span className="row-actions">
                    {canApprove?.(r) && (
                      <ActionForm action={requestAction} hidden={{ op: 'approve_pr', id: r.id }} confirm={`Approve payment request ${r.req_no}?`}>
                        <Submit className="btn small">Approve</Submit>
                      </ActionForm>
                    )}
                    {canEdit?.(r) && (
                      <EditButton
                        href={`/payment-requests/${r.id}${['draft', 'pending_payment_approval', 'returned_to_requestor'].includes(r.status) ? '' : '?edit=1'}`}
                        withdrawOp={r.status === 'pending_payment_approval' ? 'withdraw_pr' : undefined}
                      />
                    )}
                    {canDelete?.(r) && <DeleteButton op="delete_pr" id={r.id} label={`payment request ${r.req_no}`} />}
                  </span>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function FRTable({
  rows,
  empty = 'Nothing here.',
  canDelete,
  canEdit,
  canMarkReady,
  canApprove,
}: {
  rows: FundRequest[]
  empty?: string
  canDelete?: (f: FundRequest) => boolean
  canEdit?: (f: FundRequest) => FREditMode
  canMarkReady?: (f: FundRequest) => boolean
  canApprove?: (f: FundRequest) => boolean
}) {
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table className="stack-mobile">
        <thead>
          <tr>
            <th>Ref no.</th>
            <th>Type</th>
            <th>Region</th>
            <th>Payee</th>
            <th>Items</th>
            <th className="num">Amount (PHP)</th>
            <th>Payment date</th>
            <th>Status</th>
            {(canDelete || canEdit || canApprove) && <th aria-label="Actions" />}
          </tr>
        </thead>
        <tbody>
          {rows.map((f) => (
            <tr key={f.id}>
              <td data-label="Ref no.">
                <Link href={`/fund-requests/${f.id}`}>{f.ref_no || 'No Ref no. yet'}</Link>
              </td>
              <td data-label="Type">{frTypeLabel(f)}</td>
              <td data-label="Region">{frRegionOf(f)}</td>
              <td data-label="Payee">{f.payee}</td>
              <td data-label="Items">
                <ItemList items={frItems(f)} />
              </td>
              <td className="num" data-label="Amount (PHP)">{f.amount_php === null ? '' : money(f.amount_php)}</td>
              <td data-label="Payment date">{fmtDate(f.payment_date)}</td>
              <td data-label="Status">
                {canMarkReady?.(f) ? (
                  <ActionForm action={requestAction} hidden={{ op: 'ready_for_funding', id: f.id }} confirm="Put this request on Ready for funding for today?">
                    <Submit className="btn small">Ready for funding</Submit>
                  </ActionForm>
                ) : (
                  <FRStatusBadge f={f} />
                )}
              </td>
              {(canDelete || canEdit || canApprove) && (
                <td data-label="">
                  <span className="row-actions">
                    {canApprove?.(f) && (
                      f.status === 'pending_fund_approval' ? (
                        <ActionForm action={requestAction} hidden={{ op: 'quick_approve_fr', id: f.id }} confirm={`Reviewed and approve fund request ${f.ref_no || ''} for funding? It goes to Ready for funding.`}>
                          <Submit className="btn small">Approve for funding</Submit>
                        </ActionForm>
                      ) : (
                        <ActionForm action={requestAction} hidden={{ op: 'submit_approve_fr', id: f.id }} confirm={`Submit and approve fund request ${f.ref_no || ''}? It goes to Ready for funding.`}>
                          <Submit className="btn small">Submit &amp; approve</Submit>
                        </ActionForm>
                      )
                    )}
                    {canEdit?.(f) && (
                      <EditButton
                        href={`/fund-requests/${f.id}${canEdit(f) === 'in_place' ? '?edit=1' : ''}`}
                        withdrawOp={canEdit(f) === 'withdraw' ? 'withdraw_fr' : undefined}
                        label={f.status === 'in_funding_preparation' ? 'Prepare for Fund request' : 'Edit'}
                      />
                    )}
                    {canDelete?.(f) && (
                      <DeleteButton op="delete_fr" id={f.id} label={`fund request ${f.ref_no || '(no Ref no. yet)'}`} />
                    )}
                  </span>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// The items of each request, shown in every list (Ruth, 5 November).
function frItems(f: FundRequest): string[] {
  if (f.lines?.length) return f.lines.map((l) => l.description)
  // From a payment request: the purpose, then "1. item" lines.
  const lines = (f.description ?? '').split('\n').map((l) => l.trim()).filter(Boolean)
  const numbered = lines.filter((l) => /^\d+\.\s/.test(l)).map((l) => l.replace(/^\d+\.\s+/, ''))
  return numbered.length ? numbered : lines
}

function ItemList({ items }: { items: string[] }) {
  const shown = items.map((i) => i.trim()).filter(Boolean)
  if (!shown.length) return <span className="muted">–</span>
  return (
    <ul className="item-list">
      {shown.map((d, i) => (
        <li key={i}>{d}</li>
      ))}
    </ul>
  )
}
