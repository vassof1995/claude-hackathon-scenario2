---
name: adr
description: Scaffold and write the next Architecture Decision Record in /decisions. Use when a meaningful architecture or migration call is being made, when the ADR git gate asks for one, or when the user types /adr. Numbers it automatically and pre-fills from the current diff.
---

# /adr — record an architecture decision

Records a decision as a numbered ADR in `/decisions`, matching the team format
(see `decisions/0001-record-architecture-decisions.md`). This is the easy path the
deterministic commit-msg gate (ADR-0004) is designed to point people toward.

## Steps

1. **Determine the title.** Use the user's argument if given. Otherwise infer a short,
   decision-shaped title from the current work (e.g. "Web app runs on ECS Fargate, not EKS").

2. **Scaffold the file** by running:
   ```bash
   scripts/new_adr.sh "Your short title"
   ```
   It picks the next `NNNN`, slugifies the title, stamps today's date, and prints the path.

3. **Gather context** for a faithful record:
   ```bash
   git diff --staged --stat && git diff --stat
   ```
   Read the relevant changed files so Context/Decision/Consequences reflect what actually
   changed, not a guess.

4. **Fill in every section.** Replace each `TODO`:
   - **Context** — the forces and constraints that make this decision necessary now.
   - **Decision** — the call, stated plainly; name concrete services/tools (ECS vs EKS, etc.).
   - **Consequences** — what becomes true, including **risks accepted and who bears them**.
   - **Alternatives considered** — what was rejected and the honest reason.
   Set **Status** to `Accepted` once the team agrees; leave `Proposed` if still open.

5. **Link it.** If this ADR supersedes another, mark the old one `Superseded by ADR-NNNN`
   (never delete it). Cross-reference related ADRs by number.

## Guardrails
- One decision per file. If you're tempted to write two decisions, scaffold two ADRs.
- Do not invent consequences — only record what the diff and discussion support.
- The gate is satisfied by **staging** the new ADR or **referencing** `ADR-NNNN` in the
  commit message. Mention this to the user so their commit passes.
