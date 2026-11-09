#!/usr/bin/env bash
# ============================================================================
# codex-review.sh — run a read-only Codex review from the main session.
#
# Replaces spawning the `codex:codex-rescue` subagent for REVIEWS. That agent is
# a forwarder: one Bash call to codex-companion, stdout returned unchanged. As a
# Claude subagent it still loads CLAUDE.md + the always-loaded rules before that
# one call — measured in nile_bounce_legion (2026-11-06): 120 spawns, ~70k-token
# startup each, 80% of the agent's cost spent before Codex was ever invoked.
# Calling the companion here keeps the review identical and drops that startup.
#
# Writes the `codex-reviewed` receipt that guard-reviewer-order.sh reads — the
# job track-codex-review.sh does for the agent path — but only after Codex
# actually returned a non-empty review.
#
# Usage:   .claude/scripts/codex-review.sh <prompt-file>
#          Run with the Bash tool's timeout at 600000 (reviews can take minutes).
# Exit:    0 = review printed on stdout
#          3 = Codex unavailable (no node / plugin / CLI) → use the fallback reviewer
#          1 = Codex ran but failed or returned nothing → use the fallback reviewer
#
# Fix requests are NOT routed here: Codex runs without --write, so it cannot edit
# project files (this script itself writes only the state receipt). Work that
# edits files still goes through the codex:codex-rescue agent (/fix-codex).
# ============================================================================
set -uo pipefail

PROMPT_FILE="${1:-}"
if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ] || [ ! -s "$PROMPT_FILE" ]; then
    echo "usage: codex-review.sh <non-empty prompt-file>" >&2
    exit 1
fi

command -v node >/dev/null 2>&1 || { echo "codex-review: node not found" >&2; exit 3; }
command -v codex >/dev/null 2>&1 || { echo "codex-review: codex CLI not found" >&2; exit 3; }

# Newest installed plugin version first; the marketplace checkout is the fallback.
COMPANION="$(find "$HOME/.claude/plugins/cache/openai-codex/codex" -path '*/scripts/codex-companion.mjs' 2>/dev/null | sort -V | tail -1)"
[ -z "$COMPANION" ] && COMPANION="$HOME/.claude/plugins/marketplaces/openai-codex/plugins/codex/scripts/codex-companion.mjs"
[ -f "$COMPANION" ] || { echo "codex-review: codex plugin not installed (run /codex:setup)" >&2; exit 3; }

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# Progress lines ([codex] …) go to stderr; keep them out of the review text, show them only on failure.
PROGRESS_LOG="$(mktemp -t codex-review.XXXXXX)"
trap 'rm -f "$PROGRESS_LOG"' EXIT
OUTPUT="$(node "$COMPANION" task --fresh --cwd "$REPO_ROOT" --prompt-file "$(cd "$(dirname "$PROMPT_FILE")" && pwd)/$(basename "$PROMPT_FILE")" 2>"$PROGRESS_LOG")"
STATUS=$?

if [ "$STATUS" -ne 0 ] || [ -z "${OUTPUT//[[:space:]]/}" ]; then
    cat "$PROGRESS_LOG" >&2
    printf '%s\n' "$OUTPUT" >&2
    echo "codex-review: Codex failed (exit $STATUS) — use the fallback reviewer" >&2
    exit 1
fi

# Same resolution order as hooks/_lib.sh, so the reader finds the receipt.
STATE_DIR="${UNITY_HOOK_STATE_DIR:-$REPO_ROOT/.claude/state}"
mkdir -p "$STATE_DIR" && touch "$STATE_DIR/codex-reviewed" \
    || echo "codex-review: could not write $STATE_DIR/codex-reviewed — guard-reviewer-order.sh will block unity-reviewer" >&2

printf '%s\n' "$OUTPUT"
