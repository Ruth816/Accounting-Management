import 'server-only'
import { getMe } from './auth'
import { ROLE_LABEL } from './labels'
import type { Profile, Role } from './types'

// Users by region, then by role, with payment approval order (Ruth, 3 November):
// NCR and VisMin listed apart for a clearer turnover.
export const ROLE_ORDER: Role[] = ['payment_requestor', 'fund_requestor', 'payment_approver', 'fund_approver', 'admin']
export const REGION_GROUPS = ['NCR', 'VisMin', 'Both'] as const
export type RegionGroup = (typeof REGION_GROUPS)[number]

export type RoleRow = { name: string; email: string; employeeId: string; order: string; active: boolean }
type Step = { region: string; level: number; approver_id: string }

const routed = (role: Role) => role === 'payment_approver' || role === 'admin'

// A person sits in their Region; an approver also sits in every region they are routed for.
// No region and no routing: "Both".
function regionsOf(p: Profile, role: Role, steps: Step[]): RegionGroup[] {
  const set = new Set<RegionGroup>()
  if (p.region) set.add(p.region)
  if (routed(role)) for (const s of steps) if (s.approver_id === p.id) set.add(s.region as RegionGroup)
  return set.size ? REGION_GROUPS.filter((g) => set.has(g)) : ['Both']
}

export async function usersByRole() {
  const { supabase } = await getMe()
  const [{ data: users }, { data: routes }] = await Promise.all([
    supabase.from('profiles').select('*').order('full_name'),
    supabase.from('approval_routes').select('region, level, approver_id').order('region').order('level'),
  ])
  const profiles = (users ?? []) as Profile[]
  const steps = (routes ?? []) as Step[]
  return REGION_GROUPS.map((region) => ({
    region,
    label: region === 'Both' ? 'Both regions (no region set)' : region,
    roles: ROLE_ORDER.map((role) => ({
      role,
      label: ROLE_LABEL[role],
      rows: profiles
        .filter((p) => p.roles.includes(role) && regionsOf(p, role, steps).includes(region))
        .map<RoleRow>((p) => ({
          name: p.full_name,
          email: p.email,
          employeeId: p.employee_id ?? '',
          order: routed(role)
            ? steps
                .filter((s) => s.approver_id === p.id && (region === 'Both' || s.region === region))
                .map((s) => `${region === 'Both' ? s.region + ' ' : ''}Approver ${s.level}`)
                .join(', ')
            : '',
          active: p.active,
        })),
    })),
  }))
}

const cell = (v: string) => (/[",\r\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v)

export function usersByRoleCsv(groups: Awaited<ReturnType<typeof usersByRole>>) {
  const out = [['Region', 'Role', 'Name', 'Email', 'Employee ID', 'Payment approval order', 'Status'].join(',')]
  for (const g of groups)
    for (const r of g.roles)
      for (const u of r.rows)
        out.push([g.region, r.label, u.name, u.email, u.employeeId, u.order, u.active ? 'Active' : 'Inactive'].map(cell).join(','))
  return '﻿' + out.join('\r\n') + '\r\n'
}
