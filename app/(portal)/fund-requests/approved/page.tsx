import { redirect } from 'next/navigation'

// The Fund approved list is gone (Ruth, 10 November): approving a request puts
// it straight on Ready for funding, and approved requests stay on Fund requests
// until they are imported to QuickBooks. Old links land on Fund requests.
export default function FundApprovedPage() {
  redirect('/fund-requests')
}
