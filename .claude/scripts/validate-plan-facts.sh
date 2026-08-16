#!/usr/bin/env bash
# ============================================================================
# validate-plan-facts.sh — PLAN-TIME fact validation.
#
# Runs the SAME rules the write-time hook uses (.claude/hooks/lib-gateguard-facts.sh)
# over every task in a plan, before SCOPE_GATE.
#
# Why this exists: the five facts gateguard.sh demanded at write time are all
# properties of the plan, answerable before any agent spawns. Demanding them at
# write time made them unanswerable inside a subagent, which deadlocked
# /orchestrate. See docs/superpowers/specs/2026-08-16-plan-time-fact-gate-design.md
#
# Usage:
#   .claude/scripts/validate-plan-facts.sh docs/modules/02-players/
#   .claude/scripts/validate-plan-facts.sh docs/.../tasks.md
#
# Exit codes:  0 = every task passed (prints a receipt)
#              2 = at least one violation (prints each, with the reason)
#              1 = usage error / nothing to scan
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib-gateguard-facts.sh
source "${SCRIPT_DIR}/../hooks/lib-gateguard-facts.sh"

# Repo root, anchored via SCRIPT_DIR — NOT the invoking shell's cwd. The
# duplicate-type check below used to grep relative "Assets/ _GameFolders/"
# paths: invoked from any directory other than the repo root, those silently
# resolved to nothing and the check ran with zero visible effect. Anchoring
# here means the check behaves the same regardless of where this script is
# invoked from. Overridable for tests only (UNITY_FACTS_REPO_ROOT), so the
# on-disk *Module.cs fallback and the duplicate-type check can be exercised
# against a disposable fixture tree instead of this repo's real source.
REPO_ROOT="${UNITY_FACTS_REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

# Candidate .cs files under the search roots — computed once, used by both
# the duplicate-type check's receipt line (so a human can tell "checked but
# found nothing to compare against" apart from "actually compared") and
# available for reuse.
CANDIDATE_CS_COUNT=$(find "${REPO_ROOT}/Assets" "${REPO_ROOT}/_GameFolders" -type f -name '*.cs' 2>/dev/null | wc -l | tr -d ' ')

