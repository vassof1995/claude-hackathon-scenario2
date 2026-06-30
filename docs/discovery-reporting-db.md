# Current-State Discovery — `reporting-db` workload

Scope: the on-prem reporting database only. Evidence is drawn solely from files in this
repository (paths in §6). Target architecture (AWS `eu-central-1`, RDS Multi-AZ primary +
read replica) is decided in `docs/adr/ADR-003-reporting-db-read-replica.md`.

---

## 1. Runtime and data model

One `postgres:16-alpine` instance holds **two schemas** in a single database (`contoso`):

| Schema | Owner | Contents | Producer | Consumers |
|---|---|---|---|---|
| `app` | `app_user` | `customers`, `accounts`, `transactions` | `web-api` (RW) | `web-api` (RW), `batch` (RO) |
| `reporting` | `batch_user` | `daily_balances`, `reconciliation_results`, `discrepancies` | `batch` (RW) | five teams via `report_reader` (RO) |

- `app` is the **system of record** (customer-facing writes). Tables and constraints:
  `customers(email UNIQUE)`, `accounts(iban UNIQUE, customer_id FK)`,
  `transactions(account_id FK, direction CHECK IN ('DEBIT','CREDIT'), external_ref)`.
- `reporting` is **derived**: the nightly batch reads `app.transactions` for a business date,
  compares against a (mocked) external ledger, and writes per-account balances, results, and
  discrepancies. It is **idempotent per business date** — re-running a date deletes and
  rewrites that date's reporting rows. Therefore `reporting` can be **regenerated** for any
  date range by re-running the batch; it is not unique source data.
- Schema DDL is owned by **Flyway inside each Spring Boot app** (not by the init script):
  `web-api` migrates `app`, `batch` migrates `reporting`.

**Confidence: high.**

---

## 2. Roles and grants

Three least-privilege login roles, created once at first DB start by the init script:

| Role | Privilege | Used by |
|---|---|---|
| `app_user` | `LOGIN`; owns schema `app` (RW) | `web-api` |
| `batch_user` | `LOGIN`; owns schema `reporting` (RW); `USAGE` + `SELECT` on `app` | `batch` |
| `report_reader` | `LOGIN`; `USAGE` on `reporting` + `SELECT` on its tables only | the five reporting teams |

