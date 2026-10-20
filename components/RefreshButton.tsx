'use client'

// Reloads the whole page so every list and form shows the latest data.
export function RefreshButton() {
  return (
    <button className="link small" type="button" onClick={() => window.location.reload()}>
      ↻ Refresh
    </button>
  )
}
