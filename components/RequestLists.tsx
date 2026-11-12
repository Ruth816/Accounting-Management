import Link from 'next/link'
import { notFound } from 'next/navigation'
import { BulkApproveForm } from './BulkApproveForm'
import { fmtDate } from '@/lib/format'
import { todayManila } from '@/lib/summary'
import { getDirectory, getMe } from '@/lib/auth'
import { GroupedFR, GroupedPR, REGIONS, RegionTabs, type Region, frRegion, parseRegion, prRegion } from './Grouped'
import { FR_OPEN_STATUSES, PR_DELETABLE, PR_DELETABLE_BY_SELF_APPROVER, canSeeVoucher, canSubmitApprove, frEditMode } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

// Payment requests in the given statuses that the user may see. Other people's drafts stay hidden.
// Requestors (not approvers or Admins) don't see an empty region section.
const shown = (withRows: Region[], limited: boolean): Region[] => (!limited ? REGIONS : withRows.length ? withRows : REGIONS.slice(0, 1))

type ListProps = { title: string; sub: string; statuses: string[]; base: string; region?: string }
type PRListProps = ListProps & { byApprovalDay?: boolean; date?: string; by?: string }

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/
const shiftDay = (day: string, n: number) => {
  const d = new Date(day + 'T00:00:00Z')
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

export async function PaymentRequestList({ title, sub, statuses, base, region, byApprovalDay, date, by }: PRListProps) {
  const { supabase, me, is, myRegion, limited } = await getMe()
  const { name } = await getDirectory()
  const day = byApprovalDay && date && DAY_RE.test(date) && !Number.isNaN(Date.parse(date)) ? date : null
  let q = supabase
    .from('payment_requests')
    .select('*')
    .in('status', statuses)
    .or(`status.neq.draft,requestor_id.eq.${me.id}`)
  // The approval day in Philippine time; a VisMin first approver's day counts too.
  const from = day ? `${day}T00:00:00+08:00` : ''
  const to = day ? `${shiftDay(day, 1)}T00:00:00+08:00` : ''
  if (day) q = q.or(`and(approved_on.gte.${from},approved_on.lt.${to}),and(first_approved_on.gte.${from},first_approved_on.lt.${to})`)
  const { data } = await q.order(byApprovalDay ? 'approved_on' : 'updated_at', { ascending: false }).limit(day ? 1000 : 200)
  const inDay = (iso: string | null) => !day || (!!iso && Date.parse(iso) >= Date.parse(from) && Date.parse(iso) < Date.parse(to))
  // Payment approved shows every approved request in the region, by anyone; "Approved by"
  // narrows it to one approver, e.g. "Me" (Ruth, 12 November).
  const approvedBy = (r: PaymentRequest, id: string) =>
    (r.approver_id === id && inDay(r.approved_on)) || (r.first_approver_id === id && inDay(r.first_approved_on))
  const allRows = ((data ?? []) as PaymentRequest[])
    .filter((r) => !myRegion || prRegion(r) === myRegion)
    .filter((r) => !day || inDay(r.approved_on) || inDay(r.first_approved_on))
  const approverIds = [...new Set(allRows.flatMap((r) => [r.approver_id, r.first_approver_id]).filter((x): x is string => !!x))]
  const who = byApprovalDay && by && (by === me.id || approverIds.includes(by)) ? by : null
  const rows = who ? allRows.filter((r) => approvedBy(r, who)) : allRows
  const reg = myRegion ?? parseRegion(region)

  // With an approval route for the region, only the request's own approver may approve it;
  // without one, any Payment Approver may (the same rule as the database).
  const { data: routes } = await supabase.from('approval_routes').select('region')
  const routed = new Set((routes ?? []).map((x: { region: string }) => x.region))
  const canApprove = (r: PaymentRequest) =>
    // Only a Payment Approver approves; an Admin views only (Ruth, 10 November).
    !is('admin') &&
    is('payment_approver') &&
    r.status === 'pending_payment_approval' &&
    r.requestor_id !== me.id &&
    r.first_approver_id !== me.id &&
    // VisMin always goes Jonathan (approver 1), then Hoe Ming (approver 2) (Ruth, 12 November).
    (r.approver_id === me.id || (!routed.has(r.region ?? 'NCR') && r.region !== 'VisMin'))
  const visibleRegions = reg === 'all' ? shown(REGIONS.filter((g) => rows.some((r) => prRegion(r) === g)), limited) : [reg]
  const approvable = rows.filter((r) => visibleRegions.includes(prRegion(r)) && canApprove(r)).length
  const dayQ = (d: string | null) => {
    const p = new URLSearchParams()
    if (d) p.set('date', d)
    if (who) p.set('by', who)
    if (reg !== 'all' && !myRegion) p.set('region', reg)
    const s = p.toString()
    return s ? `${base}?${s}` : base
  }

  return (
    <div className="stack">
      <div>
        <h1 className="page-title">{title}</h1>
        <p className="page-sub">{sub}</p>
      </div>
      {myRegion || limited ? (
        myRegion && <p className="muted">Showing {myRegion} requests only.</p>
      ) : (
      <RegionTabs
        base={day || who ? `${base}?${new URLSearchParams({ ...(day ? { date: day } : {}), ...(who ? { by: who } : {}) })}` : base}
        current={reg}
        counts={{ all: rows.length, NCR: rows.filter((r) => prRegion(r) === 'NCR').length, VisMin: rows.filter((r) => prRegion(r) === 'VisMin').length }}
      />
      )}
      {byApprovalDay && (
        <form className="card row summary-controls" method="get" action={base}>
          {reg !== 'all' && !myRegion && <input type="hidden" name="region" value={reg} />}
          <label className="field">
            <span className="label">Approval date</span>
            <input type="date" name="date" defaultValue={day ?? ''} />
          </label>
          <label className="field">
            <span className="label">Approved by</span>
            <select name="by" defaultValue={who ?? ''}>
              <option value="">Everyone</option>
              {is('payment_approver') && !is('admin') && <option value={me.id}>Me</option>}
              {approverIds
                .filter((id) => id !== me.id || is('admin'))
                .map((id) => ({ id, n: name(id) }))
                .sort((x, y) => x.n.localeCompare(y.n))
                .map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.n || 'Unknown'}
                  </option>
                ))}
            </select>
          </label>
          <button className="btn" type="submit">
            Show
          </button>
          <span className="row">
            {day && (
              <Link className="btn secondary small" href={dayQ(shiftDay(day, -1))}>
                ← Previous day
              </Link>
            )}
            <Link className="btn secondary small" href={dayQ(todayManila())}>
              Today
            </Link>
            {day && (
              <Link className="btn secondary small" href={dayQ(shiftDay(day, 1))}>
                Next day →
              </Link>
            )}
            {day && (
              <Link className="btn secondary small" href={dayQ(null)}>
                All dates
              </Link>
            )}
          </span>
        </form>
      )}
      {byApprovalDay && (
        <p className="muted">
          {who === me.id ? 'Requests you approved' : who ? `Requests approved by ${name(who)}` : 'Approved requests'}
          {day ? ` on ${fmtDate(day)}: ${rows.length}.` : ', latest approval first.'}
        </p>
      )}
      {!byApprovalDay && <BulkApproveForm count={approvable} />}
      <GroupedPR
        rows={rows}
        name={name}
        regions={visibleRegions}
        showApprovedOn={byApprovalDay}
        canDelete={(r) =>
          // Admins view other people's payment requests only (Ruth, 10 November).
          (PR_DELETABLE.includes(r.status) && r.requestor_id === me.id) ||
          (is('admin') && PR_DELETABLE_BY_SELF_APPROVER.includes(r.status) && r.requestor_id === me.id && r.approver_id === me.id)
        }
        canEdit={(r) =>
          (r.requestor_id === me.id && ['draft', 'pending_payment_approval', 'returned_to_requestor'].includes(r.status)) ||
          (is('admin') && r.requestor_id === me.id && !['cancelled', 'expired', 'approved_posted_to_qb'].includes(r.status))
        }
        canApprove={canApprove}
      />
    </div>
  )
}

