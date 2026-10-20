import { NextResponse, type NextRequest } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { dispatchQueuedSms } from '@/lib/sms'

// Vercel Cron, daily at 08:00 Manila: day-23/28 reminders, day-30 expiry,
// then sends the SMS those created.
export async function GET(request: NextRequest) {
  if (!process.env.CRON_SECRET || request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const admin = createAdminClient()
  const { data, error } = await admin.rpc('run_daily_jobs')
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  const paths = (data?.storage_paths ?? []) as string[]
  if (paths.length) await admin.storage.from('attachments').remove(paths)
  const sms = await dispatchQueuedSms(500)
  return NextResponse.json({ ...data, storage_paths: paths.length, sms })
}
