import { STATUS_LABEL, STATUS_TONE } from '@/lib/labels'
import type { Status } from '@/lib/types'

export function StatusBadge({ status }: { status: Status }) {
  return <span className={`badge ${STATUS_TONE[status]}`}>{STATUS_LABEL[status]}</span>
}
