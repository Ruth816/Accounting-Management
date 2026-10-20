import { NextResponse, type NextRequest } from 'next/server'
import { dispatchQueuedSms } from '@/lib/sms'

// Safety net: sends any SMS still queued (for example if a send failed to
// start right after an action).
export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  return NextResponse.json(await dispatchQueuedSms(500))
}
