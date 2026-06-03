#!/usr/bin/env bash
# ============================================================================
# install.sh — Bootstrap a Unity project with this Claude Code template.
#
# Usage:
#   ./install.sh /path/to/UnityProject           # install into target
#   ./install.sh                                  # install into $PWD
#   ./install.sh /path/to/UnityProject --force    # overwrite existing .claude/
#   ./install.sh --force /path/to/UnityProject    # --force in any position
#
# Argument parsing is centralized in the loop below — a single pass accepts the
# positional target dir AND the --force flag in any order, and rejects unknown
# flags with a non-zero exit so typos don't silently install to $PWD.
# ============================================================================
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) TARGET="$arg" ;;
  esac
done
TARGET="${TARGET:-$PWD}"

echo "Unity AI Template installer"
echo "  source : $SOURCE_DIR"
echo "  target : $TARGET"
echo

# --- Preflight ---
if [ ! -d "$TARGET" ]; then
    echo "ERROR: target directory does not exist: $TARGET" >&2
    exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
    echo "ERROR: $TARGET is not a git repo. Run 'git init' there first." >&2
    exit 1
fi

if [ -d "$TARGET/.claude" ] && [ "$FORCE" != "true" ]; then
    echo "ERROR: $TARGET/.claude already exists. Re-run with --force to overwrite." >&2
    exit 1
fi

# --- Copy ---
echo "Copying .claude/ ..."
cp -R "$SOURCE_DIR/.claude" "$TARGET/.claude"

echo "Copying .claudeignore ..."
cp "$SOURCE_DIR/.claudeignore" "$TARGET/.claudeignore"

if [ -d "$SOURCE_DIR/.claude-plugin" ]; then
    echo "Copying .claude-plugin/ ..."
    cp -R "$SOURCE_DIR/.claude-plugin" "$TARGET/.claude-plugin"
fi

# --- chmod hooks ---
echo "Setting hook permissions ..."
find "$TARGET/.claude/hooks" -name "*.sh" -print0 | xargs -0 chmod +x

# --- Clear ephemeral state (don't carry source-project state into target) ---
rm -f "$TARGET/.claude/state/session.json" \
      "$TARGET/.claude/state/session-cost.jsonl" \
      "$TARGET/.claude/state/gate-cleared" \
      "$TARGET/.claude/state/sparc-approved" \
      "$TARGET/.claude/state/codex-reviewed" \
      "$TARGET/.claude/state/graph-empty-warned" 2>/dev/null || true

cat <<'NEXTSTEPS'

────────────────────────────────────────────────────────────────────────────
SUCCESS — template installed.

NEXT STEPS (manual):

1. Open the project in Claude Code:
       cd <target> && claude

2. Inside Claude Code, run:
       /setup-project

   This will:
     - configure .claude/project-features.json (Addressables / ECS / Testing / Graph)
     - delete rules and hooks for disabled features
     - generate the initial skills index

3. Manually register optional hooks in .claude/settings.json if you added any
   (Claude cannot edit settings.json — that file is protected). Specifically:
     - block-projectsettings.sh   → PreToolUse / Edit|Write
     - notify.sh                  → Notification
     - pre-compact.sh             → PreCompact

4. (Optional) Build the initial knowledge graph:
       /build-knowledge-graph

5. (Optional) Enable the GitHub PR review workflow by adding your
   ANTHROPIC_API_KEY secret to the repo (Settings > Secrets > Actions).
────────────────────────────────────────────────────────────────────────────
NEXTSTEPS
