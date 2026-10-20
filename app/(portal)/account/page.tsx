import { getMe } from '@/lib/auth'
import { ROLE_LABEL } from '@/lib/labels'
import { ActionForm, Submit } from '@/components/ActionForm'
import { changePassword } from '@/app/actions'

export default async function AccountPage() {
  const { me } = await getMe()
  return (
    <div className="stack narrow">
      <h1>Your account</h1>
      <section className="card">
        <p>
          <strong>{me.full_name}</strong> · {me.email}
        </p>
        <p className="muted">Roles: {me.roles.map((r) => ROLE_LABEL[r]).join(', ') || 'none'}</p>
        <p className="muted">SMS number: {me.mobile_no ?? 'not set (ask an Admin)'}</p>
      </section>
      <section className="card">
        <h2>Change password</h2>
        <ActionForm action={changePassword} className="stack">
          <label className="field">
            <span className="label">New password</span>
            <input type="password" name="password" autoComplete="new-password" minLength={8} required />
          </label>
          <Submit>Change password</Submit>
        </ActionForm>
      </section>
    </div>
  )
}
