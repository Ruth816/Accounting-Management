// Same formulas as the database triggers (spec 4.4 and 5.2), used to show
// live totals while a form is being filled in. The database recomputes on save.

export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100

export function parseAmount(v: unknown): number | null {
  if (v === null || v === undefined) return null
  const s = String(v).replace(/,/g, '').trim()
  if (s === '') return null
  const n = Number(s)
  return Number.isFinite(n) ? n : null
}

export function paymentAmounts(
  items: { amount: number | string | null }[],
  billing: string,
  wtaxRate: number,
) {
  const total = round2(items.reduce((sum, i) => sum + (parseAmount(i.amount) ?? 0), 0))
  const vatEx = billing === 'VAT' ? round2(total / 1.12) : total
  const wtax = round2(vatEx * wtaxRate)
  return { total, vatEx, wtax, due: round2(total - wtax) }
}

export function itemNo(count: number) {
  return count <= 1 ? '1' : `1-${count}`
}

export function fundAmounts(original: number | null, rate: number | null, taxRate: number | null) {
  const amount = original === null || rate === null ? null : round2(original * rate)
  if (amount === null || taxRate === null) return { amount, beforeTax: null, salesTax: null }
  const beforeTax = round2(amount / (1 + taxRate))
  return { amount, beforeTax, salesTax: round2(amount - beforeTax) }
}

export const REF_NO_PATTERN = /^[1-6]- 20\d{2} (0[1-9]|1[0-2]) \d{4}$/

export function refNoProblem(ref: string, requestType: number): string | null {
  if (!ref) return 'Ref no. is required'
  if (!REF_NO_PATTERN.test(ref)) return 'Ref no. must look like "2- 2026 10 0075"'
  if (Number(ref[0]) !== requestType) return `Ref no. must start with ${requestType}- for this request type`
  return null
}

export function chequeMemo(chequeNo: string, total: number, subtotal: number) {
  return `Check No. ${chequeNo} | Check total PHP ${money(total)} | Subtotal funded PHP ${money(subtotal)}`
}

export function money(n: number | null | undefined) {
  return (n ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function normalizeMobile(raw: string): string | null {
  const d = raw.replace(/\D/g, '')
  if (!d) return null
  if (/^09\d{9}$/.test(d)) return '63' + d.slice(1)
  if (/^9\d{9}$/.test(d)) return '63' + d
  if (/^63\d{10}$/.test(d)) return d
  return null
}
