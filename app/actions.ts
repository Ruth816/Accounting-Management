'use server'

import { after } from 'next/server'
import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { dispatchQueuedSms } from '@/lib/sms'
import type { ActionState } from '@/lib/types'

const str = (fd: FormData, k: string) => {
  const v = fd.get(k)
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : null
}

function done(ok = 'Saved.'): ActionState {
  revalidatePath('/', 'layout')
  after(async () => {
    try {
      await dispatchQueuedSms()
    } catch (e) {
      console.error('SMS dispatch failed', e)
    }
  })
  return { ok }
}

export async function signIn(_: ActionState, fd: FormData): Promise<ActionState> {
  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({
    email: str(fd, 'email') ?? '',
    password: String(fd.get('password') ?? ''),
  })
  if (error) {
    if (error.code === 'invalid_credentials') return { error: 'Wrong email or password.' }
    if (error.code === 'email_not_confirmed') {
      return { error: 'This account is not confirmed yet. Ask an Admin to confirm it in Supabase.' }
    }
    // Anything else is usually a setup problem (for example a wrong Supabase key), so show it.
    return { error: `Could not sign in: ${error.message}` }
  }
  redirect('/')
}

export async function signOut() {
  const supabase = await createClient()
  await supabase.auth.signOut()
  redirect('/login')
}

export async function changePassword(_: ActionState, fd: FormData): Promise<ActionState> {
  const password = String(fd.get('password') ?? '')
  if (password.length < 8) return { error: 'Use at least 8 characters.' }
  const supabase = await createClient()
  const { error } = await supabase.auth.updateUser({ password })
  if (error) return { error: error.message }
  return { ok: 'Password changed.' }
}

// Save as draft / Submit / Resubmit a payment request.
export async function savePaymentRequest(_: ActionState, fd: FormData): Promise<ActionState> {
  const supabase = await createClient()
  const id = str(fd, 'id')
  const intent = str(fd, 'intent')
  const fields = [
    'region', 'project_name', 'project_type', 'job_order_no', 'addendum_no', 'work_order_no',
    'approver_id', 'date_required', 'payable_to', 'payment_type', 'billing_type', 'currency', 'purpose',
    'po_num', 'po_date', 'po_amount', 'po_mode', 'last_payment_ref', 'wtax_rate', 'bank_transfer_fee',
  ]
  const payload: Record<string, unknown> = Object.fromEntries(fields.map((k) => [k, str(fd, k)]))
  if (payload.po_mode === 'PB') {
    const no = str(fd, 'po_progress_no')
    if (!no || !/^[1-9]\d*$/.test(no)) return { error: 'Enter the progress billing no. (1, 2, 3 …).' }
    payload.po_mode = `PB ${no}`
  }
  payload.request_kind = str(fd, 'request_kind') ?? 'regular'
  payload.reimbursable = payload.request_kind === 'reimbursable'
  payload.terms_accepted = fd.get('terms_accepted') === 'on'
  const amounts = fd.getAll('item_amount').map(String)
  payload.items = fd.getAll('item_description').map((d, i) => ({ description: String(d), amount: amounts[i] ?? '' }))
  const { data: savedId, error } = await supabase.rpc('save_payment_request', { p_id: id, p: payload })
  if (error) return { error: error.message }
  if (intent === 'submit') {
    const { error: e2 } = await supabase.rpc('submit_payment_request', { p_id: savedId })
    if (e2) {
      if (!id) redirect(`/payment-requests/${savedId}?error=${encodeURIComponent(e2.message)}`)
      revalidatePath('/', 'layout')
      return { error: e2.message }
    }
    done()
    redirect(`/payment-requests/${savedId}`)
  }
  if (!id) redirect(`/payment-requests/${savedId}`)
  return done('Draft saved.')
}

