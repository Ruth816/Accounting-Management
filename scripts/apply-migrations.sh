#!/usr/bin/env bash
# Applies new files in supabase/migrations to the live Supabase database, in
# order, each in one transaction, and records them in public.app_migrations.
# Runs from .github/workflows/database.yml on every push to main.
# Needs SUPABASE_DB_URL (the database connection string, session pooler).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${SUPABASE_DB_URL:-}" ]; then
  echo "::warning::SUPABASE_DB_URL secret is not set yet, so no database update was applied."
  exit 0
fi
PSQL=(psql "$SUPABASE_DB_URL" -X -q -v ON_ERROR_STOP=1)

# Everything up to here was applied by hand from 2026-11-01-database-updates.sql.
BASELINE=20261102000005

"${PSQL[@]}" <<'SQL'
create table if not exists public.app_migrations (
  name text primary key,
  applied_at timestamptz not null default now()
);
alter table public.app_migrations enable row level security;
revoke all on public.app_migrations from anon, authenticated;
SQL

if [ "$("${PSQL[@]}" -tA -c 'select count(*) from public.app_migrations')" = 0 ]; then
  for f in supabase/migrations/*.sql; do
    n=$(basename "$f" .sql)
    if [[ ! "${n%%_*}" > "$BASELINE" ]]; then
      "${PSQL[@]}" -c "insert into public.app_migrations (name) values ('$n') on conflict do nothing"
    fi
  done
  echo "Recorded the migrations already applied by hand (up to $BASELINE)."
fi

applied=$("${PSQL[@]}" -tA -c 'select name from public.app_migrations')
count=0
for f in supabase/migrations/*.sql; do
  n=$(basename "$f" .sql)
  if ! grep -qxF "$n" <<<"$applied"; then
    echo "Applying $n"
    "${PSQL[@]}" -1 -f "$f" -c "insert into public.app_migrations (name) values ('$n')"
    count=$((count + 1))
  fi
done
echo "Applied $count new migration(s)."
