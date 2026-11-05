'use client'

import { usePathname } from 'next/navigation'
import { BackButton } from './BackButton'

// A back arrow on every page except Home (Ruth, 5 November). Request detail
// pages render their own "Back to list" with the right list as fallback.
const DETAIL = /^\/(payment|fund)-requests\/(?!new$|approved$)[^/]+$/

export function PageBack() {
  const path = usePathname()
  if (!path || path === '/' || DETAIL.test(path)) return null
  const parent = path.replace(/\/[^/]+$/, '') || '/'
  return <BackButton fallback={parent} label="Back" />
}
