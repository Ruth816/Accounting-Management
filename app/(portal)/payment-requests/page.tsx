import { PaymentRequestList } from '@/components/RequestLists'
import { PR_OPEN_STATUSES } from '@/lib/labels'

export default async function PaymentRequestsPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
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
