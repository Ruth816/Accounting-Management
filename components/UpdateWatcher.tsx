'use client'

import { useEffect, useState } from 'react'

// Shows a banner when a newer version of the portal has been deployed
// since this page was opened, so nobody keeps working on an old screen.
export function UpdateWatcher({ current }: { current: string }) {
  const [stale, setStale] = useState(false)
  useEffect(() => {
    if (current === 'dev') return
    const check = async () => {
      try {
        const res = await fetch('/api/version', { cache: 'no-store' })
        const { version } = await res.json()
        if (version && version !== current) setStale(true)
      } catch {
        // offline or signed out: try again later
      }
    }
    const id = setInterval(check, 60_000)
    window.addEventListener('focus', check)
    return () => {
      clearInterval(id)
      window.removeEventListener('focus', check)
    }
  }, [current])
  if (!stale) return null
  return (
    <div className="update-banner no-print" role="status">
      The portal has been updated.
      <button type="button" className="btn small" onClick={() => window.location.reload()}>
        Load the new version
      </button>
    </div>
  )
}
