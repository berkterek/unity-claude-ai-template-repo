#!/usr/bin/env bash
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
  echo "  # Unity Knowledge Graph — full rebuild on commit"
  echo "  [[ -x .claude/graph/graph-builder.sh ]] || exit 0"
  echo "  nohup bash .claude/graph/graph-builder.sh --full --skip-mcp >/dev/null 2>&1 &"
  echo ""
  exit 1
fi

cat > "$POST_COMMIT" <<'EOF'
#!/usr/bin/env bash
# Auto-installed by Unity Claude AI Template — full graph rebuild on commit.
# This hook runs in the background and never blocks git commit.
[[ -x .claude/graph/graph-builder.sh ]] || exit 0
nohup bash .claude/graph/graph-builder.sh --full --skip-mcp >/dev/null 2>&1 &
exit 0
EOF
chmod +x "$POST_COMMIT"
echo "✓ Installed .git/hooks/post-commit (full graph rebuild on every commit)"

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
