import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { supabaseConfigProblem } from './config'

// Refreshes the Supabase session cookie and sends signed-out visitors to /login.
export async function updateSession(request: NextRequest) {
  const problem = supabaseConfigProblem()
  if (problem) {
    if (request.nextUrl.pathname === '/api/health') return NextResponse.next({ request })
    return new NextResponse(
      `<!doctype html><meta charset="utf-8"><title>Setup needed</title>` +
        `<body style="font-family:system-ui;max-width:40rem;margin:4rem auto;padding:0 1rem">` +
        `<h1>The portal is not set up correctly</h1><p>${problem}</p>` +
        `<p>Fix it in Vercel under Settings &rarr; Environment Variables, then redeploy. ` +
        `<a href="/api/health">Setup check</a></p></body>`,
      { status: 503, headers: { 'content-type': 'text/html; charset=utf-8' } },
    )
  }

  let response = NextResponse.next({ request })
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options))
        },
      },
    },
  )

  const { data } = await supabase.auth.getClaims()
  const path = request.nextUrl.pathname
  if (!data?.claims && !path.startsWith('/login') && !path.startsWith('/api/cron') && path !== '/api/health') {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.search = ''
    return NextResponse.redirect(url)
  }
  return response
}
