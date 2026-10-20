import Link from 'next/link'
import { getMe } from '@/lib/auth'
import { signOut } from '@/app/actions'

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const { supabase, me, is } = await getMe()
  const { count } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('recipient_id', me.id)
    .eq('read', false)

  return (
    <>
      <header className="topbar">
        <Link href="/" className="brand">
          Finance Portal
        </Link>
        <nav>
          <Link href="/">Dashboard</Link>
          {is('payment_requestor') && <Link href="/payment-requests/new">New request</Link>}
          <Link href="/search">Search</Link>
          <Link href="/notifications">
            Notifications{count ? <span className="count">{count}</span> : null}
          </Link>
          {is('admin') && <Link href="/admin">Admin</Link>}
        </nav>
        <div className="me">
          <Link href="/account" className="muted small">
            {me.full_name}
          </Link>
          <form action={signOut}>
            <button className="link small" type="submit">
              Sign out
            </button>
          </form>
        </div>
      </header>
      <main className="page">{children}</main>
    </>
  )
}
