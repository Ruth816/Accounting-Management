import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { connectWithCode, qbConfigProblem, syncLists } from '@/lib/qbo'

const STATE_COOKIE = 'qb_oauth_state'

// Intuit sends the Admin back here after they sign in and pick the company.
export async function GET(request: NextRequest) {
  const p = request.nextUrl.searchParams
  const back = (key: 'qb' | 'qb_error', value: string) => {
    const u = new URL('/admin', request.nextUrl.origin)
    u.searchParams.set(key, value)
    u.hash = 'quickbooks'
    const res = NextResponse.redirect(u)
    res.cookies.delete({ name: STATE_COOKIE, path: '/api/quickbooks' })
    return res
  }

  const supabase = await createClient()
  const [{ data: isAdmin }, { data: user }] = await Promise.all([
    supabase.rpc('has_role', { r: 'admin' }),
    supabase.auth.getUser(),
  ])
  if (!isAdmin || !user.user) return NextResponse.redirect(new URL('/', request.nextUrl.origin))
  const problem = qbConfigProblem()
  if (problem) return back('qb_error', problem)
  if (p.get('error')) return back('qb_error', `QuickBooks did not connect: ${p.get('error_description') ?? p.get('error')}`)

  const state = p.get('state')
  if (!state || state !== request.cookies.get(STATE_COOKIE)?.value) {
    return back('qb_error', 'The QuickBooks sign-in expired or came from another window. Click Connect to QuickBooks again.')
  }
  const code = p.get('code')
  const realmId = p.get('realmId')
  if (!code || !realmId) return back('qb_error', 'QuickBooks did not send the company. Click Connect to QuickBooks again.')

  try {
    await connectWithCode(code, realmId, request.nextUrl.origin, user.user.id)
  } catch (e) {
    return back('qb_error', e instanceof Error ? e.message : String(e))
  }
  try {
    await syncLists()
  } catch (e) {
    return back('qb_error', `Connected, but the lists did not sync: ${e instanceof Error ? e.message : e}`)
  }
  return back('qb', 'connected')
}
