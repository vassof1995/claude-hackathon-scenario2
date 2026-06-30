# CLAUDE.md — Project Conventions (Scenario 2: Cloud Migration)

This is the **project-level** guidance, shared by the whole team and committed to VCS.
The repo has two halves (see **ADR-0005**): the runnable on-prem **source** system under
`legacy/` (its guidance is `legacy/README.md`), and the **AWS target** stand-in at the root
(`docker-compose.yml`, `infra/`). IaC guidance lives in `infra/CLAUDE.md`. Per-workload
*target* `CLAUDE.md` files are added when each workload is actually migrated — not before, so
we don't point at files that don't exist. Personal preferences belong in your own
`~/.claude/CLAUDE.md`, not here.

## Mission
Migrate Contoso Financial's three on-prem workloads to **AWS**, producing artifacts that
**run locally with production-equivalent architecture** — we do NOT deploy live.
Design every artifact for three readers: the auditor (IaC), the CTO (ADRs), ops (runbook).

## The three workloads
They live today under `legacy/` (Spring Boot + Vue + one Postgres); the arrow is the target shape.
1. **web app** (`legacy/web-app/`) — Vue/nginx frontend + Spring Boot API → containerized, fronted by ALB, on ECS/App Runner.
2. **batch** (`legacy/batch/`) — nightly Spring Boot reconciliation job → scheduled task (EventBridge + ECS task / Batch).
3. **reporting DB** (`legacy/` Postgres `reporting` schema) — five teams query it directly → RDS Postgres + read replica.

## Local ↔ cloud mapping (name things accordingly)
Only Postgres is a datastore actually migrated from the source. Redis and S3 are deliberate
**target additions** (the legacy system has neither) — name and justify them as such (ADR-0005).
| Target stand-in (docker compose) | Stands in for | In the source? |
|----------------------------------|---------------|----------------|
| `postgres-rds`                   | Amazon RDS        | yes — migrated |
| `redis-elasticache`              | Amazon ElastiCache | no — target addition |
| `minio-s3`                       | Amazon S3          | no — target addition |

## Conventions
- **IaC = Terraform.** Idempotent, no hardcoded secrets, remote state (never check state in).
  Prefer **AWS Secrets Manager / SSM Parameter Store** for any secret — see ADR-0002.
- **No plaintext secrets, ever.** The intent is a `PreToolUse` hook that deterministically
  blocks edits writing a plaintext secret into IaC — the hard guardrail to this soft prompt
  (why one is a hook and one a prompt: ADR-0003). **Status: specified, not yet implemented**
  (see README "If We Had More Time"). The guardrails that *are* live today: a `PostToolUse`
  ADR nudge and a `Stop` docs-currency check (ADR-0004) — both in `.claude/settings.json`.
- **ADRs** for every meaningful call, in `/decisions`, numbered `NNNN-title.md`.
- **Commit often, small, and descriptively.** The commit history is judged — it's the journey.
- **Plan Mode** for anything reversible-dangerous (cutover steps, rollback). Direct execution
  for the safe paths.
- **No client or internal data.** Everything here is generated/fake Contoso data and must be
  safe to share publicly.

## Definition of "migration succeeded"
The validation suite in `tests/` is the source of truth: smoke + contract + data-integrity
checks. At least a few assertions must catch the undocumented couplings found in Discovery —
so the suite isn't theatre.

## Branching
One branch per challenge (`memo`, `discovery`, `options`, `container`, `iac`, `tests`,
`scorecard`, `survey`). PR into `main`. Keep `main` green.
