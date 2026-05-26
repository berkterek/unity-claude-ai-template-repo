#!/usr/bin/env bash
# PostToolUse hook — dotnet build check after each .cs Write/Edit
# Exit 0 always (warning mode — never blocks pipeline)
# NOTE: MCP tools are unavailable in bash hooks. Compile backend is dotnet build only.
# NOTE: .cs filter is in-script — hook matcher "Write|Edit" has no file extension support.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.path // .file_path // ""' 2>/dev/null || true)

if [[ "$FILE_PATH" != *.cs ]]; then
  exit 0
fi

FEATURES=".claude/project-features.json"
PROJECT_FOLDER="."
if [[ -f "$FEATURES" ]]; then
  PROJECT_FOLDER=$(jq -r '.unity_project_folder // "."' "$FEATURES" 2>/dev/null || echo ".")
fi

SLN=$(find "$PROJECT_FOLDER" -maxdepth 2 -name "*.sln" 2>/dev/null | head -1)
if [[ -z "$SLN" ]]; then
  echo "[verify-after-write] No .sln found under '$PROJECT_FOLDER' — skipping compile check" >&2
  exit 0
fi

echo "[verify-after-write] Running dotnet build after write to: $FILE_PATH" >&2
ERRORS=$(dotnet build "$SLN" -v q 2>&1 | grep -i " error " || true)
if [[ -n "$ERRORS" ]]; then
  echo "WARNING — Build errors detected after writing $FILE_PATH:" >&2
  echo "$ERRORS" >&2
fi

exit 0
