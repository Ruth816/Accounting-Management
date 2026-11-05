import { FundRequestList } from '@/components/RequestLists'
import { FR_APPROVED_STATUSES } from '@/lib/labels'

export default async function FundApprovedPage({ searchParams }: { searchParams: Promise<{ region?: string }> }) {
  const { region } = await searchParams
  return (
    <FundRequestList
      title="Fund approved"
      sub="Pre-approved by the Fund Approver. Click Ready for funding on a request when you are ready to fund it; it then goes to the Ready for funding list for that day."
      statuses={FR_APPROVED_STATUSES}
      base="/fund-requests/approved"
      region={region}
    />
  )
}