export async function saveFundRequest(_: ActionState, fd: FormData): Promise<ActionState> {
  const supabase = await createClient()
  const id = str(fd, 'id')!
  const intent = str(fd, 'intent')
  const fields = [
    'ref_no', 'payee', 'item_no', 'description', 'currency', 'original_amount', 'exchange_rate', 'rate_date',
    'payment_date', 'payment_method', 'cash_received_by', 'bank_account_name', 'bank_account_no', 'tax_code',
    'payment_account', 'category', 'fund_approver_id', 'cheque_mode', 'cheque_id', 'cheque_no', 'subtotal_to_fund',
  ]
  const payload: Record<string, unknown> = Object.fromEntries(fields.map((k) => [k, str(fd, k)]))
  // An unedited memo is sent empty so the database keeps pre-filling it.
  payload.memo = fd.get('memo_edited') === 'true' ? str(fd, 'memo') : null
  const { error } = await supabase.rpc('save_fund_request', { p_id: id, p: payload })
  if (error) return { error: error.message }
  if (intent === 'submit') {
    const { error: e2 } = await supabase.rpc('submit_fund_request', { p_id: id })
    if (e2) {
      revalidatePath('/', 'layout')
      return { error: e2.message }
    }
    return done('Sent for fund approval.')
  }
  return done('Draft saved.')
}

