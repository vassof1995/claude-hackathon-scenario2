# Runbook — reporting-db Cutover to Amazon RDS for PostgreSQL

Migrate Contoso's on-prem `contoso` Postgres (schemas `app` + `reporting`, roles
`app_user` / `batch_user` / `report_reader`) onto Amazon RDS for PostgreSQL Multi-AZ in
`eu-central-1`, add a read replica for the five reporting teams, validate, and (if needed)
roll back to on-prem.

Strategy: **targeted refactor**. Roles, schemas, and least-privilege grants are preserved
**exactly** as in `legacy/reporting-db/init/01-roles-and-schemas.sh`. Schema split (app vs
reporting) is **DEFERRED** — `batch_user` needs cross-schema access, so both schemas stay
on one primary instance (per `decisions/0002-target-cloud-aws.md`).

## Scope of integrity
- `app` schema (`customers`, `accounts`, `transactions`) = **system of record. CRITICAL.**
  Integrity here is non-negotiable; verified row-for-row.
- `reporting` schema (`daily_balances`, `reconciliation_results`, `discrepancies`) =
  **DERIVED + regenerable** by re-running batch's `ReconciliationService` per business date
  (idempotent DELETE+reinsert per date). We migrate it for speed, but it is **not** the
  integrity anchor — it can be rebuilt.

## Hard ordering rules (encoded throughout)
1. On-prem Postgres goes **READ-ONLY** for the entire cutover window.
2. App writers (web-api, batch) stay **FROZEN** until validation passes.
3. After restore, **reporting objects must be owned by `batch_user`** so the existing
   `ALTER DEFAULT PRIVILEGES FOR ROLE batch_user ... GRANT SELECT TO report_reader` keeps
   working. If ownership ends up wrong, **re-grant SELECT to `report_reader` explicitly**
   (step 6 asserts this; step 3.6 fixes it).

## Conventions / guardrails
- No plaintext secrets anywhere. All passwords come from **AWS Secrets Manager**; commands
  read them at runtime via `aws secretsmanager get-secret-value`. Never echo them, never
  paste literals, never write them to tracked files.
- DB is **never** publicly accessible. SG ingress on 5432 only from the app-tier SG and an
  approved analysts CIDR (a **variable**, never `0.0.0.0/0`).
- Least-privilege IAM; tag everything; encryption at rest + in transit.

## Assumptions / gaps (MARKED)
- **[ASSUMPTION]** Placeholders below — `<ACCOUNT_ID>`, `<VPC_ID>`, `subnet-<az-a/c>`,
  `<APP_TIER_SG_ID>`, `<KMS_KEY_ID>`, `<ANALYSTS_CIDR>` — are resolved from existing infra /
  Terraform variables / SSM at run time. None are hardcoded here.
- **[ASSUMPTION]** Engine pinned to PostgreSQL 16 to match `postgres:16-alpine` on-prem.
- **[GAP]** `infra/terraform/` does not exist yet. This runbook uses AWS CLI for an
  operator-driven cutover; the equivalent Terraform (idempotent, S3+DynamoDB remote state,
  Secrets Manager refs) is a separate IaC artifact and should be the durable form.
- **[ASSUMPTION]** Secrets Manager already holds the three role passwords. If not, create
  them first (step 0). Secret names used below:
  `contoso/rds/app_user`, `contoso/rds/batch_user`, `contoso/rds/report_reader`,
  plus the RDS master secret managed by RDS.
- **[ASSUMPTION]** `psql` v16 client and `aws` CLI v2 are installed on the operator host,
  which can reach RDS over the private network (bastion/VPN/SSM port-forward). The DB is not
  public, so the operator host must be inside the VPC routing domain.

---

## PRE-FLIGHT CHECKLIST (complete BEFORE the window)

- [ ] Change ticket approved; maintenance window scheduled and communicated to web-api,
      batch, and all five reporting teams.
- [ ] Operator host has private-network reachability to RDS (bastion / VPN / SSM
      port-forward verified); `psql` 16 + `aws` CLI v2 present; AWS creds via role, not file.
- [ ] Secrets Manager secrets exist and are readable:
      `contoso/rds/app_user`, `contoso/rds/batch_user`, `contoso/rds/report_reader`.
- [ ] Resolved (not hardcoded): `<VPC_ID>`, two private `subnet-*` IDs in distinct AZs,
      `<APP_TIER_SG_ID>`, `<KMS_KEY_ID>`, `<ANALYSTS_CIDR>` (CIDR, not `0.0.0.0/0`).
