# Team: The 4am Club

## Participants
- Polina Gubaidullina (role(s) played today)
- Luise Dose (role(s) played today)
- Phillip Nientiedt (role(s) played today)
- Arnd Kleinbeck (role(s) played today)
- Vasileios Sofroni (role(s) played today)
- Alexander Sturm (role(s) played today)

## Scenario
Scenario 2. Cloud Migration — *"The Lift, the Shift, and the 4am Call"*

Contoso Financial runs three on-prem workloads — a customer-facing web app, a
nightly batch reconciliation job, and a reporting database five teams query
directly. The CFO signed the cloud contract; the CTO wants "cloud-native, not
lift-and-shift"; compliance wants residency controls; SRE wants sleep. We pick
the target cloud (**AWS**) and the migration pattern, then produce cloud-ready
artifacts that **run locally with production-equivalent architecture** — no live
deploy. Docker Compose maps each service to a cloud primitive (**MinIO → S3,
Postgres → RDS, Redis → ElastiCache**). Everything is designed for three readers:
the auditor reads the IaC, the CTO reads the ADRs, and ops runs the runbook at 4am.

## What We Built
Two things exist and run today:

1. **The on-prem source system** (`legacy/`) — the production-equivalent baseline we migrate
   *from*, and it actually runs: a Vue/nginx frontend → Spring Boot API → one Postgres (schemas
   `app` + `reporting`) → a Spring Boot nightly reconciliation batch. Three least-privilege DB
   roles; the five reporting teams connect as a read-only `report_reader`. End-to-end with
   `cd legacy && docker compose up`.
2. **The Claude Code governance layer** — configuration that makes the tool enforce our
   conventions instead of just suggesting them:
   - **ADR-forcing:** a `commit-msg` git hook rejects architectural commits that don't reference
     an ADR; a `PostToolUse` hook nudges in-session; the `/adr` skill scaffolds the next ADR.
   - **Docs currency:** a `Stop` hook keeps the read-first docs (CLAUDE.md + README) honest;
     `/review-docs` is the on-demand companion.
   - **Five ADRs** capturing the calls, incl. the hook-vs-prompt principle (ADR-0003) and the
     source/target repo split (ADR-0005).

The **AWS target stand-in** at the repo root (`docker-compose.yml` + `infra/`) is **scaffolding**:
the target datastores run (RDS/ElastiCache/S3 via Postgres/Redis/MinIO), but the migrated app
containers and the Terraform are not built yet. The split — `legacy/` is the source, the root is
the target — is deliberate and documented in **ADR-0005**.

## Challenges Attempted
The standout work is cross-cutting Claude Code config (stresses the cert domains) plus a
consistency pass that reconciled the source (`legacy/`) and target (root) halves.

| # | Challenge | Status | Notes |
|---|---|---|---|
| 1 | The Memo | scaffold | `docs/01-memo.md` template; lift-vs-refactor not yet argued (a CFO/Legal stance — left for the team). |
| 2 | The Discovery | **done** | `docs/02-discovery.md`, read off the real `legacy/` code: 8 couplings incl. five teams on the `reporting` schema, batch's cross-schema read, bootstrap ordering. |
| 3 | The Options | partial | Target cloud + mapping chosen and recorded (ADR-0002 AWS, ADR-0005 layout); candidate architectures not yet scored. |
| 4 | The Container | not started | The *migrated* web-app container isn't built (root compose has a documented placeholder). |
| 5 | The Foundation | partial | Governance hooks built; the Terraform and the **secrets `PreToolUse` hook** (ADR-0003) are not. |
| 6 | The Proof | scaffold | `tests/README.md` plan; Discovery now pins the exact ★ assertions to write. |
| 7 | The Scorecard | not started | |
| 8 | The Undo | not started | |
| 9 | The Survey | not started | |

