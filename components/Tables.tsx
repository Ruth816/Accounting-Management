import Link from 'next/link'
import { StatusBadge } from './StatusBadge'
import { DeleteButton } from './DeleteButton'
import { EditButton } from './EditButton'
import { fmtDate, money } from '@/lib/format'
import { frRegionOf, frTypeLabel, prKindLabel } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

export function PRTable({
  rows,
  name,
  empty = 'Nothing here.',
  canDelete,
  canEdit,
}: {
  rows: PaymentRequest[]
  name: (id: string | null) => string
  empty?: string
  canDelete?: (r: PaymentRequest) => boolean
  canEdit?: (r: PaymentRequest) => boolean
}) {
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table>
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
            {(canDelete || canEdit) && <th aria-label="Actions" />}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td>
                <Link href={`/payment-requests/${r.id}`}>{r.req_no}</Link>
              </td>
              <td>{prKindLabel(r)}</td>
              <td>{r.region}</td>
              <td>{r.payable_to}</td>
              <td>
                <ItemList items={(r.items ?? []).map((i) => i.description)} />
              </td>
              <td>{name(r.requestor_id)}</td>
              <td className="num">
                {r.currency} {money(r.total_due)}
              </td>
              <td>{fmtDate(r.date_required)}</td>
              <td>
                <StatusBadge status={r.status} />
              </td>
              {(canDelete || canEdit) && (
                <td>
                  <span className="row-actions">
                    {canEdit?.(r) && (
                      <EditButton
                        href={`/payment-requests/${r.id}`}
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
}: {
  rows: FundRequest[]
  empty?: string
  canDelete?: (f: FundRequest) => boolean
  canEdit?: (f: FundRequest) => boolean
}) {
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table>
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
            {(canDelete || canEdit) && <th aria-label="Actions" />}
          </tr>
        </thead>
        <tbody>
          {rows.map((f) => (
            <tr key={f.id}>
              <td>
                <Link href={`/fund-requests/${f.id}`}>{f.ref_no || 'No Ref no. yet'}</Link>
              </td>
              <td>{frTypeLabel(f)}</td>
              <td>{frRegionOf(f)}</td>
              <td>{f.payee}</td>
              <td>
                <ItemList items={frItems(f)} />
              </td>
              <td className="num">{f.amount_php === null ? '' : money(f.amount_php)}</td>
              <td>{fmtDate(f.payment_date)}</td>
              <td>
                <StatusBadge status={f.status} />
              </td>
              {(canDelete || canEdit) && (
                <td>
                  <span className="row-actions">
                    {canEdit?.(f) && (
                      <EditButton
                        href={`/fund-requests/${f.id}`}
                        withdrawOp={f.status === 'pending_fund_approval' ? 'withdraw_fr' : undefined}
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
  const max = 3
  return (
    <ul className="item-list" title={shown.join('\n')}>
      {shown.slice(0, max).map((d, i) => (
        <li key={i}>{d}</li>
      ))}
      {shown.length > max && <li className="muted">+{shown.length - max} more</li>}
    </ul>
  )
}