- [ ] On-prem `contoso` is healthy; recent backup taken; `app.customers/accounts/transactions`
      row counts captured for the integrity diff.
- [ ] Disk/space headroom on operator host for the dump.
- [ ] Connection-string change for web-api / batch / teams prepared but NOT yet applied.
- [ ] Rollback connection strings (on-prem) preserved and tested-reachable.
- [ ] tests/reporting-db/ authz + data-integrity scripts present and runnable.

---

## STEP 0 — Secrets in Secrets Manager (one-time, if missing) [ASSUMPTION]

Create role-password secrets ONLY if they do not exist. Generate the password with
`aws secretsmanager get-random-password` (or migrate the values from on-prem `.env`); never
type a literal. Example (run once per role, value never printed):

```bash
aws secretsmanager create-secret \
  --name contoso/rds/report_reader \
  --description "report_reader DB password (reporting-db)" \
  --secret-string "$(aws secretsmanager get-random-password \
      --exclude-punctuation --password-length 32 \
      --query RandomPassword --output text)" \
  --tags Key=app,Value=reporting-db Key=role,Value=report_reader
```

Repeat for `contoso/rds/app_user` and `contoso/rds/batch_user`.

---

## STEP 1 — Provision RDS Multi-AZ primary + networking controls

All commands are idempotent-by-intent: if a resource exists, skip its create.

1.1 **DB subnet group** across two private subnets in distinct AZs (no public subnets):
```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name reporting-db-rds-subnets \
  --db-subnet-group-description "private subnets for reporting-db RDS" \
  --subnet-ids subnet-<az-a> subnet-<az-c> \
  --tags Key=app,Value=reporting-db
```

1.2 **Security group** for the DB (no inline ingress yet):
```bash
DB_SG_ID=$(aws ec2 create-security-group \
  --group-name reporting-db-rds-sg \
  --description "RDS reporting-db: 5432 from app-tier SG + analysts CIDR only" \
  --vpc-id <VPC_ID> \
  --query GroupId --output text)
```

1.3 **Ingress 5432 from the app-tier SG only** (web-api + batch tier):
```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$DB_SG_ID" --protocol tcp --port 5432 \
  --source-group <APP_TIER_SG_ID>
```

1.4 **Ingress 5432 from the approved analysts CIDR** (variable, NEVER `0.0.0.0/0`):
```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$DB_SG_ID" --protocol tcp --port 5432 \
  --cidr <ANALYSTS_CIDR>
```
> GATE: if `<ANALYSTS_CIDR>` is `0.0.0.0/0` or empty, STOP — violates the no-public-DB rule.

1.5 **Parameter group** (PostgreSQL 16; require TLS in transit):
```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name reporting-db-pg16 \
  --db-parameter-group-family postgres16 \
  --description "reporting-db pg16 params" \
  --tags Key=app,Value=reporting-db

aws rds modify-db-parameter-group \
  --db-parameter-group-name reporting-db-pg16 \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=pending-reboot"
```

1.6 **Create the Multi-AZ primary** — private, encrypted at rest (KMS), RDS-managed master
secret (no literal password), in the subnet group + SG above:
```bash
aws rds create-db-instance \
  --db-instance-identifier reporting-db-rds-primary \
  --engine postgres --engine-version 16 \
  --db-instance-class db.m6g.large \
  --allocated-storage 100 --storage-type gp3 \
  --multi-az \
  --db-name contoso \
  --master-username contoso \
  --manage-master-user-password \
  --storage-encrypted --kms-key-id <KMS_KEY_ID> \
  --db-subnet-group-name reporting-db-rds-subnets \
  --vpc-security-group-ids "$DB_SG_ID" \
  --db-parameter-group-name reporting-db-pg16 \
  --no-publicly-accessible \
  --backup-retention-period 7 \
  --tags Key=app,Value=reporting-db Key=tier,Value=primary
```
> `--no-publicly-accessible` and the private subnet group are both required. `contoso` is the
> superuser, matching on-prem `POSTGRES_USER=contoso`.

1.7 Wait for availability and capture the endpoint:
```bash
aws rds wait db-instance-available --db-instance-identifier reporting-db-rds-primary
PRIMARY_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier reporting-db-rds-primary \
  --query 'DBInstances[0].Endpoint.Address' --output text)
```

