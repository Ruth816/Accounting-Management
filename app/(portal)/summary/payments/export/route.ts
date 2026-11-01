import { exportSummary } from '@/lib/summaryExport'

export function GET(req: Request) {
  return exportSummary('payments', req)
}
