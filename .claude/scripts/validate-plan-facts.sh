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
        # `-not -path '*/_templates/*'` mirrors unity_plan_task_files in
        # lib-gateguard-facts.sh, and must stay in step with it. The template at
        # docs/modules/_templates/tasks.md is a FORM, not a plan: its task lines
        # carry `[Domain]` placeholders that resolve to no folder and no .asmdef,
        # so scanning it yields VIOLATIONs for paths nobody ever intends to write.
        # A validator that fails on its own template teaches the human to ignore
        # its output — the one outcome a blocking gate cannot survive. An
        # explicitly named template path is still honoured (the `-f` branch
        # below): naming it is a deliberate act, walking into it is not.
        while IFS= read -r f; do FILES+=("$f"); done \
            < <(find "$arg" -type f -name 'tasks.md' -not -path '*/_templates/*' | sort)
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

# Pin the library's search corpus to EXACTLY the documents we were handed.
# Without this, unity_find_task_line re-derives its own corpus by find-ing
# UNITY_PLAN_ROOT, so task PATHS came from the argument while task BODIES came
# from some other plan in the tree — the receipt then described a document the
# human at the gate was not looking at. See UNITY_PLAN_FILES in the library.
export UNITY_PLAN_FILES
UNITY_PLAN_FILES=$(printf '%s\n' "${FILES[@]}")

# Task paths in a plan are repo-relative. Any on-disk test against them must be
# anchored to REPO_ROOT, exactly like the duplicate-type check below — resolving
# them against the invoking shell's cwd made `unity_task_mode` flip a task from
# "new" to "edit" whenever the relative path happened to exist under that cwd,
# and an "edit" short-circuits past the Callers:/Wiring: requirement entirely.
# That is the fail-open direction, so it is anchored rather than left to cwd.
_abs_repo_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s' "${REPO_ROOT}/$1" ;;
    esac
}

