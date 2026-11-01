import { fmtDate, money } from '@/lib/format'
import { frTypeLabel } from '@/lib/labels'
import type { FundRequest } from '@/lib/types'

// Read-only fund request in QuickBooks Expense order (spec 5.2).
export function FRView({
  fr,
  chequeNo,
  chequeTotal,
  approverName,
}: {
  fr: FundRequest
  chequeNo?: string | null
  chequeTotal?: number | null
  approverName?: string
}) {
  const rows: [string, React.ReactNode][] = [
    ['Request type', `${fr.request_type} · ${frTypeLabel(fr)}`],
    ['1. Type', 'Expense'],
    ['2. Ref no.', fr.ref_no],
    ['3. Payee', fr.payee],
    ['Item no.', fr.item_no],
    ['4. Payment date', fmtDate(fr.payment_date)],
    ['5. Payment method', fr.payment_method],
  ]
  if (fr.payment_method === 'Cash') rows.push(['Cash received by', fr.cash_received_by])
  if (fr.payment_method === 'FUND TRANSFER' || fr.payment_method === 'Direct Debit') {
    rows.push(['Bank account name', fr.bank_account_name], ['Bank account number', fr.bank_account_no])
  }
  rows.push(['Original amount', fr.original_amount === null ? null : `${fr.currency} ${money(fr.original_amount)}`])
  if (fr.currency === 'USD') {
    rows.push(['Exchange rate', fr.exchange_rate === null ? null : `PHP ${fr.exchange_rate} per USD on ${fmtDate(fr.rate_date)}`])
  }
  rows.push(
    ['7. Amount, PHP, inclusive of tax', fr.amount_php === null ? null : money(fr.amount_php)],
    ['8. Tax', fr.tax_code],
    ['9. Total before tax', fr.total_before_tax === null ? null : money(fr.total_before_tax)],
    ['10. Sales tax', fr.sales_tax === null ? null : money(fr.sales_tax)],
    ['11. Payment account', fr.payment_account],
    ['12. Category', (fr.lines?.length ?? 0) > 1 ? 'Per item, see Items' : fr.category],
    ['13. Customer', fr.payee],
    ['14. Memo', fr.memo],
  )
  if (chequeNo) {
    rows.push(
      ['Cheque', chequeNo],
      ['Subtotal to fund', `PHP ${money(fr.subtotal_to_fund)}`],
      ['Total amount per cheque', `PHP ${money(chequeTotal)}`],
    )
  }
  if (approverName !== undefined) rows.push(['Assigned fund approver', approverName])
  if (fr.qb_txn_id) rows.push(['QuickBooks reference', fr.qb_txn_id])

  return (
    <section className="card">
      <h2>Expense details</h2>
      <dl className="details">
        {rows.map(([k, v]) => (
          <div key={k}>
            <dt>{k}</dt>
            <dd>{v || '–'}</dd>
          </div>
        ))}
      </dl>
      {fr.lines?.length ? (
        <>
          <h3>6. Items</h3>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>No.</th>
                  <th>Description</th>
                  <th>Category</th>
                  <th className="num">Amount ({fr.currency})</th>
                </tr>
              </thead>
              <tbody>
                {fr.lines.map((l, i) => (
                  <tr key={i}>
                    <td>{i + 1}</td>
                    <td>{l.description}</td>
                    <td>{l.category}</td>
                    <td className="num">{l.amount === null ? '' : money(l.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      ) : (
        <>
          <h3>6. Description</h3>
          <p className="pre">{fr.description}</p>
        </>
      )}
      {fr.wtax_note && <p className="note small">{fr.wtax_note}</p>}
    </section>
  )
}
