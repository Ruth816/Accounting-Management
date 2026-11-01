import { redirect } from 'next/navigation'
import { getDirectory, getMe } from '@/lib/auth'
import { PaymentRequestForm } from '@/components/PaymentRequestForm'
import { getRoutes, routeHint } from '@/lib/routes'

export default async function NewPaymentRequest() {
  const { me, is, myRegion } = await getMe()
  if (!is('payment_requestor')) redirect('/')
  const { people } = await getDirectory()
  const approvers = people.filter((p) => p.active && p.roles.includes('payment_approver') && p.id !== me.id)
  const hint = await routeHint(await getRoutes())
  return (
    <div className="stack">
      <h1>New payment request</h1>
      <PaymentRequestForm pr={null} approvers={approvers} defaultApprover={me.default_payment_approver} requestorName={me.full_name} routeHint={hint} lockedRegion={myRegion} />
      <p className="muted small">Save the draft first to attach files.</p>
    </div>
  )
}
