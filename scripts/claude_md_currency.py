#!/usr/bin/env python3
"""CLAUDE.md currency check — the hook that keeps existing guidance honest.

Runs as a Claude Code **Stop** hook. When a turn ends, it checks whether code under a
directory-scoped CLAUDE.md changed in the working tree WITHOUT that CLAUDE.md being revised.
If so, it asks Claude to review and revise the existing file before stopping.

It NEVER generates content and NEVER creates files — it only checks existing CLAUDE.md
files and drives a human-judgment revision (per the revised ADR-0004). The root CLAUDE.md
is exempt: it holds hand-curated team conventions, not code-derived facts.

To avoid nagging, it blocks at most once per session (a marker under .git records that the
nudge has fired).

Input : Claude Code Stop hook JSON on stdin (uses session_id).
Output: {"decision":"block","reason":...} when a stale scope is found; else silent. Exit 0.
"""
import json
import os
import re
import subprocess
import sys


def git(*args: str) -> str:
    try:
        return subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=5
        ).stdout
    except Exception:
        return ""


def repo_root() -> str:
    return git("rev-parse", "--show-toplevel").strip() or os.getcwd()


def changed_paths() -> list[str]:
    """All paths touched in the working tree (staged, unstaged, untracked)."""
    out = git("status", "--porcelain")
    paths = []
    for line in out.splitlines():
        p = line[3:].strip()
        if " -> " in p:  # rename: take the destination
            p = p.split(" -> ", 1)[1]
        if p:
            paths.append(p)
    return paths


def scoped_claude_mds(root: str) -> list[str]:
    """Directory-scoped CLAUDE.md files (relative dirs), excluding the repo-root one."""
    dirs = []
    for rel in git("ls-files", "*CLAUDE.md").splitlines():
        d = os.path.dirname(rel)
        if d:  # skip the root CLAUDE.md (curated conventions, not code-tracked)
            dirs.append(d)
    return sorted(set(dirs))


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    session = str(payload.get("session_id", "default"))

    root = repo_root()
    marker = os.path.join(root, ".git", f"claude_md_currency.{re.sub(r'[^A-Za-z0-9_.-]', '_', session)}")
    if os.path.exists(marker):
        return 0  # already nudged this session — don't nag

    changed = changed_paths()
    if not changed:
        return 0

    scopes = scoped_claude_mds(root)
    if not scopes:
        return 0

    stale = {}  # scope dir -> list of changed code files
    for scope in scopes:
        prefix = scope.rstrip("/") + "/"
        claude_md = prefix + "CLAUDE.md"
        # code changes in this scope (exclude docs and the CLAUDE.md itself)
        code = [
            p for p in changed
            if p.startswith(prefix) and not p.endswith(".md")
        ]
        if code and claude_md not in changed:
            stale[scope] = code[:8]

    if not stale:
        return 0

    # Block once: record the marker so we don't fire again this session.
    try:
        open(marker, "w").close()
    except Exception:
        pass

    lines = ["CLAUDE.md currency check — you changed code without revising its guidance:"]
    for scope, files in stale.items():
        lines.append(f"\n  {scope}/CLAUDE.md governs these changed files:")
        lines += [f"    - {f}" for f in files]
    lines.append(
        "\nReview each listed CLAUDE.md against the change you just made and revise it if the "
        "guidance is now stale, incomplete, or contradicted. If it is still accurate, say so "
        "explicitly and stop — do not invent edits. (This nudge fires once per session.)"
    )
    print(json.dumps({"decision": "block", "reason": "\n".join(lines)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
