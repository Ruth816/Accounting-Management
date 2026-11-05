import { STATUS_LABEL, STATUS_TONE, frStatusLabel } from '@/lib/labels'
import type { Status } from '@/lib/types'

export function StatusBadge({ status }: { status: Status }) {
  return <span className={`badge ${STATUS_TONE[status]}`}>{STATUS_LABEL[status]}</span>
}

// A fund request's status, including its funding stage after approval.
export function FRStatusBadge({ f }: { f: { status: Status; ready_for_funding_at?: string | null; funded_at?: string | null } }) {
  return <span className={`badge ${STATUS_TONE[f.status]}`}>{frStatusLabel(f)}</span>
}
