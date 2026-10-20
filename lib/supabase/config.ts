// Checks the Supabase settings the site was built with, so a setup mistake
// shows a readable message instead of a crash. Returns null when they look fine.
export function supabaseConfigProblem(): string | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? ''
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? ''
  const problems: string[] = []
  if (!url.trim()) problems.push('NEXT_PUBLIC_SUPABASE_URL is missing or empty.')
  else if (!/^https:\/\/[a-z0-9]+\.supabase\.co\/?$/.test(url))
    problems.push('NEXT_PUBLIC_SUPABASE_URL should look like https://<project>.supabase.co with no spaces or quotes.')
  if (!key.trim()) problems.push('NEXT_PUBLIC_SUPABASE_ANON_KEY is missing or empty.')
  else if (/[\s"']/.test(key)) problems.push('NEXT_PUBLIC_SUPABASE_ANON_KEY contains spaces, line breaks or quotes.')
  return problems.length ? problems.join(' ') : null
}
