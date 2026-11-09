import { describe, expect, it } from 'vitest'
import { buildExpense, expenseLines, ExpenseError, paymentType, type ExpenseInput, type QbRefs } from './qboExpense'

const base: ExpenseInput = {
  ref_no: '2- 2026 04 075',
  payee: 'ABC Supplies',
  description: 'Office chairs',
  exchange_rate: 1,
  payment_date: '2026-11-09',
  payment_method: 'FUND TRANSFER',
  amount_php: 5500,
  tax_code: '12% S - Goods',
  tax_rate: 0.12,
  total_before_tax: 4910.71,
  payment_account: 'Cash and cash equivalents',
  category: 'OFFICE EXPENSES- Admin:Office Supplies',
  memo: 'Cheque 1001 PHP 5,500.00',
  funded_at: null,
  approved_on: '2026-11-08T02:00:00Z',
  lines: [],
}

const refs: QbRefs = {
  account: (l) =>
    ({
      'Cash and cash equivalents': { id: '35', type: 'Bank' },
      'Company Visa': { id: '41', type: 'Credit Card' },
      'OFFICE EXPENSES- Admin:Office Supplies': { id: '77', type: 'Expense' },
      'BANK CHARGES:Transfer & MC Fees': { id: '12', type: 'Expense' },
    })[l],
  method: (l) => ({ 'FUND TRANSFER': { id: '5' }, Check: { id: '2' }, 'Credit Card': { id: '3' } })[l],
  tax: (l) => ({ '12% S - Goods': { id: '8', rate: 0.12 }, 'No VAT (0%)': { id: '9', rate: 0 } })[l],
}

describe('QuickBooks Expense', () => {
  it('posts a single-line request VAT-inclusive', () => {
    const e = buildExpense(base, null, refs, { id: '60', type: 'Vendor' }, new Map([['ABC Supplies', '90']]))
    expect(e).toMatchObject({
      PaymentType: 'Cash',
      AccountRef: { value: '35' },
      PaymentMethodRef: { value: '5' },
      EntityRef: { value: '60', type: 'Vendor' },
      TxnDate: '2026-11-09',
      DocNumber: '2- 2026 04 075',
      PrivateNote: 'Cheque 1001 PHP 5,500.00',
      GlobalTaxCalculation: 'TaxInclusive',
    })
    expect(e.Line).toHaveLength(1)
    expect(e.Line[0]).toMatchObject({
      Amount: 4910.71,
      AccountBasedExpenseLineDetail: { AccountRef: { value: '77' }, TaxCodeRef: { value: '8' }, TaxInclusiveAmt: 5500, CustomerRef: { value: '90' } },
    })
  })

  it('adds the bank transfer fee as a second line with no VAT', () => {
    const e = buildExpense(base, 25, refs, null, new Map())
    expect(e.Line).toHaveLength(2)
    expect(e.Line[1]).toMatchObject({
      Amount: 25,
      AccountBasedExpenseLineDetail: { AccountRef: { value: '12' }, TaxCodeRef: { value: '9' }, TaxInclusiveAmt: 25 },
    })
    expect(e).not.toHaveProperty('EntityRef')
  })

  it('posts one line per item, converted to PHP, with the total matching', () => {
    const fr: ExpenseInput = {
      ...base,
      exchange_rate: 58.333,
      amount_php: 1750,
      lines: [
        { description: 'A', amount: 10, category: 'OFFICE EXPENSES- Admin:Office Supplies', tax_code: '12% S - Goods' },
        { description: 'B', amount: 20, category: 'OFFICE EXPENSES- Admin:Office Supplies', tax_code: 'No VAT (0%)' },
      ],
    }
    const lines = expenseLines(fr, null)
    expect(lines.map((l) => l.gross)).toEqual([583.33, 1166.67])
    const e = buildExpense(fr, null, refs, null, new Map())
    expect(e.Line[0].Amount).toBe(520.83)
    expect(e.Line[1].Amount).toBe(1166.67)
  })

  it('names the value QuickBooks does not have', () => {
    expect(() => buildExpense({ ...base, category: 'Made up' }, null, refs, null, new Map())).toThrow(
      new ExpenseError('Category "Made up" is not in QuickBooks.'),
    )
    expect(() => buildExpense({ ...base, payment_method: 'Cash' }, null, refs, null, new Map())).toThrow(/Payment method "Cash"/)
  })

  it('uses the QuickBooks payment type for the account and method', () => {
    expect(paymentType('Check', 'Bank')).toBe('Check')
    expect(paymentType('Credit Card', 'Bank')).toBe('CreditCard')
    expect(paymentType('Direct Debit', 'Credit Card')).toBe('CreditCard')
    expect(paymentType('Cash', 'Bank')).toBe('Cash')
  })
})
