import { STATUS_LABEL } from '@/lib/labels'
import { fmtDateTime } from '@/lib/format'
import type { AuditEntry } from '@/lib/types'

// Status tracker (spec 7): every step, who acted and when.
export function Tracker({ entries, name }: { entries: AuditEntry[]; name: (id: string | null) => string }) {
  if (!entries.length) return <p className="muted">No activity yet.</p>
  return (
    <ol className="tracker">
      {entries.map((e) => (
        <li key={e.id}>
          <div className="tracker-head">
            <strong>{e.action}</strong>
            {e.new_status && <span className="muted"> → {STATUS_LABEL[e.new_status]}</span>}
          </div>
          <div className="muted small">
            {name(e.actor_id) || 'System'} · {fmtDateTime(e.created_at)}
            {e.fund_request_id && e.ref ? ` · ${e.ref}` : ''}
          </div>
          {e.note && <div className="small">{e.note}</div>}
        </li>
      ))}
    </ol>
  )
}
