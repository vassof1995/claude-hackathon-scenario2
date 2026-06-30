# CLAUDE.md — Project Conventions (Scenario 2: Cloud Migration)

Project-level guidance, shared by the team and committed to VCS. **Read this first.**
The repo has two halves (**ADR-0005**): the runnable on-prem **source** under `legacy/`
(its own guidance is `legacy/README.md`), and the **AWS target** at the root
(`docker-compose.yml`, `infra/`). IaC-specific rules live in `infra/CLAUDE.md`. Personal
preferences go in your own `~/.claude/CLAUDE.md`, not here.

## Mission
Migrate Contoso Financial's three on-prem workloads to **AWS**, producing artifacts that
**run locally with production-equivalent architecture** — we do **NOT** deploy live. Terraform
must *read right* for an auditor even though it's never `apply`-ed. Design every artifact for
three readers: the **auditor** (IaC), the **CTO** (ADRs), **ops** (runbook).

## Migration status — start here
**All three workloads are migrated end-to-end.** Remaining work is the secrets hook, polish, and
the stretch challenges (see "What's left").

| Workload | Source | Target pattern (plan §) | Status | Artifacts |
|----------|--------|-------------------------|--------|-----------|
| **batch** | `legacy/batch/` | EventBridge → run-to-exit ECS task (§3, ADR-0006) | ✅ done | `infra/modules/batch/` + `infra/envs/prod/`, `tests/batch_migration/`, `docs/runbook-batch.md`, CI |
| **reporting-db** | `legacy/` Postgres `reporting` | RDS Multi-AZ + read replica (§4, ADR-0007) | ✅ done | `infra/terraform/reporting-db.tf`, `tests/reporting-db/`, `docs/runbooks/reporting-db-cutover.md` |
| **web-app** | `legacy/web-app/` (Vue/nginx + Spring API) | frontend→S3/CloudFront, API→ECS/ALB (§2, ADR-0008) | ✅ done | `infra/modules/{network,ecr,ecs-web-api,s3-cloudfront}/` + `infra/envs/prod/web-app.tf`, `tests/web-app/`, `web-app/CLAUDE.md` |

The single source of truth for *what to build* is **`docs/03-migration-plan.md`** (per-workload
target shape, steps, and the coupling register) + **`docs/02-discovery.md`** (the 8 real
couplings, read off the code). Don't re-derive these — extend them.

### What's left (priority order)
1. **The secrets `PreToolUse` hook** (ADR-0003) — specified, not built. Highest-value gap.
2. **Fold `reporting-db` into the canonical layout** (`infra/modules/reporting-db/`) — see IaC layout.
3. **Stretch challenges** — The Memo (`docs/01-memo.md` still a stub), Scorecard, Survey.

## Repo map (where things live)
- `legacy/` — the on-prem system; **immutable source**, do not edit it to make the target work.
- `docs/` — `01-memo` (stub), `02-discovery` (done), `03-migration-plan` (done), per-workload
  discovery/worklog, and `runbook-batch.md` + `runbooks/` (ops cutover/rollback).
- `decisions/` — ADRs `NNNN-title.md`, currently **0001–0008** (next is **0009**).
- `infra/` — Terraform target (never applied). See **IaC layout** below.
- `<workload>/CLAUDE.md` — per-workload *target* guidance, added when a workload is migrated
  (e.g. `web-app/CLAUDE.md`, `infra/CLAUDE.md`).
- `tests/<workload>/` — bash + `psql`/`curl` validation (The Proof); asserts Discovery couplings.
- `.claude/` — `settings.json` (hooks), `hooks/adr_guard.py`, `skills/adr`, `skills/review-docs`.
- `scripts/` — `setup.sh` (wires git hooks — run once per clone), `new_adr.sh`, `docs_currency.py`.

## Local ↔ cloud mapping (name things accordingly)
Only Postgres is migrated from the source. Redis and S3 are deliberate **target additions** (the
legacy system has neither) — name and justify them as such (ADR-0005).
| Target stand-in (docker compose) | Stands in for | In the source? |
|----------------------------------|---------------|----------------|
| `postgres-rds`                   | Amazon RDS         | yes — migrated |
| `redis-elasticache`              | Amazon ElastiCache | no — target addition |
| `minio-s3`                       | Amazon S3          | no — target addition |

## The migration recipe (the established pattern)
All three workloads followed this; use it for refactors, optimizations, or any new slice. The
**batch** and **web-app** slices are the reference implementations.
1. **Discovery** — confirm the couplings from `docs/02-discovery.md` that touch this workload;
   add a per-workload deep-dive doc if useful.
