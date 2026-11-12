import { PaymentRequestList } from '@/components/RequestLists'
import { PR_APPROVED_STATUSES } from '@/lib/labels'

export default async function PaymentApprovedPage({ searchParams }: { searchParams: Promise<{ region?: string; date?: string; by?: string }> }) {
  const { region, date, by } = await searchParams
  return (
    <PaymentRequestList
      title="Payment approved"
      sub="Approved by the Payment Approver, from awaiting funding through to fully approved. Pick a date, and an approver, to see everything approved that day."
      statuses={PR_APPROVED_STATUSES}
      base="/payment-requests/approved"
      region={region}
      byApprovalDay
      date={date}
      by={by}
    />
  )
}
