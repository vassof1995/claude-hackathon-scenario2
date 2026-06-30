# Contoso Financial — Legacy On-Prem System

This is Contoso Financial's three on-prem workloads as they ran **before** the cloud
migration. It is self-contained and runs end-to-end with Docker Compose, so it can serve
as the production-equivalent baseline we migrate *from*.

## The three workloads

| Workload        | Here                         | What it is |
|-----------------|------------------------------|------------|
| Web app         | `web-app/frontend` + `web-app/api` | Customer self-service portal: Vue.js SPA (nginx) over a Spring Boot REST API. |
| Batch           | `batch`                      | Nightly reconciliation job (Spring Boot, `@Scheduled`), writes the reporting schema. |
| Reporting DB    | `reporting-db` + Postgres    | One Postgres instance; the `reporting` schema is what five teams query directly. |

## Architecture

```
web-frontend (Vue + nginx) --/api--> web-api (Spring Boot) --JDBC--> postgres
                                                                       ├── app schema        (web-api, RW)
batch (Spring Boot @Scheduled) --JDBC----------------------------------> reporting schema   (batch RW, teams RO)
five reporting teams ----------------- psql / BI tools -----------------> reporting schema   (report_reader, read-only)
```

One Postgres, two schemas, three least-privilege roles:

- `app_user` — owns `app`, used by web-api.
- `batch_user` — owns `reporting`, reads `app`, used by batch.
- `report_reader` — **read-only on `reporting`**; this is what the five teams connect with.

## Run it

Assumes Docker and nothing else.

```bash
cd legacy
cp .env.example .env        # fill in real passwords; .env is git-ignored
docker compose up --build -d
docker compose ps           # wait until all services are healthy
```

Endpoints:

| URL | What |
|-----|------|
| http://localhost:8080            | Web app (Vue) |
| http://localhost:8081/api/customers | Web API |
| http://localhost:8081/actuator/health | Web API health |
| http://localhost:8082/actuator/health | Batch health |
| `localhost:5432` db `contoso`    | Postgres |

## Trigger the batch manually

The job runs nightly (cron `RECON_CRON`, default `0 0 2 * * *`). To run it on demand
(defaults to yesterday's business date, which is what the seed data uses):

```bash
curl -X POST http://localhost:8082/run
# or a specific date:
curl -X POST "http://localhost:8082/run?date=2026-06-29"
```

## Query the reporting DB as the five teams would

```bash
docker compose exec postgres \
  psql -U report_reader -d contoso \
  -c "SELECT * FROM reporting.reconciliation_results ORDER BY account_id;"
```

`report_reader` can only `SELECT` from `reporting` — it cannot touch `app` or write anything.

## Reconciliation logic

For a business date the batch reads that day's `app.transactions`, compares each against a
mocked external ledger feed (a deterministic generator that injects a small, seeded set of
mismatches), computes per-account opening/closing balances, and writes:

- `reporting.daily_balances`
- `reporting.reconciliation_results`
- `reporting.discrepancies`

It is idempotent per business date — re-running replaces that date's reporting rows.

## Conventions

- DB schema is owned by **Flyway** in each Spring Boot app (`web-api` owns `app`,
  `batch` owns `reporting`); no Hibernate `ddl-auto` generation.
- No secrets in code or images — everything comes from `.env`.
- Multi-stage Dockerfiles; slim JRE / nginx runtime images.
