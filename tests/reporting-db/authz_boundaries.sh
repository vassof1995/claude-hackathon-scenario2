#!/usr/bin/env bash
#
# authz_boundaries.sh — prove the three least-privilege roles behave correctly
# against the LOCAL legacy Postgres (legacy/docker-compose.yml's `postgres` service).
#
# It validates the exact grants from legacy/reporting-db/init/01-roles-and-schemas.sh:
#   app_user      owns schema app      (RW)
#   batch_user    owns schema reporting (RW); USAGE + SELECT on app
#   report_reader USAGE + SELECT on reporting only (NO app, NO writes anywhere)
#
# These same boundaries must hold post-cutover on RDS (primary) and the read
# replica (where report_reader connects) — see README.md for the cloud mapping.
#
# HOW IT WORKS
#   - Connects through the running container with: docker compose exec -T postgres psql
#     so it works even if 5432 is not reachable from the host.
#   - Each role connects with its own password (PGPASSWORD, never hardcoded).
#   - POSITIVE cases must succeed (psql exit 0).
#   - NEGATIVE cases must be DENIED: we INVERT the psql exit code, so a
#     permission-denied (non-zero psql) becomes a PASS for the test.
#
# PREREQUISITES
#   - `docker compose -f legacy/docker-compose.yml up -d` (postgres healthy)
#   - web-api has run its Flyway migration (creates app.* tables) AND batch has
#     run at least once (creates reporting.* tables). Until reporting tables exist,
#     the ALTER DEFAULT PRIVILEGES grant to report_reader has nothing to attach to.
#   - A `.env` next to legacy/docker-compose.yml (copy from .env.example) providing:
#       POSTGRES_USER, POSTGRES_DB,
#       APP_DB_PASSWORD, BATCH_DB_PASSWORD, REPORT_DB_PASSWORD
#
# USAGE
#   ./tests/reporting-db/authz_boundaries.sh
#     (auto-sources legacy/.env if present; or export the vars yourself)
#
set -euo pipefail

# --- locate the legacy stack and source secrets (no secrets live in this file) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_DIR="${LEGACY_DIR:-$(cd "${SCRIPT_DIR}/../../legacy" && pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-${LEGACY_DIR}/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${LEGACY_DIR}/.env}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a; source "${ENV_FILE}"; set +a
fi

: "${POSTGRES_USER:?set POSTGRES_USER (e.g. in legacy/.env)}"
: "${POSTGRES_DB:?set POSTGRES_DB}"
: "${APP_DB_PASSWORD:?set APP_DB_PASSWORD}"
: "${BATCH_DB_PASSWORD:?set BATCH_DB_PASSWORD}"
: "${REPORT_DB_PASSWORD:?set REPORT_DB_PASSWORD}"

DC=(docker compose -f "${COMPOSE_FILE}")
FAILURES=0

# run_sql <role> <password> <sql>  -> psql exit code, output discarded except on demand
# We connect as the given role *inside* the container. -X ignores ~/.psqlrc,
# -q quiet, ON_ERROR_STOP so the first denied statement fails the whole call.
run_sql() {
  local role="$1" pw="$2" sql="$3"
  "${DC[@]}" exec -T -e "PGPASSWORD=${pw}" postgres \
    psql -X -q -v ON_ERROR_STOP=1 -U "${role}" -d "${POSTGRES_DB}" -c "${sql}" \
    >/dev/null 2>&1
}

# positive <name> <role> <pw> <sql>: PASS iff the action SUCCEEDS
positive() {
  local name="$1" role="$2" pw="$3" sql="$4"
  if run_sql "${role}" "${pw}" "${sql}"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name} — expected SUCCESS (allowed) got DENIED/ERROR"
    FAILURES=$((FAILURES + 1))
  fi
}

# negative <name> <role> <pw> <sql>: PASS iff the action is DENIED (psql non-zero).
# Exit code is inverted: deny == test PASS.
negative() {
  local name="$1" role="$2" pw="$3" sql="$4"
  if run_sql "${role}" "${pw}" "${sql}"; then
    echo "FAIL: ${name} — expected DENIED got SUCCESS (privilege leak!)"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: ${name} (action correctly denied)"
  fi
}

echo "== authz boundary tests against local legacy Postgres =="
echo "   compose: ${COMPOSE_FILE}"
echo "   db: ${POSTGRES_DB}"
echo

# Sanity: superuser can see both schemas' base tables exist (helps diagnose
# "tables not migrated yet" vs a real authz failure). Non-fatal.
if ! "${DC[@]}" exec -T -e "PGPASSWORD=${POSTGRES_PASSWORD:-}" postgres \
      psql -X -qt -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
      -c "SELECT to_regclass('app.customers'), to_regclass('reporting.daily_balances');" \
      2>/dev/null | grep -q .; then
  echo "NOTE: could not pre-check table existence as superuser (continuing)."
fi
echo

echo "-- POSITIVE: privileges that MUST be allowed --"
# report_reader CAN SELECT from reporting
positive "report_reader CAN SELECT reporting.daily_balances" \
  report_reader "${REPORT_DB_PASSWORD}" \
  "SELECT count(*) FROM reporting.daily_balances;"

# batch_user CAN SELECT from app (cross-schema read for reconciliation)
positive "batch_user CAN SELECT app.transactions" \
  batch_user "${BATCH_DB_PASSWORD}" \
  "SELECT count(*) FROM app.transactions;"

# batch_user CAN write reporting (it owns the schema). Idempotent: insert then rollback
# so the test leaves no residue. A failed INSERT (denied) fails the transaction => FAIL.
positive "batch_user CAN INSERT reporting.daily_balances (write)" \
  batch_user "${BATCH_DB_PASSWORD}" \
  "BEGIN; INSERT INTO reporting.daily_balances
     (account_id, business_date, opening_balance, closing_balance)
     VALUES (-1, DATE '1900-01-01', 0, 0); ROLLBACK;"

echo
echo "-- NEGATIVE: privileges that MUST be denied (deny == PASS) --"
# report_reader CANNOT read app
negative "report_reader CANNOT SELECT app.customers" \
  report_reader "${REPORT_DB_PASSWORD}" \
  "SELECT count(*) FROM app.customers;"

# report_reader CANNOT write reporting
negative "report_reader CANNOT INSERT reporting.daily_balances" \
  report_reader "${REPORT_DB_PASSWORD}" \
  "INSERT INTO reporting.daily_balances
     (account_id, business_date, opening_balance, closing_balance)
     VALUES (-1, DATE '1900-01-01', 0, 0);"

# report_reader CANNOT write app
negative "report_reader CANNOT INSERT app.customers" \
  report_reader "${REPORT_DB_PASSWORD}" \
  "INSERT INTO app.customers (name, email) VALUES ('x','authz-test@example.invalid');"

# batch_user CANNOT write app (only SELECT on app, never write)
negative "batch_user CANNOT INSERT app.customers" \
  batch_user "${BATCH_DB_PASSWORD}" \
  "INSERT INTO app.customers (name, email) VALUES ('x','authz-test@example.invalid');"

echo
if [[ "${FAILURES}" -eq 0 ]]; then
  echo "ALL AUTHZ BOUNDARY TESTS PASSED"
  exit 0
else
  echo "AUTHZ BOUNDARY TESTS FAILED: ${FAILURES} failure(s)"
  exit 1
fi
