import { describe, expect, it } from 'vitest'
import { chequeMemo, fundAmounts, itemNo, normalizeMobile, paymentAmounts, refNoProblem } from './calc'

describe('spec acceptance figures', () => {
  it('PHP 1,120.00 VAT-in at 2% W-tax', () => {
    expect(paymentAmounts([{ amount: '1,000' }, { amount: 120 }], 'VAT', 0.02)).toEqual({
      total: 1120,
      vatEx: 1000,
      wtax: 20,
      due: 1100,
    })
  })
  it('non-VAT billing keeps the total', () => {
    expect(paymentAmounts([{ amount: 500 }], 'Non-VAT', 0.01)).toEqual({ total: 500, vatEx: 500, wtax: 5, due: 495 })
  })
  it('PHP 5,500.00 at 12%', () => {
    expect(fundAmounts(5500, 1, 0.12)).toEqual({ amount: 5500, beforeTax: 4910.71, salesTax: 589.29 })
  })
  it('USD 420.00 at 58.25', () => {
    expect(fundAmounts(420, 58.25, 0).amount).toBe(24465)
  })
  it('item no.', () => {
    expect(itemNo(1)).toBe('1')
    expect(itemNo(3)).toBe('1-3')
  })
  it('Ref no. rules', () => {
    expect(refNoProblem('2- 2026 10 0075', 2)).toBeNull()
    expect(refNoProblem('2- 2026 13 0075', 2)).toMatch(/look like/)
    expect(refNoProblem('2-2026100075', 2)).toMatch(/look like/)
    expect(refNoProblem('3- 2026 10 0075', 2)).toMatch(/start with 2-/)
  })
  it('cheque memo', () => {
    expect(chequeMemo('100200', 25585, 1120)).toBe(
      'Check No. 100200 | Check total PHP 25,585.00 | Subtotal funded PHP 1,120.00',
    )
  })
  it('mobile numbers', () => {
    expect(normalizeMobile('0917 123 4567')).toBe('639171234567')
    expect(normalizeMobile('639171234567')).toBe('639171234567')
    expect(normalizeMobile('12345')).toBeNull()
  })
})
