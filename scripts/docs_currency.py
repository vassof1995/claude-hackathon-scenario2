#!/usr/bin/env python3
"""Docs currency check — the hook that keeps the read-first docs honest.

Runs as a Claude Code **Stop** hook. When a turn ends, it checks the working tree for two
kinds of drift and, if found, asks Claude to review and revise the existing doc before
stopping (per the revised ADR-0004):

  1. CLAUDE.md  — code under a directory-scoped CLAUDE.md changed without that file being
                  revised. (The root CLAUDE.md is exempt: curated conventions, not code-tracked.)
  2. README.md  — a story-relevant change landed (a new ADR, a how-to-run change, a new
                  skill/hook) without README.md being touched. README is the file the judges
                  read first; it must keep telling the true story.

It NEVER generates content and NEVER creates files — it only checks existing docs and drives
a judgment-based revision. It fires at most once per session (a marker under .git records it).

Input : Claude Code Stop hook JSON on stdin (uses session_id).
Output: {"decision":"block","reason":...} when drift is found; else silent. Exit 0.
"""
import json
import os
import re
import subprocess
import sys

# A change to any of these tells a story the README should reflect:
#   how-to-run (compose, Dockerfile, setup scripts), key decisions (new ADR),
#   how-we-used-Claude (skills, hooks, settings).
README_TRIGGER_RE = re.compile(
    r"(^docker-compose\.ya?ml$"
    r"|Dockerfile$"
    r"|^Makefile$"
    r"|^decisions/\d{4}-.*\.md$"
    r"|^scripts/.*\.sh$"
    r"|^\.claude/(settings\.json$|hooks/|skills/))"
)


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
    paths = []
    for line in git("status", "--porcelain").splitlines():
        p = line[3:].strip()
        if " -> " in p:  # rename: take the destination
            p = p.split(" -> ", 1)[1]
        if p:
            paths.append(p)
    return paths


def scoped_claude_dirs() -> list[str]:
    """Directories with their own CLAUDE.md, excluding the repo-root one."""
    dirs = {os.path.dirname(rel) for rel in git("ls-files", "*CLAUDE.md").splitlines()}
    return sorted(d for d in dirs if d)


def check_claude_md(changed: list[str]) -> dict:
    """scope dir -> changed code files whose CLAUDE.md wasn't revised."""
    stale = {}
    for scope in scoped_claude_dirs():
        prefix = scope.rstrip("/") + "/"
        code = [p for p in changed if p.startswith(prefix) and not p.endswith(".md")]
        if code and (prefix + "CLAUDE.md") not in changed:
            stale[scope] = code[:8]
    return stale


def check_readme(changed: list[str], root: str) -> list[str]:
    """Story-relevant changed paths when README.md itself wasn't touched."""
    if not os.path.exists(os.path.join(root, "README.md")) or "README.md" in changed:
        return []
    return [p for p in changed if README_TRIGGER_RE.search(p)][:8]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    session = re.sub(r"[^A-Za-z0-9_.-]", "_", str(payload.get("session_id", "default")))

    root = repo_root()
    marker = os.path.join(root, ".git", f"docs_currency.{session}")
    if os.path.exists(marker):
        return 0  # already nudged this session — don't nag

    changed = changed_paths()
    if not changed:
        return 0

    stale_claude = check_claude_md(changed)
    story_changes = check_readme(changed, root)
    if not stale_claude and not story_changes:
        return 0

    # Block once: record the marker so we don't fire again this session.
    try:
        open(marker, "w").close()
    except Exception:
        pass

    lines = ["Docs currency check — read-first docs may be out of date with your changes:"]
    for scope, files in stale_claude.items():
        lines.append(f"\n  {scope}/CLAUDE.md governs these changed files:")
        lines += [f"    - {f}" for f in files]
    if story_changes:
        lines.append("\n  README.md tells the story, but these story-relevant changes "
                     "landed without touching it:")
        lines += [f"    - {f}" for f in story_changes]
        lines.append("    (check What We Built / Challenges / How to Run It / How We Used Claude Code)")
    lines.append(
        "\nReview each listed doc against the change you just made and revise it where the "
        "guidance or story is now stale, incomplete, or contradicted. If a doc is still "
        "accurate, say so explicitly and stop — do not invent edits. (Fires once per session.)"
    )
    print(json.dumps({"decision": "block", "reason": "\n".join(lines)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
