# The Migration Plan — per workload (Challenge 3 · Architect)

> Target cloud: **AWS** (see [ADR-0002](../decisions/0002-target-cloud-aws.md)).
> We do **not** deploy live. Every cloud primitive is stood in for locally with Docker
> Compose, per [`scenario/02-cloud-migration.md`](../scenario/02-cloud-migration.md):
>
> | Local stand-in (docker compose) | Cloud primitive it represents |
> |---------------------------------|-------------------------------|
> | **MinIO** (`*-s3`)              | Amazon **S3**                 |
> | **Postgres** (`*-rds`)         | Amazon **RDS** (Postgres)     |
> | **Redis** (`*-elasticache`)    | Amazon **ElastiCache** (Redis)|
> | container on the compose net    | container task on **ECS Fargate** behind an **ALB** |
>
> This plan is written for three readers: the **auditor** (what gets provisioned and why it's
> safe), the **CTO** (the pattern choice and trade-offs), and **ops** (the order of operations
> at 4am). It is grounded in the actual code under [`legacy/`](../legacy), not a generic guess.

---

## 0. Migration stance — one pattern does **not** fit all three

The memo's headline is *lift-and-shift-then-optimize* (see [`01-memo.md`](01-memo.md)), but the
right *granularity* is per workload. We classify each workload with the standard 6-R lens and
pick deliberately:

| Workload            | Pattern              | Why this and not the others |
|---------------------|----------------------|-----------------------------|
| web-app **frontend**| **Re-platform**      | A built Vue SPA is just static files. Putting it on S3 + CloudFront is cheaper, faster, and more available than running nginx on a container — and it's a tiny change. |
| web-app **API**     | **Re-host (containerize)** | The Spring Boot jar already runs in a container. Move the same image to ECS Fargate behind an ALB with a config swap. Lowest risk; optimize later. |
| **batch**           | **Re-architect (trigger only)** | Keep the reconciliation *logic* untouched; replace the 24/7 `@Scheduled` daemon with EventBridge Scheduler → a run-to-exit ECS task. Cloud-native where it's cheap to be. |
| **reporting-db**    | **Re-platform**      | Move Postgres to managed **RDS + read replica**. Same engine, same schemas/roles; AWS runs backups, failover, patching. The five teams keep direct SQL access — to the **replica**. |

> The CTO wanted "cloud-native, not lift-and-shift." This is the honest answer: we go
> cloud-native exactly where the workload invites it (static hosting, scheduled jobs, managed
> DB) and re-host where refactoring would add risk without payback (the API). The aggressive
> refactors (ElastiCache caching, splitting the DB) are explicitly deferred — see §6.

---

## 1. Cross-cutting decisions (apply to every workload)

These are settled once here so the per-workload sections don't repeat them.

- **One VPC, three tiers.** Public subnets (ALB, NAT), private-app subnets (ECS tasks),
  private-data subnets (RDS, ElastiCache). Nothing in the data tier is internet-reachable.
- **Secrets** live in **AWS Secrets Manager**; tasks receive *references*, never values
  (see [ADR-0003](../decisions/0003-secrets-hook-vs-prompt.md)). Local stand-in: the
  git-ignored `.env`. The four DB passwords (`POSTGRES_PASSWORD`, `APP_DB_PASSWORD`,
  `BATCH_DB_PASSWORD`, `REPORT_DB_PASSWORD`) each become a Secrets Manager secret.
- **One shared RDS instance, not three.** The legacy code couples the workloads through a
  single Postgres (see §5, coupling C2). We preserve that: **one RDS instance, two schemas
  (`app`, `reporting`), three roles (`app_user`, `batch_user`, `report_reader`)**. Splitting
  is a post-migration option, not part of the cutover.
- **IaC = Terraform** (see [`infra/CLAUDE.md`](../infra/CLAUDE.md)): idempotent, tagged
  (owner/workload/env/cost-center), least-privilege IAM, S3+DynamoDB remote state. It must
  *read right* even though we never `apply` to a live account.
- **Schema ownership stays with Flyway** inside each Spring Boot app. RDS is provisioned
  empty; the apps migrate it on first start. This keeps the local→cloud story identical.

---

## 2. Workload: **web-app** (frontend + API)

### Current state (from the code)
- **frontend** — Vue SPA built by Vite, served by **nginx** (`nginx:alpine`). nginx does two
  jobs: serve static files *and* reverse-proxy `location /api/ → http://web-api:8080`.
