import 'server-only'
import { KIND_INFO, MONTHS, fmtTotals, loadYear, sumRows, summaryAccess, timeManila, validDay, type SummaryKind } from './summary'

const cell = (v: string | number) => {
  const s = String(v)
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}
const line = (cols: (string | number)[]) => cols.map(cell).join(',')

// CSV that opens in Excel: a heading block, the requests, then subtotals per
// day (month and year) and per month (year).
export async function exportSummary(kind: SummaryKind, req: Request) {
  const url = new URL(req.url)
  const info = KIND_INFO[kind]
  const access = await summaryAccess(kind, url.searchParams.get('approver') ?? undefined)
  if (!access.allowed) return new Response('Not allowed', { status: 403 })
  const scope = ['day', 'month', 'year'].includes(url.searchParams.get('scope') ?? '') ? url.searchParams.get('scope')! : 'day'
  const day = validDay(url.searchParams.get('date') ?? undefined)
  const year = Number(day.slice(0, 4))
  const prefix = scope === 'day' ? day : scope === 'month' ? day.slice(0, 7) : String(year)
  const rows = (await loadYear(kind, year, access.approver)).filter((r) => r.day.startsWith(prefix))
  const period =
    scope === 'day' ? day : scope === 'month' ? `${MONTHS[Number(day.slice(5, 7)) - 1]} ${year}` : `January to December ${year}`

  const out: string[] = []
  out.push(line([info.title]))
  out.push(line(['Period', period]))
  out.push(line(['Approver', access.approver === 'all' ? 'All approvers' : access.name(access.approver)]))
  out.push(line(['Downloaded', new Date().toLocaleString('en-PH', { timeZone: 'Asia/Manila' }) + ' by ' + access.me.full_name]))
  out.push('')
  const amountCols = ['Currency', 'Amount']
  out.push(
    line([
      'Date', 'Time', kind === 'funding' ? 'Ref no.' : 'REQ No.', 'Payee', 'Type',
      kind === 'funding' ? 'Payment method' : 'Payment type', info.accountLabel,
      ...(kind === 'funding' ? ['Cheque no.'] : []), 'Approved by', ...amountCols,
    ]),
  )
  for (const r of rows) {
    out.push(
      line([
        r.day, timeManila(r.approvedAt), r.ref, r.payee, r.type, r.method, r.account,
        ...(kind === 'funding' ? [r.cheque] : []), r.approver, r.currency, r.amount.toFixed(2),
      ]),
    )
  }
  out.push('')

  const group = (key: (d: string) => string, label: (k: string) => string, title: string) => {
    const keys = [...new Set(rows.map((r) => key(r.day)))].sort()
    out.push(line([title, 'Requests', 'Total']))
    for (const k of keys) {
      const rs = rows.filter((r) => key(r.day) === k)
      out.push(line([label(k), rs.length, fmtTotals(sumRows(rs))]))
    }
    out.push('')
  }
  if (scope !== 'day') group((d) => d, (d) => d, 'Subtotal per day')
  if (scope === 'year') group((d) => d.slice(0, 7), (m) => MONTHS[Number(m.slice(5)) - 1], 'Total per month')
  out.push(line([scope === 'day' ? 'Subtotal for the day' : scope === 'month' ? 'Month total' : 'Year total', rows.length, fmtTotals(sumRows(rows))]))

  const body = '﻿' + out.join('\r\n') + '\r\n'
  return new Response(body, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${info.file}-${prefix}.csv"`,
      'Cache-Control': 'no-store',
    },
  })
}
