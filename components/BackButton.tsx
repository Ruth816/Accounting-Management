'use client'

import { useRouter } from 'next/navigation'

// "Back to list": returns to the page the user came from (keeping its tab
// and filters); if they opened this page directly, goes to the fallback list.
export function BackButton({ fallback, label = 'Back to list' }: { fallback: string; label?: string }) {
  const router = useRouter()
  const onClick = () => {
    if (window.history.length > 1) router.back()
    else router.push(fallback)
  }
  return (
    <button type="button" className="btn secondary small back-btn no-print" onClick={onClick}>
      ← {label}
    </button>
  )
}
