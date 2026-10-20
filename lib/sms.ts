import 'server-only'
import { createAdminClient } from './supabase/admin'

// OneWaySMS one-way HTTP API (spec section 6). Credentials come from
// environment variables only.

const ERRORS: Record<string, string> = {
  '-100': 'Wrong API username or password',
  '-200': 'Invalid sender ID',
  '-300': 'Invalid mobile number',
  '-400': 'Invalid languagetype',
  '-500': 'Invalid characters in the message',
  '-600': 'Not enough SMS credit',
}

export function smsConfigured() {
  return Boolean(process.env.ONEWAYSMS_USERNAME && process.env.ONEWAYSMS_PASSWORD && process.env.ONEWAYSMS_SENDER_ID)
}

// languagetype=1 is plain text, so keep to printable ASCII.
function toAscii(message: string) {
  return message
    .replace(/[–—]/g, '-')
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/[^\x20-\x7e]/g, '')
    .slice(0, 459)
}

export async function sendSms(mobileNo: string, message: string): Promise<{ ok: boolean; id?: string; error?: string }> {
  const url = new URL(process.env.ONEWAYSMS_API_URL || 'https://sgateway.onewaysms.com/apis10.aspx')
  url.searchParams.set('apiusername', process.env.ONEWAYSMS_USERNAME!)
  url.searchParams.set('apipassword', process.env.ONEWAYSMS_PASSWORD!)
  url.searchParams.set('senderid', process.env.ONEWAYSMS_SENDER_ID!.slice(0, 11))
  url.searchParams.set('mobileno', mobileNo)
  url.searchParams.set('languagetype', '1')
  url.searchParams.set('message', toAscii(message))
  try {
    const res = await fetch(url, { cache: 'no-store' })
    const body = (await res.text()).trim()
    const n = Number(body)
    if (Number.isFinite(n) && n > 0) return { ok: true, id: body }
    return { ok: false, error: ERRORS[body] ? `${body} ${ERRORS[body]}` : `Unexpected reply: ${body.slice(0, 200)}` }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
}

// Sends every queued notification SMS. Safe to call after each action and
// from the cron job: rows are claimed atomically, so nothing is sent twice.
export async function dispatchQueuedSms(limit = 50) {
  if (!smsConfigured() || !process.env.SUPABASE_SERVICE_ROLE_KEY) return { sent: 0, failed: 0 }
  const admin = createAdminClient()
  const { data, error } = await admin.rpc('claim_sms_batch', { p_limit: limit })
  if (error) throw error
  let sent = 0
  let failed = 0
  for (const row of (data ?? []) as { id: string; mobile_no: string; message: string }[]) {
    const r = await sendSms(row.mobile_no, `Finance Portal: ${row.message}`)
    await admin.rpc('record_sms_result', {
      p_id: row.id,
      p_ok: r.ok,
      p_message_id: r.id ?? null,
      p_error: r.error ?? null,
    })
    if (r.ok) sent++
    else failed++
  }
  return { sent, failed }
}

export async function smsCredit(): Promise<string> {
  if (!smsConfigured()) return 'SMS is not set up yet (add the OneWaySMS settings in Vercel).'
  const url = new URL(process.env.ONEWAYSMS_CREDIT_URL || 'https://sgateway.onewaysms.com/bulkcredits10.aspx')
  url.searchParams.set('apiusername', process.env.ONEWAYSMS_USERNAME!)
  url.searchParams.set('apipassword', process.env.ONEWAYSMS_PASSWORD!)
  try {
    const res = await fetch(url, { cache: 'no-store' })
    const body = (await res.text()).trim()
    return ERRORS[body] ? `${body} ${ERRORS[body]}` : body
  } catch (e) {
    return `Could not check credit: ${e instanceof Error ? e.message : String(e)}`
  }
}
