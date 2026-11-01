import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PrintButton } from './PrintButton'
import { StatusBadge } from './StatusBadge'
import { POST_QB_FORM, PostQbForm } from './PostQbForm'
import { fmtDate, fmtDateTime, money } from '@/lib/format'
import {
  KIND_INFO,
  MONTHS,
  fmtTotals,
  loadYear,
  sumRows,
  summaryAccess,
  timeManila,
  todayManila,
  validDay,
  type SummaryKind,
  type SummaryRow,
} from '@/lib/summary'

type SP = { date?: string; approver?: string }

const shiftDay = (day: string, n: number) => {
  const d = new Date(day + 'T00:00:00Z')
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

export async function SummaryPage({ kind, searchParams }: { kind: SummaryKind; searchParams: Promise<SP> }) {
  const sp = await searchParams
  const info = KIND_INFO[kind]
  const access = await summaryAccess(kind, sp.approver)
  if (!access.allowed) notFound()

  const day = validDay(sp.date)
  const year = Number(day.slice(0, 4))
  const month = day.slice(0, 7)
  const rows = await loadYear(kind, year, access.approver)

  const dayRows = rows.filter((r) => r.day === day)
  const monthRows = rows.filter((r) => r.day.startsWith(month))
  const base = `/summary/${kind}`
  const approverQ = access.isAdmin ? `&approver=${access.approver}` : ''
  const link = (d: string) => `${base}?date=${d}${approverQ}`
  const exportLink = (scope: string) => `${base}/export?scope=${scope}&date=${day}${approverQ}`
  const approverName = access.approver === 'all' ? 'All approvers' : access.name(access.approver)

  // Day subtotals by payment method, so funds can be sent per method.
  const byMethod = new Map<string, SummaryRow[]>()
  for (const r of dayRows) byMethod.set(r.method || 'Not set', [...(byMethod.get(r.method || 'Not set') ?? []), r])

  // Days of the selected month that have approvals.
  const days = [...new Set(monthRows.map((r) => r.day))].sort()
  const showCheque = kind === 'funding'
  const canPost = kind === 'funding' && access.canPost
  const postable = (r: SummaryRow) => canPost && (r.status === 'approved_ready_for_qb' || r.status === 'sync_failed')
  const postCount = dayRows.filter(postable).length

  return (
    <div className="stack summary">
      <div>
        <h1 className="page-title">{info.title}</h1>
        <p className="page-sub">{info.sub}</p>
        <p className="print-only">
          Approver: {approverName} · Printed {fmtDateTime(new Date().toISOString())}
        </p>
      </div>

      <form className="card row summary-controls no-print" method="get">
        <label className="field">
          <span className="label">Day</span>
          <input type="date" name="date" defaultValue={day} />
        </label>
        {access.isAdmin && (
          <label className="field">
            <span className="label">Approver</span>
            <select name="approver" defaultValue={access.approver}>
              <option value="all">All approvers</option>
              {access.approvers.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.full_name}
                </option>
              ))}
            </select>
          </label>
        )}
        <button className="btn" type="submit">
          Show
        </button>
        <span className="row">
          <Link className="btn secondary small" href={link(shiftDay(day, -1))}>
            ← Previous day
          </Link>
          <Link className="btn secondary small" href={link(todayManila())}>
            Today
          </Link>
          <Link className="btn secondary small" href={link(shiftDay(day, 1))}>
            Next day →
          </Link>
        </span>
      </form>

      <div className="row no-print summary-downloads">
        <span className="label">Download for safekeeping (Excel):</span>
        <a className="btn secondary small" href={exportLink('day')}>
          This day
        </a>
        <a className="btn secondary small" href={exportLink('month')}>
          {MONTHS[Number(month.slice(5)) - 1]} {year}
        </a>
        <a className="btn secondary small" href={exportLink('year')}>
          Whole year {year}
        </a>
        <PrintButton />
      </div>

      <div className="stat-grid">
        <div className="stat-card action">
          <div className="stat-value">{fmtTotals(sumRows(dayRows))}</div>
          <div className="stat-label">Subtotal for {fmtDate(day)}</div>
        </div>
        <div className="stat-card">
          <div className="stat-value">{dayRows.length}</div>
          <div className="stat-label">Requests approved that day</div>
        </div>
        <div className="stat-card progress">
          <div className="stat-value">{fmtTotals(sumRows(monthRows))}</div>
          <div className="stat-label">
            Total for {MONTHS[Number(month.slice(5)) - 1]} {year}
          </div>
        </div>
        <div className="stat-card good">
          <div className="stat-value">{fmtTotals(sumRows(rows))}</div>
          <div className="stat-label">Total for {year}</div>
        </div>
      </div>

      <section className="card">
        <h2>Approved on {fmtDate(day)}</h2>
        {canPost && <PostQbForm count={postCount} />}
        {dayRows.length === 0 ? (
          <p className="muted">Nothing was approved on this day.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{canPost ? '' : '#'}</th>
                  <th>Time</th>
                  <th>{kind === 'funding' ? 'Ref no.' : 'REQ No.'}</th>
                  <th>{kind === 'funding' ? 'Payee' : 'Payable to'}</th>
                  <th>Type</th>
                  <th>{kind === 'funding' ? 'Payment method' : 'Payment type'}</th>
                  <th>{info.accountLabel}</th>
                  {showCheque && <th>Cheque no.</th>}
                  {access.approver === 'all' && <th>Approved by</th>}
                  <th className="num">{info.amountLabel}</th>
                  <th>Status</th>
                  <th className="no-print"></th>
                </tr>
              </thead>
              <tbody>
                {dayRows.map((r, i) => (
                  <tr key={r.id}>
                    <td>
                      {postable(r) ? (
                        <input type="checkbox" form={POST_QB_FORM} name="ids" value={r.id} aria-label={`Tick ${r.ref}`} />
                      ) : (
                        i + 1
                      )}
                    </td>
                    <td>{timeManila(r.approvedAt)}</td>
                    <td>
                      <Link href={r.href}>{r.ref || 'No Ref no.'}</Link>
                    </td>
                    <td>{r.payee}</td>
                    <td>{r.type}</td>
                    <td>{r.method}</td>
                    <td>{r.account}</td>
                    {showCheque && <td>{r.cheque}</td>}
                    {access.approver === 'all' && <td>{r.approver}</td>}
                    <td className="num">
                      {r.currency === 'PHP' && kind === 'funding' ? '' : r.currency + ' '}
                      {money(r.amount)}
                    </td>
                    <td>
                      <StatusBadge status={r.status} />
                    </td>
                    <td className="no-print row-actions">
                      {postable(r) && (
                        <button type="submit" form={POST_QB_FORM} name="one" value={r.id} className="btn small">
                          Posted to QuickBooks
                        </button>
                      )}
                      {kind === 'funding' && ['approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed'].includes(r.status) && (
                        <Link className="btn secondary small" href={`${r.href}/voucher`}>
                          Voucher
                        </Link>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                {byMethod.size > 1 &&
                  [...byMethod].map(([m, rs]) => (
                    <tr key={m} className="muted">
                      <td colSpan={showCheque ? 8 : 7} className="num">
                        {m} ({rs.length})
                      </td>
                      {access.approver === 'all' && <td />}
                      <td className="num">{fmtTotals(sumRows(rs))}</td>
                      <td colSpan={2} />
                    </tr>
                  ))}
                <tr className="total-row">
                  <td colSpan={showCheque ? 8 : 7} className="num">
                    Subtotal for the day ({dayRows.length})
                  </td>
                  {access.approver === 'all' && <td />}
                  <td className="num">{fmtTotals(sumRows(dayRows))}</td>
                  <td colSpan={2} />
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </section>

      <section className="card">
        <h2>
          Per day, {MONTHS[Number(month.slice(5)) - 1]} {year}
        </h2>
        {days.length === 0 ? (
          <p className="muted">Nothing approved this month.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Day</th>
                  <th className="num">Requests</th>
                  <th className="num">Subtotal</th>
                </tr>
              </thead>
              <tbody>
                {days.map((d) => {
                  const rs = monthRows.filter((r) => r.day === d)
                  return (
                    <tr key={d} className={d === day ? 'selected' : undefined}>
                      <td>
                        <Link href={link(d)}>{fmtDate(d)}</Link>
                      </td>
                      <td className="num">{rs.length}</td>
                      <td className="num">{fmtTotals(sumRows(rs))}</td>
                    </tr>
                  )
                })}
              </tbody>
              <tfoot>
                <tr className="total-row">
                  <td>Month total</td>
                  <td className="num">{monthRows.length}</td>
                  <td className="num">{fmtTotals(sumRows(monthRows))}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </section>

      <section className="card">
        <h2>Per month, {year}</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Month</th>
                <th className="num">Requests</th>
                <th className="num">Total</th>
              </tr>
            </thead>
            <tbody>
              {MONTHS.map((m, i) => {
                const key = `${year}-${String(i + 1).padStart(2, '0')}`
                const rs = rows.filter((r) => r.day.startsWith(key))
                return (
                  <tr key={m} className={key === month ? 'selected' : undefined}>
                    <td>
                      <Link href={link(`${key}-01`)}>{m}</Link>
                    </td>
                    <td className="num">{rs.length}</td>
                    <td className="num">{rs.length ? fmtTotals(sumRows(rs)) : '–'}</td>
                  </tr>
                )
              })}
            </tbody>
            <tfoot>
              <tr className="total-row">
                <td>Year total</td>
                <td className="num">{rows.length}</td>
                <td className="num">{fmtTotals(sumRows(rows))}</td>
              </tr>
            </tfoot>
          </table>
        </div>
        <p className="no-print row">
          <Link className="btn secondary small" href={link(`${year - 1}-12-31`)}>
            ← {year - 1}
          </Link>
          <Link className="btn secondary small" href={link(`${year + 1}-01-01`)}>
            {year + 1} →
          </Link>
        </p>
      </section>
    </div>
  )
}
