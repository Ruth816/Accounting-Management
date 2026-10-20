import { getDirectory, getMe } from '@/lib/auth'
import { FRTable, PRTable } from '@/components/Tables'
import { REQUEST_TYPE_LABEL, STATUS_LABEL } from '@/lib/labels'
import type { FundRequest, PaymentRequest, Status } from '@/lib/types'

type Q = Partial<Record<'kind' | 'status' | 'from' | 'to' | 'requestor' | 'type' | 'min' | 'max' | 'q', string>>

// Search and filter (spec 7). Row-level security limits results to what
// the user may see.
export default async function SearchPage({ searchParams }: { searchParams: Promise<Q> }) {
  const sp = await searchParams
  const { supabase } = await getMe()
  const { people, name } = await getDirectory()
  const kind = sp.kind === 'fund' ? 'fund' : 'payment'
  const like = (s: string) => `%${s.replace(/[%_,()]/g, ' ')}%`

  let prs: PaymentRequest[] = []
  let frs: FundRequest[] = []
  if (kind === 'payment') {
    let q = supabase.from('payment_requests').select('*').order('created_at', { ascending: false }).limit(200)
    if (sp.status) q = q.eq('status', sp.status)
    if (sp.from) q = q.gte('created_at', `${sp.from}T00:00:00+08:00`)
    if (sp.to) q = q.lte('created_at', `${sp.to}T23:59:59+08:00`)
    if (sp.requestor) q = q.eq('requestor_id', sp.requestor)
    if (sp.min) q = q.gte('total_due', Number(sp.min))
    if (sp.max) q = q.lte('total_due', Number(sp.max))
    if (sp.q) q = q.or(`payable_to.ilike.${like(sp.q)},req_no.ilike.${like(sp.q)}`)
    prs = ((await q).data ?? []) as PaymentRequest[]
  } else {
    let q = supabase.from('fund_requests').select('*').order('created_at', { ascending: false }).limit(200)
    if (sp.status) q = q.eq('status', sp.status)
    if (sp.from) q = q.gte('created_at', `${sp.from}T00:00:00+08:00`)
    if (sp.to) q = q.lte('created_at', `${sp.to}T23:59:59+08:00`)
    if (sp.requestor) q = q.eq('fund_requestor_id', sp.requestor)
    if (sp.type) q = q.eq('request_type', Number(sp.type))
    if (sp.min) q = q.gte('amount_php', Number(sp.min))
    if (sp.max) q = q.lte('amount_php', Number(sp.max))
    if (sp.q) q = q.or(`payee.ilike.${like(sp.q)},ref_no.ilike.${like(sp.q)}`)
    frs = ((await q).data ?? []) as FundRequest[]
  }

  return (
    <div className="stack">
      <h1>Search</h1>
      <form className="card filters" method="get">
        <label className="field">
          <span className="label">Look in</span>
          <select name="kind" defaultValue={kind}>
            <option value="payment">Payment requests</option>
            <option value="fund">Fund requests</option>
          </select>
        </label>
        <label className="field">
          <span className="label">Payee, REQ No. or Ref no.</span>
          <input name="q" defaultValue={sp.q ?? ''} />
        </label>
        <label className="field">
          <span className="label">Status</span>
          <select name="status" defaultValue={sp.status ?? ''}>
            <option value="">Any</option>
            {(Object.keys(STATUS_LABEL) as Status[]).map((s) => (
              <option key={s} value={s}>
                {STATUS_LABEL[s]}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span className="label">{kind === 'fund' ? 'Prepared by' : 'Requestor'}</span>
          <select name="requestor" defaultValue={sp.requestor ?? ''}>
            <option value="">Anyone</option>
            {people.map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span className="label">Request type (fund requests)</span>
          <select name="type" defaultValue={sp.type ?? ''}>
            <option value="">Any</option>
            {Object.entries(REQUEST_TYPE_LABEL).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span className="label">Created from</span>
          <input type="date" name="from" defaultValue={sp.from ?? ''} />
        </label>
        <label className="field">
          <span className="label">Created to</span>
          <input type="date" name="to" defaultValue={sp.to ?? ''} />
        </label>
        <label className="field">
          <span className="label">Amount from</span>
          <input name="min" inputMode="decimal" defaultValue={sp.min ?? ''} />
        </label>
        <label className="field">
          <span className="label">Amount to</span>
          <input name="max" inputMode="decimal" defaultValue={sp.max ?? ''} />
        </label>
        <div className="actions">
          <button className="btn" type="submit">
            Search
          </button>
        </div>
      </form>
      <section className="card">
        {kind === 'payment' ? <PRTable rows={prs} name={name} empty="No matching requests." /> : <FRTable rows={frs} empty="No matching fund requests." />}
      </section>
    </div>
  )
}