// Every other button: one dispatcher keyed by "op".
export async function requestAction(_: ActionState, fd: FormData): Promise<ActionState> {
  const supabase = await createClient()
  const op = str(fd, 'op')
  const id = str(fd, 'id')
  const reason = str(fd, 'reason')
  const call = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await supabase.rpc(fn, args)
    if (error) throw new Error(error.message)
    return data
  }
  try {
    switch (op) {
      case 'cancel_pr':
        await call('cancel_payment_request', { p_id: id })
        return done('Request cancelled.')
      case 'withdraw_pr':
        await call('withdraw_payment_request', { p_id: id })
        return done('Taken back for editing.')
      case 'withdraw_fr':
        await call('withdraw_fund_request', { p_id: id })
        return done('Taken back for editing.')
      case 'delete_pr':
        await call('delete_payment_request', { p_id: id, p_reason: reason })
        return done('Request deleted.')
      case 'delete_fr':
        await call('delete_fund_request', { p_id: id, p_reason: reason })
        return done('Fund request deleted.')
      case 'approve_pr':
        await call('approve_payment_request', { p_id: id })
        return done('Approved.')
      case 'disapprove_pr':
        await call('disapprove_payment_request', { p_id: id, p_reason: reason })
        return done('Returned to the requestor.')
      case 'liquidate':
        await call('liquidate_payment_request', {
          p_id: id,
          p_actual_used: str(fd, 'actual_used')?.replace(/,/g, '') ?? null,
          p_deposit_date: str(fd, 'deposit_date'),
          p_deposit_amount: str(fd, 'deposit_amount')?.replace(/,/g, '') ?? null,
          p_deposit_bank: str(fd, 'deposit_bank'),
        })
        return done('Liquidation saved.')
      case 'receive': {
        const frId = await call('receive_payment_request', { p_id: id })
        done()
        redirect(`/fund-requests/${frId}`)
      }
      case 'new_auto_debit':
      case 'new_check_payment': {
        const fn = op === 'new_auto_debit' ? 'create_auto_debit_request' : 'create_check_payment_request'
        const frId = await call(fn, {})
        done()
        redirect(`/fund-requests/${frId}`)
      }
      case 'reviewed':
        await call('set_fund_reviewed', { p_id: id, p_reviewed: fd.get('value') === 'true' })
        return done(fd.get('value') === 'true' ? 'Marked reviewed.' : 'Review cleared.')
      case 'approve_fr':
        await call('approve_fund_request', { p_id: id })
        return done('Fund request approved.')
      case 'disapprove_fr':
        await call('disapprove_fund_request', { p_id: id, p_reason: reason })
        return done('Returned to the Fund Requestor.')
      case 'return_to_approver':
        await call('return_to_payment_approver', { p_id: id, p_reason: reason })
        return done('Sent back to the payment approver.')
      case 'mark_read':
        await call('mark_notifications_read', { p_ids: id ? [id] : null })
        return done('Marked as read.')
      case 'remove_attachment': {
        const path = (await call('remove_attachment', { p_id: id })) as string | null
        if (path) await supabase.storage.from('attachments').remove([path])
        return done('File removed.')
      }
      default:
        return { error: 'Unknown action.' }
    }
  } catch (e) {
    if (e && typeof e === 'object' && 'digest' in e) throw e // redirect()
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

export async function addAttachment(prId: string | null, frId: string | null, path: string, name: string) {
  const supabase = await createClient()
  const { error } = await supabase.rpc('add_attachment', { p_pr: prId, p_fr: frId, p_path: path, p_name: name })
  if (error) {
    await supabase.storage.from('attachments').remove([path])
    return { error: error.message }
  }
  revalidatePath('/', 'layout')
  return { ok: 'File attached.' }
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

async function requireAdmin() {
  const supabase = await createClient()
  const { data } = await supabase.rpc('has_role', { r: 'admin' })
  if (!data) throw new Error('This needs the Admin role.')
  return supabase
}

export async function adminUpdateUser(_: ActionState, fd: FormData): Promise<ActionState> {
  try {
    const supabase = await requireAdmin()
    const { error } = await supabase.rpc('admin_update_user', {
      p_id: str(fd, 'id'),
      p: {
        full_name: str(fd, 'full_name'),
        roles: fd.getAll('roles').map(String),
        mobile_no: str(fd, 'mobile_no'),
        default_payment_approver: str(fd, 'default_payment_approver'),
        default_fund_approver: str(fd, 'default_fund_approver'),
        active: fd.get('active') === 'on',
      },
    })
    if (error) return { error: error.message }
    return done('User saved.')
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

// Move one person's open work to another (someone left on short notice).
export async function adminHandOver(_: ActionState, fd: FormData): Promise<ActionState> {
  try {
    const supabase = await requireAdmin()
    const { data, error } = await supabase.rpc('admin_hand_over', { p_from: str(fd, 'from'), p_to: str(fd, 'to') })
    if (error) return { error: error.message }
    const n = data as { payment_approvals: number; fund_approvals: number; fund_requests: number }
    return done(
      `Handed over: ${n.payment_approvals} payment requests to approve, ${n.fund_approvals} fund requests to approve, ${n.fund_requests} fund requests in preparation. Default approvers were updated too.`,
    )
  } catch (e) {
    return { error: (e as Error).message }
  }
}

export async function adminCreateUser(_: ActionState, fd: FormData): Promise<ActionState> {
  try {
    await requireAdmin()
    const email = str(fd, 'email')
    const password = String(fd.get('password') ?? '')
    if (!email) return { error: 'Email is required.' }
    if (password.length < 8) return { error: 'The temporary password needs at least 8 characters.' }
    const admin = createAdminClient()
    const { error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: str(fd, 'full_name') ?? email.split('@')[0] },
    })
    if (error) return { error: error.message }
    return done(`Account created for ${email}. Set their roles below.`)
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

export async function adminLookup(_: ActionState, fd: FormData): Promise<ActionState> {
  const supabase = await createClient()
  const op = str(fd, 'op')
  let error
  if (op === 'add') {
    const rate = str(fd, 'rate')
    ;({ error } = await supabase.from('lookups').insert({
      list: str(fd, 'list'),
      label: str(fd, 'label'),
      rate: rate === null ? null : Number(rate),
      sort: Number(str(fd, 'sort') ?? 99),
    }))
  } else if (op === 'toggle') {
    ;({ error } = await supabase.from('lookups').update({ active: fd.get('active') === 'true' }).eq('id', str(fd, 'id')))
  }
  if (error) return { error: error.message }
  return done('List updated.')
}

export async function sendQueuedSmsNow(): Promise<ActionState> {
  try {
    await requireAdmin()
    const r = await dispatchQueuedSms(200)
    revalidatePath('/admin')
    return { ok: `Sent ${r.sent}, failed ${r.failed}.` }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
