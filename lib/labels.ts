import type { Role, Status } from './types'
import { fmtDate } from './format'

export const STATUS_LABEL: Record<Status, string> = {
  draft: 'Draft',
  pending_payment_approval: 'Pending Payment Approval',
  returned_to_requestor: 'Returned to Requestor',
  expired: 'Expired',
  cancelled: 'Cancelled',
  approved_awaiting_funding: 'Approved – Preparing for Fund request', // Ruth, 10 November
  in_funding_preparation: 'In Funding Preparation',
  pending_fund_approval: 'Pending Fund Approval',
  returned_to_fund_requestor: 'Returned to Fund Requestor',
  approved_ready_for_qb: 'Approved',
  approved_posted_to_qb: 'Exported to QuickBooks – Locked',
  sync_failed: 'Sync Failed',
}

export const STATUS_TONE: Record<Status, 'neutral' | 'pending' | 'warn' | 'good' | 'bad'> = {
  draft: 'neutral',
  pending_payment_approval: 'pending',
  returned_to_requestor: 'warn',
  expired: 'bad',
  cancelled: 'neutral',
  approved_awaiting_funding: 'pending',
  in_funding_preparation: 'pending',
  pending_fund_approval: 'pending',
  returned_to_fund_requestor: 'warn',
  approved_ready_for_qb: 'good',
  approved_posted_to_qb: 'good',
  sync_failed: 'bad',
}

export const ROLE_LABEL: Record<Role, string> = {
  payment_requestor: 'Payment Requestor',
  payment_approver: 'Payment Approver',
  fund_requestor: 'Fund Requestor',
  fund_approver: 'Fund Approver',
  admin: 'Admin',
}

export const ROLES = Object.keys(ROLE_LABEL) as Role[]

// What each self-started fund request type is for (Ruth, 1 November).
export const AUTO_DEBIT_HELP =
  "Paid straight from the disbursement account with no cheque issued: manager's check (MC), auto deduct, or direct payment to an account."
export const FUND_REQUEST_HELP = 'Paid by cheque for the NCR or VisMin region: the funds are withdrawn, or someone is paid, using a cheque.'
export const REIMBURSABLE_HELP = 'Like a fund request, for spending that is to be reimbursed.'

export const REQUEST_TYPE_LABEL: Record<number, string> = {
  1: 'Auto debit request',
  2: 'NCR fund request',
  3: 'VisMin fund request',
  4: 'NCR reimbursable fund request',
  5: 'VisMin reimbursable fund request',
}

export const TERMS = [
  'The requestor must collect the receipts from the customer and surrender them within three (3) working days from the date of issuance, to avoid penalties.',
  'For an unused or cancelled cheque, return the cheque to the Accounting Department immediately, to avoid penalties.',
  'If a cash cheque or cash is lost, the bearer or requestor is 100% liable and must refund or return the entire amount requested to the company within three (3) days.',
]

const PO_MODE_LABEL: Record<string, string> = {
  'D/P': 'D/P down payment',
  FB: 'FB final billing',
  FP: 'FP full payment (100%)',
}

// "PB 2" -> "PB progress billing 2"
export function poModeLabel(mode: string | null) {
  if (!mode) return null
  const [code, no] = mode.split(' ')
  if (code === 'PB') return no ? `PB progress billing ${no}` : 'PB progress billing'
  return PO_MODE_LABEL[code] ?? mode
}

// The five fund request types (Ruth, 10 November). The old Check payment
// request (type 2 with no payment request) is now an NCR fund request.
type FRType = { request_type: number; payment_request_id: string | null }
export function frTypeLabel(f: FRType) {
  return REQUEST_TYPE_LABEL[f.request_type]
}
export function frTypeHelp(f: FRType) {
  if (f.payment_request_id) return undefined
  return f.request_type === 1 ? AUTO_DEBIT_HELP : f.request_type >= 4 ? REIMBURSABLE_HELP : FUND_REQUEST_HELP
}
// Types a Fund Requestor may start: all five, or only their region's.
export function newFundRequestTypes(region: 'NCR' | 'VisMin' | null) {
  return region === 'VisMin' ? [1, 3, 5] : region === 'NCR' ? [1, 2, 4] : [1, 2, 3, 4, 5]
}

// Sidebar lists: before and after each approval stage.
export const PR_OPEN_STATUSES = ['draft', 'pending_payment_approval', 'returned_to_requestor', 'expired']
export const PR_APPROVED_STATUSES = [
  'approved_awaiting_funding',
  'in_funding_preparation',
  'pending_fund_approval',
  'returned_to_fund_requestor',
  'approved_ready_for_qb',
  'approved_posted_to_qb',
  'sync_failed',
]
// Statuses a payment request can still be deleted in (before funding starts).
// Payment request "Request type" (Ruth, 1 November).
export const PR_KIND_LABEL: Record<string, string> = {
  regular: 'Regular fund request (check payment & cash)',
  auto_debit: 'Auto debit (direct debit & MC)',
  reimbursable: 'Reimbursable fund request',
  request_for_payment: 'Request for payment',
}
export const prKindLabel = (r: { request_kind?: string | null; reimbursable: boolean }) =>
  PR_KIND_LABEL[r.request_kind ?? (r.reimbursable ? 'reimbursable' : 'regular')]

