'use client'

import { Message, Submit, useSubmit } from '@/components/ActionForm'
import { adminUpdateUser } from '@/app/actions'
import { ROLE_LABEL, ROLES } from '@/lib/labels'
import type { Profile } from '@/lib/types'

// One editable row of the Admin users table. A <form> can't wrap a <tr>, so
// the form sits in the last cell and the inputs join it with form={formId}.
export function UserRow({ user, pas, fas }: { user: Profile; pas: Profile[]; fas: Profile[] }) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(adminUpdateUser)
  const f = `user-${user.id}`
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
        <label className="field small">
          <span className="label">Region (requestors see only this)</span>
          <select form={f} name="region" defaultValue={user.region ?? ''}>
            <option value="">Both regions</option>
            <option value="NCR">NCR only</option>
            <option value="VisMin">VisMin only</option>
          </select>
        </label>
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
            <Message state={state} />
          </PendingProvider>
        </form>
      </td>
    </tr>
  )
}
