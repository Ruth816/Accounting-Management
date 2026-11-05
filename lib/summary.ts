import 'server-only'
import { getDirectory, getMe } from './auth'
import { frTypeLabel } from './labels'
import { money } from './calc'
import type { Status } from './types'

// Approval summaries (Ruth, 1 November): what an approver approved per day,
// per month and over a calendar year, in Philippine time.

export type SummaryKind = 'funding' | 'quickbooks'

export type SummaryRow = {
  id: string
  href: string
  approvedAt: string
  day: string // YYYY-MM-DD, Manila
  ref: string
  payee: string
  type: string
  method: string
  account: string // payment account (funding) or requestor (payments)
  cheque: string
  currency: string
  amount: number
  approver: string
  status: Status
}

export type Totals = Record<string, number> // per currency

const TZ = 'Asia/Manila'
const dayFmt = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' })
export const manilaDay = (iso: string) => dayFmt.format(new Date(iso))
export const todayManila = () => manilaDay(new Date().toISOString())
export const timeManila = (iso: string) =>
  new Date(iso).toLocaleTimeString('en-PH', { timeZone: TZ, hour: 'numeric', minute: '2-digit' })

export const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

type KindInfo = { title: string; sub: string; role: 'fund_approver'; amountLabel: string; accountLabel: string; file: string; verb: 'approved' | 'exported' }
export const KIND_INFO: Record<SummaryKind, KindInfo> = {
  funding: {
    title: 'Summary list for funding',
    sub: 'Fund requests approved for funding. Send out funds based on the subtotal for the day.',
    role: 'fund_approver',
    amountLabel: 'Amount to fund (PHP)',
    accountLabel: 'Payment account',
    file: 'funding-summary',
    verb: 'approved',
  },
  // Replaces the approved payments summary (Ruth, 5 November): approved fund
  // requests already exported to QuickBooks, by the day they were exported.
  quickbooks: {
    title: 'QuickBooks imported summary',
    sub: 'Approved fund requests already exported to QuickBooks and locked, per day, per month and for the year.',
    role: 'fund_approver',
    amountLabel: 'Amount funded (PHP)',
    accountLabel: 'Payment account',
    file: 'quickbooks-imported-summary',
    verb: 'exported',
  },
}

export function validDay(v: string | undefined) {
  return v && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v)) ? v : todayManila()
}

export function addTotals(t: Totals, r: { currency: string; amount: number }) {
  t[r.currency] = Math.round(((t[r.currency] ?? 0) + r.amount) * 100) / 100
  return t
}
export function sumRows(rows: SummaryRow[]) {
  return rows.reduce<Totals>((t, r) => addTotals(t, r), {})
}
export function fmtTotals(t: Totals) {
  const keys = Object.keys(t).sort((a, b) => (a === 'PHP' ? -1 : b === 'PHP' ? 1 : a.localeCompare(b)))
  return keys.length ? keys.map((c) => `${c} ${money(t[c])}`).join(' · ') : 'PHP 0.00'
}

// Who may open the page, and whose approvals it shows. Admins can pick any
// approver or everyone; approvers see their own.
export async function summaryAccess(kind: SummaryKind, approverParam?: string) {
  const { me, is } = await getMe()
  const role = KIND_INFO[kind].role
  const allowed = is(role) || is('admin') || (kind === 'quickbooks' && is('payment_approver'))
  // Everyone on the QuickBooks summary sees every approver's requests;
  // Admins can pick on both pages. isAdmin here means "may pick an approver".
  const isAdmin = is('admin') || (kind === 'quickbooks' && allowed)
  let approver: string | 'all' = is(role) && kind === 'funding' ? me.id : 'all'
  if (isAdmin && approverParam === 'all') approver = 'all'
  else if (isAdmin && approverParam && /^[0-9a-f-]{36}$/i.test(approverParam)) approver = approverParam
  const { people, name } = await getDirectory()
  const approvers = people.filter((p) => p.roles.includes(role))
  return { allowed, isAdmin, approver, approvers, name, me, canPost: is('fund_approver') }
}

// Every approval in the calendar year of `day`.
export async function loadYear(kind: SummaryKind, year: number, approver: string | 'all'): Promise<SummaryRow[]> {
  const { supabase } = await getMe()
  const { name } = await getDirectory()
  const from = `${year}-01-01T00:00:00+08:00`
  const to = `${year + 1}-01-01T00:00:00+08:00`

  type FR = Record<string, any> // eslint-disable-line @typescript-eslint/no-explicit-any
  const toRow = (f: FR, at: string): SummaryRow => ({
    id: f.id,
    href: `/fund-requests/${f.id}`,
    approvedAt: at,
    day: manilaDay(at),
    ref: f.ref_no ?? '',
    payee: f.payee ?? '',
    type: frTypeLabel(f as { request_type: number; payment_request_id: string | null }),
    method: f.payment_method ?? '',
    account: f.payment_account ?? '',
    cheque: f.cheques?.cheque_no ?? chequeList(f.lines),
    currency: 'PHP',
    amount: Number(f.subtotal_to_fund ?? f.amount_php ?? 0),
    approver: name(f.approved_by),
    status: f.status,
  })

  if (kind === 'funding') {
    let q = supabase
      .from('fund_requests')
      .select('*, cheques(cheque_no)')
      .not('approved_on', 'is', null)
      .neq('status', 'cancelled')
      .gte('approved_on', from)
      .lt('approved_on', to)
      .order('approved_on')
      .limit(10000)
    if (approver !== 'all') q = q.eq('approved_by', approver)
    const { data } = await q
    return (data ?? []).map((f) => toRow(f, f.approved_on))
  }

  // QuickBooks: locked fund requests, dated by when they were exported.
  const { data } = await supabase.rpc('qb_imported_summary', { p_from: from, p_to: to })
  return ((data ?? []) as FR[])
    .filter((f) => approver === 'all' || f.approved_by === approver)
    .map((f) => toRow({ ...f, cheques: f.cheque_no ? { cheque_no: f.cheque_no } : null }, f.exported_at))
}

// Cheque numbers typed on the items of a Check request, each listed once.
function chequeList(lines: { cheque_no?: string | null }[] | null | undefined) {
  return [...new Set((lines ?? []).map((l) => l.cheque_no).filter(Boolean))].join(', ')
}
