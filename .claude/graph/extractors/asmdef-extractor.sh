#!/usr/bin/env bash
# asmdef-extractor.sh — Parse every *.asmdef and emit codebase.assemblies[] JSON.
# Usage:
#   asmdef-extractor.sh                          # scan all Assets/**/*.asmdef
#   asmdef-extractor.sh --changed-files a.asmdef,b.asmdef
set -euo pipefail

CHANGED_FILES=""
ROOT="Assets"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-files) CHANGED_FILES="$2"; shift 2 ;;
    --root)          ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Build file list
declare -a FILES=()
if [[ -n "$CHANGED_FILES" ]]; then
  IFS=',' read -ra FILES <<< "$CHANGED_FILES"
  # Filter to only .asmdef files
  declare -a FILTERED=()
  for f in "${FILES[@]}"; do
    [[ "$f" == *.asmdef ]] && FILTERED+=("$f")
  done
  FILES=("${FILTERED[@]}")
else
  while IFS= read -r -d '' f; do
    FILES+=("$f")
  done < <(find "$ROOT" -name '*.asmdef' -print0 2>/dev/null)
fi

emit_one() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "asmdef-extractor: file not found: $f" >&2
    return
  fi
  jq -c \
    --arg f "$f" \
    '{
      name:            (.name // ""),
      file:            $f,
      source_file:     $f,
      references:      (.references // []),
      platforms: {
        include: (.includePlatforms // []),
        exclude: (.excludePlatforms // [])
      },
      allowUnsafeCode: (.allowUnsafeCode // false),
      defines:         (.defineConstraints // []),
      confidence:      "EXTRACTED"
    }' "$f"
}

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

first=1
echo "["
for f in "${FILES[@]}"; do
  [[ $first -eq 0 ]] && echo ","
  emit_one "$f"
  first=0
done
echo "]"
