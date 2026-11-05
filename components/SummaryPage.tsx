import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PrintButton } from './PrintButton'
import { StatusBadge } from './StatusBadge'
import { POST_QB_FORM, PostQbForm, QB_CONFIRM } from './PostQbForm'
import { ActionForm, Submit } from './ActionForm'
import { requestAction } from '@/app/actions'
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
  const showCheque = true
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
          <div className="stat-label">Requests {info.verb} that day</div>
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

      {kind === 'funding' ? (
        <FundingDay day={day} rows={dayRows} canAct={canPost} />
      ) : (
      <section className="card">
        <h2>{info.verb === 'exported' ? 'Exported' : 'Approved'} on {fmtDate(day)}</h2>
        {canPost && <PostQbForm count={postCount} />}
        {dayRows.length === 0 ? (
          <p className="muted">Nothing was {info.verb} on this day.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{canPost ? '' : '#'}</th>
                  <th>Time</th>
                  <th>Ref no.</th>
                  <th>Payee</th>
                  <th>Type</th>
                  <th>Payment method</th>
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
                      {r.currency === 'PHP' ? '' : r.currency + ' '}
                      {money(r.amount)}
                    </td>
                    <td>
                      <StatusBadge status={r.status} />
                    </td>
                    <td className="no-print row-actions">
                      {postable(r) && (
                        <button type="submit" form={POST_QB_FORM} name="one" value={r.id} className="btn small">
                          Export to QuickBooks
                        </button>
                      )}
                      {['approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed'].includes(r.status) && (
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
      )}

      <section className="card">
        <h2>
          Per day, {MONTHS[Number(month.slice(5)) - 1]} {year}
        </h2>
        {days.length === 0 ? (
          <p className="muted">Nothing {info.verb} this month.</p>
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

const REGIONS = ['NCR', 'VisMin'] as const

// Ready for funding (Ruth, 5 November): the day's requests grouped by region, then by
// type of request, with only the ref no., items covered, date and amount, and
// a total for each group and for the day. Each region's total carries the next
// step, per region (Ruth, 5 November): Mark as funded, then Ready to import to QuickBooks.
function FundingDay({ day, rows, canAct }: { day: string; rows: SummaryRow[]; canAct: boolean }) {
  const voucherOk = (r: SummaryRow) => ['approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed'].includes(r.status)
  const open = (r: SummaryRow) => r.status === 'approved_ready_for_qb' || r.status === 'sync_failed'
  const stage = (r: SummaryRow) => (r.status === 'approved_posted_to_qb' ? 'Imported to QuickBooks' : r.funded ? 'Funded' : 'Not yet funded')
  return (
    <section className="card">
      <div className="req-group-head">
        <h2>Ready for funding on {fmtDate(day)}</h2>
        <span className="req-group-total">Total for the day: {fmtTotals(sumRows(rows))}</span>
      </div>
      {rows.length === 0 && (
        <p className="muted">Nothing was made ready for funding on this day. Use Ready for funding on the Fund approved page.</p>
      )}
      {REGIONS.map((region) => {
        const rr = rows.filter((r) => r.region === region)
        if (!rr.length) return null
        const types = [...new Set(rr.map((r) => r.type))].sort()
        return (
          <div key={region} className="req-group">
            <div className="req-group-head">
              <h3 className="region-title">{region}</h3>
              <span className="req-group-total">
                {region} total ({rr.length}): {fmtTotals(sumRows(rr))}
              </span>
            </div>
            {types.map((type) => {
              const tr = rr.filter((r) => r.type === type)
              return (
                <div key={type} className="funding-type">
                  <h4>{type}</h4>
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Ref no.</th>
                          <th>Request no.</th>
                          <th className="num">No. of items</th>
                          <th>Items covered</th>
                          <th>Payment date</th>
                          <th className="num">Amount (PHP)</th>
                          <th>Stage</th>
                          <th className="no-print" aria-label="Voucher" />
                        </tr>
                      </thead>
                      <tbody>
                        {tr.map((r) => (
                          <tr key={r.id}>
                            <td>
                              <Link href={r.href}>{r.ref || 'No Ref no.'}</Link>
                            </td>
                            <td>{r.reqNo || '–'}</td>
                            <td className="num">{r.itemCount}</td>
                            <td>{r.itemNo ? `Item ${r.itemNo}` : '–'}</td>
                            <td>{r.payDate ? fmtDate(r.payDate) : '–'}</td>
                            <td className="num">{money(r.amount)}</td>
                            <td className="small muted">{stage(r)}</td>
                            <td className="no-print">
                              {voucherOk(r) && (
                                <Link className="btn secondary small" href={`${r.href}/voucher`}>
                                  Voucher
                                </Link>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                      <tfoot>
                        <tr className="total-row">
                          <td colSpan={5} className="num">
                            {type} total ({tr.length})
                          </td>
                          <td className="num">{fmtTotals(sumRows(tr))}</td>
                          <td colSpan={2} />
                        </tr>
                      </tfoot>
                    </table>
                  </div>
                </div>
              )
            })}
            <RegionSteps region={region} day={day} rows={rr} canAct={canAct} />
          </div>
        )
      })}
      {rows.length > 0 && (
        <div className="funding-day-total">
          <div className="req-group-head">
            <strong>Grand total for {fmtDate(day)} ({rows.length})</strong>
            <strong className="req-group-total">{fmtTotals(sumRows(rows))}</strong>
          </div>
        </div>
      )}
    </section>
  )
}

function RegionSteps({ region, day, rows, canAct }: { region: string; day: string; rows: SummaryRow[]; canAct: boolean }) {
  const open = (r: SummaryRow) => r.status === 'approved_ready_for_qb' || r.status === 'sync_failed'
  const toFund = rows.filter((r) => open(r) && !r.funded)
  const toImport = rows.filter((r) => open(r) && r.funded)
  const imported = rows.filter((r) => r.status === 'approved_posted_to_qb')
  return (
    <div className="row no-print funding-steps">
      {canAct && toFund.length > 0 && (
        <ActionForm
          action={requestAction}
          hidden={{ op: 'mark_funded', ids: toFund.map((r) => r.id).join(',') }}
          confirm={`Mark ${toFund.length} ${region} request(s) for ${fmtDate(day)} as funded (${fmtTotals(sumRows(toFund))})?`}
        >
          <Submit className="btn">
            Mark {region} as funded · {fmtTotals(sumRows(toFund))}
          </Submit>
        </ActionForm>
      )}
      {canAct && toImport.length > 0 && (
        <ActionForm
          action={requestAction}
          hidden={{ op: 'import_qb', ids: toImport.map((r) => r.id).join(',') }}
          confirm={`${QB_CONFIRM} (${toImport.length} ${region} request(s))`}
        >
          <Submit className="btn">
            Ready to import {region} to QuickBooks ({toImport.length})
          </Submit>
        </ActionForm>
      )}
      {toFund.length === 0 && toImport.length === 0 && imported.length > 0 && (
        <span className="badge good">{region} funded and imported to QuickBooks</span>
      )}
    </div>
  )
}