- **api** — Spring Boot (Temurin 21 JRE), `/api/*` REST endpoints, `/actuator/health`,
  talks to Postgres `app` schema as `app_user`. Stateless.
- Exposed locally: frontend `:8080`, api `:8081`.

### Target AWS architecture
```
Internet
   │
   ▼
CloudFront ──(default)──► S3 bucket  contoso-web-frontend   (the built Vue dist/)
   │
   └──(/api/* behavior)─► ALB ──► ECS Fargate service: web-api  ──JDBC──► RDS (app schema)
```
- **frontend → S3 + CloudFront.** Upload `dist/` to S3 (`contoso-web-frontend-s3`); CloudFront
  in front. The `/api/*` path becomes a **CloudFront behavior** pointing at the ALB origin —
  this *replaces nginx's reverse proxy* and preserves the same-origin `/api` contract, so the
  Vue app needs **no code change and no CORS** (this is how we design out coupling C1).
- **api → ECS Fargate behind an ALB.** Same container image. ALB target group health check =
  `/actuator/health` (already wired in the Dockerfile/healthcheck). Min 2 tasks across 2 AZs.
- **assets bucket** (`contoso-web-assets-s3`) is provisioned for future user uploads/exports;
  legacy doesn't use object storage yet, so it ships empty.

### Local stand-in
- `minio-s3` holds the frontend bundle and the assets bucket.
- `postgres-rds` is the `app` schema.
- The `web-app` container in the **top-level** `docker-compose.yml` stands in for the
  ECS-Fargate API task; ALB/CloudFront are represented by the published port + the frontend's
  proxy.

### Migration steps
1. Build the SPA (`npm run build`) and sync `dist/` → frontend S3 bucket; create CloudFront
   distribution with the S3 default origin and the `/api/*` → ALB behavior.
2. Build & push the **web-api** image to ECR (locally: `contoso/legacy-web-api:local`).
3. Provision ALB + target group + ECS Fargate service; inject `SPRING_DATASOURCE_*` from
   Secrets Manager refs.
4. Point the API task at the RDS endpoint; let Flyway migrate the `app` schema on first start.
5. Smoke-test through CloudFront, then flip DNS.

### Risks / couplings handled
- **C1 (nginx `/api` proxy)** → replaced by the CloudFront `/api/*` behavior. No CORS, no app
  change. *Watch:* CloudFront caching must be disabled on `/api/*` (dynamic).
- API is **stateless** → horizontal scaling is free; no session affinity needed.

### Validation (feeds [The Proof](../tests))
- `GET /api/customers` through CloudFront returns 200 and the seeded customers.
- `/actuator/health` is the ALB health check and returns `UP`.
- A request to `/api/*` is **not** served from cache (assert no stale read).

### Rollback
Frontend: CloudFront still has the previous S3 object version (versioned bucket) — repoint or
invalidate. API: ALB weighted target group back to the on-prem target / previous task set.

---

## 3. Workload: **batch** (nightly reconciliation)

