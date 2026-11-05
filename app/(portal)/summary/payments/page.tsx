import { redirect } from 'next/navigation'

// The approved payments summary became the QuickBooks imported summary (Ruth, 5 November).
export default function Page() {
  redirect('/summary/quickbooks')
}
