import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// Opens an attachment through a short-lived signed URL. Row-level security
// decides whether the signed-in user may see it.
export async function GET(_: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const supabase = await createClient()
  const { data: file } = await supabase.from('attachments').select('storage_path, file_name').eq('id', id).maybeSingle()
  if (!file) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const { data, error } = await supabase.storage.from('attachments').createSignedUrl(file.storage_path, 60, {
    download: file.file_name,
  })
  if (error || !data) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.redirect(data.signedUrl)
}
