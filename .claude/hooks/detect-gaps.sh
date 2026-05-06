#!/usr/bin/env bash
# Detect-Gaps: SessionStart hook.
# Scans for undocumented systems, missing tests, and orphaned modules.
# Warnings only — never blocks. Fast scan only.

GAME_DIR="_GameFolders/Scripts/Games"
TESTS_DIR="_GameFolders/Scripts/Tests"
TDD_FILE="docs/TDD.md"
GDD_FILE="docs/GDD.md"

WARNINGS=()

# 1. Check if game folder exists at all
if [ ! -d "$GAME_DIR" ]; then
  exit 0
fi

# 2. Warn if GDD exists but no TDD
if [ -f "$GDD_FILE" ] && [ ! -f "$TDD_FILE" ]; then
  WARNINGS+=("GDD found but no TDD.md — run /architect to create the Technical Design Document")
fi

# 3. Warn if TDD exists but no WORKFLOW.md
if [ -f "$TDD_FILE" ] && [ ! -f "docs/WORKFLOW.md" ]; then
  WARNINGS+=("TDD found but no WORKFLOW.md — run /plan-workflow to generate execution plan")
fi

# 4. Scan for .cs files in Concretes/ with no matching test file
if [ -d "$GAME_DIR/Concretes" ] && [ -d "$TESTS_DIR" ]; then
  UNTESTED=0
  while IFS= read -r -d '' cs_file; do
    basename=$(basename "$cs_file" .cs)
    # Skip interfaces, configs, installers, events (they don't need direct tests)
    case "$basename" in
      I[A-Z]*|*Configuration|*Installer|*Events|*Provider|*Root) continue ;;
    esac
    # Look for a matching test file anywhere under Tests/
    if ! find "$TESTS_DIR" -name "${basename}Tests.cs" -q 2>/dev/null | grep -q .; then
      UNTESTED=$((UNTESTED + 1))
    fi
  done < <(find "$GAME_DIR/Concretes" -name "*.cs" -print0 2>/dev/null)

  if [ "$UNTESTED" -gt 0 ]; then
    WARNINGS+=("$UNTESTED class(es) in Concretes/ may be missing tests — run /generate-tests to create them")
  fi
fi

# 5. Warn if .claude/skills/learned/ is empty or missing
if [ ! -d ".claude/skills/learned" ] || [ -z "$(ls -A .claude/skills/learned 2>/dev/null)" ]; then
  WARNINGS+=("No learned skills yet — run /learn after completing a feature to extract reusable patterns")
fi

# Output warnings
if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "🔍 Detect-Gaps found ${#WARNINGS[@]} item(s):" >&2
  for warning in "${WARNINGS[@]}"; do
    echo "   • $warning" >&2
  done
fi

exit 0
