# ADR-0004: Forcing ADRs and maintaining CLAUDE.md — presence by gate, quality by prompt

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Team The 4am Club

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

For **read-first doc maintenance** (CLAUDE.md *and* README.md) we keep every file
hand-written and let one hook keep it honest — we do **not** generate or auto-create content:
- A **`Stop` hook** (`scripts/docs_currency.py`) checks, when a turn ends, for two kinds of
  drift in the working tree:
  - **CLAUDE.md** — code under a directory-scoped CLAUDE.md changed without that file being
    revised.
  - **README.md** — a story-relevant change landed (a new ADR, a how-to-run change in
    compose/Dockerfile/scripts, a new skill or hook) without README.md being touched. README
    is the file the judges read first, so it must keep telling the true story.
  If either fires, it asks Claude to review the existing doc and revise it where it is now
  stale — or to confirm explicitly that no change is needed. It fires at most once per
  session and never edits the file itself; the revision is Claude's judgment, not a template.
- The **revision is always judgment-based.** A machine can detect *that* a doc may be stale
  (deterministic: code/story touched, doc untouched); it cannot write *correct* prose. So the
  check is mechanical and the rewrite stays with the model + review.
- The **root CLAUDE.md is exempt** from the code-scope check: it holds team conventions, not
  code-tracked facts, so directory churn should not force a rewrite of it. (README is checked
  by story-relevant triggers instead, not by raw churn.)

## Consequences
- Architectural changes cannot land silently undocumented; the decision trail the CTO reads
  stays complete, and the commit history (which is judged) shows the reasoning.
- The gate enforces presence, not quality — a lazy ADR still passes. Quality is caught by
  human/Claude review and the `CLAUDE.md` prompt, exactly where judgment lives.
- `core.hooksPath` is local config, so each clone runs `scripts/setup.sh` once. The Claude
  hooks (`PostToolUse` ADR nudge, `Stop` CLAUDE.md currency) need no setup — they ship in
  committed `.claude/settings.json`.
- The read-first docs never drift silently: a code change under a scoped CLAUDE.md, or a
  story-relevant change without a README touch, forces a conscious review. But because nothing
  is generated, the docs stay fully human-authored — the check prompts a person/model, it does
  not write the prose.
- README currency is trigger-based, not churn-based, so it stays a signal not a nag: a typo
  fix won't ask you to rewrite the story, but a new ADR or a how-to-run change will.
- This same pattern (gate presence, prompt quality) generalises to the Scorecard
  (Challenge 7), which scores how often Claude proposes something a gate would block.

## Alternatives considered
- **Prompt-only ("please write an ADR")** — rejected; probabilistic, erodes under pressure,
  same failure mode as prompt-only secret handling in ADR-0003.
- **Hard pre-commit requiring a *new* ADR file on every architectural commit** — rejected;
  too strict (many commits implement one decision), so it trains people to `--no-verify`.
  Referencing an existing `ADR-NNNN` is the lower-friction, equally-deterministic rule.
- **Auto-generating CLAUDE.md content (managed/generated blocks)** — rejected; a generator can
  derive facts but not judgment, generated blocks fragment a file meant to read as one voice,
  and the value of CLAUDE.md is precisely the curated guidance a generator cannot supply. We
  enforce *currency* (a hook prompts review) without generating *content*.
- **A CI-only gate (no local hook)** — deferred, not rejected: a GitHub Action that fails a
  PR touching `infra/` without `decisions/` changes is the natural Layer-3 backstop against
  local bypass, and pairs with the non-interactive Scorecard review.
