# Runbook — batch cutover & rollback (ops, at 4am)

Operational steps for migrating the nightly reconciliation to AWS, per ADR-0006 and
[plan §3 / §7](03-migration-plan.md). The batch is **step 3** of the overall cutover (RDS →
web-api → **batch** → frontend → repoint teams). Exact sequence, not a diagram.

## Preconditions (do not start the batch step until these hold)
- [ ] RDS primary is up; `app` and `reporting` schemas exist; the three roles + grants are created.
- [ ] **web-api is live and healthy** — it owns the `app` schema via Flyway, so `app.transactions`
      exists and is seeded. (Coupling C3: batch reads `app`; it must exist first.)
- [ ] `BATCH_DB_PASSWORD` is in Secrets Manager; the task's execution role can read *only* it.
- [ ] The batch image (cloud profile, run-to-exit) is in ECR.
- [ ] On-prem DB writes are frozen for the cutover window (so `app` cannot drift).

## Cutover — batch
1. **Apply the batch IaC.**
   ```bash
   cd infra/envs/prod
   terraform init && terraform apply   # creates task def, EventBridge schedules, IAM, log group
   ```
   The nightly schedule is created **enabled**; the manual schedule is created **disabled**.
2. **Run once, manually, before trusting the schedule.** Do not wait for 02:00.
   ```bash
   aws ecs run-task --cluster contoso-prod \
     --task-definition contoso-prod-batch \
     --launch-type FARGATE \
     --network-configuration '{"awsvpcConfiguration":{"subnets":["subnet-…"],"securityGroups":["sg-…"],"assignPublicIp":"DISABLED"}}' \
     --overrides '{"containerOverrides":[{"name":"batch","environment":[{"name":"RECON_DATE","value":"<seeded/business date>"}]}]}'
   ```
3. **Verify the run.** Tail logs, then check output (psql as a read role against the replica):
   ```bash
   aws logs tail /ecs/contoso-prod-batch --since 10m
   psql "…report_reader@<replica>/contoso" -c \
     "SELECT business_date,count(*) FROM reporting.reconciliation_results GROUP BY 1 ORDER BY 1;"
   ```
   Expect one result row per active account and the expected discrepancies for the date.
4. **Re-run the same date once** and confirm **idempotency** — row counts must be stable, not
   doubled (the task deletes that date's rows before inserting). This is the guarantee
   `tests/batch_migration/validate.sh` checks locally.
5. **Confirm least privilege:** `report_reader` cannot read `app` or write; `batch_user` cannot
   write `app`. (Same checks as the local Proof.)
6. Leave the nightly EventBridge schedule enabled. Done.

## Rollback (batch)
Batch is the safest workload to roll back because every run is idempotent per business date —
no compensating cleanup is needed.
1. **Disable the nightly schedule** (stop the cloud trigger):
   ```bash
   aws scheduler update-schedule --name contoso-prod-batch-nightly --state DISABLED   # or: terraform apply with state=DISABLED
   ```
2. **Re-enable the on-prem cron** (`@Scheduled` daemon) on the legacy host.
3. If a partial/incorrect cloud run happened, simply **re-run that business date** (on-prem or
   cloud once re-fixed) — the `DELETE`-then-`INSERT` makes the latest run authoritative.
4. No data migration to undo: `reporting` is **regenerable** from `app` by re-running. Only
   `app`-schema integrity matters, and `app` had a single frozen writer during cutover.

## Failure modes seen at 4am
| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Task exits non-zero immediately, empty `reporting` | `app` schema not migrated yet (C3) | Confirm web-api/Flyway finished; EventBridge will retry (3×); else re-run after web-api is healthy |
| `permission denied for schema app` in logs | task connected as the wrong role / grants not ported | Verify it uses `batch_user` and the init SQL grants ran on RDS |
| Secret fetch fails on task start | execution role missing `secretsmanager:GetSecretValue` on the batch secret | Check the execution-role inline policy ARN matches the secret |
| Reconciliation runs at the wrong local time | schedule timezone unset/wrong (discovery #6) | Confirm `schedule_expression_timezone` on the schedule |
