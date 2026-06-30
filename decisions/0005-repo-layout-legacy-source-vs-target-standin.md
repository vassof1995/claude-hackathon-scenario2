# ADR-0005: Repository layout — `legacy/` is the migration source, the root is the AWS target stand-in

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Team The 4am Club

## Context
The repo grew two layers that were never explicitly related, which made several files read as
contradictory (see the audit that triggered this ADR):

- **`legacy/`** is a complete, runnable on-prem system — Postgres (schemas `app` + `reporting`),
  a Spring Boot web-api, a Vue/nginx frontend, and a Spring Boot nightly batch. This is what we
  migrate *from*. It comes up end-to-end with `cd legacy && docker compose up`.
- The **repo root** holds a `docker-compose.yml` that names services after AWS primitives
  (`postgres-rds`, `redis-elasticache`, `minio-s3`, `web-app`) plus the IaC, ADRs, and the
  Claude Code governance. This is the **target** architecture's local stand-in — what we
  migrate *to*.

Two concrete contradictions resulted: the root compose declared `build: ./web-app` for a
directory that does not exist (the app lives at `legacy/web-app/`), and the root `CLAUDE.md`
pointed at per-workload `web-app/CLAUDE.md` / `batch/CLAUDE.md` / `reporting-db/CLAUDE.md`
files that were never present. The mapping table also implied a Redis and an S3 component were
being *migrated*, when the source system has neither.

## Decision
We make the two layers explicit and keep them separate:

- **`legacy/` = the source system.** Self-contained, runnable, the production-equivalent
  baseline. Its guidance lives in `legacy/README.md`. We do not rename or "AWS-ify" anything
  inside it — it represents the world before the migration.
- **Repo root = the AWS target stand-in.** `docker-compose.yml` models the target topology
  with cloud-named services; `infra/` holds the Terraform; `decisions/` and `.claude/` hold the
  governance. Until a workload is actually migrated (e.g. the web app containerised in
  Challenge 4), its service in the root compose is a **documented placeholder**, not a broken
  build pointing at a non-existent path.
- **Only Postgres is a migrated datastore** (→ Amazon RDS). **ElastiCache (Redis) and S3
  (MinIO) are deliberate target *additions***, not components lifted from `legacy/` — the
  source uses neither. Anywhere we name them, we name them as target choices to be justified,
  not as one-to-one migrations.

## Consequences
- The root compose is honest: `docker compose up` brings up the target datastores; app
  containers appear only as they are actually built, each behind its own ADR.
- `CLAUDE.md` describes where things really are: source in `legacy/`, target at the root,
  per-workload *target* guidance added when each workload is migrated (not before).
- Introducing ElastiCache or S3 is a design decision with its own justification, not an
  implied given — which is exactly the kind of call The Options (Challenge 3) should score.
- Readers (auditor, CTO, ops) can tell at a glance which half of the repo they are looking at.

## Alternatives considered
- **Collapse the two into one compose** — rejected; the "before" and "after" states are both
  valuable to show, and merging them hides the migration delta the whole scenario is about.
- **Move `legacy/` out of the repo** — rejected; the source baseline is what the validation
  suite (The Proof) and the discovery (The Discovery) reference; it must stay alongside.
- **Leave the layout implicit** — rejected; that is precisely what produced the contradictory
  files this ADR resolves.
