# Team <TODO: name>

> Scenario 2 — Cloud Migration · _"The Lift, the Shift, and the 4am Call"_
> Target cloud: **AWS** · Runs locally via `docker compose` (cloud primitives stubbed: MinIO→S3, Postgres→RDS, Redis→ElastiCache)

## Participants
- <Name> (PM / BA)
- <Name> (Architect)
- <Name> (Developer)
- <Name> (Platform / Infra)
- <Name> (Quality / Test)
- <Name> (Floater / Agentic + Deck)

## Scenario
**Scenario 2: Cloud Migration.** Contoso Financial runs three on-prem workloads — a
customer-facing web app, a nightly batch reconciliation job, and a reporting database
five teams query directly. The CFO signed the cloud contract; the CTO wants cloud-native,
not lift-and-shift; Compliance wants residency controls; SRE wants sleep. We pick the
target cloud and migration pattern and produce **cloud-ready artifacts that run locally
with production-equivalent architecture** — no live deploy.

We design for three readers: the **auditor** reads the IaC, the **CTO** reads the ADRs,
and **ops** runs the runbook at 4am.

## What We Built
<!-- A couple of paragraphs. What exists in this repo that didn't exist when you
started. What runs, what's scaffolding, what's faked. Fill this in AS YOU GO. -->
_TODO — keep this current, not last-minute._

## Challenges Attempted
| # | Challenge | Role | Status | Notes |
|---|-----------|------|--------|-------|
| 1 | The Memo | PM/BA | todo | Lift-and-shift-then-optimize vs. refactor-on-the-way-in. Pick a side. |
| 2 | The Discovery | Architect | todo | Surface the undocumented couplings. |
| 3 | The Options | Architect | todo | Scored target architectures → ADR. |
| 4 | The Container | Dev | todo | Multi-stage, non-root, healthcheck. Config-swap to cloud. |
| 5 | The Foundation | Platform | todo | IaC + PreToolUse hook blocking plaintext secrets. |
| 6 | The Proof | Quality | todo | Smoke + contract + data-integrity tests. |
| 7 | The Scorecard | Quality | todo | Eval harness for Claude's IaC, runs in CI. |
| 8 | The Undo | Stretch | todo | Per-workload, per-stage rollback sequence. |
| 9 | The Survey | Stretch (agentic) | todo | Parallel Task-subagent discovery, merged. |

## Key Decisions
Biggest calls and why. Full ADRs live in [`/decisions`](./decisions).
- _TODO_

## How to Run It
Assume the reader has Docker and nothing else.
```bash
docker compose up -d        # brings up the local cloud stand-ins
# web-app:      http://localhost:8080  (→ ECS/App Runner)
# minio (S3):   http://localhost:9001  (console)
# postgres(RDS):localhost:5432
# redis (EC):   localhost:6379
docker compose down
```
_TODO — keep these commands exact as services land._

## If We Had More Time
What we'd tackle next, in priority order. Honest about what's held together with tape.
- _TODO_

## How We Used Claude Code
What worked. What surprised us. Where it saved the most time.
- Per-workload `CLAUDE.md` files so edits in `web-app/`, `batch/`, and `infra/` get the right guidance.
- _TODO_
