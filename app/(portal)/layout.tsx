import { COMPANY, LogoMark } from '@/components/Logo'
import Link from 'next/link'
import { getMe } from '@/lib/auth'
import { signOut } from '@/app/actions'
import { RefreshButton } from '@/components/RefreshButton'
import { UpdateWatcher } from '@/components/UpdateWatcher'
import { SideNav, type NavSection } from '@/components/SideNav'
import { ROLE_LABEL } from '@/lib/labels'

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const { supabase, me, is } = await getMe()
  const { count } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('recipient_id', me.id)
    .eq('read', false)

  const seesFunds = is('fund_requestor') || is('fund_approver') || is('admin')
  const sections: NavSection[] = [
    {
      title: 'Requests',
      items: [
        { href: '/', label: 'Dashboard', icon: 'dashboard' },
        { href: '/payment-requests', label: 'Payment requests', icon: 'doc' },
        { href: '/payment-requests/approved', label: 'Payment approved', icon: 'docCheck' },
        // Fund pages are for funding roles only; a Payment Requestor sees just their own requests.
        ...(seesFunds
          ? [
              { href: '/fund-requests', label: 'Fund requests', icon: 'fund' as const },
              { href: '/fund-requests/approved', label: 'Fund approved', icon: 'fundCheck' as const },
            ]
          : []),
      ],
    },
    ...(is('fund_approver') || is('payment_approver') || is('admin')
      ? [
          {
            title: 'Summaries',
            items: [
              ...(is('fund_approver') || is('admin')
                ? [{ href: '/summary/funding', label: 'Summary list for funding', icon: 'summary' as const }]
                : []),
              ...(is('payment_approver') || is('admin')
                ? [{ href: '/summary/payments', label: 'Approved payments summary', icon: 'summary' as const }]
                : []),
            ],
          },
        ]
      : []),
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
            <LogoMark size={34} />
          </span>
          <span>
            <span className="brand-name">{COMPANY}</span>
            <span className="brand-sub">Finance Portal</span>
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
        <UpdateWatcher current={process.env.VERCEL_GIT_COMMIT_SHA ?? 'dev'} />
        <main className="page">{children}</main>
      </div>
    </div>
  )
}
