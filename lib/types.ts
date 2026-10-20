export type Role = 'payment_requestor' | 'payment_approver' | 'fund_requestor' | 'fund_approver' | 'admin'

export type Status =
  | 'draft'
  | 'pending_payment_approval'
  | 'returned_to_requestor'
  | 'expired'
  | 'cancelled'
  | 'approved_awaiting_funding'
  | 'in_funding_preparation'
  | 'pending_fund_approval'
  | 'returned_to_fund_requestor'
  | 'approved_ready_for_qb'
  | 'approved_posted_to_qb'
  | 'sync_failed'

export type Currency = 'PHP' | 'USD'

export interface Profile {
  id: string
  full_name: string
  email: string
  roles: Role[]
  mobile_no: string | null
  default_payment_approver: string | null
  default_fund_approver: string | null
  active: boolean
}

export interface Person {
  id: string
  full_name: string
  email: string
  roles: Role[]
  active: boolean
}

export interface Item {
  description: string
  amount: number | null
}

export interface PaymentRequest {
  id: string
  req_no: string
  requestor_id: string
  approver_id: string | null
  status: Status
  version: number
  reimbursable: boolean
  region: 'NCR' | 'VisMin'
  project_name: string | null
  project_type: string | null
  job_order_no: string | null
  addendum_no: string | null
  work_order_no: string | null
  date_required: string | null
  payable_to: string | null
  payment_type: 'Cash' | 'Cheque' | 'Bank deposit'
  billing_type: 'VAT' | 'Non-VAT' | 'Ack/R' | 'Pakyaw'
  currency: Currency
  purpose: string | null
  items: Item[]
  item_no: string | null
  po_num: string | null
  po_date: string | null
  po_amount: number | null
  po_mode: 'D/P' | 'PB' | 'FB' | null
  last_payment_ref: string | null
  wtax_rate: number
  bank_transfer_fee: number | null
  total_vat_in: number
  total_vat_ex: number
  wtax_amount: number
  total_due: number
  terms_accepted: boolean
  disapproval_reason: string | null
  return_note: string | null
  returned_on: string | null
  expires_on: string | null
  submitted_on: string | null
  approved_on: string | null
  fund_request_id: string | null
  liq_actual_used: number | null
  liq_change: number | null
  liq_deposit_date: string | null
  liq_deposit_amount: number | null
  liq_deposit_bank: string | null
  liquidated_on: string | null
  created_at: string
  updated_at: string
}

export interface FundRequest {
  id: string
  request_type: 1 | 2 | 3 | 4 | 5
  payment_request_id: string | null
  fund_requestor_id: string
  fund_approver_id: string | null
  status: Status
  ref_no: string | null
  payee: string | null
  item_no: string | null
  description: string | null
  currency: Currency
  original_amount: number | null
  exchange_rate: number | null
  rate_date: string | null
  payment_date: string | null
  payment_method: 'Check' | 'Auto debit' | 'Bank transfer' | 'Cash' | null
  cash_received_by: string | null
  bank_account_name: string | null
  bank_account_no: string | null
  amount_php: number | null
  tax_code: string | null
  tax_rate: number | null
  total_before_tax: number | null
  sales_tax: number | null
  payment_account: string | null
  category: string | null
  memo: string | null
  memo_edited: boolean
  wtax_note: string | null
  tax_locked: boolean
  cheque_id: string | null
  subtotal_to_fund: number | null
  reviewed: boolean
  disapproval_reason: string | null
  submitted_on: string | null
  approved_by: string | null
  approved_on: string | null
  locked: boolean
  qb_txn_id: string | null
  qb_sync_error: string | null
  created_at: string
  updated_at: string
}

export interface Lookup {
  id: string
  list: 'payment_method' | 'payment_account' | 'category' | 'tax_code'
  label: string
  rate: number | null
  sort: number
  active: boolean
}

export interface AuditEntry {
  id: number
  payment_request_id: string | null
  fund_request_id: string | null
  ref: string | null
  action: string
  actor_id: string | null
  old_status: Status | null
  new_status: Status | null
  note: string | null
  created_at: string
}

export interface Attachment {
  id: string
  payment_request_id: string | null
  fund_request_id: string | null
  storage_path: string
  file_name: string
  uploaded_by: string
  created_at: string
}

export interface Notification {
  id: string
  recipient_id: string
  message: string
  payment_request_id: string | null
  fund_request_id: string | null
  read: boolean
  sms_status: 'Queued' | 'Sending' | 'Sent' | 'Failed' | 'No mobile'
  sms_mobile_no: string | null
  sms_message_id: string | null
  sms_error: string | null
  created_at: string
}

export interface Version {
  id: string
  payment_request_id: string
  version: number
  snapshot: PaymentRequest
  reason: string
  returned_by: string | null
  created_at: string
}

export type ActionState = { error?: string; ok?: string } | null
