# CLAUDE.md — batch workload

Nightly reconciliation job. Target: scheduled container task (**EventBridge Scheduler + ECS
task**, or AWS Batch) — not a long-running service.

## Guidance for edits here
- The job is **idempotent and re-runnable**: a failed or half-run night must be safe to retry
  without double-posting reconciliations.
- Reads/writes Postgres (→ RDS) and object storage (→ S3). Large intermediate files go to
  object storage, **not** a shared local filesystem mount (the shared mount is a Discovery
  gremlin — design it out, don't preserve it).
- Surface a clear exit code and structured log line on success/failure so the scheduler and
  the validation suite can assert on it.
- No interactive prompts — this runs unattended at night.
