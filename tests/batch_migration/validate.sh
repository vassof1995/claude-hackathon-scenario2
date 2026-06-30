#!/usr/bin/env bash
# The Proof — batch migration validation (ADR-0006, plan §3).
#
# Asserts the correctness guarantees the batch migration must NOT lose, against the local
# stand-in (the legacy stack; EventBridge is stood in for by POST /run, per plan §3):
#   1. A run for the seeded date writes one reconciliation_results row per active account.
#   2. The seeded id%7 ledger mismatches appear in reporting.discrepancies (deterministic: 2).
#   3. Re-running the same date is idempotent — row counts do not double.
#   4. Grant matrix survived: report_reader reads reporting but NOT app and cannot write;
#      batch_user reads app but CANNOT write app.
#
# Requires: docker (daemon running), curl, psql. Run from anywhere:
#   tests/batch_migration/validate.sh           # bring up, test, leave running
#   tests/batch_migration/validate.sh --down     # also tear the stack down at the end
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LEGACY="$REPO_ROOT/legacy"
TEARDOWN="${1:-}"
PASS=0
FAIL=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
info() { printf "\n\033[1m%s\033[0m\n" "$1"; }

require() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1"; exit 2; }; }
require docker; require curl; require psql

# --- .env (local stand-in secrets) ---------------------------------------------------------
if [ ! -f "$LEGACY/.env" ]; then
  echo "legacy/.env not found — creating from .env.example (local change-me values)."
  cp "$LEGACY/.env.example" "$LEGACY/.env"
fi
# shellcheck disable=SC1091
set -a; . "$LEGACY/.env"; set +a

PGHOST=localhost; PGPORT=5432; DB="${POSTGRES_DB:-contoso}"
# Business date the batch reconciles = yesterday (matches the seed and ReconciliationScheduler).
BIZDATE="$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)"

psql_as() { # role password "SQL"  -> stdout; returns psql exit code
  PGPASSWORD="$2" psql -tA -h "$PGHOST" -p "$PGPORT" -U "$1" -d "$DB" -v ON_ERROR_STOP=1 -c "$3" 2>/dev/null
}
expect_denied() { # role password "SQL" label
  if PGPASSWORD="$2" psql -tA -h "$PGHOST" -p "$PGPORT" -U "$1" -d "$DB" -v ON_ERROR_STOP=1 -c "$3" >/dev/null 2>&1; then
    bad "$4 (expected permission denied, but it SUCCEEDED)"
  else
    ok "$4"
  fi
}

# --- Bring up the stand-in -----------------------------------------------------------------
info "Bringing up the legacy stand-in (docker compose up --build -d)…"
( cd "$LEGACY" && docker compose up --build -d ) || { echo "compose up failed (is the docker daemon running?)"; exit 2; }

info "Waiting for postgres + web-api to be healthy (so app schema + seed exist)…"
for i in $(seq 1 80); do
  up="$(cd "$LEGACY" && docker compose ps 2>/dev/null)"
  pg_ok=$(echo "$up"  | grep -E '\bpostgres\b' | grep -c healthy)
  api_ok=$(echo "$up" | grep -E '\bweb-api\b'  | grep -c healthy)
  [ "${pg_ok:-0}" -ge 1 ] && [ "${api_ok:-0}" -ge 1 ] && break
  sleep 3
done

# --- Trigger one reconciliation (the EventBridge run-to-exit stand-in) ----------------------
info "Triggering reconciliation for $BIZDATE via POST /run…"
curl -fsS -X POST "http://localhost:8082/run?date=$BIZDATE" >/dev/null && ok "POST /run accepted" || bad "POST /run failed"

# --- Assertion 1: one result row per active account ----------------------------------------
info "Assertions"
active_accounts="$(psql_as "$POSTGRES_USER" "$POSTGRES_PASSWORD" \
  "SELECT count(DISTINCT account_id) FROM app.transactions WHERE booked_at::date = '$BIZDATE';")"