### Current state (from the code)
- Spring Boot service that runs **24/7** only to fire `@Scheduled(cron = "${recon.cron}")` at
  `0 0 2 * * *`. `ReconciliationService` reads `app.transactions`, compares to a mocked ledger
  (`id % 7 == 0 → 10.00 lower`), writes `reporting.daily_balances`,
  `reporting.reconciliation_results`, `reporting.discrepancies`. **Idempotent per business
  date** (deletes that date's rows first). Connects as `batch_user` (RW `reporting`, RO `app`).
- A manual `POST /run?date=…` trigger exists for on-demand runs.
- `depends_on web-api healthy` so the `app` tables + seed exist before the first run.

### Target AWS architecture
```
EventBridge Scheduler  (cron 0 0 2 * * *, the SAME schedule)
   │  invokes
   ▼
ECS Fargate  RunTask: batch (run-to-exit)  ──JDBC──► RDS  (reads app, writes reporting)
```
- **Re-architect the trigger, not the logic.** Drop the always-on container. EventBridge
  Scheduler runs the task once; the container reconciles yesterday's date and **exits**. We
  pay for ~minutes/day instead of 24h/day, and the schedule lives in infrastructure where ops
  can see and change it.
- Keep the **manual trigger** as a second EventBridge rule / one-off `RunTask` (ops at 4am).
- Same image, same `batch_user` Secrets Manager credentials.

### Local stand-in
- `postgres-rds` provides both schemas. EventBridge Scheduler is represented locally by the
  existing cron in the container (or by calling `POST /run`); the *behaviour* is identical.

### Migration steps
1. Containerize is already done; push image to ECR.
2. Define the ECS task definition (`batch_user` secret ref, RDS endpoint).
3. Create EventBridge Scheduler rule `0 0 2 * * *` → `ecs:RunTask` with the task def.
4. First run: confirm it reads `app`, writes the three `reporting` tables, and is idempotent
   on re-run (row counts stable, not doubled).

### Risks / couplings handled
- **C3 (batch needs `app` schema to exist first)** → in the cloud there is no `depends_on`.
  Mitigation: the batch task **tolerates a not-yet-migrated app schema** by failing fast and
  letting EventBridge retry, *and* cutover order (§7) provisions web-api (which owns `app` via
  Flyway) before the first batch run. The validation suite asserts batch fails cleanly rather
  than writing garbage when `app` is empty.
- **Idempotency** is a correctness guarantee we must not lose: the task must run the same
  `DELETE`-then-`INSERT` per business date. Asserted by The Proof.
- *Trade-off:* a run-to-exit task loses the in-process `@Scheduled` timer; that's the point —
  the schedule moves to EventBridge. The `@Scheduled` bean is disabled in the cloud profile.

### Validation (feeds [The Proof](../tests))
- After a run for the seeded date, `reporting.reconciliation_results` has one row per account
  and the seeded `id % 7` discrepancies appear in `reporting.discrepancies`.
- Re-running the same date does **not** double rows (idempotency).
- `report_reader` can read the results; `batch_user` cannot write to `app`.

### Rollback
Disable the EventBridge rule; re-enable the on-prem cron. Because each run is idempotent per
date, a re-run after rollback is safe — no compensating cleanup needed.

---

## 4. Workload: **reporting-db** (the DB five teams query directly)

### Current state (from the code)
- **One** `postgres:16-alpine`, two schemas (`app`, `reporting`), three roles created by
  `reporting-db/init/01-roles-and-schemas.sh`: `app_user` (owns `app`), `batch_user` (owns
  `reporting`, SELECT on `app`), `report_reader` (**SELECT-only on `reporting`**).
- The **five reporting teams connect straight to `:5432`** as `report_reader`.

### Target AWS architecture
```
                    ┌──────────────► RDS PRIMARY (app + reporting)  ◄── web-api (RW app)
                    │                                               ◄── batch  (RW reporting, RO app)
   five teams ──────┘ (read-only)                                    │  async replication
   psql / BI tools ─────────────────► RDS READ REPLICA (reporting)  ◄┘
                                       report_reader connects HERE
```
- **RDS Postgres (Multi-AZ) primary** holds both schemas; web-api and batch write here.
- **RDS read replica** serves the five teams' read traffic as `report_reader`, isolating
  analyst/BI load from the transactional primary. This is the scenario's
  "RDS Postgres + read replica" mapping, justified by the real access pattern.
- **Roles & grants are reproduced**, not re-invented: the same three roles, same
  least-privilege grants. The bootstrap shell script becomes a one-time SQL run against RDS
  (or an RDS-init Lambda); ongoing table DDL still belongs to each app's Flyway.

### Local stand-in
- `postgres-rds` = the primary. (A second Postgres service can stand in for the read replica
  if we want to demonstrate the split; otherwise the replica is documented and the role
  routing is shown via connection strings.)

### Migration steps
1. Provision RDS primary (Multi-AZ), parameter group, subnet group in the data tier; SG allows
   `:5432` only from the app tier **and** from the analysts' CIDR (coupling C4).
2. Create the three roles + grants (port the init script's SQL).
3. Migrate data: `pg_dump` the on-prem DB → restore into RDS (cutover window), or DMS for a
   low-downtime path. The `reporting` rows are derived (batch can regenerate per date), so the
   critical data to migrate intact is the **`app` schema** (customers/accounts/transactions).
4. Create the read replica; give the five teams the **replica** endpoint as `report_reader`.
5. Repoint web-api and batch `SPRING_DATASOURCE_URL` at the RDS **primary**.

### Risks / couplings handled
- **C2 (one DB shared by all three workloads, cross-schema grant)** → preserved as a single
  RDS instance. *We explicitly do not split it during migration* — `batch_user`'s SELECT on
  `app` would break across two instances. Splitting is deferred (§6).
- **C4 (five teams connect directly to the DB)** → preserved, but pointed at the **replica**
  and constrained by security group to the analysts' CIDR. The DB does **not** become public;
  access is network-scoped. *This is the residency/compliance-sensitive surface — least
  privilege and SG rules are auditor-facing.*
- Replication lag means the teams see *near*-real-time reporting data. Acceptable: reporting,
  not transactional. Documented for the five teams.

### Validation (feeds [The Proof](../tests))
- `report_reader` can `SELECT` from `reporting` and **cannot** read `app` or write anything
  (negative test — proves least privilege survived the move).
- `batch_user` can read `app` and write `reporting`; cannot write `app`.
- Row counts / checksums on the `app` schema match pre- and post-migration (data integrity).

### Rollback
Keep the on-prem Postgres running read-only during the window. If RDS is wrong, repoint the
apps and the five teams' connection strings back to on-prem. Because `reporting` is
regenerable by re-running batch, only `app`-schema drift matters — and the apps were the only
writers, frozen during cutover.

---

## 5. Coupling register (the "gremlins" → how each is addressed)

These are the undocumented couplings Discovery must surface; each is designed-out or
designed-around above, and the starred ones are asserted by [The Proof](../tests) so the
validation isn't theatre.

| # | Coupling (where it hides) | Migration risk | Addressed by | Asserted? |
|---|---------------------------|----------------|--------------|-----------|
| C1 | nginx reverse-proxies `/api` → `web-api:8080` by service name (`frontend/nginx.conf`) | Static frontend on S3 can't resolve `web-api`; `/api` breaks / CORS | CloudFront `/api/*` behavior → ALB origin; same-origin preserved | ✅ no-CORS / `/api` 200 |
| C2 | **One Postgres** shared by all three; `batch_user` SELECTs `app` *and* owns `reporting` | Splitting into per-workload DBs breaks batch's cross-schema read | Keep a **single RDS** instance, two schemas, three roles | ✅ grant matrix |
| C3 | batch `depends_on web-api healthy` — needs `app` tables before first run | No `depends_on` in ECS; batch could run against an empty schema | Cutover order (§7) + batch fails fast & EventBridge retries | ✅ empty-schema test |
| C4 | Five teams connect **directly** to `:5432` as `report_reader` | Hiding the DB behind the app would break five consumers | Preserve direct access, point at **read replica**, SG-scope to analyst CIDR | ✅ read-only negative test |
| C5 | batch is a 24/7 daemon only to fire a 02:00 cron (`@Scheduled`) | Paying for 24h compute; schedule invisible to ops | EventBridge Scheduler → run-to-exit ECS task; `@Scheduled` off in cloud profile | — (cost, not correctness) |

---

## 6. Explicitly deferred (refactor-later, not part of cutover)

Honesty for the CTO and the auditor — what we are **not** doing now, and why it's safe to wait:

- **ElastiCache (Redis) caching.** The legacy code has **no cache today**. The
  `redis-elasticache` stand-in is provisioned for a *future* read-through cache on hot web-api
  endpoints. Adding it during cutover would be optimizing an unproven hotspot. Phase 2.
- **Splitting the shared DB** into per-workload databases. Blocked by C2; revisit once the
  cross-schema read is removed (e.g., batch consumes an event/extract instead of reading
  `app` directly).
- **API autoscaling policies / blue-green deploys.** Start with fixed 2-task min; tune on
  real traffic.

---

## 7. Cutover order (for ops, at 4am)

Dependencies dictate the sequence. Detailed per-stage rollback is [The Undo](08-undo.md)
(stretch); this is the happy path.

1. **RDS first.** Provision primary + replica, create roles/grants, migrate `app` data,
   verify checksums. (Nothing depends on the apps yet.)
2. **web-api** onto ECS/ALB. Flyway migrates/validates `app`. Smoke `/actuator/health` and
   `GET /api/customers`.
3. **batch** task def + EventBridge rule. Run **once manually** (`RunTask`) for the seeded
   date; verify `reporting` output + idempotency on a second run.
4. **frontend** to S3/CloudFront; wire the `/api/*` behavior to the ALB.
5. **Repoint the five teams** to the read-replica endpoint as `report_reader`; confirm their
   queries return and that write/`app` access is denied.
6. **Decommission** on-prem only after a full validation pass (The Proof) is green.

> Freeze writes to the on-prem DB from step 1 until step 6 so `app` cannot drift mid-cutover.
> Each piece has an independent rollback; the DB stays recoverable because `reporting` is
> regenerable and `app` had a single frozen writer.
