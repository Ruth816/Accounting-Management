import { FundRequestList } from '@/components/RequestLists'
import { FR_OPEN_STATUSES } from '@/lib/labels'

export default async function FundRequestsPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
  const { region } = await searchParams
  return (
    <FundRequestList
      title="Fund requests"
      sub="Being prepared, waiting for fund approval, or returned to the Fund Requestor."
      statuses={FR_OPEN_STATUSES}
      base="/fund-requests"
      region={region}
    />
  )
}
