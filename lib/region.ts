// Employee ID prefixes show the region (Ruth, 1 November): NO and NFS (field
// staff) are NCR, VO and VFS (field staff) are VisMin.
export function regionFromEmployeeId(id: string | null | undefined): 'NCR' | 'VisMin' | null {
  const v = (id ?? '').trim().toUpperCase()
  if (/^(NO|NFS)/.test(v)) return 'NCR'
  if (/^(VO|VFS)/.test(v)) return 'VisMin'
  return null
}
