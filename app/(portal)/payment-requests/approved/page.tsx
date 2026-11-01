import { PaymentRequestList } from '@/components/RequestLists'
import { PR_APPROVED_STATUSES } from '@/lib/labels'

export default function PaymentApprovedPage() {
  return (
    <PaymentRequestList
      title="Payment approved"
      sub="Approved by the Payment Approver, from awaiting funding through to fully approved."
      statuses={PR_APPROVED_STATUSES}
    />
  )
}
