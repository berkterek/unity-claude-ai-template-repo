#!/usr/bin/env bash
# ============================================================================
# validate-plan-paths.sh — PLAN-TIME path validation.
#
# Extracts every Unity script path literal out of plan documents (spec.md,
# design.md, tasks.md, or any file/dir given as an argument) and runs each one
# through the SAME validator the write-time hook uses
# (.claude/hooks/lib-path-rules.sh).
#
# Why this exists: the folder-structure mistake that motivated it was authored
# in tasks.md, approved at SCOPE_GATE, and only then built. The write-time hook
# could not have caught it — by the time a file is written the plan is already
# law. This runs BEFORE the gate, so the contradiction is a decision the human
# makes rather than a discovery made three modules later.
#
# Usage:
#   .claude/scripts/validate-plan-paths.sh docs/modules/01-foo/
#   .claude/scripts/validate-plan-paths.sh docs/.../tasks.md docs/.../design.md
#
# Exit codes:  0 = all extracted paths legal (prints a positive receipt)
#              2 = at least one violation (prints each, with the rule)
#              1 = usage error / nothing to scan
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib-path-rules.sh
source "${SCRIPT_DIR}/../hooks/lib-path-rules.sh"

if [ $# -eq 0 ]; then
    echo "usage: validate-plan-paths.sh <plan-file-or-dir> [...]" >&2
    exit 1
fi

FILES=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS= read -r f; do FILES+=("$f"); done < <(find "$arg" -type f -name "*.md" | sort)
    elif [ -f "$arg" ]; then
        FILES+=("$arg")
    else
        echo "not found: $arg" >&2
        exit 1
    fi
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "no .md files to scan under: $*" >&2
    exit 1
fi

# Path literals worth checking: anything containing a Scripts/ segment. Grabs
# them out of prose, tables, code fences and tree diagrams alike. Trailing
# punctuation and tree-drawing characters are stripped; a trailing / is kept so
# folder-only declarations (the exact shape of the original mistake) are checked.
extract_paths() {
    {
        # (a) full literals written inline, in tables, or in prose
        grep -ohE '[A-Za-z0-9_./-]*(_GameFolders|Assets)/Scripts/[A-Za-z0-9_./-]*' "${FILES[@]}" 2>/dev/null \
            | sed -e 's/[.,;:)]*$//'

        # (b) ASCII tree diagrams. This is NOT optional polish — the mistake that
        # motivated this script was declared ONLY as a tree in design.md, with the
        # full path never written out anywhere. Pass (a) alone would miss it.
        # Reconstructs each entry's full path from its indent depth under the
        # nearest `.../Scripts/` root line.
        awk '
          function depth(s,   i, n) { sub(/[^ │|].*$/, "", s); n = length(s); return int(n / 4) }
          /(_GameFolders|Assets)\/Scripts\/?[ \t]*$/ { inTree = 1; delete st; next }
          inTree && /^[ \t]*```/ { inTree = 0; next }
          inTree && /^[ \t]*$/   { inTree = 0; next }
          inTree && /(├──|└──|\|--|`--)/ {
              d = depth($0)
              name = $0
              sub(/^.*(├──|└──|\|--|`--)[ ]*/, "", name)
              sub(/[ \t]+([#<].*)?$/, "", name)     # trailing comments / arrows
              # A trailing "/" means FOLDER and must survive into the emitted path:
              # without it "Games/" reads as a loose file at the root of Scripts/
              # and every legal tree reports a false violation.
              isDir = (name ~ /\/$/)
              sub(/\/$/, "", name)
              if (name == "") next
              st[d] = name
              path = ""
              for (i = 0; i <= d; i++) if (st[i] != "") path = (path == "" ? st[i] : path "/" st[i])
              print "_GameFolders/Scripts/" path (isDir ? "/" : "")
          }
          !inTree { next }
        ' "${FILES[@]}" 2>/dev/null
    } | sort -u
}

VIOLATIONS=0
CHECKED=0

while IFS= read -r p; do
    [ -z "$p" ] && continue
    # A bare "…/Scripts/" with nothing after it declares no folder — skip it.
    case "$p" in */Scripts/|*/Scripts) continue ;; esac
    CHECKED=$((CHECKED + 1))
    if ! MSG=$(unity_validate_script_path "$p"); then
        VIOLATIONS=$((VIOLATIONS + 1))
        echo ""
        echo "VIOLATION [$VIOLATIONS] $p"
        echo "$MSG" | sed 's/^/    /'
    fi
done < <(extract_paths)

echo ""
echo "--- Plan Path Validation ---"
echo "files scanned : ${#FILES[@]}"
echo "paths checked : $CHECKED"
echo "$(unity_path_rules_summary)"

if [ "$VIOLATIONS" -gt 0 ]; then
    echo "result        : $VIOLATIONS VIOLATION(S) — the plan contradicts rules/architecture.md."
    echo ""
    echo "Do NOT proceed by 'the hook did not complain'. Either fix the plan, or"
    echo "declare the exception in .claude/path-allowlist.txt + rules/architecture.md."
    echo "Show this block at SCOPE_GATE and let the human decide."
    exit 2
fi

if [ "$CHECKED" -eq 0 ]; then
    echo "result        : NO PATHS FOUND — this is NOT a pass."
    echo "                Either the plan declares no script paths, or the extraction"
    echo "                missed them. Verify by hand before treating this as green."
    exit 0
fi

echo "result        : OK — all $CHECKED path(s) legal."
exit 0
