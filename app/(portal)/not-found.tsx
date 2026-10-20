import Link from 'next/link'

export default function NotFound() {
  return (
    <div className="stack narrow">
      <h1>Not found</h1>
      <p className="muted">This request does not exist, or you do not have access to it.</p>
      <Link href="/">Back to the dashboard</Link>
    </div>
  )
}
