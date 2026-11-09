import 'server-only'
import crypto from 'node:crypto'
import { createAdminClient } from './supabase/admin'
import { buildExpense, expenseLines, expenseTotal, ExpenseError, type QbEntity, type QbRef } from './qboExpense'
import type { FundRequest } from './types'

// QuickBooks Online: OAuth 2.0 connection, list sync (Phase 2) and Expense
// posting (Phase 3). Everything runs on the server; tokens never reach the browser.

const AUTH_URL = 'https://appcenter.intuit.com/connect/oauth2'
const TOKEN_URL = 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
const REVOKE_URL = 'https://developer.api.intuit.com/v2/oauth2/tokens/revoke'
const API_BASE = {
  sandbox: 'https://sandbox-quickbooks.api.intuit.com',
  production: 'https://quickbooks.api.intuit.com',
}
const MINOR_VERSION = '75'
const SCOPE = 'com.intuit.quickbooks.accounting'

export type QbEnvironment = 'sandbox' | 'production'
export const qbEnvironment = (): QbEnvironment => (process.env.QBO_ENVIRONMENT === 'production' ? 'production' : 'sandbox')

// What is missing in Vercel before QuickBooks can be connected, or null.
export function qbConfigProblem(): string | null {
  const missing = ['QBO_CLIENT_ID', 'QBO_CLIENT_SECRET', 'QBO_TOKEN_KEY'].filter((k) => !process.env[k])
  if (missing.length) return `Add ${missing.join(', ')} in Vercel → Settings → Environment Variables, then redeploy.`
  if ((process.env.QBO_TOKEN_KEY ?? '').length < 32) return 'QBO_TOKEN_KEY must be at least 32 characters long.'
  return null
}

export const redirectUri = (origin: string) => process.env.QBO_REDIRECT_URI || `${origin}/api/quickbooks/callback`

export function authorizeUrl(state: string, origin: string) {
  const u = new URL(AUTH_URL)
  u.searchParams.set('client_id', process.env.QBO_CLIENT_ID!)
  u.searchParams.set('response_type', 'code')
  u.searchParams.set('scope', SCOPE)
  u.searchParams.set('redirect_uri', redirectUri(origin))
  u.searchParams.set('state', state)
  return u.toString()
}

// ---------------------------------------------------------------------------
// Token encryption (AES-256-GCM, key from QBO_TOKEN_KEY)
// ---------------------------------------------------------------------------

const key = () => crypto.createHash('sha256').update(process.env.QBO_TOKEN_KEY ?? '').digest()

export function seal(plain: string) {
  const iv = crypto.randomBytes(12)
  const c = crypto.createCipheriv('aes-256-gcm', key(), iv)
  const data = Buffer.concat([c.update(plain, 'utf8'), c.final()])
  return ['v1', iv.toString('base64'), c.getAuthTag().toString('base64'), data.toString('base64')].join(':')
}