## Key Decisions
Full reasoning in `/decisions`:
- **[ADR-0002](decisions/0002-target-cloud-aws.md)** — Target cloud is **AWS** (cleanest local↔cloud mapping).
- **[ADR-0003](decisions/0003-secrets-hook-vs-prompt.md)** — Secrets: a **hook blocks, a prompt prefers** (the hook is specified; implementation pending).
- **[ADR-0004](decisions/0004-forcing-adrs-and-claude-md-maintenance.md)** — **Force the *presence* of ADRs and *currency* of docs by gate; leave *quality* to prompt + review.**
- **[ADR-0005](decisions/0005-repo-layout-legacy-source-vs-target-standin.md)** — **`legacy/` is the migration source; the root is the AWS target stand-in.** Only Postgres is migrated; Redis/S3 are target additions.

## How to Run It
Assumes Docker (and Python 3 for the governance hooks). Two stacks:

```bash
# A) The legacy source system — runs end-to-end.
cd legacy
cp .env.example .env          # fill the change-me values; .env is git-ignored
docker compose up --build -d
docker compose ps             # wait until all services are healthy
#   :8080 web app   ·   :8081/api   ·   :8082 batch   ·   :5432 postgres
curl -X POST http://localhost:8082/run   # trigger the reconciliation manually
```

```bash
# B) The AWS target datastores stand-in (repo root).
bash scripts/setup.sh         # activate the team git hooks (once per clone)
cp .env.example .env
docker compose up -d postgres-rds redis-elasticache minio-s3
#   postgres-rds -> RDS   ·   redis-elasticache -> ElastiCache   ·   minio-s3 -> S3
```

```bash
# The governance layer in action — this commit is REJECTED (arch change, no ADR referenced):
echo 'resource "x" "y" {}' > infra/demo.tf && git add infra/demo.tf
git commit -m "add terraform"            # blocked by .githooks/commit-msg
git restore --staged infra/demo.tf && rm infra/demo.tf
#   /adr "..."  scaffolds the next ADR so the easy path is the compliant one.
```

## If We Had More Time
In priority order, honest about what's held together with tape:
1. **The secrets `PreToolUse` hook (ADR-0003)** — specified and described in our docs, but
   **not yet implemented**. Highest-value gap.
2. **The Container (Challenge 4)** — containerize the migrated web app and wire it into the root
   compose (`build: ./web-app`), so the target stack runs end-to-end too.
3. **The Foundation Terraform (Challenge 5)** — the target IaC with tags / least-priv IAM / remote state.
4. **The Proof (Challenge 6)** — implement the ★ assertions Discovery identified (reporting
   contract, batch integrity, role isolation).
5. **The Memo (Challenge 1)** — argue lift-and-shift vs refactor for Legal/CFO.
6. **Scorecard (7), Undo (8), Survey (9)** — the quality + agentic stretch.

## How We Used Claude Code
We treated the scenario as a Claude Code configuration exercise, not just coding:
- **Hooks as guardrails, not vibes.** "Every architectural change gets an ADR" and "the
  read-first docs stay current" are deterministic hooks (`commit-msg`, `PostToolUse`, `Stop`),
  not hopes. Where judgment is genuinely needed (is this change meaningful? is this guidance
  right?) we kept it a prompt — the line drawn in ADR-0003 and ADR-0004.
- **Skills for the easy path.** `/adr` and `/review-docs` make the compliant action the
  low-friction one, so the gates point somewhere instead of just blocking.
- **Dogfooding caught real bugs.** Building the ADR nudge, it fired on our own `infra/CLAUDE.md`
  edit — a false positive — so we tightened the matcher to exclude `*.md` docs.
- **Claude audited its own repo.** After merging the team's `legacy/` app, we had Claude review
  the whole repo for drift; it surfaced the source/target contradiction (a broken `build: ./web-app`,
  docs pointing at deleted files, a hook claimed-but-unbuilt) — which became ADR-0005 and this pass.
