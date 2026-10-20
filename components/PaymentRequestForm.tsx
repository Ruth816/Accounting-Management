'use client'

import { useState } from 'react'
import { savePaymentRequest } from '@/app/actions'
import { Message, Submit, useSubmit } from './ActionForm'
import { itemNo, money, paymentAmounts } from '@/lib/calc'
import { TERMS } from '@/lib/labels'
import type { PaymentRequest, Person } from '@/lib/types'

type Row = { description: string; amount: string }

export function PaymentRequestForm({
  pr,
  approvers,
  defaultApprover,
  requestorName,
  initialError,
}: {
  pr: PaymentRequest | null
  approvers: Person[]
  defaultApprover: string | null
  requestorName: string
  initialError?: string
}) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(
    savePaymentRequest,
    initialError ? { error: initialError } : null,
  )
  const [rows, setRows] = useState<Row[]>(
    pr?.items.length
      ? pr.items.map((i) => ({ description: i.description, amount: i.amount === null ? '' : String(i.amount) }))
      : [{ description: '', amount: '' }],
  )
  const [billing, setBilling] = useState<string>(pr?.billing_type ?? 'VAT')
  const [wtax, setWtax] = useState<number>(Number(pr?.wtax_rate ?? 0))
  const [currency, setCurrency] = useState<string>(pr?.currency ?? 'PHP')
  const totals = paymentAmounts(rows, billing, wtax)
  const returned = pr?.status === 'returned_to_requestor'
  const filled = rows.filter((r) => r.description.trim() || r.amount.trim()).length

  const setRow = (i: number, patch: Partial<Row>) => setRows(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)))

  return (
    <form onSubmit={onSubmit} className="stack">
      <PendingProvider value={pending}>
      {pr && <input type="hidden" name="id" value={pr.id} />}

      <section className="card">
        <h2>Request details</h2>
        <div className="grid">
          <Field label="Payment REQ No.">
            <input value={pr?.req_no ?? 'Given on first save'} readOnly disabled />
          </Field>
          <Field label="Requested by">
            <input value={requestorName} readOnly disabled />
          </Field>
          <Field label="Reimbursable?">
            <select name="reimbursable" defaultValue={pr?.reimbursable ? 'true' : 'false'}>
              <option value="false">No</option>
              <option value="true">Yes</option>
            </select>
          </Field>
          <Field label="Region">
            <select name="region" defaultValue={pr?.region ?? 'NCR'}>
              <option>NCR</option>
              <option>VisMin</option>
            </select>
          </Field>
          <Field label="Project name" hint="Site name and address">
            <input name="project_name" defaultValue={pr?.project_name ?? ''} />
          </Field>
          <Field label="Type of project" hint="For example FTTB">
            <input name="project_type" defaultValue={pr?.project_type ?? ''} />
          </Field>
          <Field label="Job order no.">
            <input name="job_order_no" defaultValue={pr?.job_order_no ?? ''} />
          </Field>
          <Field label="Addendum no.">
            <input name="addendum_no" defaultValue={pr?.addendum_no ?? ''} />
          </Field>
          <Field label="Work order no.">
            <input name="work_order_no" defaultValue={pr?.work_order_no ?? ''} />
          </Field>
          <Field label="Approved by *" hint={returned ? 'Locked when resubmitting' : undefined}>
            {returned && <input type="hidden" name="approver_id" value={pr?.approver_id ?? ''} />}
            <select
              name={returned ? undefined : 'approver_id'}
              defaultValue={pr ? pr.approver_id ?? '' : defaultApprover ?? ''}
              disabled={returned}
            >
              <option value="">Choose an approver</option>
              {approvers.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.full_name}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Date required *">
            <input type="date" name="date_required" defaultValue={pr?.date_required ?? ''} />
          </Field>
          <Field label="Payable to *" hint="The payee">
            <input name="payable_to" defaultValue={pr?.payable_to ?? ''} />
          </Field>
          <Field label="Type of payment">
            <select name="payment_type" defaultValue={pr?.payment_type ?? 'Cheque'}>
              <option>Cash</option>
              <option>Cheque</option>
              <option value="Bank deposit">Bank deposit (over the counter)</option>
            </select>
          </Field>
          <Field label="Type of billing">
            <select name="billing_type" value={billing} onChange={(e) => setBilling(e.target.value)}>
              <option>VAT</option>
              <option>Non-VAT</option>
              <option>Ack/R</option>
              <option>Pakyaw</option>
            </select>
          </Field>
          <Field label="Currency">
            <select name="currency" value={currency} onChange={(e) => setCurrency(e.target.value)}>
              <option>PHP</option>
              <option>USD</option>
            </select>
          </Field>
        </div>
      </section>

      <section className="card">
        <h2>Purpose of payment request</h2>
        <Field label="Purpose *">
          <textarea name="purpose" rows={3} defaultValue={pr?.purpose ?? ''} />
        </Field>
        <div className="items">
          <div className="items-head small muted">
            <span>No.</span>
            <span>Description</span>
            <span>Amount ({currency})</span>
            <span />
          </div>
          {rows.map((r, i) => (
            <div className="item-row" key={i}>
              <span className="muted">{i + 1}</span>
              <input
                name="item_description"
                aria-label={`Item ${i + 1} description`}
                value={r.description}
                onChange={(e) => setRow(i, { description: e.target.value })}
              />
              <input
                name="item_amount"
                aria-label={`Item ${i + 1} amount`}
                inputMode="decimal"
                className="num"
                value={r.amount}
                onChange={(e) => setRow(i, { amount: e.target.value })}
              />
              <button
                type="button"
                className="link danger"
                onClick={() => setRows(rows.length > 1 ? rows.filter((_, j) => j !== i) : [{ description: '', amount: '' }])}
                aria-label={`Remove item ${i + 1}`}
              >
                ✕
              </button>
            </div>
          ))}
          <button type="button" className="btn secondary small" onClick={() => setRows([...rows, { description: '', amount: '' }])}>
            Add item
          </button>
          <p className="small muted">Item no.: {itemNo(Math.max(filled, 1))}</p>
        </div>
      </section>

      <section className="card">
        <h2>For supplier and customer payment</h2>
        <div className="grid">
          <Field label="PO num">
            <input name="po_num" defaultValue={pr?.po_num ?? ''} />
          </Field>
          <Field label="PO date">
            <input type="date" name="po_date" defaultValue={pr?.po_date ?? ''} />
          </Field>
          <Field label="PO amount">
            <input name="po_amount" inputMode="decimal" className="num" defaultValue={pr?.po_amount ?? ''} />
          </Field>
          <Field label="Mode of payment">
            <select name="po_mode" defaultValue={pr?.po_mode ?? ''}>
              <option value="">None</option>
              <option value="D/P">D/P down payment</option>
              <option value="PB">PB progress billing</option>
              <option value="FB">FB final billing</option>
            </select>
          </Field>
          <Field label="Reference of last payment">
            <input name="last_payment_ref" defaultValue={pr?.last_payment_ref ?? ''} />
          </Field>
        </div>
      </section>

      <section className="card">
        <h2>Amounts ({currency})</h2>
        <dl className="amounts">
          <dt>Total amount (VAT-in)</dt>
          <dd>{money(totals.total)}</dd>
          <dt>Total amount less VAT (VAT-ex)</dt>
          <dd>{money(totals.vatEx)}</dd>
          <dt>
            <label htmlFor="wtax_rate">Less W-tax</label>
          </dt>
          <dd>
            <select id="wtax_rate" name="wtax_rate" value={String(wtax)} onChange={(e) => setWtax(Number(e.target.value))}>
              <option value="0">None</option>
              <option value="0.01">1%</option>
              <option value="0.02">2%</option>
              <option value="0.05">5%</option>
            </select>
          </dd>
          <dt>W-tax amount</dt>
          <dd>{money(totals.wtax)}</dd>
          <dt className="strong">Total amount due</dt>
          <dd className="strong">{money(totals.due)}</dd>
          <dt>
            <label htmlFor="bank_transfer_fee">Bank transfer fee (non-UB account)</label>
          </dt>
          <dd>
            <input
              id="bank_transfer_fee"
              name="bank_transfer_fee"
              inputMode="decimal"
              className="num"
              defaultValue={pr?.bank_transfer_fee ?? ''}
            />
          </dd>
        </dl>
        <p className="small muted">The bank transfer fee is recorded only and is not added to the total.</p>
      </section>

      <section className="card">
        <h2>Terms and conditions</h2>
        <ol className="small">
          {TERMS.map((t) => (
            <li key={t}>{t}</li>
          ))}
        </ol>
        <label className="check">
          <input type="checkbox" name="terms_accepted" defaultChecked={pr?.terms_accepted ?? false} />I have read and
          understood the terms and conditions
        </label>
      </section>

      <Message state={state} />
      <div className="actions sticky">
        <Submit className="btn secondary" name="intent" value="save">
          Save as draft
        </Submit>
        <Submit name="intent" value="submit">
          {returned ? 'Resubmit for approval' : 'Submit for approval'}
        </Submit>
      </div>
      </PendingProvider>
    </form>
  )
}

export function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="field">
      <span className="label">{label}</span>
      {children}
      {hint && <span className="hint">{hint}</span>}
    </label>
  )
}
