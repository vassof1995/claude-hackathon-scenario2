# Work Log — reporting-db migration artifacts

Trace of the reporting-db specialist work, so the steps are auditable later.
Scope: `reporting-db` workload only. Target: AWS `eu-central-1`, RDS Multi-AZ primary +
read replica. Strategy: targeted refactor (unchanged).

## Step 0 — Repository inspection (evidence gathering)
- `find` over `infra/`, `tests/`, `docs/`, `decisions/`, `scripts/`, `.claude/`, `.githooks/`.
- Confirmed the on-prem reporting DB lives **only** under `legacy/`:
  - Roles/grants: `legacy/reporting-db/init/01-roles-and-schemas.sh`
  - Local Postgres + direct `5432` exposure for the five teams: `legacy/docker-compose.yml`
  - Architecture narrative + the five `report_reader` consumers: `legacy/README.md`
  - App-schema DDL (critical data): `legacy/web-app/api/src/main/resources/db/migration/V1__create_app_schema.sql`
  - Reporting-schema DDL (derived data): `legacy/batch/src/main/resources/db/migration/V1__create_reporting_schema.sql`
  - Batch reads `app`, writes `reporting`, regenerable per business date:
    `legacy/batch/src/main/java/com/contoso/batch/ReconciliationService.java`
- Cloud stand-in service name `postgres-rds` is in the **root** `docker-compose.yml` (does not
  yet create the three roles). The role-creating Postgres is `legacy/docker-compose.yml`'s
  `postgres` service. **No local read-replica service exists** → documented as primary-only.
- IaC rules: `infra/CLAUDE.md` (idempotent, no plaintext secrets, tag everything, least
  privilege, no `0.0.0.0/0` on sensitive ports). `infra/terraform/` does **not** exist yet.
- Governance hooks: `.githooks/commit-msg` requires an `ADR-NNNN` (4-digit) reference or
  `[no-adr:]` for commits touching `*.tf`/`infra/`/compose. PreToolUse secrets hook is
  described in `decisions/0003-secrets-hook-vs-prompt.md` but not wired in `.claude/settings.json`.
- Pre-existing target decision: `decisions/0002-target-cloud-aws.md` already names
  "RDS Postgres + read replica" for reporting — this work implements that.

## Assumptions / gaps recorded
- ADR placed at `decisions/0007-reporting-db-read-replica.md`, following the repo convention
  (`decisions/NNNN-title.md`). Renumbered to 0007 on cherry-pick into `main` (0003 was taken).
- No real replication implemented locally (none present). Local Compose = **primary only**;
  replica routing is represented by a distinct production connection string in docs.
- Role passwords come from `.env` (git-ignored). Tests read them from the environment; no
  secret is ever written to a tracked file.

## Steps performed
1. Inspected repo (Step 0 above).
2. Wrote `docs/discovery-reporting-db.md` — current-state report (7 required sections).
3. **Ran a parallel workflow** (run id `wf_28ac2311-eb4`) to author + adversarially verify the
   remaining four artifacts (per the "kannst du das als workflow machen" request). Pattern:
   pipeline of `author → verify` per artifact, one agent each, verify forced to a structured
   pass/issues verdict. Result: **4/4 passed, 0 failures** (8 agents, ~220k tokens).
   - `decisions/0007-reporting-db-read-replica.md` — Multi-AZ + read replica decision.
   - `docs/runbooks/reporting-db-cutover.md` — ordered cutover + rollback (7 steps, GO/NO-GO).
   - `tests/reporting-db/` — authz-boundary tests (3 positive + 4 negative) + data-integrity
     script + README. Reuses local Postgres via `docker compose exec` + `psql`; no new framework.
   - `infra/terraform/reporting-db.tf` — target-state scaffold (Multi-AZ, private, read replica,
     tags, SG rules, Secrets Manager refs). Clearly labelled as NOT applied.
4. Independent post-workflow guard scan (not just trusting the verifiers): files present, both
   `.sh` made executable + `bash -n` clean, **no plaintext password literal**, and the only
   `0.0.0.0/0` in the `.tf` are a comment, a validation guard that *rejects* it, and an egress
   rule (not DB ingress). Spot-read `authz_boundaries.sh` — negative-case exit-code inversion
   and `BEGIN/ROLLBACK` write test are correct.
5. Final summary + validation commands + suggested commit message.

## Known minor staleness
- `reporting-db-cutover.md` carries a `[GAP] infra/terraform/ not yet present` marker because it
  was authored in parallel with the Terraform file. The scaffold now exists at
  `infra/terraform/reporting-db.tf`; the marker is harmless but could be tidied later.
