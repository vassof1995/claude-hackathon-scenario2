# The Discovery (Challenge 2 · Architect)

> Surface the real current state — including the ugly inter-dependencies nobody documented.
> Whatever you uncover must visibly shape The Options.

## Workloads
### 1. Web app
- Runtime / language: _TODO_
- Talks to: Postgres, Redis, object storage
- Config: _TODO_

### 2. Batch reconciliation (nightly)
- Schedule: _TODO_
- Reads/writes: _TODO_

### 3. Reporting database
- Five direct consumers: _TODO (who, what they query)_

## The undocumented couplings (the gremlins)
These are what make the migration risky. Each must be designed-out or designed-around in
The Options, and at least a few must be asserted by the validation suite (The Proof).

| # | Coupling | Where it hides | Migration risk | Designed-out in Options? | Asserted in tests? |
|---|----------|----------------|----------------|--------------------------|--------------------|
| 1 | Hardcoded IP | _TODO_ | | | |
| 2 | Shared filesystem mount | _TODO_ | | | |
| 3 | Cron pings endpoint to keep cache warm | _TODO_ | | | |

> Tip: role-play the stakeholder interviews with Claude (CFO, CTO, Compliance, SRE) to draw
> these out — see The Survey (Challenge 9) for the parallel-subagent version.
