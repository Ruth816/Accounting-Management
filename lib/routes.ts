import 'server-only'
import { getDirectory, getMe } from './auth'

export type Routes = { NCR: string[]; VisMin: string[] }

// Payment approval routing set on the Admin page (Ruth, 1 November).
export async function getRoutes(): Promise<Routes> {
  const { supabase } = await getMe()
  const { data } = await supabase.from('approval_routes').select('region, level, approver_id').order('level')
  const routes: Routes = { NCR: [], VisMin: [] }
  for (const r of (data ?? []) as { region: 'NCR' | 'VisMin'; level: number; approver_id: string }[]) {
    routes[r.region][r.level - 1] = r.approver_id
  }
  return routes
}

export async function routeHint(routes: Routes) {
  const { name } = await getDirectory()
  const part = (reg: 'NCR' | 'VisMin') =>
    routes[reg].length
      ? `${reg} goes to ${routes[reg].filter(Boolean).map((id) => name(id)).join(', then ')}${routes[reg][0] ? '' : ' (Approver 1 not set yet)'}`
      : null
  const parts = [part('NCR'), part('VisMin')].filter(Boolean)
  return parts.length ? `Set by routing: ${parts.join('. ')}.` : undefined
}
