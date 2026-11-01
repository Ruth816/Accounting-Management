'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

export type NavItem = { href: string; label: string; icon: keyof typeof ICONS; badge?: number }
export type NavSection = { title: string; items: NavItem[] }

// Simple line icons, 24px grid.
const ICONS = {
  dashboard: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
  doc: 'M6 3h9l3 3v15H6zM9 9h6M9 13h6M9 17h4',
  docCheck: 'M6 3h9l3 3v15H6zM9 13l2 2 4-4',
  fund: 'M3 7h18v10H3zM12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z',
  fundCheck: 'M3 7h18v10H3zM9 12l2 2 4-4',
  plus: 'M12 5v14M5 12h14M4 4h16v16H4z',
  summary: 'M4 20V10M10 20V4M16 20v-7M2 20h20',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
  bell: 'M6 16V11a6 6 0 1 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0',
  admin: 'M12 3l8 4v5c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V7zM9 12l2 2 4-4',
  user: 'M12 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8zM4 20c1-4 4.5-6 8-6s7 2 8 6',
}

export function SideNav({ sections }: { sections: NavSection[] }) {
  const path = usePathname()
  const hrefs = sections.flatMap((s) => s.items.map((i) => i.href))
  // The longest matching link wins, so /payment-requests/approved doesn't also light up /payment-requests.
  const best = hrefs.filter((h) => (h === '/' ? path === '/' : path === h || path.startsWith(h + '/'))).sort((a, b) => b.length - a.length)[0]
  const active = (href: string) => href === best
  return (
    <nav className="side-nav" aria-label="Main">
      {sections.map((s) => (
        <div key={s.title} className="side-section">
          <div className="side-title">{s.title}</div>
          {s.items.map((i) => (
            <Link key={i.href} href={i.href} className={`side-link${active(i.href) ? ' active' : ''}`}>
              <svg viewBox="0 0 24 24" aria-hidden="true">
                <path d={ICONS[i.icon]} />
              </svg>
              <span className="side-label">{i.label}</span>
              {i.badge ? <span className="side-badge">{i.badge}</span> : null}
            </Link>
          ))}
        </div>
      ))}
    </nav>
  )
}
