#!/usr/bin/env python3
"""ADR guard — the SOFT layer (in-session nudge).

Runs as a Claude Code PostToolUse hook after Edit/Write. If Claude just touched an
architectural file but there is no ADR work in the current working tree, it injects a
reminder that Claude sees on its next turn. It never blocks — blocking the *presence* of
an ADR is the job of the deterministic commit-msg git hook (see .githooks/commit-msg and
ADR-0004). This layer only nudges; the model decides whether the change is "meaningful".

Input : Claude Code PostToolUse JSON on stdin.
Output: optional JSON with hookSpecificOutput.additionalContext on stdout. Always exit 0.
"""
import json
import re
import subprocess
import sys

# Architectural surfaces: a change here usually deserves a recorded decision.
ARCH_PATTERN = re.compile(
    r"(^|/)(infra/|docker-compose\.ya?ml$|.*Dockerfile$|.*\.tf$)"
)


def emit(context: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": context,
        }
    }))


def git(*args: str) -> str:
    try:
        return subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=5
        ).stdout
    except Exception:
        return ""


def adr_in_working_tree() -> bool:
    """True if any decisions/NNNN-*.md is added/modified in the working tree."""
    porcelain = git("status", "--porcelain")
    for line in porcelain.splitlines():
        path = line[3:].strip()
        if re.match(r"decisions/\d{4}-.*\.md$", path):
            return True
    return False


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # never break the session on a parse error

    if payload.get("tool_name") not in ("Edit", "Write"):
        return 0

    file_path = (payload.get("tool_input") or {}).get("file_path", "")
    if not file_path or not ARCH_PATTERN.search(file_path):
        return 0

    # Don't nudge about edits to the ADRs themselves.
    if re.search(r"decisions/\d{4}-.*\.md$", file_path):
        return 0

    if adr_in_working_tree():
        return 0  # an ADR is already in flight this session — no nag

    emit(
        f"Reminder: you just edited an architectural file ({file_path}) but no "
        "decisions/NNNN-*.md is in the working tree. If this is a meaningful call, "
        "scaffold one with the /adr skill (or reference an existing ADR in your commit "
        "message as ADR-NNNN). The commit-msg git hook will enforce this at commit time "
        "— see ADR-0004."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
