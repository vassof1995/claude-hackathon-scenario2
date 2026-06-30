# The Discovery (Challenge 2 · Architect)

> Surface the real current state — including the ugly inter-dependencies nobody documented.
> Whatever you uncover must visibly shape The Options.

This is read off the **actual `legacy/` source**, not guessed. The legacy stack is one Postgres
(schemas `app` + `reporting`), a Spring Boot `web-api`, a Vue/nginx `web-frontend`, and a Spring
Boot `batch`. It runs end-to-end with `cd legacy && docker compose up`.

## Workloads
### 1. Web app (`legacy/web-app/`)
- **Frontend:** Vue 3 SPA served by **nginx**; `nginx.conf` reverse-proxies `/api/` →
  `http://web-api:8080`. Dev server (`vite.config.js`) proxies `/api` → `http://localhost:8081`.
- **API:** Spring Boot (`contoso-legacy-web-api`), port 8080, JPA with
  `hibernate.ddl-auto: validate` — **schema owned by Flyway**, never auto-generated. Owns the
  `app` schema (customers, accounts, transactions). Connects as `app_user`.
- **Health:** `/actuator/health`.

### 2. Batch reconciliation (`legacy/batch/`)
- **Schedule:** Spring `@Scheduled(cron = "${recon.cron}")`, default `0 0 2 * * *` (02:00),
  overridable via `RECON_CRON`. Manual trigger: `POST /run[?date=YYYY-MM-DD]`.
- **Business date:** reconciles `LocalDate.now().minusDays(1)` — i.e. *yesterday* by wall clock.
- **Reads/writes:** reads `app.transactions` (cross-schema), compares each against a **mocked
  external ledger** (in-process: `id % 7 == 0` → ledger is 10.00 lower), writes
  `reporting.daily_balances`, `reporting.reconciliation_results`, `reporting.discrepancies`.
  Connects as `batch_user`. **Idempotent per business date** (deletes that date's rows first).

### 3. Reporting database (`legacy/` Postgres, `reporting` schema)
- One Postgres instance, **port 5432 exposed**. Roles/schemas created once by
  `reporting-db/init/01-roles-and-schemas.sh` (superuser, on first start).
- **The five direct consumers** connect as **`report_reader`** — `SELECT`-only on `reporting`,
  no access to `app`, no writes. This is the database "five teams query directly".

## The undocumented couplings (the gremlins)
Each must be designed-out or designed-around in The Options, and the starred ones must be
asserted by the validation suite (The Proof).

| # | Coupling | Where it hides | Migration risk | Design-around (→ The Options) | Assert (→ The Proof) |
|---|----------|----------------|----------------|-------------------------------|----------------------|
| 1 | **Five teams query the `reporting` schema directly** as `report_reader` | `01-roles-and-schemas.sh`; port 5432 exposed | Splitting the DB or changing the `reporting` column shapes silently breaks five external consumers | Keep a stable `reporting` contract; expose via RDS **read replica** for the teams; least-priv `report_reader` preserved | ★ contract test pins `reporting.*` column shapes; a read-only role can `SELECT` reporting and **cannot** touch `app` |
| 2 | **Batch reads the web app's `app` schema** (cross-schema) | `ReconciliationService` SQL `FROM app.transactions`; grant in init script | If web-app and batch migrate to separate DBs, batch loses its input | Keep one RDS with both schemas (or an explicit data path); preserve `batch_user` SELECT-on-`app` grant | ★ integrity test: batch totals == sum of `app.transactions` for the date |
| 3 | **Startup ordering: batch depends on web-api being healthy** | `legacy/docker-compose.yml` `batch.depends_on: web-api (healthy)` | web-api's Flyway must create+seed `app` before batch's first run; lose the order → empty/failed reconciliation | Make schema bootstrap explicit and ordered in IaC (migrations job before batch task), not implicit container ordering | ★ smoke test: batch run on a fresh DB after web-api migration yields the expected rows |
| 4 | **Schema/role bootstrap split across 3 places** | init script (roles+schemas) + web-api Flyway (`app`) + batch Flyway (`reporting`) | A lift-and-shift that runs only the apps' Flyway never creates the roles → connections fail | Replicate the init step as an RDS bootstrap (Secrets Manager users + grants) run before the apps | smoke test: all three roles exist and own the right schemas |
| 5 | **Frontend → API by compose DNS name** `web-api` | `nginx.conf` `proxy_pass http://web-api:8080` | The name `web-api` doesn't exist behind an ALB; hardcoded host breaks routing | API base must become **config** (ALB DNS / service-discovery), injected at deploy, not baked into the image | smoke test: frontend reaches the API through configured base, not a literal `web-api` |
| 6 | **Business-date = "yesterday" by wall clock** | `ReconciliationScheduler` / `ReconciliationController` `LocalDate.now().minusDays(1)` | Container timezone differences shift which day is reconciled → wrong/empty results | Pin the task's timezone in IaC; pass the business date explicitly for re-runs | integrity test runs with a fixed date and asserts the known seeded discrepancies |
| 7 | **External ledger feed is mocked in-process** | `ReconciliationService.expectedFromLedger` | The real settlement system is an unbuilt external integration the cutover must plan for | Treat as a target integration point (queue / API) with its own ADR; keep the mock for local tests | integrity test asserts the seeded mismatch pattern (`id % 7`) so the contract is explicit |
| 8 | **Plaintext default passwords as env fallbacks** | `application.yml` `${...:change-me-*}` | Defaults can ship into an image / cloud config | Source every credential from Secrets Manager/SSM; no literal fallbacks in the target (ADR-0003) | the (planned) secrets `PreToolUse` hook + a config scan |

### What the brief's example gremlins turned into here
The brief suggested looking for *a hardcoded IP, a shared filesystem mount, and a cron pinging an
endpoint to keep a cache warm*. Honest finding: **none of those exist in this system** —
- no hardcoded IP, but the analogue is the **hardcoded service name `web-api`** (coupling #5);
- **no shared filesystem** — all cross-workload data flows through Postgres (couplings #1, #2);
- **no cache at all** — the legacy app has no Redis, so there is no cache-warming cron (which is
  also why ElastiCache in the target is a deliberate *addition*, not a migration — ADR-0005).

This is itself a Discovery result: the real couplings are **database-centric** (direct reads,
cross-schema grants, bootstrap order), which is what should drive The Options.
