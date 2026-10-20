'use client'

import { createContext, startTransition, useActionState, useContext } from 'react'
import type { ActionState } from '@/lib/types'

type Action = (state: ActionState, fd: FormData) => Promise<ActionState>

const Pending = createContext(false)

// Submits without React's automatic form reset, so typed values survive an
// error message. The clicked button's name/value is included.
export function useSubmit(action: Action, initial: ActionState = null, confirmText?: string) {
  const [state, dispatch, pending] = useActionState(action, initial)
  const onSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (confirmText && !window.confirm(confirmText)) return
    const submitter = (e.nativeEvent as SubmitEvent).submitter as HTMLElement | null
    const fd = new FormData(e.currentTarget, submitter)
    startTransition(() => dispatch(fd))
  }
  return { state, onSubmit, pending, PendingProvider: Pending.Provider }
}

export function ActionForm({
  action,
  hidden = {},
  children,
  className,
  confirm,
}: {
  action: Action
  hidden?: Record<string, string>
  children: React.ReactNode
  className?: string
  confirm?: string
}) {
  const { state, onSubmit, pending, PendingProvider } = useSubmit(action, null, confirm)
  return (
    <form onSubmit={onSubmit} className={className}>
      <PendingProvider value={pending}>
        {Object.entries(hidden).map(([k, v]) => (
          <input key={k} type="hidden" name={k} value={v} />
        ))}
        {children}
        <Message state={state} />
      </PendingProvider>
    </form>
  )
}

export function Message({ state }: { state: ActionState }) {
  if (state?.error) return <p className="msg error" role="alert">{state.error}</p>
  if (state?.ok) return <p className="msg ok" role="status">{state.ok}</p>
  return null
}

export function Submit({
  children,
  className = 'btn',
  name,
  value,
  disabled,
}: {
  children: React.ReactNode
  className?: string
  name?: string
  value?: string
  disabled?: boolean
}) {
  const pending = useContext(Pending)
  return (
    <button type="submit" className={className} name={name} value={value} disabled={pending || disabled}>
      {children}
    </button>
  )
}