---

## STEP 2 — Port roles + grants onto RDS (passwords from Secrets Manager)

Connect to the primary as the master user `contoso` (the RDS-managed master secret supplies
its password — fetch it; do not print it). Inject the three role passwords from Secrets
Manager as psql variables so **no literal ever appears**.

2.1 Fetch passwords into shell vars (not logged, not committed):
```bash
APP_PW=$(aws secretsmanager get-secret-value     --secret-id contoso/rds/app_user      --query SecretString --output text)
BATCH_PW=$(aws secretsmanager get-secret-value    --secret-id contoso/rds/batch_user    --query SecretString --output text)
REPORT_PW=$(aws secretsmanager get-secret-value   --secret-id contoso/rds/report_reader --query SecretString --output text)
MASTER_PW=$(aws secretsmanager get-secret-value \
  --secret-id "$(aws rds describe-db-instances --db-instance-identifier reporting-db-rds-primary \
      --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)" \
  --query SecretString --output text | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')
```

2.2 Apply roles, schemas, and the **exact** least-privilege grants from
`01-roles-and-schemas.sh` (only difference: passwords are psql variables, not literals):
```bash
PGPASSWORD="$MASTER_PW" psql "host=$PRIMARY_HOST dbname=contoso user=contoso sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -v app_pw="$APP_PW" -v batch_pw="$BATCH_PW" -v report_pw="$REPORT_PW" <<'EOSQL'
  CREATE ROLE app_user      LOGIN PASSWORD :'app_pw';
  CREATE ROLE batch_user    LOGIN PASSWORD :'batch_pw';
  CREATE ROLE report_reader LOGIN PASSWORD :'report_pw';

  CREATE SCHEMA app       AUTHORIZATION app_user;
  CREATE SCHEMA reporting AUTHORIZATION batch_user;

  -- batch reads the app schema to reconcile it
  GRANT USAGE ON SCHEMA app TO batch_user;
  ALTER DEFAULT PRIVILEGES FOR ROLE app_user IN SCHEMA app
      GRANT SELECT ON TABLES TO batch_user;

  -- the five teams: read-only on reporting, nothing else
  GRANT USAGE ON SCHEMA reporting TO report_reader;
  ALTER DEFAULT PRIVILEGES FOR ROLE batch_user IN SCHEMA reporting
      GRANT SELECT ON TABLES TO report_reader;
EOSQL
```
> The `ALTER DEFAULT PRIVILEGES FOR ROLE batch_user IN SCHEMA reporting ... TO report_reader`
> is the critical coupling: it only auto-applies to tables **created/owned by `batch_user`**.
> Step 3.6 guarantees that ownership; step 6 asserts the resulting SELECT works.
> `report_reader` gets NO access to `app` and NO writes anywhere — preserved exactly.

---

## STEP 3 — Cutover window: READ-ONLY source, dump, restore

> WINDOW BEGINS. On-prem goes read-only; web-api and batch are FROZEN.

3.1 **Freeze app writers**: stop web-api and batch (scale to 0 / stop containers). Confirm no
active write connections to on-prem.

3.2 **Put on-prem Postgres READ-ONLY** (blocks stray writes for the whole window):
```bash
# on the on-prem superuser connection (contoso):
psql "$ONPREM_CONN" -c "ALTER DATABASE contoso SET default_transaction_read_only = on;"
# new sessions are read-only; verify no lingering writers before continuing.
```

3.3 Capture source row counts for the integrity gate (app schema is the anchor):
```bash
psql "$ONPREM_CONN" -At -c \
"SELECT 'customers',count(*) FROM app.customers
 UNION ALL SELECT 'accounts',count(*) FROM app.accounts
 UNION ALL SELECT 'transactions',count(*) FROM app.transactions;" > /tmp/src_counts.txt
```

3.4 **pg_dump** — dump schema data only (roles + schemas/owners already created in step 2).
Dump `app` (critical) and `reporting` (convenience; regenerable) data:
```bash
pg_dump "$ONPREM_CONN" \
  --format=custom --no-owner --no-privileges \
  --schema=app --schema=reporting \
  --file=/tmp/contoso_cutover.dump
```
> `--no-owner --no-privileges`: we restore objects then explicitly set ownership in 3.6, so
> the RDS roles/grants from step 2 govern access — not the dump's privilege lines.

