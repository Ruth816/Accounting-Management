'use client'

import { useState } from 'react'
import { regionFromEmployeeId } from '@/lib/region'

// Employee ID and Region. Typing an ID that starts with NO / NFS picks NCR,
// VO / VFS picks VisMin; the Region can still be changed by hand.
export function EmployeeRegion({
  form,
  employeeId = '',
  region = '',
  small,
}: {
  form?: string
  employeeId?: string
  region?: string
  small?: boolean
}) {
  const [reg, setReg] = useState(region)
  const cls = small ? 'field small' : 'field'
  return (
    <>
      <label className={cls}>
        <span className="label">Employee ID</span>
        <input
          form={form}
          name="employee_id"
          defaultValue={employeeId}
          placeholder="NO…, NFS…, VO…, VFS…"
          onChange={(e) => {
            const r = regionFromEmployeeId(e.target.value)
            if (r) setReg(r)
          }}
        />
      </label>
      <label className={cls}>
        <span className="label">Region (requestors see only this)</span>
        <select form={form} name="region" value={reg} onChange={(e) => setReg(e.target.value)}>
          <option value="">Both regions</option>
          <option value="NCR">NCR only</option>
          <option value="VisMin">VisMin only</option>
        </select>
      </label>
    </>
  )
}
