'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/browser'
import { addAttachment, requestAction } from '@/app/actions'
import type { Attachment } from '@/lib/types'

export function Attachments({
  files,
  prId = null,
  frId = null,
  canEdit,
  userId,
}: {
  files: Attachment[]
  prId?: string | null
  frId?: string | null
  canEdit: boolean
  userId: string
}) {
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [busy, startTransition] = useTransition()

  async function upload(list: FileList | null) {
    if (!list?.length) return
    setError(null)
    const supabase = createClient()
    for (const file of Array.from(list)) {
      const safe = file.name.replace(/[^\w.\-]+/g, '_')
      const path = `${userId}/${crypto.randomUUID()}-${safe}`
      const { error: upErr } = await supabase.storage.from('attachments').upload(path, file)
      if (upErr) {
        setError(`${file.name}: ${upErr.message}`)
        continue
      }
      const r = await addAttachment(prId, frId, path, file.name)
      if (r.error) setError(`${file.name}: ${r.error}`)
    }
    startTransition(() => router.refresh())
  }

  function remove(id: string) {
    const fd = new FormData()
    fd.set('op', 'remove_attachment')
    fd.set('id', id)
    startTransition(async () => {
      const r = await requestAction(null, fd)
      if (r?.error) setError(r.error)
      router.refresh()
    })
  }

  return (
    <div>
      {files.length === 0 && <p className="muted">No files attached.</p>}
      <ul className="files">
        {files.map((f) => (
          <li key={f.id}>
            <a href={`/api/attachments/${f.id}`} target="_blank" rel="noreferrer">
              {f.file_name}
            </a>
            {canEdit && f.uploaded_by === userId && (
              <button type="button" className="link danger" onClick={() => remove(f.id)} disabled={busy}>
                Remove
              </button>
            )}
          </li>
        ))}
      </ul>
      {canEdit && (
        <label className="upload">
          <input type="file" multiple onChange={(e) => upload(e.target.files)} disabled={busy} />
        </label>
      )}
      {error && <p className="msg error">{error}</p>}
    </div>
  )
}
