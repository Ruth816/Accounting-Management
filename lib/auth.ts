import 'server-only'
import { cache } from 'react'
import { redirect } from 'next/navigation'
import { createClient } from './supabase/server'
import type { Person, Profile, Role } from './types'

export const getMe = cache(async () => {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const uid = claims?.claims?.sub
  if (!uid) redirect('/login')
  const { data: profile } = await supabase.from('profiles').select('*').eq('id', uid).single<Profile>()
  if (!profile || !profile.active) redirect('/login?inactive=1')
  // An Admin covers every role (Ruth, 1 November), so is() is true for them.
  const is = (r: Role) => profile.roles.includes(r) || profile.roles.includes('admin')
  // Requestors with a region see only that region (Ruth, 1 November).
  // Admins and approvers on both regions' routing see every region.
  const limited = !profile.roles.some((r) => r === 'admin' || r === 'payment_approver' || r === 'fund_approver')
  let myRegion = limited ? (profile.region ?? null) : null
  // A Payment Approver routed for one region only sees that region (Ruth, 2 November).
  if (!myRegion && profile.roles.includes('payment_approver') && !profile.roles.includes('admin')) {
    const { data: routes } = await supabase.from('approval_routes').select('region').eq('approver_id', uid)
    const regions = [...new Set((routes ?? []).map((r: { region: 'NCR' | 'VisMin' }) => r.region))]
    if (regions.length === 1) myRegion = regions[0]
  }
  return { supabase, me: profile, is, myRegion, limited }
})

export const getDirectory = cache(async () => {
  const supabase = await createClient()
  const { data } = await supabase.from('directory').select('*').order('full_name')
  const people = (data ?? []) as Person[]
  const byId = new Map(people.map((p) => [p.id, p]))
  return { people, name: (id: string | null | undefined) => (id ? byId.get(id)?.full_name ?? '' : '') }
})
