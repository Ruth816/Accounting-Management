'use client'

import { ActionForm, Submit } from '@/components/ActionForm'
import { signIn } from '@/app/actions'

export function LoginForm() {
  return (
    <ActionForm action={signIn} className="stack">
      <label className="field">
        <span className="label">Email</span>
        <input type="email" name="email" autoComplete="email" required />
      </label>
      <label className="field">
        <span className="label">Password</span>
        <input type="password" name="password" autoComplete="current-password" required />
      </label>
      <Submit>Sign in</Submit>
    </ActionForm>
  )
}
