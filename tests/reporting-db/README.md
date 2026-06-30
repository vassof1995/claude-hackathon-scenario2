# reporting-db migration validation tests

Two self-contained bash scripts that prove the things that must stay true through the
on-prem -> AWS RDS cutover for the Contoso reporting database:

| Script | Proves |
|---|---|
| `authz_boundaries.sh` | The three least-privilege roles (`app_user`, `batch_user`, `report_reader`) have exactly the grants from `legacy/reporting-db/init/01-roles-and-schemas.sh` — no more, no less. |
| `data_integrity.sh` | The CRITICAL `app` schema (system of record) is identical between a source and a destination DB: row counts, content checksums, and zero duplicate business keys. |

No test framework is added — just `bash` + `psql`. No secrets live in either file;
passwords are read from the environment / a sourced `.env`.

## Prerequisites

1. Bring the legacy stack up and let migrations run:
   ```bash
   cd legacy
   cp .env.example .env        # fill in real passwords (git-ignored)
   docker compose up -d         # postgres + web-api (migrates app.*) + batch (migrates reporting.*)
   ```
   The `app.*` tables are created by web-api's Flyway migration and `reporting.*` by
   batch's. Until batch has run at least once, the `report_reader` SELECT grant on
   `reporting` has no tables to attach to (`ALTER DEFAULT PRIVILEGES` only affects
   tables created *after* it). Trigger a batch run if needed (`POST :8082/run`).
2. `docker` + `docker compose` available; for `data_integrity.sh` against remote
   endpoints you also need `psql` on PATH.

## Running

### `authz_boundaries.sh`
Runs entirely through the container (`docker compose exec`), so it works even if host
port 5432 is closed.

```bash
chmod +x tests/reporting-db/*.sh
./tests/reporting-db/authz_boundaries.sh
```
It auto-sources `legacy/.env` for `POSTGRES_USER`, `POSTGRES_DB`,
`APP_DB_PASSWORD`, `BATCH_DB_PASSWORD`, `REPORT_DB_PASSWORD`. Each case prints
`PASS` or `FAIL: expected X got Y`; the script exits non-zero on any failure.

Cases:
- POSITIVE: `report_reader` SELECTs `reporting`; `batch_user` SELECTs `app`;
  `batch_user` INSERTs `reporting` (rolled back, leaves no residue).
- NEGATIVE (deny == PASS, psql exit code inverted): `report_reader` reads `app`;
  `report_reader` writes `reporting`; `report_reader` writes `app`;
  `batch_user` writes `app`.

### `data_integrity.sh`
Compares the `app` schema between `SRC` and `DST` libpq connection strings.

Local self-check (both sides = local DB; should always PASS — proves the harness):
```bash
PGPASSWORD_SRC="$POSTGRES_PASSWORD" ./tests/reporting-db/data_integrity.sh
```
(With no `SRC`/`DST` set, both default to the local DB on `127.0.0.1:5432` using the
superuser from `legacy/.env`.)

Real cutover validation (on-prem vs RDS, both read-only). Pass connection strings and
per-endpoint passwords via env — never in the file:
```bash
SRC="host=onprem.local port=5432 dbname=contoso user=app_user sslmode=require" \
DST="host=contoso.xxxx.eu-central-1.rds.amazonaws.com port=5432 dbname=contoso user=app_user sslmode=require" \
PGPASSWORD_SRC=... PGPASSWORD_DST=... \
  ./tests/reporting-db/data_integrity.sh
```
Use a role that can read `app.*` (e.g. `app_user` or superuser). `report_reader`
cannot read `app` by design. Checks: (a) row counts of customers/accounts/transactions,
(b) per-table MD5 over PK-ordered rows, (c) duplicate `email`/`iban` = 0 on both sides.
Exits non-zero on any mismatch and prints the `src=… dst=…` diff.

## How this maps to post-cutover cloud validation

Target: AWS `eu-central-1`, RDS for PostgreSQL Multi-AZ primary holding BOTH `app`
and `reporting`; a read replica serves the five reporting teams as `report_reader`.
The same 3 roles and least-privilege grants are preserved exactly (schema split is
deferred — `batch_user` still needs cross-schema read of `app`).

- **`authz_boundaries.sh`** is the role-grant contract. After the roles are recreated
  on RDS, re-run the same logic against the RDS endpoint to confirm no privilege drifted
  during migration. Point it at the primary (writes evaluated there) and additionally
  confirm the NEGATIVE/POSITIVE read cases hold on the **read replica** for
  `report_reader` — the replica is read-only at the engine level, which reinforces (not
  replaces) the role-level `report_reader` deny-write boundary. Replace
  `docker compose exec` with a direct `psql "host=<rds-endpoint> sslmode=require"` and
  source passwords from AWS Secrets Manager instead of `.env`.
- **`data_integrity.sh`** is the cutover gate. During the freeze window (on-prem
  READ-ONLY, app writers frozen) run it with `SRC`=on-prem and `DST`=RDS primary. Only
  cut over web-api / batch / the five teams when it prints PASS. If it fails, roll back
  by repointing all three back to on-prem — nothing was written to on-prem during the
  window, so rollback is safe.
- **`reporting` is intentionally not compared.** It is derived and regenerable by
  re-running batch per business date, so app-schema integrity is the only load-bearing
  equivalence check.

## Assumptions / gaps
- Assumes web-api and batch have already migrated their schemas (Flyway owns the table
  DDL, not the init script). If `reporting.*` tables do not yet exist, the
  `report_reader` SELECT positive case will fail because the default-privilege grant has
  nothing to bind to — bring the stack fully up first.
- `data_integrity.sh` reads only; it never writes either endpoint. It does not compare
  sequence current values (BIGSERIAL) since those are not business data and reseed on
  the target.
- TLS: examples use `sslmode=require` for remote endpoints; the local container check
  does not (loopback inside Docker). RDS must never be publicly reachable — run these
  from within the VPC / a bastion.
