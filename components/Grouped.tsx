import Link from 'next/link'
import { FRTable, PRTable } from './Tables'
import { fmtTotals } from '@/lib/summary'
import type { FundRequest, PaymentRequest } from '@/lib/types'

// Requests split by region (NCR / VisMin) and, inside each, by kind:
// Regular fund request (check payment), Auto debit request, Reimbursables (Ruth, 1 November).

export type Region = 'NCR' | 'VisMin'
export const REGIONS: Region[] = ['NCR', 'VisMin']
type Kind = 'regular' | 'auto' | 'reimb'
const KIND_LABEL: Record<Kind, string> = {
  regular: 'Regular fund request (check payment)',
  auto: 'Auto debit request',
  reimb: 'Reimbursables',
}

export const prRegion = (r: PaymentRequest): Region => (r.region === 'VisMin' ? 'VisMin' : 'NCR')
const prKind = (r: PaymentRequest): Kind => (r.reimbursable ? 'reimb' : 'regular')
// Fund request types: 1 auto debit (no region; listed under NCR), 2 NCR regular,
// 3 VisMin regular, 4 NCR reimbursable, 5 VisMin reimbursable.
export const frRegion = (f: FundRequest): Region => (f.request_type === 3 || f.request_type === 5 ? 'VisMin' : 'NCR')
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
}: {
  rows: PaymentRequest[]
  name: (id: string | null) => string
  regions?: Region[]
  canDelete?: (r: PaymentRequest) => boolean
}) {
  const kinds: Kind[] = ['regular', 'reimb']
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
                  {rs.length > 0 && <PRTable rows={rs} name={name} canDelete={canDelete} />}
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
}: {
  rows: FundRequest[]
  regions?: Region[]
  canDelete?: (f: FundRequest) => boolean
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
              if (k === 'auto' && reg === 'VisMin' && !rs.length) return null
              const total = fmtTotals({ PHP: rs.reduce((t, f) => t + Number(f.amount_php ?? 0), 0) })
              return (
                <Group key={k} title={KIND_LABEL[k]} count={rs.length} total={total}>
                  {rs.length > 0 && <FRTable rows={rs} canDelete={canDelete} />}
                </Group>
              )
            })}
          </section>
        )
      })}
    </>
  )
}
