// The deployed version, so open pages can tell when a newer one is live.
export const dynamic = 'force-dynamic'

export function GET() {
  return Response.json(
    { version: process.env.VERCEL_GIT_COMMIT_SHA ?? 'dev' },
    { headers: { 'Cache-Control': 'no-store' } },
  )
}