3.5 **Restore into RDS** as the master user. Restore `app` first (the integrity-critical
path); `reporting` second (regenerable):
```bash
PGPASSWORD="$MASTER_PW" pg_restore \
  --host="$PRIMARY_HOST" --username=contoso --dbname=contoso \
  --no-owner --no-privileges --exit-on-error \
  /tmp/contoso_cutover.dump
```

3.6 **Fix ownership so the default-privileges coupling holds** (HARD RULE). All `app` objects
owned by `app_user`; all `reporting` objects owned by `batch_user` — otherwise
`report_reader` loses SELECT:
```bash
PGPASSWORD="$MASTER_PW" psql "host=$PRIMARY_HOST dbname=contoso user=contoso sslmode=require" \
  -v ON_ERROR_STOP=1 <<'EOSQL'
  -- app schema owned by app_user
  DO $$ DECLARE r record; BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='app' LOOP
      EXECUTE format('ALTER TABLE app.%I OWNER TO app_user', r.tablename);
    END LOOP;
  END $$;
  -- reporting schema owned by batch_user (keeps report_reader SELECT via ALTER DEFAULT PRIVILEGES)
  DO $$ DECLARE r record; BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='reporting' LOOP
      EXECUTE format('ALTER TABLE reporting.%I OWNER TO batch_user', r.tablename);
    END LOOP;
  END $$;

  -- Belt-and-suspenders: ALTER DEFAULT PRIVILEGES only covers FUTURE tables. Restored
  -- tables already exist, so re-grant SELECT explicitly to be certain report_reader reads them.
  GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO report_reader;
  GRANT SELECT ON ALL TABLES IN SCHEMA app       TO batch_user;
EOSQL
```
> If `reporting` is migrated empty (chose to regenerate instead), batch must run as
> `batch_user` so freshly created tables inherit `report_reader` SELECT via default privileges.

---

## STEP 4 — Create the read replica (for the five reporting teams)

```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier reporting-db-rds-replica \
  --source-db-instance-identifier reporting-db-rds-primary \
  --db-instance-class db.m6g.large \
  --no-publicly-accessible \
  --vpc-security-group-ids "$DB_SG_ID" \
  --db-subnet-group-name reporting-db-rds-subnets \
  --kms-key-id <KMS_KEY_ID> \
  --tags Key=app,Value=reporting-db Key=tier,Value=replica

aws rds wait db-instance-available --db-instance-identifier reporting-db-rds-replica
REPLICA_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier reporting-db-rds-replica \
  --query 'DBInstances[0].Endpoint.Address' --output text)
```
> Roles/grants replicate from the primary — `report_reader` exists on the replica and is
> SELECT-only on `reporting`. The replica is read-only by nature, reinforcing least privilege.

---

## STEP 5 — Update connection strings (do NOT unfreeze writers yet)

Update config (env / SSM / task definitions). **[ASSUMPTION]** connection params come from
Secrets Manager refs in each service — only the host/endpoint changes here.

| Consumer | Role | Endpoint | Schema access |
|----------|------|----------|---------------|
| web-api (system of record) | `app_user` | `$PRIMARY_HOST` (writer) | RW `app` |
| batch (reconciliation) | `batch_user` | `$PRIMARY_HOST` (writer) | RW `reporting`, RO `app` |
| Reporting teams (x5) | `report_reader` | `$REPLICA_HOST` (read replica) | RO `reporting` |

5.1 Point **web-api** at `$PRIMARY_HOST` as `app_user`.
5.2 Point **batch** at `$PRIMARY_HOST` as `batch_user`.
5.3 Point **each of the five reporting teams** at `$REPLICA_HOST` as `report_reader`
    (replacing the old direct `host:5432` on-prem connection).
> Writers stay FROZEN (not restarted) until Step 6 passes.

---

## STEP 6 — Validation (writers still frozen)

Run the suite in `tests/reporting-db/` against RDS. Validation must cover authz + data
integrity AND the default-privileges coupling.

