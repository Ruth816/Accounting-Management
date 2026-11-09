// Builds the QuickBooks Online Expense (API entity "Purchase") for a fund
// request. Pure, so it can be tested without QuickBooks.
//
// Amounts on the portal are VAT-inclusive PHP. The Expense is sent with
// GlobalTaxCalculation "TaxInclusive": each line's Amount is the amount before
// tax and TaxInclusiveAmt the VAT-inclusive amount, with the tax code, so the
// Expense total in QuickBooks equals the portal's PHP amount.

import type { FundLine, FundRequest } from './types'

export const BANK_FEE_CATEGORY = 'BANK CHARGES:Transfer & MC Fees'
export const BANK_FEE_TAX = 'No VAT (0%)'

export type QbRef = { id: string; type?: string | null; rate?: number | null }
export type QbRefs = {
  account: (label: string) => QbRef | undefined // payment accounts and categories
  method: (label: string) => QbRef | undefined
  tax: (label: string) => QbRef | undefined
}
export type QbEntity = { id: string; type: 'Vendor' | 'Customer' | 'Employee' }

export type ExpenseInput = Pick<
  FundRequest,
  | 'ref_no' | 'payee' | 'description' | 'exchange_rate' | 'payment_date' | 'payment_method' | 'amount_php'
  | 'tax_code' | 'tax_rate' | 'total_before_tax' | 'payment_account' | 'category' | 'memo' | 'funded_at' | 'approved_on'
> & { lines: FundLine[] }

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100

export class ExpenseError extends Error {}

function need<T>(v: T | undefined | null, msg: string): T {
  if (v === undefined || v === null || v === '') throw new ExpenseError(msg)
  return v
}

// Manila date (YYYY-MM-DD) of a timestamp.
const manilaDay = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' })

export type ExpenseLine = { description: string; category: string; tax: string; gross: number; customer?: string | null }

// The lines that go on the Expense, in PHP, VAT-inclusive.
export function expenseLines(fr: ExpenseInput, bankFee: number | null): ExpenseLine[] {
  const rate = Number(fr.exchange_rate ?? 1) || 1
  const out: ExpenseLine[] = []
  if (fr.lines.length > 0) {
    for (const [i, l] of fr.lines.entries()) {
      out.push({
        description: l.description,
        category: need(l.category, `Item ${i + 1} has no category.`),
        tax: need(l.tax_code ?? fr.tax_code, `Item ${i + 1} has no tax.`),
        gross: round2(Number(need(l.amount, `Item ${i + 1} has no amount.`)) * rate),
        customer: l.customer ?? fr.payee,
      })
    }
    // Item amounts are rounded one by one; put any cent left over on the last item
    // so the total matches the approved PHP amount.
    if (fr.amount_php !== null) {
      const diff = round2(Number(fr.amount_php) - out.reduce((s, l) => s + l.gross, 0))
      if (diff !== 0 && Math.abs(diff) < 0.05) out[out.length - 1].gross = round2(out[out.length - 1].gross + diff)
    }
  } else {
    out.push({
      description: fr.description ?? '',
      category: need(fr.category, 'The fund request has no category.'),
      tax: need(fr.tax_code, 'The fund request has no tax.'),
      gross: round2(Number(need(fr.amount_php, 'The fund request has no PHP amount.'))),
      customer: fr.payee,
    })
  }
  if (bankFee && bankFee > 0) {
    out.push({ description: 'Bank transfer fee', category: BANK_FEE_CATEGORY, tax: BANK_FEE_TAX, gross: round2(bankFee) })
  }
  return out
}

export function paymentType(method: string | null, accountType: string | null | undefined) {
  if (accountType === 'Credit Card' || method === 'Credit Card') return 'CreditCard'
  if (method === 'Check') return 'Check'
  return 'Cash'
}

export function buildExpense(
  fr: ExpenseInput,
  bankFee: number | null,
  refs: QbRefs,
  entity: QbEntity | null,
  customers: Map<string, string>,
) {
  const accountLabel = need(fr.payment_account, 'The fund request has no payment account.')
  const account = need(refs.account(accountLabel), `Payment account "${accountLabel}" is not in QuickBooks.`)
  const methodLabel = need(fr.payment_method, 'The fund request has no payment method.')
  const method = refs.method(methodLabel)
  if (!method) throw new ExpenseError(`Payment method "${methodLabel}" is not in QuickBooks.`)

  const Line = expenseLines(fr, bankFee).map((l) => {
    const cat = need(refs.account(l.category), `Category "${l.category}" is not in QuickBooks.`)
    const tax = need(refs.tax(l.tax), `Tax code "${l.tax}" is not in QuickBooks.`)
    const taxRate = Number(tax.rate ?? 0)
    const net = round2(l.gross / (1 + taxRate))
    const customerId = l.customer ? customers.get(l.customer) : undefined
    return {
      DetailType: 'AccountBasedExpenseLineDetail',
      Amount: net,
      Description: l.description.slice(0, 4000),
      AccountBasedExpenseLineDetail: {
        AccountRef: { value: cat.id },
        TaxCodeRef: { value: tax.id },
        TaxInclusiveAmt: l.gross,
        ...(customerId ? { CustomerRef: { value: customerId } } : {}),
      },
    }
  })

  const day = fr.payment_date ?? (fr.funded_at ? manilaDay(fr.funded_at) : fr.approved_on ? manilaDay(fr.approved_on) : undefined)
  return {
    PaymentType: paymentType(methodLabel, account.type),
    AccountRef: { value: account.id },
    PaymentMethodRef: { value: method.id },
    ...(entity ? { EntityRef: { value: entity.id, type: entity.type } } : {}),
    ...(day ? { TxnDate: day } : {}),
    ...(fr.ref_no ? { DocNumber: fr.ref_no.slice(0, 21) } : {}),
    ...(fr.memo ? { PrivateNote: fr.memo.slice(0, 4000) } : {}),
    GlobalTaxCalculation: 'TaxInclusive',
    Line,
  }
}

// VAT-inclusive total of the Expense, used to spot one already in QuickBooks.
export const expenseTotal = (lines: ExpenseLine[]) => round2(lines.reduce((s, l) => s + l.gross, 0))
