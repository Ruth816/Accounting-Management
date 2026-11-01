import { FundRequestList } from '@/components/RequestLists'
import { FR_OPEN_STATUSES } from '@/lib/labels'

export default function FundRequestsPage() {
  return (
    <FundRequestList
      title="Fund requests"
      sub="Being prepared, waiting for fund approval, or returned to the Fund Requestor."
      statuses={FR_OPEN_STATUSES}
    />
  )
}