Grant mechanics worth preserving exactly:
- `batch_user`'s read of `app` is via `GRANT USAGE ON SCHEMA app` + `ALTER DEFAULT PRIVILEGES
  FOR ROLE app_user IN SCHEMA app GRANT SELECT ON TABLES TO batch_user`.
- `report_reader`'s read of `reporting` is via `GRANT USAGE ON SCHEMA reporting` + `ALTER
  DEFAULT PRIVILEGES FOR ROLE batch_user IN SCHEMA reporting GRANT SELECT ON TABLES TO
  report_reader`.
- `report_reader` has **no** access to `app` and **no** write anywhere. This is the
  authorization boundary the validation suite must prove (positive + negative).

**These roles and grants must be preserved verbatim by the migration — not redesigned.**

**Confidence: high.**

---

## 3. Direct consumer access pattern

- **Five reporting teams connect directly to Postgres on port `5432` as `report_reader`** and
  query the `reporting` schema with `psql` / BI tools.
- In the on-prem stand-in this is the published host port `5432:5432`, commented in compose as
  *"exposed so the five reporting teams can query directly."*
- The teams are **external, direct database consumers** — they are not mediated by any API or
  service. There is no application indirection to repoint; their connection string *is* the
  contract.

Implications for target state:
- Read traffic from the five teams is routed to the **RDS read replica** endpoint, still as
  `report_reader`, so the contract (role + schema + table shape) is unchanged for them.
- Their access is governed by a security group restricted to an **approved analysts CIDR**;
  the database is never publicly accessible.

**Confidence: high** that five teams connect directly as `report_reader` (stated in
`legacy/README.md` and compose). **Confidence: low** on the *identity* of the five teams and
their exact query set — not present in the repo; see Risks.

---

## 4. Hidden dependencies and migration couplings

| # | Coupling | Why it constrains the migration | Confidence |
|---|---|---|---|
| 1 | **Cross-schema grant: `batch_user` reads `app`, writes `reporting`** | `app` and `reporting` live in one database specifically so `batch_user` can `SELECT` across schemas in a single connection. **This prevents a safe split of `app` and `reporting` into separate DB instances during this migration** — splitting would break the batch's read of `app`. Schema split is therefore explicitly deferred. | high |
| 2 | **Five teams' access depends on `ALTER DEFAULT PRIVILEGES FOR ROLE batch_user`** | `report_reader`'s `SELECT` is granted via *default privileges tied to objects created by `batch_user`*. If, post-migration, reporting tables are ever created by a different role (e.g. a restore as superuser, or a different migration identity), `report_reader` **silently loses access**. Cutover must restore/recreate reporting objects under `batch_user` (or re-grant explicitly) and the suite must assert team read access afterward. | high |
| 3 | **`reporting` is derived, `app` is authoritative** | Integrity validation must focus on `app` (customers/accounts/transactions). `reporting` does not need byte-for-byte migration — it can be regenerated by re-running the batch for the required date range after cutover. This shrinks the integrity-critical surface and the cutover window. | high |
| 4 | **Direct `5432` exposure is the consumer contract** | Because teams connect at the DB protocol level (not an API), the migration cannot "adapt" the interface — it must present the same role/schema on a reachable endpoint (the replica) behind an SG, or the teams break. | high |
| 5 | **Schema ownership is Flyway-on-app-boot, not in the DB dump** | A `pg_dump` of data + the init-script roles is not the whole story: table DDL originates from the apps' Flyway. Ordering at cutover (roles → app schema present → data restore → reporting regenerated) matters. | medium |

**Confidence: high** on the set of couplings; the report_reader-via-default-privileges
fragility (#2) is the one a single-pass review most easily misses.

---

## 5. Risks

| Risk | Severity | Notes |
|---|---|---|
| **Public database exposure** | High | On-prem stand-in publishes `5432` to the host for the five teams. In cloud this must become private-only RDS + SG-restricted; a lift-and-shift of the exposure pattern would be a compliance breach. |
| **Direct DB access is a compliance-sensitive surface** | High | Five external teams hold direct credentials to the production reporting data. Auditable, least-privilege, network-restricted access is mandatory; the read replica isolates this read load from the transactional primary. |
| **Silent loss of team read access (coupling #2)** | High | Mis-ordered restore breaks `report_reader` without an error at restore time — only the teams notice. Must be asserted in validation before declaring success. |
| **Unknown consumer inventory** | Medium | The repo states "five teams" but not who/what they query. Cutover comms and contract tests need this list; flagged as a gap to fill from stakeholders. |
| **Replica lag for read consumers** | Medium | Teams reading the replica may see slightly stale `reporting` rows vs primary. Acceptable for reporting; documented so analysts know reads are eventually-consistent. |
| **Cross-schema split temptation** | Medium | Pressure to "modernize" by splitting `reporting` out would break coupling #1. Explicitly deferred in the ADR. |
| **Seed/demo data in app migrations** | Low | `V2__seed_demo_data.sql` inserts fake customers; a prod restore path must not re-run seed. Out of strict reporting-db scope but noted. |

---

## 6. Evidence (repository file paths)

| Claim | Evidence |
|---|---|
| Single `postgres:16-alpine`, port `5432` published for teams | `legacy/docker-compose.yml` (`postgres` service, `ports: "5432:5432"`, comment) |
| Three roles + grants, exact privileges | `legacy/reporting-db/init/01-roles-and-schemas.sh` |
| Five teams connect directly as `report_reader` | `legacy/README.md` (architecture diagram + "the five teams"), `legacy/docker-compose.yml` comment |
| `app` schema tables/constraints (critical data) | `legacy/web-app/api/src/main/resources/db/migration/V1__create_app_schema.sql` |
| `app` seed/demo data | `legacy/web-app/api/src/main/resources/db/migration/V2__seed_demo_data.sql` |
| `reporting` schema tables (derived data) | `legacy/batch/src/main/resources/db/migration/V1__create_reporting_schema.sql` |
| Batch reads `app`, writes `reporting`, idempotent per date (regenerable) | `legacy/batch/src/main/java/com/contoso/batch/ReconciliationService.java` |
| Batch connects as `batch_user` | `legacy/docker-compose.yml` (`batch` env), `legacy/batch/src/main/resources/application.yml` |
| web-api connects as `app_user` | `legacy/docker-compose.yml` (`web-api` env), `legacy/web-app/api/src/main/resources/application.yml` |
| Target = RDS + read replica already chosen | `decisions/0002-target-cloud-aws.md` |
| IaC guardrails (no secrets, tags, least privilege, no `0.0.0.0/0`) | `infra/CLAUDE.md` |

---

## 7. Confidence summary

| Finding | Confidence |
|---|---|
| Data model, two schemas, derived `reporting` | High |
| Roles and exact grants | High |
| Five teams connect directly as `report_reader` | High |
| Cross-schema grant blocks a safe DB split (coupling #1) | High |
| `report_reader` default-privileges fragility (coupling #2) | High |
| Direct DB access is compliance-sensitive | High |
| Identity of the five teams / exact query set | Low (not in repo — gap) |
| Flyway-ownership ordering at cutover (#5) | Medium |
