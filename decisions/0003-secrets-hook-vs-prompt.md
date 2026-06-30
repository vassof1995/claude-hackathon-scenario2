# ADR-0003: Secrets in IaC — a hook blocks, a prompt prefers

- **Status:** Accepted (decision); **hook implementation pending**
- **Date:** 2026-06-30
- **Deciders:** Team The 4am Club

## Context
Plaintext secrets in IaC are a hard "never." But "prefer the secret manager for X" is a soft
preference that depends on context. The brief draws a deliberate distinction between
**deterministic guardrails** (hooks) and **probabilistic preferences** (prompts), and the
cert stresses knowing which is which.

## Decision
- A **`PreToolUse` hook** deterministically **blocks** any Claude edit that would write a
  plaintext secret into IaC. No model judgment involved — it either matches the pattern or
  it doesn't.
- A **prompt in `CLAUDE.md`** ("prefer AWS Secrets Manager / SSM for credentials") expresses
  the **preference** for how to do it right, where judgment is appropriate.

> **Implementation status (2026-06-30):** the *decision* stands, but the `PreToolUse` hook is
> **not yet built** — the live hooks today are the ADR nudge and docs-currency check (ADR-0004).
> Until the secrets hook exists, the no-plaintext-secrets rule is enforced only by prompt. See
> README "If We Had More Time". This ADR is the spec the hook must satisfy when written.

## Consequences
- The dangerous, unambiguous failure mode is caught with 100% reliability, not "usually."
- The nuanced "what's the cleanest secret reference here" question stays with the model.
- The Scorecard (Challenge 7) measures how often Claude confidently proposes something the
  hook would block — a false-confidence rate, not a vibe.

## Alternatives considered
- **Prompt-only** ("please don't commit secrets") — rejected; probabilistic, will eventually leak.
- **Hook for everything** — rejected; over-blocks legitimate, context-dependent choices.
