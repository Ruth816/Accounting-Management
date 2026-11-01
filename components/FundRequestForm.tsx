'use client'

import { useState } from 'react'
import { saveFundRequest } from '@/app/actions'
import { Message, Submit, useSubmit } from './ActionForm'
import { Field } from './PaymentRequestForm'
import { chequeMemo, fundAmounts, money, parseAmount, refNoProblem } from '@/lib/calc'
import { REQUEST_TYPE_LABEL } from '@/lib/labels'
import type { FundRequest, Lookup, Person } from '@/lib/types'

export type ChequeOption = { id: string; cheque_no: string; total: number }

export function FundRequestForm({
  fr,
  lookups,
  approvers,
  cheques,
}: {
  fr: FundRequest
  lookups: Lookup[]
  approvers: Person[]
  cheques: ChequeOption[]
}) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(saveFundRequest)
  const manual = fr.payment_request_id === null // auto debit or check payment: fields are typed
  const list = (l: Lookup['list']) => lookups.filter((x) => x.list === l && x.active)

  const [method, setMethod] = useState(fr.payment_method ?? '')
  const [currency, setCurrency] = useState(fr.currency)
  const [original, setOriginal] = useState(fr.original_amount === null ? '' : String(fr.original_amount))
  const [rate, setRate] = useState(fr.exchange_rate === null || fr.currency === 'PHP' ? '' : String(fr.exchange_rate))
  const [tax, setTax] = useState(fr.tax_code ?? '')
  const [payee, setPayee] = useState(fr.payee ?? '')
  const [refNo, setRefNo] = useState(fr.ref_no ?? '')
  const [mode, setMode] = useState<'none' | 'existing' | 'new'>(fr.cheque_id ? 'existing' : method === 'Check' ? 'new' : 'none')
  const [chequeId, setChequeId] = useState(fr.cheque_id ?? '')
  const [chequeNo, setChequeNo] = useState('')
  const [subtotal, setSubtotal] = useState(fr.subtotal_to_fund === null ? '' : String(fr.subtotal_to_fund))
  const [memoEdited, setMemoEdited] = useState(fr.memo_edited)
  const [memo, setMemo] = useState(fr.memo ?? '')

  const taxRate = fr.tax_locked ? fr.tax_rate : list('tax_code').find((t) => t.label === tax)?.rate ?? null
  const amounts = fundAmounts(parseAmount(original), currency === 'PHP' ? 1 : parseAmount(rate), taxRate === null ? null : Number(taxRate))
  const usesCheque = method === 'Check' || method === 'Auto debit'
  const sub = parseAmount(subtotal) ?? 0
  const chosen = cheques.find((c) => c.id === chequeId)
  // The listed total includes this request's saved subtotal when it is already on that cheque.
  const otherOnCheque = chosen ? chosen.total - (fr.cheque_id === chosen.id ? fr.subtotal_to_fund ?? 0 : 0) : 0
  const memoPreview =
    usesCheque && mode === 'existing' && chosen
      ? chequeMemo(chosen.cheque_no, otherOnCheque + sub, sub)
      : usesCheque && mode === 'new' && chequeNo
        ? chequeMemo(chequeNo, sub, sub)
        : ''
  const refProblem = refNo ? refNoProblem(refNo, fr.request_type) : null

  return (
    <form onSubmit={onSubmit} className="stack">
      <PendingProvider value={pending}>
        <input type="hidden" name="id" value={fr.id} />
        <input type="hidden" name="memo_edited" value={String(memoEdited)} />

        <section className="card">
          <h2>Expense details</h2>
          <div className="grid">
            <Field label="Request type">
              <input value={`${fr.request_type} · ${REQUEST_TYPE_LABEL[fr.request_type]}`} readOnly disabled />
            </Field>
            <Field label="1. Type">
              <input value="Expense" readOnly disabled />
            </Field>
            <Field label="2. Ref no. *" hint={refProblem ?? `Format ${fr.request_type}- YYYY MM NNNN`}>
              <input
                name="ref_no"
                value={refNo}
                placeholder={`${fr.request_type}- 2026 10 0001`}
                onChange={(e) => setRefNo(e.target.value)}
                aria-invalid={Boolean(refProblem)}
              />
            </Field>
            <Field label="3. Payee *">
              <input name="payee" value={payee} onChange={(e) => setPayee(e.target.value)} readOnly={!manual} />
            </Field>
            <Field label="Item no.">
              <input name="item_no" defaultValue={fr.item_no ?? ''} readOnly={!manual} />
            </Field>
            <Field label="4. Payment date *">
              <input type="date" name="payment_date" defaultValue={fr.payment_date ?? ''} />
            </Field>
            <Field label="5. Payment method *">
              <select
                name="payment_method"
                value={method}
                onChange={(e) => {
                  setMethod(e.target.value)
                  if (e.target.value === 'Check' && mode === 'none') setMode(cheques.length ? 'existing' : 'new')
                }}
              >
                <option value="">Choose</option>
                {list('payment_method').map((m) => (
                  <option key={m.id}>{m.label}</option>
                ))}
              </select>
            </Field>
            {method === 'Cash' && (
              <Field label="Cash received by">
                <input name="cash_received_by" defaultValue={fr.cash_received_by ?? ''} />
              </Field>
            )}
            {(method === 'Bank transfer' || method === 'Auto debit') && (
              <>
                <Field label={`Bank account name${method === 'Bank transfer' ? ' *' : ''}`}>
                  <input name="bank_account_name" defaultValue={fr.bank_account_name ?? ''} />
                </Field>
                <Field label={`Bank account number${method === 'Bank transfer' ? ' *' : ''}`}>
                  <input name="bank_account_no" defaultValue={fr.bank_account_no ?? ''} />
                </Field>
              </>
            )}
          </div>
          <Field label="6. Description *">
            <textarea name="description" rows={4} defaultValue={fr.description ?? ''} readOnly={!manual} />
          </Field>
        </section>

        <section className="card">
          <h2>Amount</h2>
          <div className="grid">
            <Field label="Original currency">
              <select name="currency" value={currency} onChange={(e) => setCurrency(e.target.value as 'PHP' | 'USD')} disabled={!manual}>
                <option>PHP</option>
                <option>USD</option>
              </select>
            </Field>
            <Field label="Original amount *">
              <input
                name="original_amount"
                inputMode="decimal"
                className="num"
                value={original}
                onChange={(e) => setOriginal(e.target.value)}
                readOnly={!manual}
              />
            </Field>
            {currency === 'USD' && (
              <>
                <Field label="Exchange rate (PHP per 1 USD) *">
                  <input name="exchange_rate" inputMode="decimal" className="num" value={rate} onChange={(e) => setRate(e.target.value)} />
                </Field>
                <Field label="Rate date *">
                  <input type="date" name="rate_date" defaultValue={fr.rate_date ?? ''} />
                </Field>
              </>
            )}
            <Field label="8. Tax *" hint={fr.tax_locked ? 'No VAT because the payment request is not VAT-billed' : undefined}>
              <select name="tax_code" value={tax} onChange={(e) => setTax(e.target.value)} disabled={fr.tax_locked}>
                <option value="">Choose</option>
                {list('tax_code').map((t) => (
                  <option key={t.id}>{t.label}</option>
                ))}
              </select>
            </Field>
          </div>
          <dl className="amounts">
            <dt className="strong">7. Amount, PHP, inclusive of tax</dt>
            <dd className="strong">{amounts.amount === null ? '–' : money(amounts.amount)}</dd>
            <dt>9. Total before tax</dt>
            <dd>{amounts.beforeTax === null ? '–' : money(amounts.beforeTax)}</dd>
            <dt>10. Sales tax</dt>
            <dd>{amounts.salesTax === null ? '–' : money(amounts.salesTax)}</dd>
          </dl>
          {fr.wtax_note && <p className="note small">{fr.wtax_note}</p>}
        </section>

        <section className="card">
          <h2>Accounts</h2>
          <div className="grid">
            <Field label="11. Payment account *">
              <select name="payment_account" defaultValue={fr.payment_account ?? ''}>
                <option value="">Choose</option>
                {list('payment_account').map((a) => (
                  <option key={a.id}>{a.label}</option>
                ))}
              </select>
            </Field>
            <Field label="12. Category *">
              <select name="category" defaultValue={fr.category ?? ''}>
                <option value="">Choose</option>
                {list('category').map((c) => (
                  <option key={c.id}>{c.label}</option>
                ))}
              </select>
            </Field>
            <Field label="13. Customer" hint="Always the payee">
              <input value={payee} readOnly disabled />
            </Field>
            <Field label="Assigned fund approver *">
              <select name="fund_approver_id" defaultValue={fr.fund_approver_id ?? ''}>
                <option value="">Choose a fund approver</option>
                {approvers.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.full_name}
                  </option>
                ))}
              </select>
            </Field>
          </div>
        </section>

        {usesCheque && (
          <section className="card">
            <h2>Cheque{method === 'Auto debit' ? ' (optional)' : ''}</h2>
            <div className="segmented" role="radiogroup">
              {method === 'Auto debit' && (
                <label>
                  <input type="radio" name="cheque_mode" value="none" checked={mode === 'none'} onChange={() => setMode('none')} /> No cheque
                </label>
              )}
              <label>
                <input type="radio" name="cheque_mode" value="existing" checked={mode === 'existing'} onChange={() => setMode('existing')} />{' '}
                Select existing cheque
              </label>
              <label>
                <input type="radio" name="cheque_mode" value="new" checked={mode === 'new'} onChange={() => setMode('new')} /> New cheque
              </label>
            </div>
            <div className="grid">
              {mode === 'existing' && (
                <Field label="Cheque">
                  <select name="cheque_id" value={chequeId} onChange={(e) => setChequeId(e.target.value)}>
                    <option value="">Choose a cheque</option>
                    {cheques.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.cheque_no} (PHP {money(c.total)} so far)
                      </option>
                    ))}
                  </select>
                </Field>
              )}
              {mode === 'new' && (
                <Field label="New cheque number">
                  <input name="cheque_no" value={chequeNo} onChange={(e) => setChequeNo(e.target.value)} />
                </Field>
              )}
              {mode !== 'none' && (
                <>
                  <Field label="Subtotal to fund (PHP) *">
                    <input
                      name="subtotal_to_fund"
                      inputMode="decimal"
                      className="num"
                      value={subtotal}
                      onChange={(e) => setSubtotal(e.target.value)}
                    />
                  </Field>
                  <Field label="Total amount per cheque">
                    <input value={money(mode === 'existing' ? otherOnCheque + sub : sub)} readOnly disabled className="num" />
                  </Field>
                </>
              )}
            </div>
          </section>
        )}

        <section className="card">
          <h2>14. Memo</h2>
          <textarea
            name="memo"
            rows={2}
            value={memoEdited ? memo : memoPreview}
            onChange={(e) => {
              setMemoEdited(true)
              setMemo(e.target.value)
            }}
          />
          <p className="small muted">
            {memoEdited ? (
              <button type="button" className="link" onClick={() => setMemoEdited(false)}>
                Go back to the automatic memo
              </button>
            ) : (
              'Filled from the cheque until you edit it.'
            )}
          </p>
        </section>

        <Message state={state} />
        <div className="actions sticky">
          <Submit className="btn secondary" name="intent" value="save">
            Save as draft
          </Submit>
          <Submit name="intent" value="submit">
            {fr.status === 'returned_to_fund_requestor' ? 'Resubmit' : 'Send for fund approval'}
          </Submit>
        </div>
      </PendingProvider>
    </form>
  )
}
