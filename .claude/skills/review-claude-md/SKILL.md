---
name: review-claude-md
description: Review existing CLAUDE.md files against the current code and revise stale guidance. Use when the CLAUDE.md currency hook flags drift, before a PR, or when the user types /review-claude-md. Never creates new CLAUDE.md files and never generates content — it revises existing files by judgment.
---

# /review-claude-md — keep existing guidance honest

Reviews the CLAUDE.md files already in the repo and revises any guidance that the code has
outgrown. This is the on-demand companion to the `Stop` currency hook (ADR-0004).

## Rules (per ADR-0004)
- **Do not create new CLAUDE.md files.** Only review files that already exist.
- **Do not generate content or insert managed/generated blocks.** Every line stays
  hand-authored prose. You are revising judgment, not templating facts.
- **The root CLAUDE.md is conventions** — touch it only if a *convention* actually changed,
  not because some directory churned.

## Steps
1. **Find scope.** List existing files: `git ls-files '*CLAUDE.md'`. If the user named one,
   review just that.
2. **See what changed.** For each directory-scoped CLAUDE.md, look at recent changes under
   its directory:
   ```bash
   git log --oneline -10 -- <dir>/
   git diff HEAD~5 -- <dir>/      # adjust range to taste
   ```
   Also check the working tree: `git status --short`.
3. **Compare guidance to reality.** Read the CLAUDE.md and the changed code. Flag anything
   that is now: contradicted (rule no longer holds), stale (names a removed file/var/path),
   or incomplete (a new convention the code follows but the doc doesn't mention).
4. **Revise in place.** Edit only what's wrong. Keep the file's voice and structure. Prefer
   the smallest change that makes the guidance true again.
5. **If it's still accurate, say so and stop.** Do not invent edits to look busy — an
   unchanged file is the correct outcome when nothing drifted.

## Output
A short note per file: `accurate` / `revised (what & why)`, so the reviewer sees the call you
made. If you revised guidance tied to an architectural change, the ADR gate still applies.
