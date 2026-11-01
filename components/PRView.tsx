import { fmtDate, money } from '@/lib/format'
import { poModeLabel, prKindLabel } from '@/lib/labels'
import type { PaymentRequest } from '@/lib/types'

// Read-only payment request, laid out like the paper form.
export function PRView({ pr, name }: { pr: PaymentRequest; name: (id: string | null) => string }) {
  const rows: [string, React.ReactNode][] = [
    ['Payment REQ No.', pr.req_no],
    ['Version', pr.version],
    ['Request type', prKindLabel(pr)],
    ['Region', pr.region],
    ['Date', fmtDate(pr.created_at)],
    ['Requested by', name(pr.requestor_id)],
    ['Project name', pr.project_name],
    ['Type of project', pr.project_type],
    ['Job order no.', pr.job_order_no],
    ['Addendum no.', pr.addendum_no],
    ['Work order no.', pr.work_order_no],
    ...(pr.first_approver_id
      ? ([['Approver 1', `${name(pr.first_approver_id)} · ${fmtDate(pr.first_approved_on)}`]] as [string, React.ReactNode][])
      : []),
    [pr.status === 'pending_payment_approval' ? (pr.first_approver_id ? 'Waiting for approver 2' : 'Waiting for') : 'Approved by', name(pr.approver_id)],
    ['Date required', fmtDate(pr.date_required)],
    ['Payable to', pr.payable_to],
    ['Type of payment', pr.payment_type],
    ['Type of billing', pr.billing_type],
    ['Currency', pr.currency],
  ]
  const po: [string, React.ReactNode][] = [
    ['PO num', pr.po_num],
    ['PO date', fmtDate(pr.po_date)],
    ['PO amount', pr.po_amount === null ? null : money(pr.po_amount)],
    ['Mode of payment', poModeLabel(pr.po_mode)],
    ['Reference of last payment', pr.last_payment_ref],
  ]
  return (
    <>
      <section className="card">
        <h2>Request details</h2>
        <dl className="details">
          {rows.map(([k, v]) => (
            <div key={k}>
              <dt>{k}</dt>
              <dd>{v || '–'}</dd>
            </div>
          ))}
        </dl>
      </section>
      <section className="card">
        <h2>Purpose of payment request</h2>
        <p className="pre">{pr.purpose}</p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>No.</th>
                <th>Description</th>
                <th className="num">Amount ({pr.currency})</th>
              </tr>
            </thead>
            <tbody>
              {pr.items.map((i, n) => (
                <tr key={n}>
                  <td>{n + 1}</td>
                  <td>{i.description}</td>
                  <td className="num">{i.amount === null ? '' : money(i.amount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="small muted">Item no.: {pr.item_no}</p>
      </section>
      {po.some(([, v]) => v) && (
        <section className="card">
          <h2>For supplier and customer payment</h2>
          <dl className="details">
            {po.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v || '–'}</dd>
              </div>
            ))}
          </dl>
        </section>
      )}
      <section className="card">
        <h2>Amounts ({pr.currency})</h2>
        <dl className="amounts">
          <dt>Total amount (VAT-in)</dt>
          <dd>{money(pr.total_vat_in)}</dd>
          <dt>Total amount less VAT (VAT-ex)</dt>
          <dd>{money(pr.total_vat_ex)}</dd>
          <dt>Less W-tax</dt>
          <dd>{pr.wtax_rate ? `${Math.round(pr.wtax_rate * 100)}%` : 'None'}</dd>
          <dt>W-tax amount</dt>
          <dd>{money(pr.wtax_amount)}</dd>
          <dt className="strong">Total amount due</dt>
          <dd className="strong">{money(pr.total_due)}</dd>
          <dt>Bank transfer fee (non-UB account)</dt>
          <dd>{pr.bank_transfer_fee === null ? '–' : money(pr.bank_transfer_fee)}</dd>
        </dl>
      </section>
    </>
  )
}