# _declared_subjects <ext-regex> — the subject path of every task-declaring
# line in FILES, using EXACTLY unity_find_task_line's line semantics:
#   * fenced (```) regions suppressed;
#   * checkbox-prefixed lines only;
#   * the FIRST backticked `*.cs`/`*.asmdef` token on the line is the subject.
#
# This script used to enumerate with plain greps that did neither the fence
# suppression nor the first-token restriction, so the two halves disagreed
# about what a task IS. Both directions were wrong. Fail-closed direction: a
# checkbox line quoted inside a ``` example block was enumerated as a real
# task, then immediately reported "no task declares this path" because the
# library — correctly — could not see it; that is what made every
# /create-plan-format document hard-block on its own narrative. Fail-OPEN
# direction: the same fenced examples polluted ALL_TASK_PATHS/ALL_ASMDEF_PATHS,
# so an illustrative `FooModule.cs` inside a code fence could cross-verify a
# real service's Wiring:, and an example .asmdef could satisfy a real task's
# owning-assembly check. One matcher, one answer.
_declared_subjects() {
    awk -v extre="$1" '
      # Fence state is PER FILE. The library runs one awk per file and so gets
      # this for free; this helper passes every file to a SINGLE awk, where
      # `fence` would otherwise carry across the file boundary. A plan file
      # with an odd number of ``` lines (an unterminated fence, or a nested
      # one) would then suppress every task in every FOLLOWING file — the
      # enumerator silently reports "tasks checked: 0" for them and exits 0.
      # That is the same silent fail-open this script exists to close, so the
      # reset is load-bearing, not tidiness. Only reachable with a directory
      # or multi-file argument (/plan-module, /orchestrate); /create-plan
      # passes one file and is unaffected either way.
      FNR == 1 { fence = 0 }
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {
          if (match($0, /`[^`]*\.(cs|asmdef)`/)) {
              p = substr($0, RSTART + 1, RLENGTH - 2)
              if (p ~ extre) print p
          }
      }
    ' "${FILES[@]}" 2>/dev/null
}

# Restricted to checkbox-prefixed task-declaring lines, NOT the whole file —
# a blanket file-wide grep would also match backtick .cs mentions inside a
# Callers: sub-bullet, letting an invented caller vacuously satisfy the
# "is this path declared as a task in this plan" check against its own
# mention instead of a real task declaration.
ALL_TASK_PATHS=$(_declared_subjects '\.cs$' | sort -u)

# .asmdef literals declared by a checkbox task line in the scanned plan — NOT
# a blanket file-wide grep. A prose sentence that merely MENTIONS an .asmdef
# path (e.g. "no task creates Foo.asmdef yet") is not a plan commitment to
# create it; only a checkbox task line is. Without this restriction, an
# incidental backtick mention anywhere in the document is a working escape
# hatch around the owning-asmdef check below.
ALL_ASMDEF_PATHS=$(_declared_subjects '\.asmdef$' | sort -u)

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
    P_ABS=$(_abs_repo_path "$p")

    case "$p" in
        */Tests/*) EXEMPT=$((EXEMPT + 1)); continue ;;
    esac

    # new vs edit: absent from disk AND not created by an earlier task
    MODE=$(unity_task_mode "$P_ABS")
    if [ "$MODE" = "new" ] && printf '%s\n' "$SEEN_PATHS" | grep -qxF "$p"; then
        MODE="edit"
    fi
    SEEN_PATHS="${SEEN_PATHS}
${p}"
    [ "$MODE" = "new" ] && NEW=$((NEW + 1)) || EDIT=$((EDIT + 1))

    # P_ABS, not $p: the rename/[SerializeField] branch greps the target file,
    # which is the same cwd-dependence anchored above. The two-way suffix match
    # in unity_find_task_line resolves the absolute form against the plan's
    # repo-relative declaration unchanged.
    if ! MSG=$(unity_validate_task_facts "$P_ABS" "$MODE"); then
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
            if [ ! -f "$(_abs_repo_path "$c")" ] && ! printf '%s\n' "$ALL_TASK_PATHS" | grep -vxF "$p" | grep -qxF "$c"; then
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
    # `Wiring:` is free prose. Three successive review rounds each closed one
    # instance of the same defect class — the receipt printing "cross-verified"
    # for a check that never resolved anything — and each time an adversarial
    # pass found another of identical shape, because the script was trying to
    # infer "the asserted target module" out of English by heuristic:
    #   - "modeled on AudioModule, but actually registered in GhostModule"
    #     resolved the FIRST-mentioned token, with no notion of which mention
    #     is the asserted target.
    #   - "NOT registered in GhostModule — TBD" and "TBD (compare GhostModule)"
    #     both booked as green: an explicit negation and an explicit TBD.
    # A hedge-word blacklist is unbounded — the next wording nobody listed
    # would break it again. So this stops parsing prose entirely.
    #
    # THE RULE: a *Service task earns cross-verified wiring ONLY when its
    # Wiring: line contains EXACTLY ONE backticked `<Name>Module.cs` token,
    # and that named module resolves either
    #   (a) to a checkbox task in this plan other than the service's own
    #       (and NOT under a /Tests/ path — a test stub is itself exempt from
    #       every check in this script and must never satisfy a production
    #       service), OR
    #   (b) to a file existing on disk.
    #
    # EVERY other shape — prose with no backticked token, more than one
    # backticked module token, bare unbackticked identifiers, hedges,
    # negations — is presence-only. Not a violation: presence-only. It is a
    # legitimate declaration the machine simply did not verify, and the
    # receipt says exactly that. This flips the default so ambiguity resolves
    # to an honest under-claim; under-claiming is always acceptable in this
    # receipt, over-claiming never is.
    #
    # Exactly one token that resolves NOWHERE is still a violation: the plan
    # asserted one unambiguous, machine-checkable registration target and that
    # target provably does not exist.
    #
    # AppModules.cs satisfies neither branch, structurally rather than by a
    # special case: it ends in "Modules.cs" (plural), so the token regex —
    # which requires a singular "Module.cs" ending — never extracts it, and
    # neither branch's basename comparison can ever equal it. Per
    # bootstrap-pattern.md a service registers in a domain [Domain]Module.cs,
    # which then contributes one line to AppModules.cs; AppModules.cs itself
    # is never the registration target.
    case "$BASE" in
        *Service)
            WIRE_LINE=$(printf '%s\n' "$BODY" | grep -E '^[[:space:]]*-[[:space:]]*Wiring:' | head -1)

            MODULE_TOKENS=$(printf '%s\n' "$WIRE_LINE" | grep -oE '`[A-Za-z0-9_]*Module\.cs`' | tr -d '`')
            MODULE_TOKEN_COUNT=$(printf '%s\n' "$MODULE_TOKENS" | grep -c '[^[:space:]]')

            MODULE_ID=""
            if [ "$MODULE_TOKEN_COUNT" -eq 1 ]; then
                MODULE_ID=$(printf '%s\n' "$MODULE_TOKENS" | grep '[^[:space:]]' | head -1)
                MODULE_ID=${MODULE_ID%.cs}
            fi

            if [ -z "$MODULE_ID" ]; then
                # Zero tokens (prose/hedge/negation/bare identifier) or two or
                # more (ambiguous which one is the asserted target) — nothing
                # unambiguous to resolve, so nothing is claimed either way.
                WIRING_PRESENCE=$((WIRING_PRESENCE + 1))
            else
                SVC_WIRING_OK=0
                # (a) a checkbox task elsewhere in the plan declaring exactly
                # this module's path — matched on basename, not substring, and
                # never a /Tests/ path.
                while IFS= read -r tp; do
                    [ -z "$tp" ] && continue
                    case "$tp" in */Tests/*) continue ;; esac
                    if [ "$(basename "$tp" .cs)" = "$MODULE_ID" ]; then
                        SVC_WIRING_OK=1
                        break
                    fi
                done < <(printf '%s\n' "$ALL_TASK_PATHS" | grep -vxF "$p")

                # (b) that same module exists on disk — matched on basename,
                # not substring, so an unrelated on-disk module (a different
                # domain, or AppModules.cs) can never satisfy a different name.
                # /Tests/ is skipped here for exactly the reason it is skipped
                # in branch (a): a test stub is itself exempt from every check
                # in this script, so it can never be the evidence that a
                # production service is wired. Whether that stub is a plan task
                # or already on disk is not a semantic difference, and the
                # on-disk case is the likelier one in any repo that already has
                # test assemblies. The glob is textually identical to the
                # task-exempt glob at the top of the loop, deliberately — the
                # two must never drift apart.
                if [ "$SVC_WIRING_OK" -ne 1 ]; then
                    while IFS= read -r mdf; do
                        [ -z "$mdf" ] && continue
                        case "$mdf" in */Tests/*) continue ;; esac
                        if [ "$(basename "$mdf" .cs)" = "$MODULE_ID" ]; then
                            SVC_WIRING_OK=1
                            break
                        fi
                    done < <(find "${REPO_ROOT}/Assets" "${REPO_ROOT}/_GameFolders" -type f -name '*Module.cs' 2>/dev/null)
                fi

                if [ "$SVC_WIRING_OK" -eq 1 ]; then
                    WIRING_SVC_OK=$((WIRING_SVC_OK + 1))
                else
                    _violation "$p" "Wiring: names ${MODULE_ID}.cs — no such module exists as a task in this plan or on disk"
                    continue
                fi
            fi
            ;;
        *) WIRING_PRESENCE=$((WIRING_PRESENCE + 1)) ;;
    esac
done < <(_declared_subjects '\.cs$')

echo ""
echo "--- Plan Facts Validation ---"
echo "files scanned  : ${#FILES[@]}"
echo "tasks checked  : $CHECKED   (new: $NEW, edit: $EDIT, test-exempt: $EXEMPT)"
echo "duplicate-type : checked $DUP_CHECKED task(s) against ${REPO_ROOT} (${CANDIDATE_CS_COUNT} candidate file(s) found)"
echo "cross-verified : callers $CALLERS_OK, wiring $WIRING_SVC_OK service task(s)"
echo "presence-only  : callers $CALLERS_PRESENCE (task-ID/prose references — NOT machine-verified)"
echo "presence-only  : wiring $WIRING_PRESENCE (non-service, or no single backticked \`<Name>Module.cs\` — NOT machine-verified)"
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

# CHECKED counts every task line SEEN, including the /Tests/-exempt ones that
# returned before a single rule ran. Reporting "all $CHECKED pass" credited
# those exemptions as passes. Report only what was actually examined.
EXAMINED=$((CHECKED - EXEMPT))

if [ "$EXAMINED" -eq 0 ]; then
    echo "result         : NO TASKS EXAMINED — this is NOT a pass."
    echo "                 All $CHECKED task(s) found were /Tests/-exempt, so no"
    echo "                 rule ran against any of them. Verify by hand."
    exit 0
fi

echo "result         : OK — all $EXAMINED examined task(s) pass ($EXEMPT test-exempt, not examined)."
exit 0
