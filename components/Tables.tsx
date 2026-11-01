import Link from 'next/link'
import { StatusBadge } from './StatusBadge'
import { fmtDate, money } from '@/lib/format'
import { frTypeLabel } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

export function PRTable({
  rows,
  name,
  empty = 'Nothing here.',
}: {
  rows: PaymentRequest[]
  name: (id: string | null) => string
  empty?: string
}) {
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>REQ No.</th>
            <th>Payable to</th>
            <th>Requested by</th>
            <th className="num">Amount due</th>
            <th>Required</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td>
                <Link href={`/payment-requests/${r.id}`}>{r.req_no}</Link>
              </td>
              <td>{r.payable_to}</td>
              <td>{name(r.requestor_id)}</td>
              <td className="num">
                {r.currency} {money(r.total_due)}
              </td>
              <td>{fmtDate(r.date_required)}</td>
              <td>
                <StatusBadge status={r.status} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function FRTable({ rows, empty = 'Nothing here.' }: { rows: FundRequest[]; empty?: string }) {
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Ref no.</th>
            <th>Type</th>
            <th>Payee</th>
            <th className="num">Amount (PHP)</th>
            <th>Payment date</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((f) => (
            <tr key={f.id}>
              <td>
                <Link href={`/fund-requests/${f.id}`}>{f.ref_no || 'No Ref no. yet'}</Link>
              </td>
              <td>{frTypeLabel(f)}</td>
              <td>{f.payee}</td>
              <td className="num">{f.amount_php === null ? '' : money(f.amount_php)}</td>
              <td>{fmtDate(f.payment_date)}</td>
              <td>
                <StatusBadge status={f.status} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
