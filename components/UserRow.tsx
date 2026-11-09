'use client'

import { Message, Submit, useSubmit } from '@/components/ActionForm'
import { adminDeleteUser, adminUpdateUser } from '@/app/actions'
import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { ROLE_LABEL, ROLES } from '@/lib/labels'
import type { Profile } from '@/lib/types'
import { EmployeeRegion } from './EmployeeRegion'

// One editable row of the Admin users table. A <form> can't wrap a <tr>, so
// the form sits in the last cell and the inputs join it with form={formId}.
export function UserRow({ user, pas, fas }: { user: Profile; pas: Profile[]; fas: Profile[] }) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(adminUpdateUser)
  const f = `user-${user.id}`
  const [deleting, startDelete] = useTransition()
  const router = useRouter()
  const onDelete = () => {
    if (!window.confirm(`Delete ${user.full_name} (${user.email}) for good? They will no longer be able to sign in. This cannot be undone.`)) return
    const fd = new FormData()
    fd.set('id', user.id)
    startDelete(async () => {
      const res = await adminDeleteUser(null, fd)
      window.alert(res?.error ?? `${user.full_name} was deleted.`)
      router.refresh()
    })
  }
  return (
    <tr>
      <td>
        <input form={f} name="full_name" defaultValue={user.full_name} aria-label="Name" />
        <div className="small muted email">{user.email}</div>
      </td>
      <td>
        <input form={f} name="mobile_no" defaultValue={user.mobile_no ?? ''} placeholder="09171234567" aria-label="Mobile (SMS)" />
      </td>
      <td>
        <div className="role-list">
          {ROLES.map((r) => (
            <label key={r} className="check small">
              <input form={f} type="checkbox" name="roles" value={r} defaultChecked={user.roles.includes(r)} /> {ROLE_LABEL[r]}
            </label>
          ))}
        </div>
        <EmployeeRegion form={f} employeeId={user.employee_id ?? ''} region={user.region ?? ''} small />
      </td>
      <td>
        <label className="field small">
          <span className="label">Payment approver</span>
          <select form={f} name="default_payment_approver" defaultValue={user.default_payment_approver ?? ''}>
            <option value="">None</option>
            {pas.filter((p) => p.id !== user.id).map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
              </option>
            ))}
          </select>
        </label>
        <label className="field small">
          <span className="label">Fund approver</span>
          <select form={f} name="default_fund_approver" defaultValue={user.default_fund_approver ?? ''}>
            <option value="">None</option>
            {fas.filter((p) => p.id !== user.id).map((p) => (
              <option key={p.id} value={p.id}>
                {p.full_name}
              </option>
            ))}
          </select>
        </label>
      </td>
      <td>
        <input form={f} type="checkbox" name="active" defaultChecked={user.active} aria-label="Active" />
      </td>
      <td>
        <form id={f} onSubmit={onSubmit}>
          <PendingProvider value={pending}>
            <input type="hidden" name="id" value={user.id} />
            <Submit className="btn small">Save</Submit>
            <button type="button" className="btn small danger secondary" onClick={onDelete} disabled={deleting}>
              {deleting ? 'Deleting…' : 'Delete'}
            </button>
            <Message state={state} />
          </PendingProvider>
        </form>
      </td>
    </tr>
  )
}
