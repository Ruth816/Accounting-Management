import 'server-only'
import { getMe } from './auth'
import { ROLE_LABEL } from './labels'
import type { Profile, Role } from './types'

// Users grouped by role, with region and payment approval order (Ruth, 3 November).
export const ROLE_ORDER: Role[] = ['payment_requestor', 'fund_requestor', 'payment_approver', 'fund_approver', 'admin']

export type RoleRow = { name: string; email: string; employeeId: string; region: string; order: string; active: boolean }

export async function usersByRole() {
  const { supabase } = await getMe()
  const [{ data: users }, { data: routes }] = await Promise.all([
    supabase.from('profiles').select('*').order('full_name'),
    supabase.from('approval_routes').select('region, level, approver_id').order('region').order('level'),
  ])
  const profiles = (users ?? []) as Profile[]
  const steps = (routes ?? []) as { region: string; level: number; approver_id: string }[]
  return ROLE_ORDER.map((role) => ({
    role,
    label: ROLE_LABEL[role],
    rows: profiles
      .filter((p) => p.roles.includes(role))
      .map<RoleRow>((p) => ({
        name: p.full_name,
        email: p.email,
        employeeId: p.employee_id ?? '',
        region: p.region ?? 'Both',
        order:
          role === 'payment_approver' || role === 'admin'
            ? steps.filter((s) => s.approver_id === p.id).map((s) => `${s.region} approver ${s.level}`).join(', ')
            : '',
        active: p.active,
      })),
  }))
}

const cell = (v: string) => (/[",\r\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v)

export function usersByRoleCsv(groups: Awaited<ReturnType<typeof usersByRole>>) {
  const out = [['Role', 'Name', 'Email', 'Employee ID', 'Region', 'Payment approval order', 'Status'].join(',')]
  for (const g of groups)
    for (const r of g.rows)
      out.push([g.label, r.name, r.email, r.employeeId, r.region, r.order, r.active ? 'Active' : 'Inactive'].map(cell).join(','))
  return '﻿' + out.join('\r\n') + '\r\n'
}
