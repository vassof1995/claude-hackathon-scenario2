#!/usr/bin/env bash
# smoke_test.sh — web-app workload smoke tests
# Validates "migration succeeded" definition for Contoso Financial web-app.
# Covers coupling C1 (nginx /api/ reverse-proxy → web-api) found in Discovery.
#
# Usage:
#   FRONTEND_URL=http://localhost:8080 API_URL=http://localhost:8081 ./smoke_test.sh

set -euo pipefail

FRONTEND_URL="${FRONTEND_URL:-http://localhost:8080}"
API_URL="${API_URL:-http://localhost:8081}"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  local result="$2"   # 0 = pass, non-zero = fail
  if [ "$result" -eq 0 ]; then
    echo "[PASS] $name"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $name"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test 1 — API health endpoint
# ---------------------------------------------------------------------------
test_api_health() {
  local response
  local http_status
  local body

  response=$(curl -s -w "\n%{http_code}" "${API_URL}/actuator/health" 2>/dev/null) || return 1
  http_status=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n -1)

  [ "$http_status" -eq 200 ] || return 1
  echo "$body" | grep -q "UP" || return 1
  return 0
}
run_test "API health (GET /actuator/health returns HTTP 200 with UP)" "$(test_api_health; echo $?)"

# ---------------------------------------------------------------------------
# Test 2 — Customers endpoint returns seeded data
# ---------------------------------------------------------------------------
test_customers_seeded() {
  local response
  local http_status
  local body

  response=$(curl -s -w "\n%{http_code}" "${API_URL}/api/customers" 2>/dev/null) || return 1
  http_status=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n -1)

  [ "$http_status" -eq 200 ] || return 1
  echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if len(d)>0 else 1)" 2>/dev/null || return 1
  return 0
}
run_test "Customers endpoint returns seeded data (GET /api/customers is non-empty JSON array)" "$(test_customers_seeded; echo $?)"

# ---------------------------------------------------------------------------
# Test 3 — Frontend index page
# ---------------------------------------------------------------------------
test_frontend_index() {
  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/" 2>/dev/null) || return 1
  [ "$http_status" -eq 200 ] || return 1
  return 0
}
run_test "Frontend index page (GET / returns HTTP 200)" "$(test_frontend_index; echo $?)"

# ---------------------------------------------------------------------------
# Test 4 — C1 coupling: nginx /api/ proxies to web-api locally
# In cloud: CloudFront /api/* → ALB. Locally: nginx → web-api.
# ---------------------------------------------------------------------------
test_c1_coupling() {
  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/api/customers" 2>/dev/null) || return 1
  [ "$http_status" -eq 200 ] || return 1
  return 0
}
run_test "C1 coupling: nginx /api/ proxies to web-api locally (GET FRONTEND_URL/api/customers returns HTTP 200)" "$(test_c1_coupling; echo $?)"

# ---------------------------------------------------------------------------
# Test 5 — No CORS on /api/ path (same-origin contract)
# PASS if Access-Control-Allow-Origin header is absent (same-origin, CORS not needed).
# FAIL if header is present (would indicate broken same-origin contract).
# ---------------------------------------------------------------------------
test_no_cors() {
  local headers
  headers=$(curl -sI "${FRONTEND_URL}/api/customers" 2>/dev/null) || return 1
  if echo "$headers" | grep -qi "access-control-allow-origin"; then
    return 1  # CORS header present — same-origin contract broken
  fi
  return 0
}
run_test "No CORS on /api/ path (same-origin contract: no Access-Control-Allow-Origin header)" "$(test_no_cors; echo $?)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
