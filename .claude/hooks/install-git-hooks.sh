#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# install-git-hooks.sh — One-time setup: install post-commit (and optionally pre-commit) hooks.
# Usage:
#   bash .claude/hooks/install-git-hooks.sh          # install post-commit
#   bash .claude/hooks/install-git-hooks.sh --strict  # also install pre-commit (blocks on errors)
#
# NOTE: Claude must NOT run this script automatically. It is a one-time developer setup step.
set -euo pipefail

STRICT=0
for arg in "$@"; do
  [[ "$arg" == "--strict" ]] && STRICT=1
done

# ── Verify we're in a git repo ────────────────────────────────────────────────
if [[ ! -d ".git" ]]; then
  echo "error: .git directory not found — run from the project root" >&2
  exit 1
fi

# ── post-commit hook ──────────────────────────────────────────────────────────
POST_COMMIT=".git/hooks/post-commit"

if [[ -e "$POST_COMMIT" ]]; then
  echo "error: $POST_COMMIT already exists — merge manually to avoid clobbering your existing hook." >&2
  echo ""
  echo "Add this to your existing post-commit hook:"
  echo ""
  echo "  # Unity Knowledge Graph — incremental rebuild on commit (preserves MCP cache)"
  echo "  [[ -f .claude/graph/graph-builder.py ]] || exit 0"
  echo "  nohup python3 .claude/graph/graph-builder.py --incremental >/dev/null 2>&1 &"
  echo ""
  exit 1
fi

cat > "$POST_COMMIT" <<'EOF'
#!/usr/bin/env bash
# Auto-installed by Unity Claude AI Template — incremental graph rebuild on commit.
# Preserves MCP cache (prefabs, scenes). Use /build-knowledge-graph --full to force
# a full rebuild with live MCP extraction when Unity Editor is open.
# This hook runs in the background and never blocks git commit.
[[ -f .claude/graph/graph-builder.py ]] || exit 0
nohup python3 .claude/graph/graph-builder.py --incremental >/dev/null 2>&1 &
exit 0
EOF
chmod +x "$POST_COMMIT"
echo "✓ Installed .git/hooks/post-commit (incremental graph rebuild on every commit)"

# ── pre-commit hook (--strict only) ──────────────────────────────────────────
if [[ $STRICT -eq 1 ]]; then
  PRE_COMMIT=".git/hooks/pre-commit"

  if [[ -e "$PRE_COMMIT" ]]; then
    echo "error: $PRE_COMMIT already exists — merge manually." >&2
    exit 1
  fi

  cat > "$PRE_COMMIT" <<'EOF'
#!/usr/bin/env bash
# Auto-installed by Unity Claude AI Template (--strict) — block commit on graph errors.
[[ -x .claude/graph/graph-validator.sh ]] || exit 0
[[ -f .claude/graph/graph.json ]] || exit 0
bash .claude/graph/graph-validator.sh .claude/graph/graph.json >/dev/null 2>&1
exit $?
EOF
  chmod +x "$PRE_COMMIT"
  echo "✓ Installed .git/hooks/pre-commit (blocks commit on validation.errors)"
fi

echo ""
echo "Next steps:"
echo "  1. Add the PostToolUse hook to .claude/settings.json (see CLAUDE.md > Knowledge Graph)"
echo "  2. (optional) Run watch loop: bash .claude/graph/graph-watch.sh"
