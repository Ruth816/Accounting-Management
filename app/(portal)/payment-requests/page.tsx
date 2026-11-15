import { redirect } from 'next/navigation'
import { PaymentRequestList } from '@/components/RequestLists'
import { getMe } from '@/lib/auth'
import { PR_OPEN_STATUSES } from '@/lib/labels'

export default async function PaymentRequestsPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
  const { seesOpenPaymentRequests } = await getMe()
  if (!seesOpenPaymentRequests) redirect('/payment-requests/approved')
  const { region } = await searchParams
  return (
    <PaymentRequestList
      title="Payment requests"
      sub="Not yet approved by the Payment Approver: drafts, pending, returned and expired."
      statuses={PR_OPEN_STATUSES}
      base="/payment-requests"
      region={region}
    />
  )
}
