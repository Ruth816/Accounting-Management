import { FundRequestList } from '@/components/RequestLists'
import { FR_OPEN_STATUSES } from '@/lib/labels'

// Approved requests stay here until imported to QuickBooks, showing Preparing
// for funding, then Funded with its date (Ruth, 10 November).
const STATUSES = [...FR_OPEN_STATUSES, 'approved_ready_for_qb', 'sync_failed']

export default async function FundRequestsPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
  const { region } = await searchParams
  return (
    <FundRequestList
      title="Fund requests"
      sub="Being prepared, waiting for fund approval, returned to the Fund Requestor, or approved and waiting to be imported to QuickBooks. Approved requests show Preparing for funding, then Funded with the date funded."
      statuses={STATUSES}
      base="/fund-requests"
      region={region}
    />
  )
}
