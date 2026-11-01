import { getDirectory, getMe } from '@/lib/auth'
import { FRTable, PRTable } from './Tables'
import type { FundRequest, PaymentRequest } from '@/lib/types'

// Payment requests in the given statuses that the user may see. Other people's drafts stay hidden.
export async function PaymentRequestList({ title, sub, statuses }: { title: string; sub: string; statuses: string[] }) {
  const { supabase, me } = await getMe()
  const { name } = await getDirectory()
  const { data } = await supabase
    .from('payment_requests')
    .select('*')
    .in('status', statuses)
    .or(`status.neq.draft,requestor_id.eq.${me.id}`)
    .order('updated_at', { ascending: false })
    .limit(200)
  const rows = (data ?? []) as PaymentRequest[]
  return (
    <div className="stack">
      <div>
        <h1 className="page-title">{title}</h1>
        <p className="page-sub">{sub}</p>
      </div>
      <section className="card">
        <PRTable rows={rows} name={name} empty="Nothing here yet." />
      </section>
    </div>
  )
}

export async function FundRequestList({ title, sub, statuses }: { title: string; sub: string; statuses: string[] }) {
  const { supabase } = await getMe()
  const { data } = await supabase
    .from('fund_requests')
    .select('*')
    .in('status', statuses)
    .order('updated_at', { ascending: false })
    .limit(200)
  const rows = (data ?? []) as FundRequest[]
  return (
    <div className="stack">
      <div>
        <h1 className="page-title">{title}</h1>
        <p className="page-sub">{sub}</p>
      </div>
      <section className="card">
        <FRTable rows={rows} empty="Nothing here yet." />
      </section>
    </div>
  )
}
