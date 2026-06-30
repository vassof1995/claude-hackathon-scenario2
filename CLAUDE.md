# CLAUDE.md — Project Conventions (Scenario 2: Cloud Migration)

This is the **project-level** guidance, shared by the whole team and committed to VCS.
Per-workload specifics live in `web-app/CLAUDE.md`, `batch/CLAUDE.md`,
`reporting-db/CLAUDE.md`, and `infra/CLAUDE.md`. Personal preferences belong in your
own `~/.claude/CLAUDE.md`, not here.

## Mission
Migrate Contoso Financial's three on-prem workloads to **AWS**, producing artifacts that
**run locally with production-equivalent architecture** — we do NOT deploy live.
Design every artifact for three readers: the auditor (IaC), the CTO (ADRs), ops (runbook).

## The three workloads
1. **web-app/** — customer-facing web application → containerized, fronted by ALB, runs on ECS/App Runner.
2. **batch/** — nightly reconciliation job → scheduled task (EventBridge + ECS task / Batch).
3. **reporting-db/** — reporting database five teams query directly → RDS Postgres + read replica.

## Local ↔ cloud mapping (name things accordingly)
| Local (docker compose) | Stands in for | Name it like |
|------------------------|---------------|--------------|
| MinIO                  | Amazon S3     | `*-s3`, bucket names |
| Postgres               | Amazon RDS    | `*-rds` |
| Redis                  | ElastiCache   | `*-elasticache` |

## Conventions
- **IaC = Terraform.** Idempotent, no hardcoded secrets, remote state (never check state in).
  Prefer **AWS Secrets Manager / SSM Parameter Store** for any secret — see ADR-0002.
- **No plaintext secrets, ever.** A `PreToolUse` hook deterministically blocks edits that
  write a plaintext secret into IaC. The hook is the hard guardrail; this prompt is the
  soft preference. (Why one is a hook and one is a prompt: ADR-0003.)
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