export function unseal(sealed: string) {
  const [v, iv, tag, data] = sealed.split(':')
  if (v !== 'v1') throw new Error('Unknown token format.')
  const d = crypto.createDecipheriv('aes-256-gcm', key(), Buffer.from(iv, 'base64'))
  d.setAuthTag(Buffer.from(tag, 'base64'))
  return Buffer.concat([d.update(Buffer.from(data, 'base64')), d.final()]).toString('utf8')
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

type ConnectionRow = {
  environment: QbEnvironment
  realm_id: string
  company_name: string | null
  access_token: string
  refresh_token: string
  access_expires_at: string
  refresh_expires_at: string | null
  connected_by: string | null
  connected_at: string
  last_sync_at: string | null
  last_sync_error: string | null
}
export type QbStatus = Omit<ConnectionRow, 'access_token' | 'refresh_token'>

type TokenReply = { access_token: string; refresh_token: string; expires_in: number; x_refresh_token_expires_in?: number }

async function tokenRequest(body: Record<string, string>): Promise<TokenReply> {
  const basic = Buffer.from(`${process.env.QBO_CLIENT_ID}:${process.env.QBO_CLIENT_SECRET}`).toString('base64')
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { Authorization: `Basic ${basic}`, Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(body),
    cache: 'no-store',
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(`QuickBooks sign-in failed: ${json.error_description ?? json.error ?? res.status}`)
  return json as TokenReply
}

const tokenFields = (t: TokenReply) => ({
  access_token: seal(t.access_token),
  refresh_token: seal(t.refresh_token),
  access_expires_at: new Date(Date.now() + t.expires_in * 1000).toISOString(),
  refresh_expires_at: t.x_refresh_token_expires_in
    ? new Date(Date.now() + t.x_refresh_token_expires_in * 1000).toISOString()
    : null,
})

// After the Admin signs in to Intuit: store the company and its tokens.
export async function connectWithCode(code: string, realmId: string, origin: string, userId: string) {
  const t = await tokenRequest({ grant_type: 'authorization_code', code, redirect_uri: redirectUri(origin) })
  const admin = createAdminClient()
  const { error } = await admin.from('qb_connection').upsert({
    id: true,
    environment: qbEnvironment(),
    realm_id: realmId,
    company_name: null,
    connected_by: userId,
    connected_at: new Date().toISOString(),
    last_sync_at: null,
    last_sync_error: null,
    ...tokenFields(t),
  })
  if (error) throw new Error(error.message)
  try {
    const info = await qbFetch(`/companyinfo/${realmId}`)
    await admin.from('qb_connection').update({ company_name: info.CompanyInfo?.CompanyName ?? null }).eq('id', true)
  } catch (e) {
    console.error('QuickBooks company info failed', e)
  }
}

async function loadConnection(): Promise<ConnectionRow | null> {
  const { data, error } = await createAdminClient().from('qb_connection').select('*').maybeSingle()
  if (error) throw new Error(error.message)
  return data as ConnectionRow | null
}

export async function qbStatus(): Promise<QbStatus | null> {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return null
  const row = await loadConnection()
  if (!row) return null
  const { access_token: _a, refresh_token: _r, ...rest } = row
  return rest
}

export async function qbConnected() {
  if (qbConfigProblem()) return false
  return !!(await loadConnection())
}

export async function disconnect() {
  const row = await loadConnection()
  if (!row) return
  try {
    const basic = Buffer.from(`${process.env.QBO_CLIENT_ID}:${process.env.QBO_CLIENT_SECRET}`).toString('base64')
    await fetch(REVOKE_URL, {
      method: 'POST',
      headers: { Authorization: `Basic ${basic}`, Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: unseal(row.refresh_token) }),
    })
  } catch (e) {
    console.error('QuickBooks revoke failed', e)
  }
  const { error } = await createAdminClient().from('qb_connection').delete().eq('id', true)
  if (error) throw new Error(error.message)
}

// A valid access token, refreshed when it is within 5 minutes of expiring.
async function session() {
  const row = await loadConnection()
  if (!row) throw new Error('QuickBooks is not connected. An Admin can connect it under Admin → QuickBooks.')
  if (row.environment !== qbEnvironment()) {
    throw new Error(`QuickBooks was connected in ${row.environment} but QBO_ENVIRONMENT is ${qbEnvironment()}. Disconnect and connect again.`)
  }
  if (new Date(row.access_expires_at).getTime() - Date.now() > 5 * 60 * 1000) {
    return { realm: row.realm_id, token: unseal(row.access_token), env: row.environment }
  }
  let t: TokenReply
  try {
    t = await tokenRequest({ grant_type: 'refresh_token', refresh_token: unseal(row.refresh_token) })
  } catch (e) {
    throw new Error(`${e instanceof Error ? e.message : e}. An Admin may need to connect QuickBooks again.`)
  }
  const { error } = await createAdminClient().from('qb_connection').update(tokenFields(t)).eq('id', true)
  if (error) throw new Error(error.message)
  return { realm: row.realm_id, token: t.access_token, env: row.environment }
}

// ---------------------------------------------------------------------------
// API calls
// ---------------------------------------------------------------------------

type Fault = { Fault?: { Error?: { Message?: string; Detail?: string; code?: string }[] } }
function faultText(json: Fault, status: number) {
  const errs = json.Fault?.Error ?? []
  if (!errs.length) return `QuickBooks answered ${status}.`
  return errs.map((e) => [e.Message, e.Detail].filter(Boolean).join(': ')).join('; ')
}

async function qbFetch(path: string, init: { method?: string; body?: unknown; form?: FormData } = {}) {
  const s = await session()
  const url = new URL(`${API_BASE[s.env]}/v3/company/${s.realm}${path}`)
  url.searchParams.set('minorversion', MINOR_VERSION)
  const headers: Record<string, string> = { Authorization: `Bearer ${s.token}`, Accept: 'application/json' }
  if (init.body !== undefined) headers['Content-Type'] = 'application/json'
  const res = await fetch(url, {
    method: init.method ?? (init.body !== undefined || init.form ? 'POST' : 'GET'),
    headers,
    body: init.form ?? (init.body !== undefined ? JSON.stringify(init.body) : undefined),
    cache: 'no-store',
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok || json.Fault) throw new Error(faultText(json, res.status))
  return json
}

const q = (s: string) => s.replace(/\\/g, '\\\\').replace(/'/g, "\\'")

// Runs a query, following pages of 1000.
async function queryAll<T>(entity: string, where = ''): Promise<T[]> {
  const out: T[] = []
  for (let start = 1; ; start += 1000) {
    const sql = `select * from ${entity}${where ? ` where ${where}` : ''} startposition ${start} maxresults 1000`
    const json = await qbFetch(`/query?query=${encodeURIComponent(sql)}`)
    const rows = (json.QueryResponse?.[entity] ?? []) as T[]
    out.push(...rows)
    if (rows.length < 1000) return out
  }
}

// ---------------------------------------------------------------------------
// Phase 2: dropdown lists from QuickBooks
// ---------------------------------------------------------------------------

type QbAccount = { Id: string; FullyQualifiedName: string; AccountType: string; Active: boolean }
type QbNamed = { Id: string; Name: string; Active?: boolean }
type QbTaxCode = QbNamed & { PurchaseTaxRateList?: { TaxRateDetail?: { TaxRateRef: { value: string } }[] } }
type QbTaxRate = { Id: string; RateValue?: number }

const CATEGORY_TYPES = ['Expense', 'Other Expense', 'Cost of Goods Sold']
const PAYMENT_ACCOUNT_TYPES = ['Bank', 'Credit Card', 'Other Current Asset']

export async function syncLists() {
  const admin = createAdminClient()
  try {
    const [accounts, methods, taxCodes, taxRates] = await Promise.all([
      queryAll<QbAccount>('Account', 'Active = true'),
      queryAll<QbNamed>('PaymentMethod', 'Active = true'),
      queryAll<QbTaxCode>('TaxCode', 'Active = true'),
      queryAll<QbTaxRate>('TaxRate'),
    ])
    const rateOf = new Map(taxRates.map((r) => [r.Id, Number(r.RateValue ?? 0)]))
    const byName = (a: { label: string }, b: { label: string }) => a.label.localeCompare(b.label)
    const acc = (types: string[]) =>
      accounts
        .filter((a) => types.includes(a.AccountType))
        .map((a) => ({ label: a.FullyQualifiedName, qb_id: a.Id, qb_type: a.AccountType, rate: null }))
        .sort((a, b) => types.indexOf(a.qb_type) - types.indexOf(b.qb_type) || byName(a, b))
    const lists = {
      category: acc(CATEGORY_TYPES),
      payment_account: acc(PAYMENT_ACCOUNT_TYPES),
      payment_method: methods.map((m) => ({ label: m.Name, qb_id: m.Id, qb_type: null, rate: null })).sort(byName),
      // Only tax codes that apply to purchases, with their combined rate as a fraction (12% = 0.12).
      tax_code: taxCodes
        .filter((t) => (t.PurchaseTaxRateList?.TaxRateDetail ?? []).length > 0)
        .map((t) => ({
          label: t.Name,
          qb_id: t.Id,
          qb_type: null,
          rate: Math.round((t.PurchaseTaxRateList!.TaxRateDetail!.reduce((s, d) => s + (rateOf.get(d.TaxRateRef.value) ?? 0), 0) / 100) * 10000) / 10000,
        }))
        .sort(byName),
    }
    const { data, error } = await admin.rpc('qb_apply_lists', { p_lists: lists })
    if (error) throw new Error(error.message)
    await admin.from('qb_connection').update({ last_sync_at: new Date().toISOString(), last_sync_error: null }).eq('id', true)
    return data as Record<string, number>
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    await admin.from('qb_connection').update({ last_sync_error: msg.slice(0, 1000) }).eq('id', true)
    throw e
  }
}

// ---------------------------------------------------------------------------
// Phase 3: post a fund request as an Expense
// ---------------------------------------------------------------------------

async function findEntity(name: string): Promise<QbEntity | null> {
  for (const type of ['Vendor', 'Customer', 'Employee'] as const) {
    const rows = await queryAll<{ Id: string }>(type, `DisplayName = '${q(name)}'`)
    if (rows[0]) return { id: rows[0].Id, type }
  }
  return null
}

async function payeeEntity(payee: string | null): Promise<QbEntity | null> {
  const name = payee?.trim()
  if (!name) return null
  const found = await findEntity(name)
  if (found) return found
  // A payee QuickBooks doesn't know yet is added as a vendor, as QuickBooks itself does.
  const json = await qbFetch('/vendor', { body: { DisplayName: name.slice(0, 500) } })
  return { id: json.Vendor.Id, type: 'Vendor' }
}

const CONTENT_TYPES: Record<string, string> = {
  pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', xls: 'application/vnd.ms-excel',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', doc: 'application/msword',
  csv: 'text/csv', txt: 'text/plain',
}

async function attachFiles(frId: string, txnId: string) {
  const admin = createAdminClient()
  const { data: files } = await admin.from('attachments').select('storage_path, file_name').eq('fund_request_id', frId).order('created_at')
  const failed: string[] = []
  for (const f of (files ?? []) as { storage_path: string; file_name: string }[]) {
    try {
      const { data: blob, error } = await admin.storage.from('attachments').download(f.storage_path)
      if (error || !blob) throw new Error(error?.message ?? 'not found')
      const ext = f.file_name.split('.').pop()?.toLowerCase() ?? ''
      const type = CONTENT_TYPES[ext]
      if (!type) throw new Error('QuickBooks does not take this file type')
      const form = new FormData()
      form.append(
        'file_metadata_01',
        new Blob([JSON.stringify({ AttachableRef: [{ EntityRef: { type: 'Purchase', value: txnId } }], FileName: f.file_name, ContentType: type })], { type: 'application/json' }),
        'attachment.json',
      )
      form.append('file_content_01', new Blob([await blob.arrayBuffer()], { type }), f.file_name)
      await qbFetch('/upload', { form })
    } catch (e) {
      failed.push(`${f.file_name} (${e instanceof Error ? e.message : e})`)
    }
  }
  return failed
}

// Creates the Expense in QuickBooks, or finds the one already there. Returns
// the QuickBooks ID and any attachment that could not be uploaded.
export async function postExpense(frId: string): Promise<{ txnId: string; warning: string | null }> {
  const admin = createAdminClient()
  const { data } = await admin.from('fund_requests').select('*').eq('id', frId).maybeSingle()
  const fr = data as FundRequest | null
  if (!fr) throw new Error('Fund request not found.')
  if (fr.qb_txn_id) return { txnId: fr.qb_txn_id, warning: null }

  const [{ data: pr }, { data: lookups }] = await Promise.all([
    fr.payment_request_id
      ? admin.from('payment_requests').select('bank_transfer_fee').eq('id', fr.payment_request_id).maybeSingle()
      : Promise.resolve({ data: null }),
    admin.from('lookups').select('list, label, qb_id, qb_type, rate'),
  ])
  const bankFee = pr?.bank_transfer_fee ? Number(pr.bank_transfer_fee) : null
  const rows = (lookups ?? []) as { list: string; label: string; qb_id: string | null; qb_type: string | null; rate: number | null }[]
  const ref = (lists: string[]) => (label: string): QbRef | undefined => {
    const l = rows.find((r) => lists.includes(r.list) && r.label === label && r.qb_id)
    return l ? { id: l.qb_id!, type: l.qb_type, rate: l.rate === null ? null : Number(l.rate) } : undefined
  }
  const refs = { account: ref(['payment_account', 'category']), method: ref(['payment_method']), tax: ref(['tax_code']) }

  const lines = expenseLines(fr, bankFee)
  // Already in QuickBooks (for example the last try timed out after QuickBooks saved it)?
  if (fr.ref_no) {
    const existing = await queryAll<{ Id: string; TotalAmt: number }>('Purchase', `DocNumber = '${q(fr.ref_no.slice(0, 21))}'`)
    const same = existing.find((p) => Math.abs(Number(p.TotalAmt) - expenseTotal(lines)) < 0.01)
    if (same) return { txnId: same.Id, warning: 'Found the Expense already in QuickBooks; linked it.' }
  }

  const customers = new Map<string, string>()
  for (const name of new Set(lines.map((l) => l.customer?.trim()).filter((n): n is string => !!n))) {
    const rowsC = await queryAll<{ Id: string }>('Customer', `DisplayName = '${q(name)}'`)
    if (rowsC[0]) customers.set(name, rowsC[0].Id)
  }
  // Check the lists before touching QuickBooks, so a bad category doesn't add a vendor.
  buildExpense(fr, bankFee, refs, null, customers)
  const entity = await payeeEntity(fr.payee)
  const body = buildExpense(fr, bankFee, refs, entity, customers)
  const json = await qbFetch('/purchase', { body })
  const txnId = String(json.Purchase.Id)
  const failed = await attachFiles(frId, txnId)
  return { txnId, warning: failed.length ? `Not attached in QuickBooks: ${failed.join(', ')}` : null }
}

export { ExpenseError }
