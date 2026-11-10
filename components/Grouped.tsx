import Link from 'next/link'
import { FRTable, PRTable } from './Tables'
import { fmtTotals } from '@/lib/summary'
import { type FREditMode, PR_KIND_LABEL, frRegionOf } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

// Requests split by region (NCR / VisMin) and, inside each, by kind:
// Regular fund request (check payment), Auto debit request, Reimbursables (Ruth, 1 November).

export type Region = 'NCR' | 'VisMin'
export const REGIONS: Region[] = ['NCR', 'VisMin']
type Kind = 'regular' | 'auto' | 'reimb' | 'rfp'
const KIND_LABEL: Record<Kind, string> = {
  regular: PR_KIND_LABEL.regular,
  auto: PR_KIND_LABEL.auto_debit,
  reimb: PR_KIND_LABEL.reimbursable,
  rfp: PR_KIND_LABEL.request_for_payment,
}

export const prRegion = (r: PaymentRequest): Region => (r.region === 'VisMin' ? 'VisMin' : 'NCR')
const prKind = (r: PaymentRequest): Kind =>
  r.request_kind === 'request_for_payment' ? 'rfp' : r.request_kind === 'auto_debit' ? 'auto' : r.request_kind === 'reimbursable' || r.reimbursable ? 'reimb' : 'regular'
// Fund request types: 1 auto debit, 2 NCR regular, 3 VisMin regular,
// 4 NCR reimbursable, 5 VisMin reimbursable. Region comes from the payment
// request; a standalone auto debit or check payment request has none and is listed under NCR.
export const frRegion = (f: FundRequest): Region => frRegionOf(f)
const frKind = (f: FundRequest): Kind => (f.request_type === 1 ? 'auto' : f.request_type >= 4 ? 'reimb' : 'regular')

export function parseRegion(v: string | undefined): Region | 'all' {
  return v === 'NCR' || v === 'VisMin' ? v : 'all'
}

// Tabs: All / NCR / VisMin, as links that keep the current page.
export function RegionTabs({ base, current, counts }: { base: string; current: Region | 'all'; counts: Record<Region | 'all', number> }) {
  const tabs: (Region | 'all')[] = ['all', ...REGIONS]
  return (
    <nav className="region-tabs" aria-label="Region">
      {tabs.map((t) => (
        <Link key={t} href={t === 'all' ? base : `${base}?region=${t}`} className={`region-tab${t === current ? ' active' : ''}`}>
          {t === 'all' ? 'All' : t} <span className="tab-count">{counts[t]}</span>
        </Link>
      ))}
    </nav>
  )
}

function Group({ title, count, total, children }: { title: string; count: number; total: string; children: React.ReactNode }) {
  return (
    <div className="req-group">
      <div className="req-group-head">
        <h3>
          {title} <span className="tab-count">{count}</span>
        </h3>
        {count > 0 && <span className="req-group-total">Subtotal {total}</span>}
      </div>
      {children}
    </div>
  )
}

export function GroupedPR({
  rows,
  name,
  regions = REGIONS,
  canDelete,
  canEdit,
  canApprove,
}: {
  rows: PaymentRequest[]
  name: (id: string | null) => string
  regions?: Region[]
  canDelete?: (r: PaymentRequest) => boolean
  canEdit?: (r: PaymentRequest) => boolean
  canApprove?: (r: PaymentRequest) => boolean
}) {
  const kinds: Kind[] = ['rfp', 'regular', 'auto', 'reimb']
  return (
    <>
      {regions.map((reg) => {
        const inRegion = rows.filter((r) => prRegion(r) === reg)
        return (
          <section key={reg} className="card region-card">
            <h2 className="region-title">
              {reg} <span className="tab-count">{inRegion.length}</span>
            </h2>
            {kinds.map((k) => {
              const rs = inRegion.filter((r) => prKind(r) === k)
              // Payment requests are now all Requests for payment; the older types show only while they have requests.
              if (k !== 'rfp' && rs.length === 0) return null
              const total = fmtTotals(rs.reduce<Record<string, number>>((t, r) => ({ ...t, [r.currency]: (t[r.currency] ?? 0) + Number(r.total_due ?? 0) }), {}))
              return (
                <Group key={k} title={KIND_LABEL[k]} count={rs.length} total={total}>
                  {rs.length > 0 && <PRTable rows={rs} name={name} canDelete={canDelete} canEdit={canEdit} canApprove={canApprove} />}
                </Group>
              )
            })}
          </section>
        )
      })}
    </>
  )
}

