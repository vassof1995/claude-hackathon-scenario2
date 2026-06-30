---
name: review-docs
description: Review the read-first docs (CLAUDE.md files and README.md) against the current code and revise anything stale. Use when the docs-currency hook flags drift, before a PR, or when the user types /review-docs. Never creates new docs and never generates content — it revises existing files by judgment.
---

# /review-docs — keep the read-first docs honest

Reviews the docs the judges read first — the CLAUDE.md files and `README.md` — and revises
anything the code has outgrown. This is the on-demand companion to the `Stop` docs-currency
hook (ADR-0004).

## Rules (per ADR-0004)
- **Do not create new docs.** Only review files that already exist.
- **Do not generate content or insert managed/generated blocks.** Every line stays
  hand-authored prose. You are revising judgment, not templating facts.
- **The root CLAUDE.md is conventions** — touch it only if a *convention* actually changed,
  not because some directory churned.

## CLAUDE.md
1. **Find scope.** `git ls-files '*CLAUDE.md'`. If the user named one, review just that.
2. **See what changed** under each scoped file's directory: `git log --oneline -10 -- <dir>/`
   and `git diff HEAD~5 -- <dir>/`; also `git status --short`.
3. **Compare guidance to reality.** Flag guidance that is contradicted (rule no longer holds),
   stale (names a removed file/var/path), or incomplete (a new convention the doc omits).
4. **Revise in place**, smallest change that makes it true again, keeping the file's voice.

## README.md
The story file. Check it against the four sections the judges read:
- **What We Built** — does it still match what exists in the repo?
- **Challenges Attempted** — status table current with the work actually done?
- **How to Run It** — do the commands still work? (compose/Dockerfile/scripts changed?)
- **How We Used Claude Code** — new skills, hooks, or subagents to mention?
Cross-check with: `git log --oneline -15`, `git status --short`, and the `decisions/` list
(a new ADR usually means a new decision worth a line in the story).

## Output
A short note per file: `accurate` / `revised (what & why)`, so the reviewer sees the call you
made. If you're still accurate, say so and stop — do not invent edits to look busy. If a
revision is tied to an architectural change, the ADR gate still applies.