// Region of a fund request: from its payment request, else from its type (3/5 VisMin).
// A standalone auto debit or check payment request has none and counts as NCR.
export const frRegionOf = (f: { region?: string | null; request_type: number }): 'NCR' | 'VisMin' =>
  f.region === 'VisMin' || f.request_type === 3 || f.request_type === 5 ? 'VisMin' : 'NCR'

export const PR_DELETABLE: string[] = [
  'draft',
  'pending_payment_approval',
  'returned_to_requestor',
  'expired',
]
// Approved requests are registered and can no longer be deleted (Ruth, 5 November).
// Except by an Admin who is both its requestor and its approver: they may
// delete it up to the approved stage, until its fund request is approved (Ruth, 9 November).
export const PR_DELETABLE_BY_SELF_APPROVER: string[] = [
  'approved_awaiting_funding',
  'in_funding_preparation',
  'pending_fund_approval',
  'returned_to_fund_requestor',
]
export const FR_OPEN_STATUSES = ['in_funding_preparation', 'pending_fund_approval', 'returned_to_fund_requestor']
export const FR_APPROVED_STATUSES = ['approved_ready_for_qb', 'approved_posted_to_qb', 'sync_failed']

// Funding stages after approval (Ruth, 10 November): approved for funding,
// which the requestor sees as preparing for funding, then funded on the date
// the Fund Approver typed, then exported to QuickBooks.
type FRStage = { status: Status; ready_for_funding_at?: string | null; funded_at?: string | null; funded_on?: string | null }
export function frStatusLabel(f: FRStage) {
  if (f.status === 'approved_ready_for_qb' || f.status === 'sync_failed') {
    const base = f.status === 'sync_failed' ? 'Sync Failed · ' : ''
    if (f.funded_at) return base + (f.funded_on ? `Funded ${fmtDate(f.funded_on)}` : 'Funded')
    return base + 'Approved – Preparing for funding'
  }
  return STATUS_LABEL[f.status]
}
// The voucher (Ruth, 10 November): Admins and Fund Approvers see it from fund
// approval; Fund Requestors (and anyone else who can see the request) once it
// is ready for funding, then funded, then exported. Mirrors can_see_voucher
// in the database, which enforces it.
type VoucherStage = FRStage & { locked?: boolean | null }
export function canSeeVoucher(f: VoucherStage, is: (role: Role) => boolean) {
  if (!f.locked || !FR_APPROVED_STATUSES.includes(f.status)) return false
  if (is('admin') || is('fund_approver')) return true
  return !!(f.ready_for_funding_at || f.funded_at || f.status === 'approved_posted_to_qb')
}

// Who may edit a fund request, and how (Ruth, 10 November). Mirrors
// fund_request_edit_mode in the database, which enforces it.
//   prep      being prepared: edit, then send for approval;
//   in_place  already sent or approved: save changes with remarks, the status stays;
//   withdraw  its requestor's own request waiting for approval: take it back first.
// A Fund Requestor may edit their own request until it is approved (Ruth,
// 10 November); after that only an Admin or a Fund Approver corrects it. Cancelled requests and
// requests exported to QuickBooks stay locked.
export type FREditMode = 'prep' | 'in_place' | 'withdraw' | null
type FREditable = { status: Status; locked?: boolean | null; fund_requestor_id: string; funded_at?: string | null }
export function frEditMode(f: FREditable, is: (role: Role) => boolean, meId: string): FREditMode {
  if (f.status === 'cancelled' || f.status === 'approved_posted_to_qb') return null
  const staff = is('admin') || is('fund_approver')
  if (!f.locked && (f.status === 'in_funding_preparation' || f.status === 'returned_to_fund_requestor')) {
    return staff || is('fund_requestor') ? 'prep' : null
  }
  if (!['pending_fund_approval', 'approved_ready_for_qb', 'sync_failed'].includes(f.status)) return null
  if (staff) return 'in_place'
  if (!is('fund_requestor') || f.fund_requestor_id !== meId) return null
  return f.status === 'pending_fund_approval' ? 'withdraw' : null
}

// Admins and Fund Approvers who also prepare fund requests can send and approve their own in one click (Ruth, 5 November).
// Only on their own requests: other requestors' requests get Approve once sent.
export const canSubmitApprove = (f: { status: string; locked?: boolean | null; fund_requestor_id: string }, is: (role: Role) => boolean, meId: string) =>
  f.fund_requestor_id === meId && is('fund_requestor') && is('fund_approver') && !f.locked && ['in_funding_preparation', 'returned_to_fund_requestor'].includes(f.status)
