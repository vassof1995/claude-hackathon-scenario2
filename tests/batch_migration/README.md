# The Proof — batch migration

Validates that the batch migration (ADR-0006, [plan §3](../../docs/03-migration-plan.md))
preserves the correctness guarantees that matter, against the local stand-in. Same assertions
run pre-cutover (here) and would run post-cutover against RDS with only connection changes.

## What it asserts (the anti-theatre checks)
| # | Assertion | Coupling it guards |
|---|-----------|--------------------|
| 1 | A run writes one `reporting.reconciliation_results` row per active account | logic preserved across the trigger move |
| 2 | The seeded `id % 7` ledger mismatches land in `reporting.discrepancies` (deterministic) | reconciliation math unchanged |
| 3 | Re-running the same business date does **not** double rows | **idempotency** (ADR-0006) survives run-to-exit |
| 4 | `report_reader` reads `reporting` but **not** `app`, and cannot write; `batch_user` reads `app` but **cannot write** `app` | grant matrix / least privilege (discovery C2, C4) |

## Run
```bash
tests/batch_migration/validate.sh          # bring up stand-in, assert, leave running
tests/batch_migration/validate.sh --down    # also tear down afterwards
```
Requires a running Docker daemon, plus `curl` and `psql` on the host. The script brings up the
legacy stack (`legacy/docker compose`), waits for health, triggers one reconciliation via
`POST /run` (the local stand-in for the EventBridge run-to-exit task, per plan §3), then runs
the assertions and prints a pass/fail summary (non-zero exit on any failure).

## Not yet automated here
- **C3 empty-schema fail-fast** (batch run before `app` exists fails cleanly, no garbage) — the
  cutover order (plan §7) prevents it; an extended test would stand up postgres+batch without
  web-api and assert a clean failure. Tracked in README "If We Had More Time".
