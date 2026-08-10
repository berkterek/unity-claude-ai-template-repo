#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# --- Hook Audit Logging ---
_hook_log() {
    local code=$1
    local log="${HOME}/.claude/hook-audit.log"
    mkdir -p "$(dirname "$log")"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local proj; proj=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    local file="${FILE_PATH:-}"
    local status
    if [ "$code" -eq 2 ]; then status="BLOCKED"
    elif [ "$code" -eq 0 ]; then status="OK"
    else status="WARN"; fi
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-architecture-doc" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Two triggers, one subject (the per-domain ARCHITECTURE.md contract).
#   A) a .cs write into Games/Concretes/<Domain>/ whose doc is missing -> WARN
#   B) a write of an ARCHITECTURE.md itself -> validate shape, BLOCK if malformed
# Event: PostToolUse. Trigger B reads the doc's content FROM DISK; under
#        PreToolUse the file would not exist yet and the `[ -f ]` guard would
#        silently skip 100% of validation. Consequence, accepted deliberately:
#        a malformed doc lands on disk first and is then blocked as corrective
#        feedback (same contract as check-no-runtime-instantiate.sh).
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

should_skip_path "$FILE_PATH" && exit 0

# Pure ASCII headings -> plain byte comparison, no locale or Unicode
# normalization exposure.
REQUIRED_H2=("## Purpose" "## Boundary" "## How to extend" "## Gotchas")

# Fenced code blocks are stripped before counting headings: a `# comment` inside
# a ``` fence would otherwise be counted as a second H1 and spuriously block a
# perfectly legal doc.
strip_fences() { awk '/^```/{f=!f;next} !f' "$1"; }

# 'Module' is DELIBERATELY absent from this alternation. Module names are
# convention-fixed by rules/bootstrap-pattern.md and are never renamed, so
# `PlayerModule.Install` in a doc cannot rot. Do not "fix" this by adding it —
# /new-module's own generated template references [X]Module and would then
# block itself.
SYMBOL_RE='\b[A-Z][A-Za-z0-9]*(Service|Manager|Controller|Handler|Provider|View|Event|Config|Configuration|Scope|Installer)\b'

# =============================================================================
# Trigger B — the write IS an ARCHITECTURE.md
# =============================================================================
case "$FILE_PATH" in
  */ARCHITECTURE.md)
      case "$FILE_PATH" in
          *Games/Abstracts/*)
              unity_hook_block "ARCHITECTURE.md belongs at Games/Concretes/<Domain>/, never under Abstracts/.
Interface files document themselves; the intent doc lives on the Concretes side only." ;;
      esac

      case "$FILE_PATH" in *Games/Concretes/*) ;; *) exit 0 ;; esac

      TAIL=${FILE_PATH#*Games/Concretes/}
      [ "$TAIL" = "$FILE_PATH" ] && exit 0
      DOMAIN=${TAIL%%/*}

      if [ "$DOMAIN" = "$TAIL" ]; then
          unity_hook_block "ARCHITECTURE.md must live at Games/Concretes/<Domain>/ARCHITECTURE.md,
not directly under Concretes/. One doc per domain — there is no project-wide one here."
      fi

      # This guard is exactly why the hook is PostToolUse.
      [ -f "$FILE_PATH" ] || exit 0

      # awk, NOT wc -l: on a file with no trailing newline `wc -l` reports one
      # fewer, so a 41-line doc would slip past a <= 40 cap.
      LINES=$(awk 'END{print NR}' "$FILE_PATH")
      if [ "$LINES" -gt 40 ]; then
          unity_hook_block "ARCHITECTURE.md is $LINES lines; the cap is 40.
This file carries intent, not inventory. If it does not fit in 40 lines, the
domain has grown too big — split the domain, do not grow the doc.
Type inventory: /knowledge-graph"
      fi

      H1=$(strip_fences "$FILE_PATH" | grep -c '^# ')
      if [ "$H1" -ne 1 ]; then
          unity_hook_block "Exactly one H1 title line is required (found $H1).
First line should be: # <Domain>"
      fi

      if ! diff <(strip_fences "$FILE_PATH" | grep '^## ') \
                <(printf '%s\n' "${REQUIRED_H2[@]}") >/dev/null 2>&1; then
          unity_hook_block "Headings must be exactly these four, in this order:
$(printf '%s\n' "${REQUIRED_H2[@]}")
Found:
$(strip_fences "$FILE_PATH" | grep '^## ')"
      fi

      HITS=$(grep -nE "$SYMBOL_RE" "$FILE_PATH")
      if [ -n "$HITS" ]; then
          unity_hook_block "Class names rot. The voxel-blast project lost 15 of 25 architecture docs
to a single unpropagated rename — every rotted line contained a class name,
and no intent line rotted.
$HITS
Describe the SHAPE instead of the names: which layer, which folder, how it is
wired. Example for '## How to extend':
  contract interface in Abstracts/<domain>/ -> pure C# handler in
  Concretes/<domain>/ -> register in this domain's Module.Install
Concrete names on demand: /knowledge-graph implementers <interface>
('Module' is the one allowed suffix — module names never get renamed.)
Kill switch: DISABLE_HOOK_CHECK_ARCHITECTURE_DOC=1"
      fi

      exit 0 ;;
esac

# =============================================================================
# Trigger A — a .cs write into a domain whose doc is missing.
# NO domain is exempt. An earlier draft skipped Infrastructure on the aesthetic
# grounds that it "is not a real domain"; that was backwards — it hosts the
# project's most frequently confused boundary (app-lifetime vs scene-lifetime
# registration, scope vs module). Its doc is a short pointer to
# rules/bootstrap-pattern.md. Exceptions get forgotten, questioned, and
# multiplied; having none is worth more than the one doc saved.
# =============================================================================
case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac
case "$FILE_PATH" in *Games/Concretes/*) ;; *) exit 0 ;; esac

TAIL=${FILE_PATH#*Games/Concretes/}
[ "$TAIL" = "$FILE_PATH" ] && exit 0
DOMAIN=${TAIL%%/*}

# unity_hook_warn exits 0 and TERMINATES — it must be the last statement on its
# branch. This deliberately does NOT defer to check-domain-folder-structure.sh:
# that hook may be disabled, in warn mode, or gated out by the minimal profile,
# and each hook must be independently correct.
[ "$DOMAIN" = "$TAIL" ] && unity_hook_warn "No domain folder for '$FILE_PATH'.
Move it under Games/Concretes/<Domain>/ — see rules/architecture.md."

DOC="${FILE_PATH%%Games/Concretes/*}Games/Concretes/$DOMAIN/ARCHITECTURE.md"
[ -f "$DOC" ] && exit 0

unity_hook_warn "Missing $DOC
Write it: English, <= 40 lines, intent only, no class names. Exactly:

# $DOMAIN

$(printf '%s\n' "${REQUIRED_H2[@]}")

'## Boundary' is the part that earns its keep — it records what this domain must
NOT do, which is the one thing /knowledge-graph can never tell you."
