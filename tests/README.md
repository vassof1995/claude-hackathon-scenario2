# Validation Suite — "Did the migration succeed?" (Challenge 6 · Quality)

This suite is the **definition of success**. It runs against the local stand-ins now, and is
designed to run again against the real cloud post-cutover with only config changes.

## Layers
1. **Smoke** — services come up, health endpoints green, connectivity works.
2. **Contract** — the reporting DB's five consumers still get the shape they depend on; the
   web app's API contract holds.
3. **Data integrity** — reconciliation totals match; no rows lost/duplicated across migration.

## Anti-theatre assertions
At least a few assertions specifically catch the **Discovery gremlins** (see
`docs/02-discovery.md`), so passing means more than "it boots":
- [ ] No hardcoded IP path is relied on (env-var indirection verified).
- [ ] No shared-filesystem dependency (object storage used instead).
- [ ] Cache-warm behavior is provided by the target design, not the old cron.

## Run
```bash
# TODO: wire to your chosen runner (pytest / vitest / bats…)
```
