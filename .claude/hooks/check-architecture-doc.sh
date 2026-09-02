#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
# unity_path_is_allowlisted — the third arch-doc scope is derived from
# path-allowlist.txt rather than hardcoded here, so the two never drift apart.
source "${SCRIPT_DIR}/lib-path-rules.sh"

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
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Two triggers, one subject (the per-domain ARCHITECTURE.md contract).
#   A) a .cs write into Games/Concretes/<Domain>/ — or into a _Framework/<Subfolder>/
#      that owns an .asmdef — whose doc is missing -> WARN
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

# _arch_doc_scope <file-path>
#
# Echoes "<scope-prefix>|<unit-kind>" for a path this hook governs, or nothing.
# THIS is the mechanism — there is no marker to register and no function to add a
# symbol to. Adding a scope means adding a line to path-allowlist.txt (for a
# project folder) or a branch to the case below (for a framework-wide one).
#
# Three scopes, one contract:
#   Games/Concretes/<Domain>/   FEATURE boundary  — a convention, enforced by review
#   _Framework/<Subfolder>/     ASSEMBLY boundary — a physical fact: .asmdef flags
#                               (noEngineReferences, platform filters) are per-folder
#                               and unenforceable per-file, so the folder IS the boundary
#   Scripts/<Allowlisted>/      ASSEMBLY boundary — same reason, which is exactly what
#                               path-allowlist.txt already requires as the grounds for an
#                               entry ("the folder needs its own .asmdef")
#
# The third scope is DERIVED from path-allowlist.txt rather than hardcoded. A project
# that declares a top-level folder there gets the arch-doc gate on it for free, on the
# same day, with no hook edit — and no second list can drift out of step with the first.
_arch_doc_scope() {
    local path="$1" first
    case "$path" in
        *Games/Concretes/*) echo "Games/Concretes/|domain"  ; return 0 ;;
        *_Framework/*)      echo "_Framework/|subfolder"    ; return 0 ;;
    esac

    # Scripts/<X>/... where Scripts/<X> is a declared exception.
    case "$path" in
        *Scripts/*) ;;
        *) return 1 ;;
    esac
    first=${path#*Scripts/}
    first=${first%%/*}
    [ -n "$first" ] || return 1
    case "$first" in Games|Tests|Editors) return 1 ;; esac
    if unity_path_is_allowlisted "Scripts/$first" 2>/dev/null; then
        echo "Scripts/$first/|assembly"
        return 0
    fi
    return 1
}

# _arch_doc_unit <scope-prefix> <file-path>
#
# The documented unit is the NEAREST directory at or below the scope root that owns an
# .asmdef. That one sentence covers both real layouts without guessing: a container of
# assemblies (_Framework/, or a Scripts/ folder split into per-domain assemblies) yields
# the subfolder; a folder that is itself one assembly yields the folder. Echoes the unit
# path relative to the scope root, or nothing when no .asmdef is found — in which case
# there is no assembly boundary here and the hook has nothing to ask for.
#
# Games/Concretes/ does NOT use this: its unit is the domain folder by convention, and
# domains do not own .asmdefs.
_arch_doc_unit() {
    local scope="$1" path="$2" root tail candidate rel
    root="${path%%$scope*}$scope"
    tail=${path#*$scope}
    [ "$tail" = "$path" ] && return 1

    rel=""
    candidate="${root%/}"
    if [ -n "$(find "$candidate" -maxdepth 1 -name '*.asmdef' -print -quit 2>/dev/null)" ]; then
        echo ""            # the scope root is itself the assembly
        return 0
    fi
    rel=${tail%%/*}
    [ "$rel" = "$tail" ] && return 1
    if [ -n "$(find "${root}${rel}" -maxdepth 1 -name '*.asmdef' -print -quit 2>/dev/null)" ]; then
        echo "$rel"
        return 0
    fi
    return 1
}

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

      # Two scopes, one contract. A Games/Concretes/<Domain>/ doc records a FEATURE
      # boundary; a _Framework/<Subfolder>/ doc records an ASSEMBLY boundary, which is
      # stricter — .asmdef flags (noEngineReferences, platform filters) are per-folder and
      # unenforceable per-file, so the folder IS the boundary. Same four headings, same cap.
      # Before this, a _Framework doc fell through to `exit 0`: silently accepted and never
      # validated. That is worse than a block — nothing told the author the doc was unchecked.
      _SCOPE_INFO=$(_arch_doc_scope "$FILE_PATH") || exit 0
      SCOPE=${_SCOPE_INFO%%|*}
      UNIT_KIND=${_SCOPE_INFO##*|}

      TAIL=${FILE_PATH#*$SCOPE}
      [ "$TAIL" = "$FILE_PATH" ] && exit 0
      DOMAIN=${TAIL%%/*}

      if [ "$DOMAIN" = "$TAIL" ]; then
          # A doc sitting directly at the scope root is legal in exactly one case: the
          # root IS the assembly. Trigger A already resolves that case and warns for a
          # root doc there — so without this check the two triggers CONTRADICT: the warn
          # demands a file the validator refuses, and the only way to satisfy one is to
          # violate the other. Found by running the two against the same tree. Both
          # triggers now answer with _arch_doc_unit, so they cannot disagree by
          # construction rather than by inspection.
          #
          # _Framework/ and Games/Concretes/ still block a root doc, and for the same
          # reason rather than a special case: neither root owns an .asmdef. They are
          # containers of independent boundaries, so one doc there would speak for all
          # of them.
          if [ "$UNIT_KIND" != "domain" ] && \
             [ -n "$(find "${FILE_PATH%/*}" -maxdepth 1 -name '*.asmdef' -print -quit 2>/dev/null)" ]; then
              :   # root doc, and the root really is one assembly — fall through and validate
          else
              unity_hook_block "ARCHITECTURE.md must live at ${SCOPE}<$UNIT_KIND>/ARCHITECTURE.md,
not directly under ${SCOPE}. One doc per $UNIT_KIND — there is no project-wide one here.
${SCOPE} owns no .asmdef of its own, so it is a container of independent boundaries,
not a boundary itself; a root doc would speak for all of them.
(A scope root that DOES own an .asmdef is one assembly, and a root doc there is correct.)"
          fi
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
_SCOPE_INFO=$(_arch_doc_scope "$FILE_PATH") || exit 0
SCOPE=${_SCOPE_INFO%%|*}
UNIT_KIND=${_SCOPE_INFO##*|}

TAIL=${FILE_PATH#*$SCOPE}
[ "$TAIL" = "$FILE_PATH" ] && exit 0
DOMAIN=${TAIL%%/*}

# Assembly scopes resolve the unit from the .asmdef, so a folder that is not a boundary is
# exempt automatically — Installers/ holds a single interface, owns no .asmdef, and belongs
# to whichever assembly picks it up. Derived rather than skip-listed, so a folder that later
# GAINS an .asmdef starts being asked for a doc on the day it becomes a boundary.
# Games/Concretes/ keeps its by-convention domain unit; domains own no .asmdef.
if [ "$UNIT_KIND" != "domain" ]; then
    UNIT=$(_arch_doc_unit "$SCOPE" "$FILE_PATH") || exit 0
    if [ -n "$UNIT" ]; then
        DOMAIN="$UNIT"
    else
        # The scope root is itself the assembly: its doc sits at the root.
        DOC="${FILE_PATH%%$SCOPE*}${SCOPE}ARCHITECTURE.md"
        [ -f "$DOC" ] && exit 0
        unity_hook_warn "Missing $DOC
This folder owns an .asmdef, so it is an assembly boundary and carries one
ARCHITECTURE.md. English, <= 40 lines, intent only, no class names. Exactly:

$(printf '%s\n' "${REQUIRED_H2[@]}")"
    fi
fi

# unity_hook_warn exits 0 and TERMINATES — it must be the last statement on its
# branch. This deliberately does NOT defer to check-domain-folder-structure.sh:
# that hook may be disabled, in warn mode, or gated out by the minimal profile,
# and each hook must be independently correct.
[ "$DOMAIN" = "$TAIL" ] && unity_hook_warn "No domain folder for '$FILE_PATH'.
Move it under Games/Concretes/<Domain>/ — see rules/architecture.md."

DOC="${FILE_PATH%%$SCOPE*}$SCOPE$DOMAIN/ARCHITECTURE.md"
[ -f "$DOC" ] && exit 0

unity_hook_warn "Missing $DOC
Write it: English, <= 40 lines, intent only, no class names. Exactly:

# $DOMAIN

$(printf '%s\n' "${REQUIRED_H2[@]}")

'## Boundary' is the part that earns its keep — it records what this domain must
NOT do, which is the one thing /knowledge-graph can never tell you."