2. **ADR** — record the pattern decision. Run `/adr "<title>"` (scaffolds the next number) or
   `scripts/new_adr.sh`. Reference the plan section it implements.
3. **IaC** — add a reusable module + wire it in an env (see layout below). No plaintext secrets;
   tags on everything; least-privilege IAM; private subnets; declared remote state.
4. **The Proof** — `tests/<workload>/`: assert the couplings this workload owns (anti-theatre).
5. **Runbook** — exact cutover + rollback sequence + a "4am failure modes" table.
6. **Per-workload `<workload>/CLAUDE.md`** — target guidance for editors of that workload.
7. **Update `README.md` + this file's status table.** README is judged and read first; keep it true.

## IaC layout
**Canonical layout** (use this for all work): reusable `infra/modules/<name>/` consumed by
`infra/envs/<env>/` (e.g. `prod`). **batch** and **web-app** follow it. Modules today:
`network` (shared VPC/subnets/SGs), `batch`, `ecr`, `ecs-web-api`, `s3-cloudfront`; the prod env
wires them in `infra/envs/prod/*.tf`. Reuse the shared `network` module — don't re-declare a VPC.
> Known inconsistency / tech-debt: **reporting-db** is a single flat `infra/terraform/reporting-db.tf`
> (authored on a stale branch before the convention settled). Fold it into
> `infra/modules/reporting-db/` + `infra/envs/prod/` — tracked in "What's left" and README.

## Conventions
- **IaC = Terraform.** Idempotent, no hardcoded secrets, remote state via S3 + DynamoDB lock
  (declared, never checked in; `*.tfstate` is git-ignored). Validate offline:
  `terraform init -backend=false && terraform validate`. Run `terraform fmt` before committing —
  CI runs `fmt -check -recursive` over `infra/`, so an unformatted file turns `main` red.
- **No plaintext secrets, ever.** Secrets are **Secrets Manager / SSM references**, never literals
  (ADR-0003). Intent: a `PreToolUse` hook that deterministically blocks such edits — the hard
  guardrail to this soft prompt. **Status: specified, not yet implemented** (highest-value gap;
  see README). Live guardrails today: a `PostToolUse` ADR nudge + a `Stop` docs-currency check
  (ADR-0004), in `.claude/settings.json`.
- **ADRs** for every meaningful call, in `decisions/`, numbered `NNNN-title.md`. The
  **`commit-msg` git hook blocks** any commit touching architectural files (`infra/`, `*.tf`,
  Dockerfile, `docker-compose.yml`) unless the message references an `ADR-NNNN`, stages a new
  `decisions/NNNN-*.md`, or opts out with `[no-adr: <reason>]`. **Run `bash scripts/setup.sh` once
  per clone** to activate it (it sets `core.hooksPath`). Bypass only in emergencies: `--no-verify`.
- **Commit often, small, descriptive.** The history is judged — it's the journey.
- **Plan Mode** for reversible-dangerous work (cutover, rollback). Direct execution for safe paths.
- **No client or internal data.** Everything is generated/fake Contoso data, safe to share publicly.

## Definition of "migration succeeded"
`tests/` is the source of truth: smoke + contract + data-integrity checks. At least a few
assertions must catch the **undocumented couplings** from Discovery (e.g. the `report_reader`
least-privilege boundary, batch's cross-schema read, idempotency) — so the suite isn't theatre.

## Branching & teamwork
- **One branch per workload/challenge** (e.g. `feature/<workload>-migration`); PR into `main`.
  Keep `main` green.
- **Rebase your branch on `main` before opening/merging a PR.** Lesson learned: a long-lived
  branch that forked early will, on a plain merge, silently **revert** shared files (README,
  CLAUDE.md, ADRs) and **delete** newer work. If a branch is stale and its contribution is purely
  additive (new files in its own paths), **cherry-pick those files onto `main`** instead of merging.
- New workload artifacts go in **workload-specific paths** (`infra/modules/<wl>/`, `tests/<wl>/`,
  `docs/runbooks/<wl>-*.md`) so parallel branches don't collide.

## Quick commands
```bash
bash scripts/setup.sh                        # activate git hooks (once per clone)
cd legacy && cp .env.example .env && docker compose up --build -d   # run the source stack
tests/batch_migration/validate.sh --down     # batch Proof (idempotency + grant matrix)
tests/reporting-db/authz_boundaries.sh       # reporting-db authz Proof (least-privilege)
tests/web-app/smoke_test.sh                  # web-app Proof (frontend → /api → DB)
terraform -chdir=infra/envs/prod init -backend=false && terraform -chdir=infra/envs/prod validate
```
