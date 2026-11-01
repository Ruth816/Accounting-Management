import { FundRequestList } from '@/components/RequestLists'
import { FR_APPROVED_STATUSES } from '@/lib/labels'

export default async function FundApprovedPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
  const { region } = await searchParams
  return (
    <FundRequestList
      title="Fund approved"
      sub="Approved by the Fund Approver, ready for or posted to QuickBooks."
      statuses={FR_APPROVED_STATUSES}
      base="/fund-requests/approved"
      region={region}
    />
  )
}
