#!/usr/bin/env bash
#
# data_integrity.sh — prove the CRITICAL `app` schema (the system of record) is
# byte-for-byte equivalent between a SOURCE and a DESTINATION Postgres.
#
# This is the gate for the cutover: on-prem stays READ-ONLY during the window,
# app writers stay frozen, and we do NOT repoint traffic until this prints PASS.
# (The `reporting` schema is DERIVED and regenerable by re-running batch per date,
#  so it is intentionally NOT compared here — only `app` integrity is load-bearing.)
#
# WHAT IT COMPARES (app schema only):
#   (a) ROW COUNTS         of app.customers / app.accounts / app.transactions
#   (b) DETERMINISTIC      a per-table MD5 over rows ordered by primary key, so the
#       AGGREGATE/CHECKSUM  comparison is order-independent and content-sensitive
#   (c) DUPLICATE BIZ KEYS  app.customers.email and app.accounts.iban must have 0 dups
#                           on BOTH sides (these are UNIQUE in DDL; a violation means a
#                           broken/partial copy or a constraint that did not migrate)
#
# CONNECTIONS (no secrets in this file — pass them via env):
#   SRC  libpq connection string for the SOURCE (on-prem). Default: local self-check.
#   DST  libpq connection string for the DESTINATION (cloud RDS primary). Default: SRC.
#
#   Examples:
#     # self-check against the local stack (SRC and DST default to the local DB; PASS)
#     PGPASSWORD_SRC="$POSTGRES_PASSWORD" ./tests/reporting-db/data_integrity.sh
#
#     # real cutover validation (read-only on both ends), secrets from your shell/Secrets Manager:
#     SRC="host=onprem.local port=5432 dbname=contoso user=report_reader sslmode=require" \
#     DST="host=contoso.xxxx.eu-central-1.rds.amazonaws.com port=5432 dbname=contoso user=report_reader sslmode=require" \
#     PGPASSWORD_SRC=... PGPASSWORD_DST=... \
#       ./tests/reporting-db/data_integrity.sh
#
#   Use a role that can SELECT app.* (e.g. app_user or the superuser). report_reader
#   canNOT read app by design — pick an appropriate read role for this check.
#
# PREREQUISITES
#   - psql on PATH (or run inside a container that has it).
#   - SRC reachable read-only; DST reachable read-only.
#   - For the local self-check default, the legacy stack must be up and migrated.
#
set -euo pipefail

# --- connection config -----------------------------------------------------------
# Default SRC/DST to a local connection via the legacy postgres container.
# We don't bake passwords; for the local default we read them from legacy/.env at call
# time through PGPASSWORD_SRC/PGPASSWORD_DST if the caller exported them.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_DIR="${LEGACY_DIR:-$(cd "${SCRIPT_DIR}/../../legacy" && pwd)}"
ENV_FILE="${ENV_FILE:-${LEGACY_DIR}/.env}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a; source "${ENV_FILE}"; set +a
fi

# Local default connection string (host-published port 5432). Uses superuser, which
# can read app.*. Passwords NEVER appear here; supplied via PGPASSWORD_SRC/_DST.
LOCAL_CONN="host=127.0.0.1 port=5432 dbname=${POSTGRES_DB:-contoso} user=${POSTGRES_USER:-contoso}"

SRC="${SRC:-${LOCAL_CONN}}"
DST="${DST:-${SRC}}"

# For the local self-check, default both passwords to the superuser password if the
# caller didn't set per-endpoint passwords (still sourced from .env, not hardcoded).
PGPASSWORD_SRC="${PGPASSWORD_SRC:-${POSTGRES_PASSWORD:-}}"
PGPASSWORD_DST="${PGPASSWORD_DST:-${PGPASSWORD_SRC}}"

FAILURES=0

# q <endpoint: SRC|DST> <sql> -> single scalar value on stdout (tuples-only)
q() {
  local which="$1" sql="$2" conn pw
  if [[ "${which}" == "SRC" ]]; then conn="${SRC}"; pw="${PGPASSWORD_SRC}"; else conn="${DST}"; pw="${PGPASSWORD_DST}"; fi
  PGPASSWORD="${pw}" psql -X -q -At -v ON_ERROR_STOP=1 "${conn}" -c "${sql}"
}

# compare <label> <sql>: run on both sides, PASS iff equal; print the diff on FAIL
compare() {
  local label="$1" sql="$2" sv dv
  sv="$(q SRC "${sql}")"
  dv="$(q DST "${sql}")"
  if [[ "${sv}" == "${dv}" ]]; then
    echo "PASS: ${label}  (src=${sv} dst=${dv})"
  else
    echo "FAIL: ${label}  expected src==dst, got src=${sv} dst=${dv}"
    FAILURES=$((FAILURES + 1))
  fi
}

# expect_zero <label> <which> <sql>: PASS iff the scalar result is 0 (used for dup checks)
expect_zero() {
  local label="$1" which="$2" sql="$3" v
  v="$(q "${which}" "${sql}")"
  if [[ "${v}" == "0" ]]; then
    echo "PASS: ${label}  (${which}=0)"
  else
    echo "FAIL: ${label}  expected 0 on ${which}, got ${v}"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "== app-schema data integrity: SRC vs DST =="
echo "   SRC: ${SRC}"
echo "   DST: ${DST}"
echo

echo "-- (a) row counts --"
compare "row count app.customers"    "SELECT count(*) FROM app.customers;"
compare "row count app.accounts"     "SELECT count(*) FROM app.accounts;"
compare "row count app.transactions" "SELECT count(*) FROM app.transactions;"

echo
echo "-- (b) deterministic content checksum (md5 over PK-ordered rows) --"
# md5 of the concatenation of every row rendered as text, ordered by primary key.
# Order-independent across replicas; sensitive to any value difference.
compare "checksum app.customers" \
  "SELECT md5(string_agg(t::text, '|' ORDER BY t.id)) FROM app.customers t;"
compare "checksum app.accounts" \
  "SELECT md5(string_agg(t::text, '|' ORDER BY t.id)) FROM app.accounts t;"
compare "checksum app.transactions" \
  "SELECT md5(string_agg(t::text, '|' ORDER BY t.id)) FROM app.transactions t;"

echo
echo "-- (c) duplicate business keys must be 0 (both sides) --"
# app.customers.email and app.accounts.iban are UNIQUE in DDL. A non-zero count means
# the unique constraint did not migrate, or rows were doubled by a bad copy.
for side in SRC DST; do
  expect_zero "dup app.customers.email (${side})" "${side}" \
    "SELECT count(*) FROM (SELECT email FROM app.customers GROUP BY email HAVING count(*) > 1) d;"
  expect_zero "dup app.accounts.iban (${side})" "${side}" \
    "SELECT count(*) FROM (SELECT iban FROM app.accounts GROUP BY iban HAVING count(*) > 1) d;"
done

echo
if [[ "${FAILURES}" -eq 0 ]]; then
  echo "DATA INTEGRITY OK — app schema matches between SRC and DST"
  exit 0
else
  echo "DATA INTEGRITY FAILED: ${FAILURES} mismatch(es) — DO NOT cut over"
  exit 1
fi
