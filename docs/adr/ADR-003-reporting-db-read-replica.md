# ADR-003: Reporting DB on RDS PostgreSQL with Read Replica

Status: Accepted
Date: 2026-06-30

> Repo convention: ADRs live under `decisions/NNNN-title.md` (e.g. `decisions/0003-reporting-db-read-replica.md`). This file mirrors that decision in the `docs/adr/` tree. See **ADR-0002** (`decisions/0002-target-cloud-aws.md`, target cloud — already names "RDS Postgres + read replica" for reporting) and **ADR-0003** (secrets — AWS Secrets Manager / SSM references, no plaintext).

## Context

On-prem today (`legacy/`) runs a single `postgres:16-alpine` container (db `contoso`) that publishes `5432:5432` so the five reporting teams can query directly. `legacy/reporting-db/init/01-roles-and-schemas.sh` provisions three LOGIN roles and two schemas:

- `app_user` — owns schema `app` (RW). System of record.
- `batch_user` — owns schema `reporting` (RW); has `USAGE ON SCHEMA app` plus `ALTER DEFAULT PRIVILEGES FOR ROLE app_user IN SCHEMA app GRANT SELECT ON TABLES TO batch_user` (cross-schema SELECT into `app`).
- `report_reader` — `USAGE ON SCHEMA reporting` plus `ALTER DEFAULT PRIVILEGES FOR ROLE batch_user IN SCHEMA reporting GRANT SELECT ON TABLES TO report_reader`. SELECT-only on `reporting`; no access to `app`; no writes anywhere.

The `app` schema (`app.customers`, `app.accounts`, `app.transactions`) is critical integrity data and the system of record. The `reporting` schema (`reporting.daily_balances`, `reporting.reconciliation_results`, `reporting.discrepancies`) is derived and regenerable: `ReconciliationService` reads `app.transactions` for a business date and rewrites `reporting.*` idempotently (DELETE + reinsert per date). Table DDL is owned by Flyway inside each Spring app (web-api migrates `app`, batch migrates `reporting`), not by the init script.

We are moving to AWS `eu-central-1`. We need a managed Postgres target that preserves these roles and grants exactly, keeps the database off the public internet, and still lets the five teams query directly.

## Decision

- Provision **Amazon RDS for PostgreSQL, Multi-AZ, as the primary**, holding **both** the `app` and `reporting` schemas. web-api writes `app` on the primary; batch writes `reporting` and reads `app` on the primary.
- Provision a **read replica**. **Read traffic from the five reporting teams is routed to the replica endpoint**, where they connect as `report_reader`.
- **Preserve the existing three roles and their grants verbatim** (`app_user`, `batch_user`, `report_reader`). We do not redesign or rename roles or grants.
- **The schema split is explicitly deferred** — `app` and `reporting` stay co-located on one primary instance for now.

## Alternatives considered

**(a) RDS primary only (no replica).** Simplest. Rejected: the five teams' read traffic would land on the writer instance, competing with web-api writes and batch reconciliation I/O, and any analyst connection storm would directly threaten the system-of-record. No read isolation.

**(b) RDS primary + read replica — SELECTED.** Multi-AZ primary carries all writes and the `batch_user` cross-schema reads; the replica absorbs the five teams' `report_reader` SELECT load. Write workload is isolated from analyst read load, the replica gives a failover/read-scaling lever, and `batch_user`'s `USAGE ON SCHEMA app` + cross-schema SELECT grant keep working unchanged because both schemas remain on the same logical database. Matches ADR-0002.

**(c) Separate reporting database instance — DEFERRED.** A dedicated instance for `reporting` would require either replicating `app` into it or breaking `batch_user`'s cross-schema dependency: batch reconciliation reads `app.transactions` and writes `reporting.*` in the same database, relying on `batch_user`'s `USAGE ON SCHEMA app` and the `app_user`-granted SELECT default privileges. Splitting now would force redesigning that grant chain (or adding cross-instance replication/ETL) and risk the integrity data. Because `reporting` is derived and regenerable, the split buys us little today and is deferred until there is a concrete driver.

## Consequences

- Read isolation: analyst load on the replica, writers protected on the Multi-AZ primary.
- Grants survive unchanged; the `batch_user` cross-schema path keeps functioning since both schemas share one database.
- Replica lag is acceptable: `reporting` is batch-produced per business date, not real-time.
- Connection management: the five teams must use the **replica** endpoint; the primary endpoint is for web-api and batch only. Document both endpoints clearly.
- Single instance for both schemas means a future schema split is a known, tracked debt (see Deferred work).
- Flyway ownership is unchanged: web-api migrates `app`, batch migrates `reporting`, both against the primary.

## Security and compliance controls

- **Private only**: RDS instances (primary and replica) are `publicly_accessible = false`, in private subnets. The database is never reachable from the internet.
- **Security group**: ingress on 5432 allowed ONLY from (1) the app-tier SG and (2) an approved analysts CIDR supplied as a Terraform variable — never a literal, never `0.0.0.0/0`.
- **Secrets**: role passwords (`APP_DB_PASSWORD`, `BATCH_DB_PASSWORD`, `REPORT_DB_PASSWORD`) come from AWS Secrets Manager / SSM references, never plaintext in tracked files (see ADR-0003). No hardcoded credentials, account IDs, or CIDRs in IaC.
- **Encryption**: encryption at rest (KMS) and in transit (TLS / `rds.force_ssl`) enabled on primary and replica.
- **Least-privilege boundary**: `report_reader` remains SELECT-only on `reporting`, with no access to `app` and no write capability anywhere. The replica endpoint exposes only this role to the five teams, so analyst access cannot reach or mutate the system of record. IAM follows least privilege (no `*:*`), per `infra/CLAUDE.md`.

## Deferred work

- **Schema split** into a separate reporting instance — deferred until a concrete driver exists; requires resolving the `batch_user` cross-schema grant (cross-instance replication or ETL) first.
- **`infra/terraform/`** does not exist yet; the RDS module (primary, replica, SG, subnet group, parameter group with `force_ssl`, Secrets Manager wiring) must be authored. Remote state = S3 backend + DynamoDB lock (described in `infra/CLAUDE.md`, not yet stood up).
- **Cutover runbook**: keep on-prem Postgres READ-ONLY during the cutover window; app writers frozen until validation completes; rollback = repoint web-api, batch, and the five teams back to on-prem. `reporting` can be regenerated by re-running batch over the affected date range rather than migrated.
- **No local read-replica stand-in** exists in the repo today (root `docker-compose.yml` has only `postgres-rds`, which does not create the roles); decide whether to add one for local parity.
