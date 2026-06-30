# Team &lt;name&gt;

> **TODO (team):** fill in the team name above and the participants below. Everything else
> in this README is factual and reflects the current state of the repo.

## Participants
- &lt;Name&gt; (role(s) played today)
- &lt;Name&gt; (role(s) played today)
- &lt;Name&gt; (role(s) played today)

## Scenario
Scenario 2: Cloud Migration — *"The Lift, the Shift, and the 4am Call"*. Migrate Contoso
Financial's three on-prem workloads (web app, nightly batch reconciliation, reporting DB) to
**AWS**, producing artifacts that run locally with production-equivalent architecture. We do
not deploy live; local stand-ins map to cloud primitives (MinIO→S3, Postgres→RDS,
Redis→ElastiCache).

## What We Built
The work that exists and runs today is the **Claude Code governance layer** — the
configuration that makes the tool enforce our conventions instead of just suggesting them.
Concretely, three things that did not exist when we started:

1. **ADR-forcing.** Architectural changes cannot land undocumented. A deterministic
   `commit-msg` git hook rejects any commit touching `infra/`, `*.tf`, `docker-compose`, or a
   `Dockerfile` unless the message references an `ADR-NNNN`, stages a new ADR, or carries a
   conscious `[no-adr: reason]` opt-out. An in-session `PostToolUse` hook nudges Claude the
   moment it edits such a file without an ADR in flight, and the `/adr` skill scaffolds the
   next-numbered ADR from the diff so the easy path is also the compliant one.
2. **Docs currency.** The three files the judges read first stay honest. A `Stop` hook
   (`scripts/docs_currency.py`) checks, when a turn ends, whether code under a directory-scoped
   `CLAUDE.md` changed without that file being revised, or whether a story-relevant change (a
   new ADR, a how-to-run change, a new skill/hook) landed without touching `README.md` — and
   drives a review. It generates nothing and creates no files; the revision stays human/model
   judgment. The `/review-docs` skill is the on-demand companion.
3. **The decision record.** Four ADRs (`decisions/0001`–`0004`) capture the reasoning,
   including the principle we apply throughout: **deterministic guardrails are hooks,
   probabilistic preferences are prompts** (ADR-0003), and we enforce the *presence* of a
   decision while leaving its *quality* to review (ADR-0004).

Everything else in the repo is **scaffolding** carried from the brief: `docker-compose.yml`
(the local stand-in topology, runnable for the backends), per-area `CLAUDE.md` guidance,
templates for the memo/discovery/tests, and `presentation.html`. The cloud services
themselves are **faked** by local stand-ins (MinIO/Postgres/Redis).

## Challenges Attempted
The standout work is cross-cutting Claude Code configuration rather than a single numbered
challenge — it stresses the cert domains (config, context management, tool design) and feeds
Challenges 1, 3, and 5.

| # | Challenge | Status | Notes |
|---|---|---|---|
| 1 | The Memo | scaffold | Template in `docs/01-memo.md`; the lift-vs-refactor case is not yet argued. |
| 2 | The Discovery | scaffold | Template in `docs/02-discovery.md`; the undocumented couplings are not yet filled in. |
| 3 | The Options | partial | Target cloud + service mapping chosen and recorded (ADR-0002, AWS); candidate architectures not yet scored. |
| 4 | The Container | not started | No `Dockerfile` / web-app build context yet. |
| 5 | The Foundation | partial | The hook-vs-prompt discipline for secrets is recorded (ADR-0003) and the ADR/docs guardrails are built; the Terraform and the *secrets* `PreToolUse` hook itself are not yet written. |
| 6 | The Proof | scaffold | `tests/README.md` defines the plan (smoke / contract / data-integrity, anti-theatre assertions); no assertions implemented. |
| 7 | The Scorecard | not started | |
| 8 | The Undo | not started | |
| 9 | The Survey | not started | |

