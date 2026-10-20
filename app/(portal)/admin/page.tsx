import { redirect } from 'next/navigation'
import { getDirectory, getMe } from '@/lib/auth'
import { ActionForm, Submit } from '@/components/ActionForm'
import { adminCreateUser, adminLookup, adminUpdateUser, sendQueuedSmsNow } from '@/app/actions'
import { ROLE_LABEL, ROLES } from '@/lib/labels'
import { fmtDateTime } from '@/lib/format'
import { smsCredit } from '@/lib/sms'
import type { Lookup, Notification, Profile } from '@/lib/types'

const LISTS: [Lookup['list'], string][] = [
  ['payment_method', 'Payment methods'],
  ['payment_account', 'Payment accounts'],
  ['category', 'Categories'],
  ['tax_code', 'Tax codes'],
]

export default async function AdminPage() {
  const { supabase, is } = await getMe()
  if (!is('admin')) redirect('/')
  const { name } = await getDirectory()
  const [{ data: users }, { data: lookups }, { data: sms }, credit] = await Promise.all([
    supabase.from('profiles').select('*').order('full_name'),
    supabase.from('lookups').select('*').order('list').order('sort'),
    supabase.from('notifications').select('*').order('created_at', { ascending: false }).limit(100),
    smsCredit(),
  ])
  const profiles = (users ?? []) as Profile[]
  const pas = profiles.filter((p) => p.active && p.roles.includes('payment_approver'))
  const fas = profiles.filter((p) => p.active && p.roles.includes('fund_approver'))

  return (
    <div className="stack">
      <h1>Admin</h1>

      <section className="card">
        <h2>Add a user</h2>
        <ActionForm action={adminCreateUser} className="grid">
          <label className="field">
            <span className="label">Full name</span>
            <input name="full_name" required />
          </label>
          <label className="field">
            <span className="label">Email</span>
            <input type="email" name="email" required />
          </label>
          <label className="field">
            <span className="label">Temporary password</span>
            <input name="password" minLength={8} required autoComplete="off" />
          </label>
          <div className="actions">
            <Submit>Create account</Submit>
          </div>
        </ActionForm>
        <p className="small muted">Give the person their email and temporary password; they can change it under their name at the top.</p>
      </section>

      <section className="card">
        <h2>Users</h2>
        <div className="users">
          {profiles.map((u) => (
            <ActionForm key={u.id} action={adminUpdateUser} hidden={{ id: u.id }} className="user-row">
              <div className="grid">
                <label className="field">
                  <span className="label">Name</span>
                  <input name="full_name" defaultValue={u.full_name} />
                </label>
                <label className="field">
                  <span className="label">Email</span>
                  <input value={u.email} readOnly disabled />
                </label>
                <label className="field">
                  <span className="label">Mobile (SMS)</span>
                  <input name="mobile_no" defaultValue={u.mobile_no ?? ''} placeholder="09171234567" />
                </label>
                <label className="field">
                  <span className="label">Default payment approver</span>
                  <select name="default_payment_approver" defaultValue={u.default_payment_approver ?? ''}>
                    <option value="">None</option>
                    {pas.filter((p) => p.id !== u.id).map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.full_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span className="label">Default fund approver</span>
                  <select name="default_fund_approver" defaultValue={u.default_fund_approver ?? ''}>
                    <option value="">None</option>
                    {fas.filter((p) => p.id !== u.id).map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.full_name}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              <fieldset className="roles">
                <legend className="label">Roles</legend>
                {ROLES.map((r) => (
                  <label key={r} className="check">
                    <input type="checkbox" name="roles" value={r} defaultChecked={u.roles.includes(r)} /> {ROLE_LABEL[r]}
                  </label>
                ))}
                <label className="check">
                  <input type="checkbox" name="active" defaultChecked={u.active} /> Active
                </label>
              </fieldset>
              <Submit className="btn small">Save</Submit>
            </ActionForm>
          ))}
        </div>
      </section>

      <section className="card">
        <h2>Dropdown lists</h2>
        <p className="small muted">Phase 1 placeholders. Replace them with the real QuickBooks lists.</p>
        <div className="lists">
          {LISTS.map(([list, title]) => (
            <div key={list}>
              <h3>{title}</h3>
              <ul className="plain">
                {((lookups ?? []) as Lookup[])
                  .filter((l) => l.list === list)
                  .map((l) => (
                    <li key={l.id} className={l.active ? '' : 'muted'}>
                      <ActionForm action={adminLookup} hidden={{ op: 'toggle', id: l.id, active: String(!l.active) }} className="row">
                        <span>
                          {l.label}
                          {l.rate !== null ? ` (${Number(l.rate) * 100}%)` : ''}
                        </span>
                        <Submit className="link small">{l.active ? 'Hide' : 'Show'}</Submit>
                      </ActionForm>
                    </li>
                  ))}
              </ul>
              <ActionForm action={adminLookup} hidden={{ op: 'add', list }} className="row">
                <input name="label" placeholder="New value" aria-label={`New ${title}`} required />
                {list === 'tax_code' && <input name="rate" placeholder="Rate, e.g. 0.12" aria-label="Tax rate" required />}
                <Submit className="btn secondary small">Add</Submit>
              </ActionForm>
            </div>
          ))}
        </div>
      </section>

      <section className="card">
        <div className="card-head">
          <h2>SMS log</h2>
          <ActionForm action={sendQueuedSmsNow}>
            <Submit className="btn secondary small">Send queued SMS now</Submit>
          </ActionForm>
        </div>
        <p className="small">OneWaySMS credit: {credit}</p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>When</th>
                <th>To</th>
                <th>Message</th>
                <th>SMS</th>
              </tr>
            </thead>
            <tbody>
              {((sms ?? []) as Notification[]).map((n) => (
                <tr key={n.id}>
                  <td>{fmtDateTime(n.created_at)}</td>
                  <td>
                    {name(n.recipient_id)}
                    <div className="small muted">{n.sms_mobile_no}</div>
                  </td>
                  <td>{n.message}</td>
                  <td>
                    {n.sms_status}
                    {n.sms_message_id && <div className="small muted">ID {n.sms_message_id}</div>}
                    {n.sms_error && <div className="small error">{n.sms_error}</div>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
