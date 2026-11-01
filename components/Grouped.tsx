import Link from 'next/link'
import { FRTable, PRTable } from './Tables'
import { fmtTotals } from '@/lib/summary'
import { PR_KIND_LABEL, frRegionOf } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

// Requests split by region (NCR / VisMin) and, inside each, by kind:
// Regular fund request (check payment), Auto debit request, Reimbursables (Ruth, 1 November).

export type Region = 'NCR' | 'VisMin'
export const REGIONS: Region[] = ['NCR', 'VisMin']
type Kind = 'regular' | 'auto' | 'reimb'
const KIND_LABEL: Record<Kind, string> = {
  regular: PR_KIND_LABEL.regular,
  auto: PR_KIND_LABEL.auto_debit,
  reimb: PR_KIND_LABEL.reimbursable,
}

export const prRegion = (r: PaymentRequest): Region => (r.region === 'VisMin' ? 'VisMin' : 'NCR')
const prKind = (r: PaymentRequest): Kind =>
  r.request_kind === 'auto_debit' ? 'auto' : r.request_kind === 'reimbursable' || r.reimbursable ? 'reimb' : 'regular'
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
}: {
  rows: PaymentRequest[]
  name: (id: string | null) => string
  regions?: Region[]
  canDelete?: (r: PaymentRequest) => boolean
  canEdit?: (r: PaymentRequest) => boolean
}) {
  const kinds: Kind[] = ['regular', 'auto', 'reimb']
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
              const total = fmtTotals(rs.reduce<Record<string, number>>((t, r) => ({ ...t, [r.currency]: (t[r.currency] ?? 0) + Number(r.total_due ?? 0) }), {}))
              return (
                <Group key={k} title={KIND_LABEL[k]} count={rs.length} total={total}>
                  {rs.length > 0 && <PRTable rows={rs} name={name} canDelete={canDelete} canEdit={canEdit} />}
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
}: {
  rows: FundRequest[]
  regions?: Region[]
  canDelete?: (f: FundRequest) => boolean
  canEdit?: (f: FundRequest) => boolean
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
                  {rs.length > 0 && <FRTable rows={rs} canDelete={canDelete} canEdit={canEdit} />}
                </Group>
              )
            })}
          </section>
        )
      })}
    </>
  )
}