## Key Decisions
The biggest calls, with the full reasoning in `/decisions`:
- **[ADR-0002](decisions/0002-target-cloud-aws.md) — Target cloud is AWS.** Chosen for the
  cleanest local↔cloud mapping (MinIO→S3, Postgres→RDS, Redis→ElastiCache).
- **[ADR-0003](decisions/0003-secrets-hook-vs-prompt.md) — A hook blocks, a prompt prefers.**
  Plaintext secrets in IaC are blocked deterministically by a hook; "prefer the secret
  manager" is a prompt, because one is unambiguous and the other needs judgment.
- **[ADR-0004](decisions/0004-forcing-adrs-and-claude-md-maintenance.md) — Forcing ADRs and
  maintaining docs.** Enforce the *presence* of decisions and *currency* of docs by gate;
  leave *quality* to prompt and review. No generated doc content, no auto-created files.

## How to Run It
Assumes Docker and Python 3. From the repo root:

```bash
# 1. Activate the team git hooks once per clone (sets core.hooksPath).
bash scripts/setup.sh

# 2. Provide local secrets (git-ignored). In AWS these become Secrets Manager / SSM refs.
cp .env.example .env   # then edit the change-me values

# 3. Bring up the cloud stand-ins (these work today):
docker compose up -d postgres-rds redis-elasticache minio-s3
#   postgres-rds       -> Amazon RDS        :5432
#   redis-elasticache  -> Amazon ElastiCache:6379
#   minio-s3           -> Amazon S3          :9000 (console :9001)
```

> **Honest caveat:** `docker compose up` for the **web-app** service is not runnable yet — it
> has a `build: ./web-app` context but no `Dockerfile` (Challenge 4 is not started). Bring up
> only the three backend stand-ins as shown above.

Try the governance layer:
```bash
# The ADR gate in action — this is rejected (architectural change, no ADR referenced):
echo 'resource "x" "y" {}' > infra/demo.tf && git add infra/demo.tf
git commit -m "add terraform"          # -> blocked by .githooks/commit-msg
git restore --staged infra/demo.tf && rm infra/demo.tf

# Scaffold a decision:
#   /adr "Web app runs on ECS Fargate, not EKS"
```

## If We Had More Time
In priority order, honest about what is held together with tape:
1. **The secrets `PreToolUse` hook (Challenge 5).** ADR-0003 and `CLAUDE.md` describe a hook
   that blocks plaintext secrets in IaC — it is specified but **not yet implemented**. This is
   the highest-value gap because the docs currently imply it exists.
2. **The Container (Challenge 4)** so `docker compose up` runs end-to-end: multi-stage build,
   non-root user, `/healthz` matching the compose healthcheck.
3. **The Foundation (Challenge 5) Terraform** for the AWS target, with the tags / least-privilege
   IAM / remote-state story the auditor expects.
4. **The Discovery (Challenge 2)** filled with the real couplings, then **The Proof
   (Challenge 6)** asserting them — so the validation suite isn't theatre.
5. **The Scorecard (Challenge 7)** and **The Survey (Challenge 9)** as the agentic stretch.

## How We Used Claude Code
We treated the scenario as a Claude Code configuration exercise, not just a coding task:
- **Hooks as guardrails, not vibes.** We encoded "every architectural change gets an ADR" and
  "the read-first docs stay current" as deterministic hooks (`commit-msg`, `PostToolUse`,
  `Stop`) rather than hoping a prompt would hold. Where judgment was genuinely needed (is this
  change meaningful? is this guidance correct?) we kept it a prompt — the explicit line drawn
  in ADR-0003 and ADR-0004.
- **Skills for the easy path.** `/adr` and `/review-docs` make the compliant action the
  low-friction one, so the gates point somewhere instead of just blocking.
- **Dogfooding paid off.** While building the ADR nudge we triggered it on our own
  `infra/CLAUDE.md` edit — a false positive — and tightened the matcher to exclude `*.md`
  docs. The guardrail caught its own bug.
