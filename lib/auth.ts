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
  const is = (r: Role) => profile.roles.includes(r)
  return { supabase, me: profile, is }
})

export const getDirectory = cache(async () => {
  const supabase = await createClient()
  const { data } = await supabase.from('directory').select('*').order('full_name')
  const people = (data ?? []) as Person[]
  const byId = new Map(people.map((p) => [p.id, p]))
  return { people, name: (id: string | null | undefined) => (id ? byId.get(id)?.full_name ?? '' : '') }
})
