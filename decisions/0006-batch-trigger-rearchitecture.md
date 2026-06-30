# ADR-0006: Batch migration — re-architect the trigger (EventBridge Scheduler → run-to-exit ECS task)

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Team The 4am Club

## Context
The nightly reconciliation (`legacy/batch/`) is a Spring Boot service that runs **24/7** only
to fire `@Scheduled(cron = "0 0 2 * * *")`. The reconciliation *logic* is sound and idempotent
per business date; the *hosting model* is wasteful (a daemon paid for 24h to do minutes of
work) and the schedule is invisible to ops (buried in code, not infrastructure).

[`docs/03-migration-plan.md` §3](../docs/03-migration-plan.md) chose **re-architect the trigger,
not the logic**, and this ADR records the implementation decision for that workload. It is
constrained by:
- **ADR-0005** — `legacy/` is the immutable migration *source*; target artifacts live on the
  target side (`infra/`, root stand-in). We do **not** edit `legacy/batch/`.
- **ADR-0003** — secrets are Secrets Manager *references*, never literals, in IaC.
- **ADR-0002** — target cloud is AWS.

## Decision
Migrate the batch by **moving the schedule out of the container and into infrastructure**:

- **EventBridge Scheduler** holds the cron (`0 0 2 * * *`, the *same* schedule) and invokes
  **`ecs:RunTask`** for a **run-to-exit** Fargate task: the container reconciles yesterday's
  business date and exits. Compute is billed per run (~minutes/day), not 24h/day.
- The **same reconciliation logic** is reused. The target image runs with
  `SPRING_PROFILES_ACTIVE=cloud`, a profile that **disables the `@Scheduled` bean** (the schedule
  now lives in EventBridge) and runs the reconciliation once on start, then exits. Producing
  that image is a target-build concern (a thin cloud-profile/run-once entrypoint over the legacy
  jar) — **not** a change to `legacy/`. Until that image exists, the local stand-in for "the
  scheduler fired" is the legacy app's existing `POST /run` endpoint (plan §3), whose behaviour
  is identical (one idempotent reconciliation for a date).
- A **second EventBridge schedule** (disabled by default) plus ad-hoc `ecs:RunTask` preserve the
  manual 4am re-run path.
- **Least-privilege IAM:** the task role may read only the `batch_user` secret and write only its
  CloudWatch log group; the scheduler role may only `RunTask`/`PassRole` for this task def.
- **Secrets** (`BATCH_DB_PASSWORD`, datasource URL/user) are injected as ECS `secrets` from
  Secrets Manager ARNs — no literals in the task definition (ADR-0003).

## Consequences
- Cost: 24h/day daemon → minutes/day task. The schedule is now ops-visible and changeable in
  Terraform without a redeploy (coupling **C5** addressed).
- Coupling **C3** (batch needs the `app` schema to exist first): there is no ECS `depends_on`.
  The task **fails fast** on an empty/absent `app` schema and EventBridge retries; cutover order
  (plan §7) provisions web-api (Flyway owns `app`) before the first batch run. The validation
  suite asserts batch fails cleanly rather than writing garbage.
- **Idempotency** must survive the move: the task runs the same `DELETE`-then-`INSERT` per
  business date. Asserted by The Proof (`tests/batch_migration/`).
- The in-process `@Scheduled` timer is intentionally lost — that is the point; the schedule is
  externalised. The cloud profile disables the bean so it cannot double-fire.
- We do **not** apply this Terraform to a live account (scenario rule); it must *read right* for
  the auditor: tagged, least-privilege, secret references, remote-state backend declared.

## Alternatives considered
- **Lift-and-shift the daemon onto ECS as an always-on service** — rejected; keeps the 24/7
  cost and the invisible in-code schedule. The whole point of touching batch is to fix exactly
  that, cheaply.
- **AWS Batch instead of EventBridge → ECS RunTask** — viable; rejected for this size as
  heavier than needed. One scheduled run-to-exit Fargate task is the simplest thing that works;
  AWS Batch earns its keep with queues/array jobs we don't have.
- **Step Functions to orchestrate** — rejected; a single idempotent job needs no state machine.
- **Rewrite the reconciliation as Lambda** — rejected; the logic is JVM/JDBC and batch-shaped,
  not a 15-minute function; re-architecting the trigger gets the cloud-native win without a
  risky logic rewrite (plan §0 stance: cloud-native where the workload invites it).
