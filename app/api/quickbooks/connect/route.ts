import crypto from 'node:crypto'
import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { authorizeUrl, qbConfigProblem } from '@/lib/qbo'

const STATE_COOKIE = 'qb_oauth_state'

// Admin → "Connect to QuickBooks": sends the Admin to Intuit to sign in and
// pick the company.
export async function GET(request: NextRequest) {
  const admin = new URL('/admin#quickbooks', request.nextUrl.origin)
  const supabase = await createClient()
  const { data: isAdmin } = await supabase.rpc('has_role', { r: 'admin' })
  if (!isAdmin) return NextResponse.redirect(new URL('/', request.nextUrl.origin))
  const problem = qbConfigProblem()
  if (problem) {
    admin.searchParams.set('qb_error', problem)
    return NextResponse.redirect(admin)
  }
  const state = crypto.randomBytes(24).toString('base64url')
  const res = NextResponse.redirect(authorizeUrl(state, request.nextUrl.origin))
  res.cookies.set(STATE_COOKIE, state, {
    httpOnly: true,
    secure: request.nextUrl.protocol === 'https:',
    sameSite: 'lax',
    path: '/api/quickbooks',
    maxAge: 600,
  })
  return res
}
