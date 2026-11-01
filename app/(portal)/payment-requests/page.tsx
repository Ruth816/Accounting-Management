import { PaymentRequestList } from '@/components/RequestLists'
import { PR_OPEN_STATUSES } from '@/lib/labels'

export default function PaymentRequestsPage() {
  return (
    <PaymentRequestList
      title="Payment requests"
      sub="Not yet approved by the Payment Approver: drafts, pending, returned and expired."
      statuses={PR_OPEN_STATUSES}
    />
  )
}
