import { notFound } from 'next/navigation'
import { getMe } from '@/lib/auth'
import { FRView } from '@/components/FRView'
import { PrintButton } from '@/components/PrintButton'
import { fmtDate } from '@/lib/format'
import type { FundRequest } from '@/lib/types'

type Voucher = {
  fund_request: FundRequest
  cheque_no: string | null
  cheque_total: number | null
  req_no: string | null
  payment_requested_by: string | null
  payment_requested_on: string | null
  payment_approved_by: string | null
  payment_approved_on: string | null
  fund_prepared_by: string | null
  fund_prepared_on: string | null
  fund_approved_by: string | null
  fund_approved_on: string | null
}

// Approval record (spec 5.8). "Print / Save as PDF" gives the PDF.
export default async function VoucherPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const { supabase } = await getMe()
  const { data, error } = await supabase.rpc('get_voucher', { p_id: id })
  if (error || !data) notFound()
  const v = data as Voucher
  const fr = v.fund_request
  if (!fr.locked) notFound()

  const signatures: [string, string | null, string | null][] = [
    ['Payment requested', v.payment_requested_by, v.payment_requested_on],
    ['Payment approved', v.payment_approved_by, v.payment_approved_on],
    ['Fund request prepared', v.fund_prepared_by, v.fund_prepared_on],
    ['Fund approved', v.fund_approved_by, v.fund_approved_on],
  ]

  return (
    <div className="voucher stack">
      <div className="page-head no-print">
        <h1>Expense voucher</h1>
        <PrintButton />
      </div>
      <header className="voucher-head">
        <h2>Expense voucher · {fr.ref_no}</h2>
        {v.req_no && <p className="muted">Payment request {v.req_no}</p>}
      </header>
      <FRView fr={fr} chequeNo={v.cheque_no} chequeTotal={v.cheque_total} />
      <section className="card signatures">
        {signatures.map(([label, who, when]) => (
          <div key={label} className="signature">
            <div className="sig-line">{who ?? ''}</div>
            <div className="small">{label}</div>
            <div className="small muted">{fmtDate(when)}</div>
          </div>
        ))}
      </section>
    </div>
  )
}