export function GroupedFR({
  rows,
  regions = REGIONS,
  canDelete,
  canEdit,
  canApprove,
  canVoucher,
}: {
  rows: FundRequest[]
  regions?: Region[]
  canApprove?: (f: FundRequest) => boolean
  canDelete?: (f: FundRequest) => boolean
  canEdit?: (f: FundRequest) => FREditMode
  canVoucher?: (f: FundRequest) => boolean
}) {
  const kinds: Kind[] = ['regular', 'auto', 'reimb']
  return (
    <>
      {regions.map((reg) => {
        const inRegion = rows.filter((f) => frRegion(f) === reg)
        return (
          <section key={reg} className="card region-card">
            <h2 className="region-title">
              {reg} <span className="tab-count">{inRegion.length}</span>
            </h2>
            {kinds.map((k) => {
              const rs = inRegion.filter((f) => frKind(f) === k)
              const total = fmtTotals({ PHP: rs.reduce((t, f) => t + Number(f.amount_php ?? 0), 0) })
              return (
                <Group key={k} title={KIND_LABEL[k]} count={rs.length} total={total}>
                  {rs.length > 0 && <FRTable rows={rs} canDelete={canDelete} canEdit={canEdit} canApprove={canApprove} canVoucher={canVoucher} />}
                </Group>
              )
            })}
          </section>
        )
      })}
    </>
  )
}

// Dashboard queues: count and total per region and type, each linking to the
// page that lists the requests in full (Ruth, 5 November).
function QueueSummary({ lines, base }: { lines: { region: Region; kind: Kind; count: number; total: string }[]; base: string }) {
  const shown = lines.filter((l) => l.count > 0)
  if (!shown.length) return null
  return (
    <div className="table-wrap">
      <table className="stack-mobile">
        <thead>
          <tr>
            <th>Region</th>
            <th>Type</th>
            <th className="num">No.</th>
            <th className="num">Total</th>
            <th aria-label="Open" />
          </tr>
        </thead>
        <tbody>
          {shown.map((l) => (
            <tr key={`${l.region}-${l.kind}`}>
              <td data-label="Region">{l.region}</td>
              <td data-label="Type">{KIND_LABEL[l.kind]}</td>
              <td className="num" data-label="No.">{l.count}</td>
              <td className="num" data-label="Total">{l.total}</td>
              <td data-label="">
                <Link className="btn small secondary" href={`${base}?region=${l.region}`}>
                  Open list
                </Link>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

const KINDS: Kind[] = ['regular', 'auto', 'reimb']

export function SummaryPR({ rows, base }: { rows: PaymentRequest[]; base: string }) {
  const lines = REGIONS.flatMap((region) =>
    KINDS.map((kind) => {
      const rs = rows.filter((r) => prRegion(r) === region && prKind(r) === kind)
      const total = fmtTotals(rs.reduce<Record<string, number>>((t, r) => ({ ...t, [r.currency]: (t[r.currency] ?? 0) + Number(r.total_due ?? 0) }), {}))
      return { region, kind, count: rs.length, total }
    }),
  )
  return <QueueSummary lines={lines} base={base} />
}

export function SummaryFR({ rows, base }: { rows: FundRequest[]; base: string }) {
  const lines = REGIONS.flatMap((region) =>
    KINDS.map((kind) => {
      const rs = rows.filter((f) => frRegion(f) === region && frKind(f) === kind)
      return { region, kind, count: rs.length, total: fmtTotals({ PHP: rs.reduce((t, f) => t + Number(f.amount_php ?? 0), 0) }) }
    }),
  )
  return <QueueSummary lines={lines} base={base} />
}
