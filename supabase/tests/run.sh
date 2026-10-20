#!/usr/bin/env bash
# Applies the migrations to a scratch database and runs the workflow tests.
# Usage: PSQL="psql -h localhost -U postgres" supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PSQL=${PSQL:-psql}
$PSQL -q -c "drop database if exists finance_portal_test" -c "create database finance_portal_test"
for f in tests/supabase_stub.sql migrations/*.sql seed.sql tests/workflow_test.sql; do
  $PSQL -q -v ON_ERROR_STOP=1 -d finance_portal_test -f "$f"
done
