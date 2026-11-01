import Link from 'next/link'
import { getMe } from '@/lib/auth'
import { signOut } from '@/app/actions'
import { RefreshButton } from '@/components/RefreshButton'
import { SideNav, type NavSection } from '@/components/SideNav'
import { ROLE_LABEL } from '@/lib/labels'

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const { supabase, me, is } = await getMe()
  const { count } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('recipient_id', me.id)
    .eq('read', false)

  const sections: NavSection[] = [
    {
      title: 'Requests',
      items: [
        { href: '/', label: 'Dashboard', icon: 'dashboard' },
        { href: '/payment-requests', label: 'Payment requests', icon: 'doc' },
        { href: '/payment-requests/approved', label: 'Payment approved', icon: 'docCheck' },
        { href: '/fund-requests', label: 'Fund requests', icon: 'fund' },
        { href: '/fund-requests/approved', label: 'Fund approved', icon: 'fundCheck' },
      ],
    },
    {
      title: 'Tools',
      items: [
        ...(is('payment_requestor') ? [{ href: '/payment-requests/new', label: 'New payment request', icon: 'plus' as const }] : []),
        { href: '/search', label: 'Search', icon: 'search' },
        { href: '/notifications', label: 'Notifications', icon: 'bell', badge: count ?? 0 },
      ],
    },
    ...(is('admin') ? [{ title: 'Administration', items: [{ href: '/admin', label: 'Users & settings', icon: 'admin' as const }] }] : []),
    { title: 'Account', items: [{ href: '/account', label: 'My account', icon: 'user' }] },
  ]

  return (
    <div className="shell">
      <aside className="sidebar">
        <Link href="/" className="side-brand">
          <span className="logo" aria-hidden="true">
            FP
          </span>
          <span>
            <span className="brand-name">Finance Portal</span>
            <span className="brand-sub">Payments · Funds</span>
          </span>
        </Link>
        <SideNav sections={sections} />
      </aside>
      <div className="main">
        <div className="signed-in">
          <span>
            Signed in as <strong>{me.full_name}</strong>
            {me.roles.length ? ` · ${me.roles.map((r) => ROLE_LABEL[r]).join(', ')}` : ''}
          </span>
          <span className="signed-in-actions">
            <RefreshButton />
            <form action={signOut}>
              <button className="link small" type="submit">
                Sign out
              </button>
            </form>
          </span>
        </div>
        <main className="page">{children}</main>
      </div>
    </div>
  )
}