if [ $# -eq 0 ]; then
    echo "usage: validate-plan-facts.sh <plan-file-or-dir> [...]" >&2
    exit 1
fi

FILES=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS= read -r f; do FILES+=("$f"); done < <(find "$arg" -type f -name 'tasks.md' | sort)
    elif [ -f "$arg" ]; then
        FILES+=("$arg")
    else
        echo "not found: $arg" >&2
        exit 1
    fi
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "no tasks.md to scan under: $*" >&2
    exit 1
fi

# Restricted to checkbox-prefixed task-declaring lines, NOT the whole file —
# a blanket file-wide grep would also match backtick .cs mentions inside a
# Callers: sub-bullet, letting an invented caller vacuously satisfy the
# "is this path declared as a task in this plan" check against its own
# mention instead of a real task declaration.
ALL_TASK_PATHS=$(grep -hoE '^[[:space:]]*-[[:space:]]*\[[ xX]\].*`[^`]*\.cs`' "${FILES[@]}" 2>/dev/null \
                    | grep -oE '`[^`]*\.cs`' | tr -d '`' | sort -u)

# .asmdef literals declared by a checkbox task line in the scanned plan — NOT
# a blanket file-wide grep. A prose sentence that merely MENTIONS an .asmdef
# path (e.g. "no task creates Foo.asmdef yet") is not a plan commitment to
# create it; only a checkbox task line is. Without this restriction, an
# incidental backtick mention anywhere in the document is a working escape
# hatch around the owning-asmdef check below.
ALL_ASMDEF_PATHS=$(grep -hoE '^[[:space:]]*-[[:space:]]*\[[ xX]\].*`[^`]*\.asmdef`' "${FILES[@]}" 2>/dev/null \
                    | grep -oE '`[^`]*\.asmdef`' | tr -d '`' | sort -u)

VIOLATIONS=0; CHECKED=0; NEW=0; EDIT=0; EXEMPT=0; DUP_CHECKED=0
CALLERS_OK=0; CALLERS_PRESENCE=0; WIRING_SVC_OK=0; WIRING_PRESENCE=0
SEEN_PATHS=""

_violation() {
    VIOLATIONS=$((VIOLATIONS + 1))
    echo ""
    echo "VIOLATION [$VIOLATIONS] $1"
    echo "    $2"
}

# Iterate task-declaring lines in document order so the plan-internal
# "an earlier task created it" rule can classify later occurrences as edits.
while IFS= read -r p; do
    [ -z "$p" ] && continue
    CHECKED=$((CHECKED + 1))
    BODY=$(unity_find_task_line "$p")
    BASE=$(basename "$p" .cs)

    case "$p" in
        */Tests/*) EXEMPT=$((EXEMPT + 1)); continue ;;
    esac

    # new vs edit: absent from disk AND not created by an earlier task
    MODE=$(unity_task_mode "$p")
    if [ "$MODE" = "new" ] && printf '%s\n' "$SEEN_PATHS" | grep -qxF "$p"; then
        MODE="edit"
    fi
    SEEN_PATHS="${SEEN_PATHS}
${p}"
    [ "$MODE" = "new" ] && NEW=$((NEW + 1)) || EDIT=$((EDIT + 1))

    if ! MSG=$(unity_validate_task_facts "$p" "$MODE"); then
        _violation "$p" "$MSG"
        continue
    fi
    [ "$MODE" = "edit" ] && continue

    # --- automatic check #2: duplicate type ---
    # Plan-time only. At write time the file being created IS the match, so this
    # check deliberately lives here and not in the library. Anchored to
    # REPO_ROOT (not cwd) so it behaves the same regardless of invocation dir.
    DUP_CHECKED=$((DUP_CHECKED + 1))
    if DUP=$(grep -rln "class ${BASE}\b" "${REPO_ROOT}/Assets/" "${REPO_ROOT}/_GameFolders/" 2>/dev/null | grep -v "/${BASE}.cs$" | head -1); then
        if [ -n "$DUP" ]; then
            _violation "$p" "a type named ${BASE} already exists in ${DUP} — confirm no existing type serves this purpose"
            continue
        fi
    fi

    # --- automatic check #3: owning asmdef ---
    ASMDEF=""; DIR_WALK=$(dirname "$p")
    while [ "$DIR_WALK" != "." ] && [ "$DIR_WALK" != "/" ]; do
        FOUND=$(find "$DIR_WALK" -maxdepth 1 -name '*.asmdef' 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then ASMDEF="$FOUND"; break; fi
        DIR_WALK=$(dirname "$DIR_WALK")
    done
    # No .asmdef on disk yet — fall back to a plan-declared one. A task in the
    # SAME plan may declare the .asmdef this file will land in; that assembly
    # doesn't exist on disk at plan time, so the disk walk above can never see
    # it. Accept it when its directory is an ancestor of (or equal to) the
    # task path's own directory — never a bypass, just the plan-time source
    # of truth the disk walk is blind to. Iterated line-by-line (not word
    # splitting) so a path containing whitespace is never silently mangled.
    if [ -z "$ASMDEF" ]; then
        P_DIR=$(dirname "$p")
        while IFS= read -r ad; do
            [ -z "$ad" ] && continue
            AD_DIR=$(dirname "$ad")
            case "$P_DIR" in
                "$AD_DIR"|"$AD_DIR"/*) ASMDEF="$ad"; break ;;
            esac
        done <<< "$ALL_ASMDEF_PATHS"
    fi

    if [ -z "$ASMDEF" ]; then
        _violation "$p" "no .asmdef owns this location — the file would land in no assembly"
        continue
    fi

    # --- Callers: cross-verification ---
    # Only a backticked .cs token that actually resolves — against disk or
    # against another task's declared path — counts as cross-verified. A
    # task-ID reference ("Callers: T005"), prose, or an empty value asserts
    # nothing a machine can check, and must NOT be counted as verified —
    # doing so is exactly the over-reporting this check exists to prevent.
    CALLER_LINE=$(printf '%s\n' "$BODY" | grep -E '^[[:space:]]*-[[:space:]]*Callers:' | head -1)
    CALLER_CS_TOKENS=$(printf '%s\n' "$CALLER_LINE" | grep -oE '`[^`]*\.cs`' | tr -d '`')
    if [ -z "$CALLER_CS_TOKENS" ]; then
        CALLERS_PRESENCE=$((CALLERS_PRESENCE + 1))
    else
        CALLER_BAD=""
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            # Exact match only — a substring match (e.g. grep -F) would let a
            # declared task path like ".../PlayerController.cs" satisfy a
            # caller literally written as "Controller.cs". Excludes the
            # task's OWN path from the pool it resolves against — without
            # this, ALL_TASK_PATHS contains $p itself, so a task naming
            # itself as its own caller would vacuously resolve against its
            # own declaration instead of asserting a real caller relationship.
            if [ ! -f "$c" ] && ! printf '%s\n' "$ALL_TASK_PATHS" | grep -vxF "$p" | grep -qxF "$c"; then
                CALLER_BAD="$c"; break
            fi
        done <<< "$CALLER_CS_TOKENS"
        if [ -n "$CALLER_BAD" ]; then
            _violation "$p" "declared caller ${CALLER_BAD} exists neither on disk nor as a task in this plan"
            continue
        fi
        CALLERS_OK=$((CALLERS_OK + 1))
    fi

    # --- Wiring: cross-verification (services only) ---
    # Both branches resolve the SPECIFIC module NAMED in this task's own
    # Wiring: text — never a blanket "does ANY Module.cs exist anywhere"
    # check. Unifying on a single extracted identifier closes three related
    # holes at once (all were forms of the same "unanchored/untargeted
    # matching" defect):
    #   1. Substring matching let a named-but-nonexistent module (e.g.
    #      "SuperGhostModule" when only "GhostModule.cs" exists) satisfy the
    #      check via unrelated substring overlap.
    #   2. Branch (a) alone let ANY *Module.cs checkbox task anywhere in the
    #      plan — including an unrelated domain's — cross-verify EVERY
    #      *Service in the plan, regardless of what that service's own
    #      Wiring: text actually said.
    #   3. Branch (b) alone let an on-disk module from a DIFFERENT domain
    #      (e.g. AudioModule.cs) satisfy an unrelated service (e.g. a Ghosts
    #      service) purely because some *Module.cs existed somewhere on disk.
    #
    # Procedure:
    #   1. Extract ONE module identifier from the Wiring: line — either a
    #      backticked `<Name>Module.cs` literal, or a bare <Name>Module word
    #      token (word-boundary anchored: "AppModules" never matches, since
    #      \b fails between "Module" and the trailing "s").
    #   2. No identifier extractable (e.g. "TBD", "registered somewhere") →
    #      presence-only, NOT a violation. The Wiring: text asserts nothing
    #      a machine can check, so nothing is claimed either way.
    #   3. An identifier WAS extracted → it must resolve, via EITHER:
    #        (a) a *Module.cs declared by a checkbox task other than the
    #            service's own task, whose basename equals the identifier, OR
    #        (b) a *Module.cs that exists ON DISK whose basename equals the
    #            identifier — normal per bootstrap-pattern.md once a domain's
    #            first module has landed: later services in that domain
    #            register in the EXISTING [Domain]Module.cs, with no Module
    #            task in the plan at all.
    #      Resolving via either is cross-verified. Naming an identifier that
    #      resolves via NEITHER is a violation — the plan asserts a specific
    #      registration target that provably does not exist.
    #
    # AppModules.cs deliberately never satisfies (a) or (b): it ends in
    # "Modules.cs" (plural), not "Module.cs" — the bare-word extraction's
    # \b anchor never yields "AppModule" as an identifier from "AppModules",
    # and neither branch's basename comparison can equal "AppModules" against
    # an identifier that (by construction) always ends in singular "Module".
    case "$BASE" in
        *Service)
            WIRE_LINE=$(printf '%s\n' "$BODY" | grep -E '^[[:space:]]*-[[:space:]]*Wiring:' | head -1)

            MODULE_ID=$(printf '%s\n' "$WIRE_LINE" | grep -oE '`[A-Za-z0-9_]*Module\.cs`' | head -1 | tr -d '`')
            MODULE_ID=${MODULE_ID%.cs}
            if [ -z "$MODULE_ID" ]; then
                MODULE_ID=$(printf '%s\n' "$WIRE_LINE" | grep -oE '\b[A-Za-z0-9_]*Module\b' | head -1)
            fi

            if [ -z "$MODULE_ID" ]; then
                # Wiring: names no resolvable module at all — nothing to
                # cross-verify, but also nothing false being claimed.
                WIRING_PRESENCE=$((WIRING_PRESENCE + 1))
            else
                SVC_WIRING_OK=0
                # (a) a checkbox task elsewhere in the plan declaring exactly
                # this module's path — matched on basename, not substring.
                while IFS= read -r tp; do
                    [ -z "$tp" ] && continue
                    if [ "$(basename "$tp" .cs)" = "$MODULE_ID" ]; then
                        SVC_WIRING_OK=1
                        break
                    fi
                done < <(printf '%s\n' "$ALL_TASK_PATHS" | grep -vxF "$p")

                # (b) that same module exists on disk — matched on basename,
                # not substring, so an unrelated on-disk module (a different
                # domain, or AppModules.cs) can never satisfy a different name.
                if [ "$SVC_WIRING_OK" -ne 1 ]; then
                    while IFS= read -r mdf; do
                        [ -z "$mdf" ] && continue
                        if [ "$(basename "$mdf" .cs)" = "$MODULE_ID" ]; then
                            SVC_WIRING_OK=1
                            break
                        fi
                    done < <(find "${REPO_ROOT}/Assets" "${REPO_ROOT}/_GameFolders" -type f -name '*Module.cs' 2>/dev/null)
                fi

                if [ "$SVC_WIRING_OK" -eq 1 ]; then
                    WIRING_SVC_OK=$((WIRING_SVC_OK + 1))
                else
                    _violation "$p" "a *Service with no Module.Install task anywhere in this plan — state where it is registered"
                    continue
                fi
            fi
            ;;
        *) WIRING_PRESENCE=$((WIRING_PRESENCE + 1)) ;;
    esac
done < <(grep -hoE '^[[:space:]]*-[[:space:]]*\[[ xX]\].*`[^`]*\.cs`' "${FILES[@]}" 2>/dev/null \
            | grep -oE '`[^`]*\.cs`' | tr -d '`')

echo ""
echo "--- Plan Facts Validation ---"
echo "files scanned  : ${#FILES[@]}"
echo "tasks checked  : $CHECKED   (new: $NEW, edit: $EDIT, test-exempt: $EXEMPT)"
echo "duplicate-type : checked $DUP_CHECKED task(s) against ${REPO_ROOT} (${CANDIDATE_CS_COUNT} candidate file(s) found)"
echo "cross-verified : callers $CALLERS_OK, wiring $WIRING_SVC_OK service task(s)"
echo "presence-only  : callers $CALLERS_PRESENCE (task-ID/prose references — NOT machine-verified)"
echo "presence-only  : wiring $WIRING_PRESENCE (non-service — NOT machine-verified)"
echo "$(unity_gateguard_facts_summary)"

if [ "$VIOLATIONS" -gt 0 ]; then
    echo "result         : $VIOLATIONS VIOLATION(S) — the plan cannot satisfy the write-time gate."
    echo ""
    echo "Fix the plan, not the hook. Show this block at SCOPE_GATE and let the human decide."
    exit 2
fi

if [ "$CHECKED" -eq 0 ]; then
    echo "result         : NO TASKS FOUND — this is NOT a pass."
    echo "                 Either the plan declares no script paths, or the parser"
    echo "                 missed them. Verify by hand before treating this as green."
    exit 0
fi

echo "result         : OK — all $CHECKED task(s) pass."
exit 0
