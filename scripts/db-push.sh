#!/usr/bin/env bash
# Apply migrations to the HOSTED dev project (PHASES.md option A).
#
# This used to run `supabase link` + `supabase db push`. That was a live
# footgun: the CLI records what it has applied in
# supabase_migrations.schema_migrations, while scripts/db/run.mjs records it in
# public.schema_migrations. All 16 migrations were applied through run.mjs, so
# the CLI's ledger was empty - and `db push` would have tried to apply every
# one of them again to a database that already had them.
#
# One ledger, one code path. This is now a thin wrapper so that the command
# CLAUDE.md tells you to run and the command CI runs are the same command.
#
# There is no local stack, and `db reset` is deliberately never used: it would
# wipe data shared by everyone working against the hosted project.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No .env - copy .env.example and fill it."; exit 1; }
exec node scripts/db/run.mjs migrate
