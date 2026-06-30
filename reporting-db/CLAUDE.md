# CLAUDE.md — reporting-db workload

Reporting database that **five teams query directly**. Target: **RDS Postgres** with a
**read replica** for reporting load, so analysts don't contend with transactional traffic.

## Guidance for edits here
- Five direct consumers = five contracts. Treat the schema (and any reporting views) as a
  **public API**: breaking changes need a migration story and a heads-up, not a surprise.
- One Discovery gremlin lives near here: a **cron pings an endpoint to keep a cache warm**.
  Capture it, decide where it belongs in the target architecture (e.g. scheduled warmer vs.
  caching strategy change), and make sure the validation suite asserts the cache behavior.
- Seed/fixture data only — generated, never real customer data.
- Document who the five consumers are and what they query, so The Options can reason about
  read-replica sizing and access patterns.
