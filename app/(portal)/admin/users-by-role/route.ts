import { getMe } from '@/lib/auth'
import { usersByRole, usersByRoleCsv } from '@/lib/usersByRole'

export async function GET() {
  const { is } = await getMe()
  if (!is('admin')) return new Response('Admins only.', { status: 403 })
  const day = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' })
  return new Response(usersByRoleCsv(await usersByRole()), {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="users-by-role-${day}.csv"`,
      'Cache-Control': 'no-store',
    },
  })
}
