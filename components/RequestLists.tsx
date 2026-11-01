import { notFound } from 'next/navigation'
import { getDirectory, getMe } from '@/lib/auth'
import { GroupedFR, GroupedPR, REGIONS, RegionTabs, frRegion, parseRegion, prRegion } from './Grouped'
import { FR_OPEN_STATUSES, PR_DELETABLE } from '@/lib/labels'
import type { FundRequest, PaymentRequest } from '@/lib/types'

// Payment requests in the given statuses that the user may see. Other people's drafts stay hidden.
type ListProps = { title: string; sub: string; statuses: string[]; base: string; region?: string }

export async function PaymentRequestList({ title, sub, statuses, base, region }: ListProps) {
  const { supabase, me, is } = await getMe()
  const { name } = await getDirectory()
  const { data } = await supabase
    .from('payment_requests')
    .select('*')
    .in('status', statuses)
    .or(`status.neq.draft,requestor_id.eq.${me.id}`)
    .order('updated_at', { ascending: false })
    .limit(200)
  const rows = (data ?? []) as PaymentRequest[]
  const reg = parseRegion(region)
  return (
    <div className="stack">
      <div>
        <h1 className="page-title">{title}</h1>
        <p className="page-sub">{sub}</p>
      </div>
      <RegionTabs
        base={base}
        current={reg}
        counts={{ all: rows.length, NCR: rows.filter((r) => prRegion(r) === 'NCR').length, VisMin: rows.filter((r) => prRegion(r) === 'VisMin').length }}
      />
      <GroupedPR
        rows={rows}
        name={name}
        regions={reg === 'all' ? REGIONS : [reg]}
        canDelete={(r) => PR_DELETABLE.includes(r.status) && (r.requestor_id === me.id || is('admin'))}
        canEdit={(r) => (r.requestor_id === me.id || is('admin')) && ['draft', 'pending_payment_approval', 'returned_to_requestor'].includes(r.status)}
      />
    </div>
  )
}

export async function FundRequestList({ title, sub, statuses, base, region }: ListProps) {
  const { supabase, is } = await getMe()
  if (!(is('fund_requestor') || is('fund_approver') || is('admin'))) notFound()
  const mayDelete = is('fund_requestor') || is('admin')
  const { data } = await supabase
    .from('fund_requests')
    .select('*')
    .in('status', statuses)
    .order('updated_at', { ascending: false })
    .limit(200)
  const rows = (data ?? []) as FundRequest[]
  const reg = parseRegion(region)
  return (
    <div className="stack">
      <div>
        <h1 className="page-title">{title}</h1>
        <p className="page-sub">{sub}</p>
      </div>
      <RegionTabs
        base={base}
        current={reg}
        counts={{ all: rows.length, NCR: rows.filter((f) => frRegion(f) === 'NCR').length, VisMin: rows.filter((f) => frRegion(f) === 'VisMin').length }}
      />
      <GroupedFR
        rows={rows}
        regions={reg === 'all' ? REGIONS : [reg]}
        canDelete={(f) => mayDelete && !f.locked && FR_OPEN_STATUSES.includes(f.status)}
        canEdit={(f) => is('fund_requestor') && !f.locked && FR_OPEN_STATUSES.includes(f.status)}
      />
    </div>
  )
}
