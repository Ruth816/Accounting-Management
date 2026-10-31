import type { Role, Status } from './types'

export const STATUS_LABEL: Record<Status, string> = {
  draft: 'Draft',
  pending_payment_approval: 'Pending Payment Approval',
  returned_to_requestor: 'Returned to Requestor',
  expired: 'Expired',
  cancelled: 'Cancelled',
  approved_awaiting_funding: 'Approved – Awaiting Funding',
  in_funding_preparation: 'In Funding Preparation',
  pending_fund_approval: 'Pending Fund Approval',
  returned_to_fund_requestor: 'Returned to Fund Requestor',
  approved_ready_for_qb: 'Approved – Ready for QuickBooks',
  approved_posted_to_qb: 'Approved – Posted to QuickBooks',
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
