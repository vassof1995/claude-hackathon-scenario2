#!/usr/bin/env bash
# Scaffold the next-numbered ADR from the team template. Prints the new file path.
# Usage: scripts/new_adr.sh "Short title of the decision"
set -euo pipefail

title="${*:-}"
if [ -z "$title" ]; then
  echo "usage: scripts/new_adr.sh \"Short title\"" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
dir="$repo_root/decisions"
mkdir -p "$dir"

# Highest existing NNNN, default 0.
last="$(find "$dir" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-*.md' -exec basename {} \; \
        | sed -E 's/^([0-9]{4}).*/\1/' | sort -n | tail -1 || true)"
next="$(printf '%04d' "$(( 10#${last:-0} + 1 ))")"

slug="$(echo "$title" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
file="$dir/$next-$slug.md"

today="$(date +%Y-%m-%d)"
cat > "$file" <<EOF
# ADR-$next: $title

- **Status:** Proposed
- **Date:** $today
- **Deciders:** Team <name>

## Context
<!-- Why are we deciding this now? What forces are in play? -->
TODO

## Decision
<!-- The call we are making, stated plainly. -->
TODO

## Consequences
<!-- What becomes true once this is accepted — including risks accepted and who bears them. -->
TODO

## Alternatives considered
<!-- What we rejected and why. -->
TODO
EOF

echo "$file"
