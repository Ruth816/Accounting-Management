export { money } from './calc'

const TZ = 'Asia/Manila'

export function fmtDate(v: string | null | undefined) {
  if (!v) return ''
  const d = v.length === 10 ? new Date(v + 'T00:00:00+08:00') : new Date(v)
  return d.toLocaleDateString('en-PH', { timeZone: TZ, year: 'numeric', month: 'short', day: 'numeric' })
}

export function fmtDateTime(v: string | null | undefined) {
  if (!v) return ''
  return new Date(v).toLocaleString('en-PH', {
    timeZone: TZ,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}
