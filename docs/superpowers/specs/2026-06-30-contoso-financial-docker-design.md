# Contoso Financial — On-Prem Workloads in Docker

**Date:** 2026-06-30
**Status:** Approved (design)

## Context

Contoso Financial runs three on-prem workloads that we want to represent as a
realistic, container-based reference system (production-grade foundation):

1. A customer-facing web app.
2. A nightly batch reconciliation job.
3. A reporting database that five teams query directly.

This spec describes a Docker Compose system that models these three workloads
as a classic 3-tier architecture, suitable as a foundation for further
development and a later cloud migration.

## Decisions (from brainstorming)

- **Purpose:** Production foundation — care about security, migrations, config.
- **Web tier:** Vue.js frontend + dedicated Spring Boot REST API + its own app data.
- **Database topology:** One PostgreSQL instance with separate schemas
  (`app` and `reporting`).
- **Batch scheduling:** Long-running container using Spring `@Scheduled` (cron),
  with a REST endpoint to trigger the job manually for testing.

## Architecture

```
┌──────────────┐      ┌───────────────────┐      ┌─────────────────────────────┐
│ web-frontend │─────▶│ web-api            │─────▶│ postgres                     │
│ (Vue.js +    │ HTTP │ (Spring Boot REST) │ JDBC │ ┌─────────┬────────────────┐ │
│  nginx)      │      └───────────────────┘      │ │ app     │ reporting       │ │
└──────────────┘                                 │ │ schema  │ schema          │ │
                      ┌───────────────────┐      │ └─────────┴────────────────┘ │
                      │ batch-recon        │─────▶│        ▲                     │
                      │ (Spring Boot,      │ JDBC └────────┼─────────────────────┘
                      │  @Scheduled cron)  │               │ (read-only)
                      └───────────────────┘      ┌─────────┴───────────────────┐
                                                 │ 5 teams (report_reader user, │
                                                 │ read-only on reporting)      │
                                                 └──────────────────────────────┘
```

### Containers (docker-compose)

1. **postgres** — single PostgreSQL 16 instance.
   - Schema `app`: web application data (read/write by web-api).
   - Schema `reporting`: reconciliation output (written by batch-recon,
     read by the five teams).
   - DB users:
     - `app_user` — RW on `app`.
     - `batch_user` — read on `app`, RW on `reporting`.
     - `report_reader` — read-only on `reporting` (this is what the five
       teams connect with).
   - Health check via `pg_isready`.

2. **web-api** — Spring Boot REST service.
   - Exposes `/api/...` endpoints for customers, accounts, transactions.
   - Connects as `app_user`.
   - Flyway migrations own the `app` schema.
   - Actuator health endpoint for the container health check.

3. **web-frontend** — Vue.js single-page app.
   - Built with Vite, served by nginx.
   - nginx reverse-proxies `/api` to `web-api`.

4. **batch-recon** — Spring Boot application.
   - Long-running; `@Scheduled` cron triggers the nightly reconciliation.
   - `POST /run` endpoint to trigger the job manually.
   - Connects as `batch_user`.
   - Flyway migrations own the `reporting` schema.
   - Actuator health endpoint.

The five teams are not a container; they connect externally to the exposed
Postgres port using `report_reader`.

## Data Model

### `app` schema (owned by web-api Flyway)

- `customers` — `id`, `name`, `email`, `created_at`.
- `accounts` — `id`, `customer_id` (FK), `iban`, `currency`, `balance`,
  `opened_at`.
- `transactions` — `id`, `account_id` (FK), `amount`, `direction`
  (DEBIT/CREDIT), `booked_at`, `external_ref`.

### `reporting` schema (owned by batch-recon Flyway)

- `daily_balances` — `id`, `account_id`, `business_date`, `opening_balance`,
  `closing_balance`, `computed_at`.
- `reconciliation_results` — `id`, `business_date`, `account_id`,
  `transactions_count`, `total_amount`, `matched_count`, `unmatched_count`,
  `status`, `computed_at`.
- `discrepancies` — `id`, `business_date`, `account_id`, `transaction_ref`,
  `expected_amount`, `actual_amount`, `reason`, `detected_at`.

## Reconciliation Logic (batch-recon)

For a given business date:

1. Read the day's `app.transactions`.
2. Compare them against a mocked external settlement/ledger feed (a deterministic
   in-process generator that derives expected entries from the transactions, then
   injects a small, seeded set of discrepancies so the output is non-trivial).
3. Compute per-account opening/closing balances → `reporting.daily_balances`.
4. Record matched/unmatched counts and status →
   `reporting.reconciliation_results`.
5. Record each mismatch → `reporting.discrepancies`.

The job is idempotent per business date (re-running replaces that date's
reporting rows).

## Production-Grade Concerns

- **Migrations:** Flyway versioned SQL in both Spring Boot apps; no Hibernate
  `ddl-auto`. web-api owns `app`; batch-recon owns `reporting`. A small
  bootstrap step creates schemas, roles, and grants (via a Postgres init script
  in `/docker-entrypoint-initdb.d`).
- **Secrets/config:** `.env` file consumed by Compose; no credentials hardcoded
  in images or committed code. `.env.example` checked in.
- **Health checks:** All long-running containers expose health checks;
  `depends_on` uses `condition: service_healthy`.
- **Least privilege:** Three distinct DB roles as above; teams get read-only.
- **Images:** Multi-stage Dockerfiles (build stage + slim runtime); JRE-only
  runtime images for the Java services, nginx for the frontend.

## Seed Data

A Postgres init script (or a Flyway repeatable seed in web-api) inserts a handful
of customers, accounts, and a day of transactions so that the web app shows
content and the batch job has something to reconcile on first run.

## Testing Strategy

- **web-api:** Spring Boot test slices for the controllers/repositories against a
  test Postgres (Testcontainers).
- **batch-recon:** Unit tests for the reconciliation logic (matching, balance
  computation, discrepancy detection) plus an integration test against
  Testcontainers verifying reporting rows are written and idempotent.
- **web-frontend:** Component-level tests for the main views and the API client.
- **System smoke:** `docker compose up` brings the stack healthy; a documented
  manual check (open the web app, trigger `POST /run`, query reporting as
  `report_reader`).

## Out of Scope

- Authentication/authorization for end users (customer login) — modelled as a
  fixed/demo customer context for now.
- TLS termination, real external settlement integration, and the actual cloud
  migration target — these are future increments.

## Repository Layout

```
cloudmigration/
├── docker-compose.yml
├── .env.example
├── postgres/
│   └── init/                # schema + roles + grants bootstrap
├── web-api/                 # Spring Boot REST API (app schema)
├── batch-recon/             # Spring Boot batch (reporting schema)
├── web-frontend/            # Vue.js + nginx
└── docs/superpowers/specs/  # this spec
```
