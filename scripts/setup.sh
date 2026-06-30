#!/usr/bin/env bash
# One-time local setup. Wires the committed git hooks (core.hooksPath can't be committed,
# so each clone runs this once). Safe to re-run.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.sh 2>/dev/null || true

echo "✓ git hooks active (core.hooksPath=.githooks)"
echo "  - commit-msg : ADR gate for architectural changes (ADR-0004)"
echo "✓ run 'git config --unset core.hooksPath' to disable."
