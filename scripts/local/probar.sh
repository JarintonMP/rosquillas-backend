#!/usr/bin/env bash
# Corre las migraciones y las pruebas pgTAP en un PostgreSQL normal,
# sin Docker ni Supabase CLI. Útil cuando no se puede usar `supabase test db`.
#
# Requisitos: psql, pg_prove y la extensión pgtap instalada en el servidor.
# Uso: PGHOST=localhost PGPORT=5432 PGUSER=postgres scripts/local/probar.sh
set -euo pipefail

BASE="${BASE_PRUEBAS:-rosquillas_pruebas}"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
PSQL=(psql -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" -d postgres -c "drop database if exists ${BASE}" -c "create database ${BASE}"
"${PSQL[@]}" -d "$BASE" -f "$RAIZ/scripts/local/stub_supabase.sql"

for migracion in "$RAIZ"/supabase/migrations/*.sql; do
  echo "Aplicando $(basename "$migracion")"
  "${PSQL[@]}" -d "$BASE" -f "$migracion"
done

# Igual que `supabase db start`: también carga los datos de ejemplo.
"${PSQL[@]}" -d "$BASE" -f "$RAIZ/supabase/seed.sql"

pg_prove -d "$BASE" "$RAIZ"/supabase/tests/database/*.test.sql
