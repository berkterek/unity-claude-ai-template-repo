#!/usr/bin/env bash
# sandbox.sh — Backup/restore graph files mutated by tests.
# Pre-existing files are restored from backup; files newly created by the test run are removed.
# Cleanup runs on EXIT and on INT/TERM so state is preserved even on failure or Ctrl-C.

SANDBOX_BACKUP_DIR="$(mktemp -d -t graphify-verify-XXXXXX)"
GRAPH_DIR="$REPO_ROOT/.claude/graph"

PROTECTED=(
  "$GRAPH_DIR/graph.json"
  "$GRAPH_DIR/graph.json.bak"
  "$GRAPH_DIR/.last-build"
  "$GRAPH_DIR/cache/file-hashes.json"
  "$GRAPH_DIR/cache/mcp-extract.json"
  "$REPO_ROOT/.claude/state/graph-updates.log"
)

# Bash 3.2 (macOS default) lacks associative arrays — use a temp dir of marker files instead.
# For each PROTECTED path that exists at setup time, we write a marker file into SANDBOX_EXISTED_DIR.
SANDBOX_EXISTED_DIR="$(mktemp -d -t graphify-existed-XXXXXX)"

_existed_marker() {
  # Stable filename from path: replace / with __ (no special chars in mktemp names)
  echo "$SANDBOX_EXISTED_DIR/$(echo "$1" | sed 's|/|__|g')"
}

sandbox_setup() {
  mkdir -p "$SCRIPT_DIR/.work"
  local f backed_up=0
  for f in "${PROTECTED[@]}"; do
    if [[ -f "$f" ]]; then
      cp "$f" "$SANDBOX_BACKUP_DIR/$(basename "$f")"
      touch "$(_existed_marker "$f")"
      backed_up=$((backed_up + 1))
    fi
  done
  echo "sandbox: backed up $backed_up files to $SANDBOX_BACKUP_DIR"
}

cleanup() {
  local f bak restored=0 removed=0
  for f in "${PROTECTED[@]}"; do
    bak="$SANDBOX_BACKUP_DIR/$(basename "$f")"
    if [[ -f "$(_existed_marker "$f")" ]]; then
      [[ -f "$bak" ]] && cp "$bak" "$f" && restored=$((restored + 1)) || true
    else
      [[ -f "$f" ]] && rm -f "$f" && removed=$((removed + 1)) || true
    fi
  done
  rm -rf "$SANDBOX_BACKUP_DIR" "$SANDBOX_EXISTED_DIR" 2>/dev/null || true
  echo "sandbox: restored $restored, removed $removed new files"
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM
