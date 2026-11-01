import { PaymentRequestList } from '@/components/RequestLists'
import { PR_APPROVED_STATUSES } from '@/lib/labels'

export default async function PaymentApprovedPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
  const { region } = await searchParams
  return (
    <PaymentRequestList
      title="Payment approved"
      sub="Approved by the Payment Approver, from awaiting funding through to fully approved."
      statuses={PR_APPROVED_STATUSES}
      base="/payment-requests/approved"
      region={region}
    />
  )
}
