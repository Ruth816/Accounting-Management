import { redirect } from 'next/navigation'
import { getDirectory, getMe } from '@/lib/auth'
import { PaymentRequestForm } from '@/components/PaymentRequestForm'

export default async function NewPaymentRequest() {
  const { me, is } = await getMe()
  if (!is('payment_requestor')) redirect('/')
  const { people } = await getDirectory()
  const approvers = people.filter((p) => p.active && p.roles.includes('payment_approver') && p.id !== me.id)
  return (
    <div className="stack">
      <h1>New payment request</h1>
      <PaymentRequestForm pr={null} approvers={approvers} defaultApprover={me.default_payment_approver} requestorName={me.full_name} />
      <p className="muted small">Save the draft first to attach files.</p>
    </div>
  )
}
