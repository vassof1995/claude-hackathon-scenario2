# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** <TODO>
- **Deciders:** Team <name>

## Context
The CTO reads our ADRs. We need a lightweight, durable record of every meaningful
architecture and migration decision — what we chose, what we rejected, and why — so the
reasoning survives past the hackathon and a reader can reconstruct our judgment.

## Decision
We record decisions as numbered Markdown ADRs in `/decisions`, one file per decision,
named `NNNN-short-title.md`. Each ADR states context, the decision, the alternatives
considered, and the consequences (including risks accepted and who bears them).

## Consequences
- Decisions are reviewable in PRs and visible in commit history (which is judged).
- The Memo (Challenge 1) and The Options (Challenge 3) both land as ADRs.
- Superseded ADRs are marked `Superseded by ADR-NNNN`, never deleted.

## Alternatives considered
- **A decisions section in the README** — rejected; doesn't scale and buries the reasoning.
- **No formal record** — rejected; the CTO is an explicit reader and the journey is judged.
