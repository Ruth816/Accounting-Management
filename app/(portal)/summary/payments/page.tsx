import { SummaryPage } from '@/components/SummaryPage'

export default function Page({ searchParams }: { searchParams: Promise<{ date?: string; approver?: string }> }) {
  return <SummaryPage kind="payments" searchParams={searchParams} />
}
