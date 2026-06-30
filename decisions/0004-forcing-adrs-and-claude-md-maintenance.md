# ADR-0004: Forcing ADRs and maintaining CLAUDE.md — presence by gate, quality by prompt

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Team <name>

## Context
ADR-0001 says we record every meaningful decision; the project `CLAUDE.md` says "ADRs for
every meaningful call" and "commit often." Both are *preferences* — and preferences erode
under deadline pressure. We want the discipline to hold without a human policing every PR.

The same question applies to keeping `CLAUDE.md` accurate: as services and modules change,
the per-workload guidance drifts and silently misleads both Claude and human readers.

ADR-0003 already drew the line we reuse here: **deterministic guardrails belong in hooks,
probabilistic preferences belong in prompts.** The trap is overreaching — trying to make a
hook enforce *quality* (is this ADR any good? is this guidance correct?), which a
deterministic check cannot judge.

## Decision
We enforce the **presence and acknowledgement** of decisions deterministically, and leave
their **quality** to prompts and review. Concretely, an escalation ladder:

1. **Soft, in-session (Claude-facing):** a `PostToolUse` hook
   (`.claude/hooks/adr_guard.py`) nudges when an architectural file (`infra/`,
   `docker-compose`, `Dockerfile`, `*.tf`) is edited with no ADR in the working tree.
   It never blocks — it only reminds, because "is this change meaningful?" needs judgment.

2. **Hard, at commit (deterministic):** a `commit-msg` git hook (`.githooks/commit-msg`)
   rejects any commit that touches an architectural surface unless the message references
   an `ADR-NNNN`, stages a new `decisions/NNNN-*.md`, or carries a conscious
   `[no-adr: <reason>]` opt-out. This runs with or without Claude and survives
   `--no-verify` only as a visible, deliberate bypass.

3. **The easy path:** the `/adr` skill scaffolds the next-numbered ADR and pre-fills it
   from the diff, so satisfying the gate costs seconds, not friction.

For **CLAUDE.md maintenance** we split the file by trust:
- **Facts** (service list, module list, the local↔cloud mapping table) are *generated* from
  the repo by the `/sync-claude-md` skill — they must match reality, so a machine derives them.
- **Conventions** (opinions, guidance, "prefer X") stay *hand-curated* — they encode judgment
  a generator cannot supply. A `SessionStart` hook surfaces staleness (code newer than the
  CLAUDE.md that documents it) but never rewrites opinions.

## Consequences
- Architectural changes cannot land silently undocumented; the decision trail the CTO reads
  stays complete, and the commit history (which is judged) shows the reasoning.
- The gate enforces presence, not quality — a lazy ADR still passes. Quality is caught by
  human/Claude review and the `CLAUDE.md` prompt, exactly where judgment lives.
- `core.hooksPath` is local config, so each clone runs `scripts/setup.sh` once. The
  `PostToolUse` Claude hook needs no setup (it ships in committed `.claude/settings.json`).
- `CLAUDE.md` factual drift is mechanically fixable; only the opinionated parts need a human.
- This same pattern (gate presence, prompt quality) generalises to the Scorecard
  (Challenge 7), which scores how often Claude proposes something a gate would block.

## Alternatives considered
- **Prompt-only ("please write an ADR")** — rejected; probabilistic, erodes under pressure,
  same failure mode as prompt-only secret handling in ADR-0003.
- **Hard pre-commit requiring a *new* ADR file on every architectural commit** — rejected;
  too strict (many commits implement one decision), so it trains people to `--no-verify`.
  Referencing an existing `ADR-NNNN` is the lower-friction, equally-deterministic rule.
- **Fully auto-generating CLAUDE.md** — rejected; a generator can derive facts but not
  judgment, and overwriting curated guidance would destroy the file's main value.
- **A CI-only gate (no local hook)** — deferred, not rejected: a GitHub Action that fails a
  PR touching `infra/` without `decisions/` changes is the natural Layer-3 backstop against
  local bypass, and pairs with the non-interactive Scorecard review.
