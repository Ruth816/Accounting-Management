import { NextResponse } from 'next/server'

// Setup check: shows which Supabase project the deployed keys belong to and
// whether Supabase accepts them. Never returns the keys themselves.
export const dynamic = 'force-dynamic'

type KeyReport = {
  set: boolean
  length: number
  format: string
  hasSpacesOrQuotes: boolean
  project?: string
  role?: string
  supabaseAccepts?: boolean | string
}

function projectRef(url: string) {
  return url.match(/^https:\/\/([a-z0-9]+)\.supabase\.co\/?$/)?.[1]
}

function describeKey(raw: string | undefined): KeyReport {
  const key = raw ?? ''
  const report: KeyReport = {
    set: key.length > 0,
    length: key.length,
    format: 'unknown',
    hasSpacesOrQuotes: /[\s"']/.test(key),
  }
  const clean = key.trim().replace(/^["']|["']$/g, '')
  if (clean.startsWith('sb_publishable_')) report.format = 'publishable key'
  else if (clean.startsWith('sb_secret_')) report.format = 'secret key'
  else if (clean.split('.').length === 3 && clean.startsWith('eyJ')) {
    report.format = 'legacy JWT key'
    try {
      const claims = JSON.parse(Buffer.from(clean.split('.')[1], 'base64url').toString())
      report.project = claims.ref
      report.role = claims.role
    } catch {
      report.format = 'damaged JWT key'
    }
  }
  return report
}

async function probe(url: string, key: string | undefined) {
  if (!url || !key) return 'not tested'
  try {
    const res = await fetch(`${url.replace(/\/$/, '')}/auth/v1/settings`, {
      headers: { apikey: key },
      cache: 'no-store',
    })
    return res.ok ? true : `rejected (HTTP ${res.status})`
  } catch (e) {
    return `could not reach Supabase: ${(e as Error).message}`
  }
}

export async function GET() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? ''
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  const anon = describeKey(anonKey)
  anon.supabaseAccepts = await probe(url, anonKey)
  const service = describeKey(serviceKey)
  service.supabaseAccepts = await probe(url, serviceKey)

  return NextResponse.json({
    deployment: {
      commit: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? 'unknown',
      environment: process.env.VERCEL_ENV ?? 'unknown',
    },
    supabaseUrl: {
      value: url || '(not set)',
      project: projectRef(url) ?? 'not a https://<project>.supabase.co URL',
      hasSpacesOrQuotes: /[\s"']/.test(url),
    },
    NEXT_PUBLIC_SUPABASE_ANON_KEY: anon,
    SUPABASE_SERVICE_ROLE_KEY: service,
  })
}
