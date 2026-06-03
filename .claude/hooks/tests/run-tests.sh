#!/usr/bin/env bash
# Run all hook self-tests. Requires bats-core (brew install bats-core).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
    cat >&2 <<'EOF'
ERROR: bats is not installed.

Install:
  macOS : brew install bats-core
  Linux : npm install -g bats
EOF
    exit 1
fi

cd "$SCRIPT_DIR"
shopt -s nullglob
files=( *.bats )
if [ ${#files[@]} -eq 0 ]; then
    echo "ERROR: no .bats files found in $SCRIPT_DIR" >&2
    exit 1
fi
bats "${files[@]}"
