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
#1 We created the onPrem legacy app to have a starting point for the cloud migratin szenario

## Challenges Attempted
| # | Challenge | Status | Notes |
|---|---|---|---|
| 1 | The <name> | done / partial / skipped | |
| 2 | | | |

## Key Decisions
Biggest calls you made and why. Link into `/decisions` for the full ADRs.

## How to Run It
Exact commands. Assume the reader has Docker and nothing else.

## If We Had More Time
What you'd tackle next, in priority order. Be honest about what's held
together with tape.

## How We Used Claude Code
What worked. What surprised you. Where it saved the most time.