result_rows="$(psql_as "$POSTGRES_USER" "$POSTGRES_PASSWORD" \
  "SELECT count(*) FROM reporting.reconciliation_results WHERE business_date = '$BIZDATE';")"
[ -n "$result_rows" ] && [ "$result_rows" = "$active_accounts" ] \
  && ok "reconciliation_results has one row per active account ($result_rows = $active_accounts)" \
  || bad "reconciliation_results row count $result_rows != active accounts $active_accounts"

# --- Assertion 2: seeded id%7 discrepancies present ----------------------------------------
expected_disc="$(psql_as "$POSTGRES_USER" "$POSTGRES_PASSWORD" \
  "SELECT count(*) FROM app.transactions WHERE booked_at::date = '$BIZDATE' AND id % 7 = 0;")"
got_disc="$(psql_as "$POSTGRES_USER" "$POSTGRES_PASSWORD" \
  "SELECT count(*) FROM reporting.discrepancies WHERE business_date = '$BIZDATE';")"
[ -n "$got_disc" ] && [ "$got_disc" = "$expected_disc" ] \
  && ok "discrepancies match the seeded id%7 mismatches ($got_disc = $expected_disc)" \
  || bad "discrepancies $got_disc != expected seeded mismatches $expected_disc"

# --- Assertion 3: idempotency (re-run does not double rows) ---------------------------------
curl -fsS -X POST "http://localhost:8082/run?date=$BIZDATE" >/dev/null
result_rows2="$(psql_as "$POSTGRES_USER" "$POSTGRES_PASSWORD" \
  "SELECT count(*) FROM reporting.reconciliation_results WHERE business_date = '$BIZDATE';")"
disc2="$(psql_as "$POSTGRES_USER" "$POSTGRES_PASSWORD" \
  "SELECT count(*) FROM reporting.discrepancies WHERE business_date = '$BIZDATE';")"
[ "$result_rows2" = "$result_rows" ] && [ "$disc2" = "$got_disc" ] \
  && ok "idempotent re-run: counts stable (results=$result_rows2, discrepancies=$disc2)" \
  || bad "re-run changed counts (results $result_rows->$result_rows2, disc $got_disc->$disc2)"

# --- Assertion 4: the grant matrix survived (least privilege) ------------------------------
rr_reporting="$(psql_as report_reader "$REPORT_DB_PASSWORD" \
  "SELECT count(*) FROM reporting.reconciliation_results;" && echo OK)"
[ -n "$rr_reporting" ] && ok "report_reader can SELECT reporting" || bad "report_reader cannot read reporting (should be allowed)"
expect_denied report_reader "$REPORT_DB_PASSWORD" "SELECT count(*) FROM app.customers;" "report_reader CANNOT read app schema"
expect_denied report_reader "$REPORT_DB_PASSWORD" "INSERT INTO reporting.discrepancies(business_date,account_id,transaction_ref,expected_amount,actual_amount,reason) VALUES ('$BIZDATE',1,'X',0,0,'x');" "report_reader CANNOT write reporting"
batch_app_read="$(psql_as batch_user "$BATCH_DB_PASSWORD" "SELECT count(*) FROM app.transactions;" && echo OK)"
[ -n "$batch_app_read" ] && ok "batch_user can SELECT app (cross-schema read)" || bad "batch_user cannot read app (should be allowed)"
expect_denied batch_user "$BATCH_DB_PASSWORD" "INSERT INTO app.transactions(account_id,amount,direction,booked_at,external_ref) VALUES (1,1,'CREDIT',now(),'X');" "batch_user CANNOT write app"

# --- Teardown / summary --------------------------------------------------------------------
if [ "$TEARDOWN" = "--down" ]; then
  info "Tearing down…"; ( cd "$LEGACY" && docker compose down -v )
else
  echo; echo "Stand-in left running. Tear down with: ( cd legacy && docker compose down -v )"
fi

info "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