export async function FundRequestList({ title, sub, statuses, base, region }: ListProps) {
  const { supabase, me, is, myRegion, limited } = await getMe()
  if (!(is('fund_requestor') || is('fund_approver') || is('admin'))) notFound()
  const mayDelete = is('fund_requestor') || is('admin')
  const { data } = await supabase
    .from('fund_requests')
    .select('*')
    .in('status', statuses)
    .order('updated_at', { ascending: false })
    .limit(200)
  const rows = ((data ?? []) as FundRequest[]).filter((f) => !myRegion || frRegion(f) === myRegion)
  const reg = myRegion ?? parseRegion(region)
  return (
    <div className="stack">
      <div>
        <h1 className="page-title">{title}</h1>
        <p className="page-sub">{sub}</p>
      </div>
      {myRegion || limited ? (
        myRegion && <p className="muted">Showing {myRegion} requests only.</p>
      ) : (
      <RegionTabs
        base={base}
        current={reg}
        counts={{ all: rows.length, NCR: rows.filter((f) => frRegion(f) === 'NCR').length, VisMin: rows.filter((f) => frRegion(f) === 'VisMin').length }}
      />
      )}
      <GroupedFR
        rows={rows}
        regions={reg === 'all' ? shown(REGIONS.filter((g) => rows.some((f) => frRegion(f) === g)), limited) : [reg]}
        canDelete={(f) => mayDelete && !f.locked && FR_OPEN_STATUSES.includes(f.status)}
        canEdit={(f) => frEditMode(f, is, me.id)}
        canApprove={(f) => (is('fund_approver') && f.status === 'pending_fund_approval' && (f.fund_approver_id === me.id || f.fund_requestor_id === me.id || is('admin'))) || canSubmitApprove(f, is, me.id)}
        canVoucher={(f) => canSeeVoucher(f, is)}
      />
    </div>
  )
}