6.1 **Data integrity (app = anchor)** — compare row counts and key constraints to
`/tmp/src_counts.txt`:
```bash
PGPASSWORD="$APP_PW" psql "host=$PRIMARY_HOST dbname=contoso user=app_user sslmode=require" -At -c \
"SELECT 'customers',count(*) FROM app.customers
 UNION ALL SELECT 'accounts',count(*) FROM app.accounts
 UNION ALL SELECT 'transactions',count(*) FROM app.transactions;" > /tmp/dst_counts.txt
diff /tmp/src_counts.txt /tmp/dst_counts.txt   # MUST be empty
```
Run `tests/reporting-db/` data-integrity scripts: assert UNIQUE (`email`, `iban`), FK
(`accounts.customer_id`, `transactions.account_id`), and `direction CHECK IN('DEBIT','CREDIT')`.

6.2 **Authz tests** (`tests/reporting-db/` authz scripts) — MUST assert all of:
- `report_reader` **CAN SELECT** `reporting.*` on the **replica** — this is the
  default-privileges coupling; if it fails, ownership in 3.6 is wrong -> re-grant or stop.
- `report_reader` **CANNOT** read `app.*` (USAGE not granted).
- `report_reader` **CANNOT** write anywhere (no INSERT/UPDATE/DELETE).
- `batch_user` **CAN SELECT** `app.*` and RW `reporting.*`.
- `app_user` RW `app.*`, no `reporting` access beyond grant.

```bash
# Key coupling assertion (against the REPLICA):
PGPASSWORD="$REPORT_PW" psql "host=$REPLICA_HOST dbname=contoso user=report_reader sslmode=require" \
  -c "SELECT count(*) FROM reporting.daily_balances;"   # MUST succeed (no permission error)
PGPASSWORD="$REPORT_PW" psql "host=$REPLICA_HOST dbname=contoso user=report_reader sslmode=require" \
  -c "SELECT count(*) FROM app.customers;"              # MUST fail: permission denied
```

6.3 **Connectivity / SG**: confirm app-tier reaches primary; analysts CIDR reaches replica;
DB not reachable publicly.

> **GO / NO-GO GATE** — proceed to unfreeze ONLY if ALL hold:
> - app row-count diff empty AND constraints intact;
> - `report_reader` SELECT on `reporting` (replica) SUCCEEDS;
> - `report_reader` denied on `app` and denied all writes;
> - batch/app role checks pass;
> - replica `Available` and lag near zero.
> If ANY fails -> **NO-GO -> Step 7 Rollback**. Do not unfreeze writers.

6.4 **On GO — unfreeze writers**: start web-api, then batch (or let EventBridge schedule it).
If `reporting` was migrated empty, run batch's `ReconciliationService` for the required
business-date range to regenerate `reporting.*` (idempotent per date). Re-run 6.2 coupling
assertion afterward.

---

## STEP 7 — Rollback (repoint to on-prem)

**Trigger conditions (any one):** app row-count/constraint mismatch; `report_reader` cannot
read `reporting`; `report_reader` can read `app` or write anywhere; replica won't reach
`Available` / unacceptable lag; app-tier cannot connect to primary; window overrun.

Because on-prem was kept READ-ONLY and writers were FROZEN, on-prem is still the untouched
source of truth — rollback is a repoint, not a data merge.

7.1 Keep web-api and batch **frozen** (they never unfroze if we're rolling back pre-GO).
7.2 **Repoint web-api** back to on-prem `host:5432` as `app_user`.
7.3 **Repoint batch** back to on-prem `host:5432` as `batch_user`.
7.4 **Repoint the five reporting teams** back to on-prem `host:5432` as `report_reader`.
7.5 **Lift on-prem read-only** so writers can resume:
```bash
psql "$ONPREM_CONN" -c "ALTER DATABASE contoso RESET default_transaction_read_only;"
```
7.6 Unfreeze on-prem writers (start web-api, then batch). Confirm writes land on on-prem.
7.7 Leave RDS primary + replica provisioned for post-mortem; do NOT delete until root cause is
known. Tear down later via a separate change.

> If rollback happens **after** writers were unfrozen against RDS (post-GO), any RDS-only
> writes must be reconciled back to on-prem before resuming on-prem writes — escalate; do not
> silently repoint. **[GAP]** This runbook freezes writers through the GO gate specifically to
> avoid that split-brain; treat post-GO rollback as an incident.

---

## Post-cutover cleanup (after a stable bake period, separate change)
- Decommission on-prem `contoso` and remove the public `5432:5432` exposure.
- Confirm replica is the only path for the five teams.
- Migrate this procedure into `infra/terraform/` (idempotent, S3+DynamoDB state, Secrets
  Manager refs) so the cloud topology is code, not CLI. **[GAP]**
