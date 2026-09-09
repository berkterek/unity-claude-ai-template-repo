#!/usr/bin/env bash
# ============================================================================
# lib-gateguard-facts.sh — single source of truth for the fact rules that used
# to live only inside gateguard.sh's write-time Guard 2.
#
# Two callers, no cache, same shape as lib-path-rules.sh:
#   scripts/validate-plan-facts.sh  — plan time, every task, before the gate
#   hooks/gateguard.sh              — write time, one path, recomputed live
#
# The plan document IS the manifest. Nothing here writes state; a plan edit is
# picked up on the very next call.
# ============================================================================

# Root under which tasks.md files are searched. Overridable for tests only.
#
# CLAUDE_PROJECT_DIR first, bare relative "docs" only as a last resort — the
# same fix already applied to _lib.sh's _resolve_state_dir() and
# lib-path-rules.sh's unity_path_allowlist_file() (both 2026-08-29), and missed
# here. A bare relative root resolves against the CALLER's cwd, and a subagent's
# tool-execution cwd is not guaranteed to be the repo root. When it is not,
# `find docs` matches nothing and unity_find_task_line returns empty for a path
# the plan DOES declare.
#
# That failure is silent and it is the worst possible direction: coverage is the
# ONLY door gateguard.sh leaves open to a subagent (its retry branch is depth-0
# only), while guard-pipeline-direct-work.sh simultaneously blocks the Director.
# So a cwd that is merely different deadlocks the whole pipeline, and reports it
# as "no task declares this path" — pointing at the plan, which is correct.
# Measured 2026-09-07 against a real plan whose tasks were properly declared:
# COVERED from the repo root, NOT COVERED from anywhere else, same input.
if [ -z "${UNITY_PLAN_ROOT:-}" ] \
   && [ -n "${CLAUDE_PROJECT_DIR:-}" ] \
   && [ -d "$CLAUDE_PROJECT_DIR/docs" ]; then
    UNITY_PLAN_ROOT="$CLAUDE_PROJECT_DIR/docs"
fi
UNITY_PLAN_ROOT="${UNITY_PLAN_ROOT:-docs}"

# UNITY_PLAN_FILES — OPTIONAL explicit corpus, newline-separated file list.
#
# When non-empty it REPLACES the UNITY_PLAN_ROOT find entirely: only these
# files are searched for declaring task lines.
#
# Why it exists: validate-plan-facts.sh is HANDED a document. Before this
# existed it collected task PATHS from its argument but pulled task BODIES
# from whatever tasks.md happened to live under UNITY_PLAN_ROOT — so a human
# approving at the gate read a receipt sourced from a document they were not
# looking at, and a same-path task elsewhere in the tree could silently
# supply the Callers:/Wiring: fields the argument's own task omitted.
#
# The three write-time hooks deliberately do NOT set this: they receive one
# path being written and no document, so "search every plan under the root"
# is the correct corpus for them.
UNITY_PLAN_FILES="${UNITY_PLAN_FILES:-}"

# unity_plan_task_files — the corpus to search: the explicit list when the
# caller supplied one, otherwise every plan tasks.md with templates excluded.
unity_plan_task_files() {
    if [ -n "${UNITY_PLAN_FILES:-}" ]; then
        printf '%s\n' "$UNITY_PLAN_FILES"
        return 0
    fi
    find "$UNITY_PLAN_ROOT" -name 'tasks.md' -not -path '*/_templates/*' 2>/dev/null | sort
}

# unity_plan_root_status — 0 = the corpus is resolvable, 1 = it is not.
#
# Exists because the failure it names is otherwise INVISIBLE and points at the
# wrong place: an unresolvable root makes `find` match nothing, so every path
# reads as "no task declares this" — a verdict about the plan, delivered when
# the plan was never opened. That is what made a cwd bug read as a planning
# defect for a full session. The cwd fix above makes this rare; this makes it
# self-reporting when it does happen.
#
# An explicit UNITY_PLAN_FILES corpus is always ok: the caller was handed the
# documents, so there is no root to resolve.
unity_plan_root_status() {
    if [ -n "${UNITY_PLAN_FILES:-}" ]; then
        echo "ok (explicit corpus)"
        return 0
    fi
    if [ -d "$UNITY_PLAN_ROOT" ]; then
        echo "ok (${UNITY_PLAN_ROOT})"
        return 0
    fi
    echo "PLAN ROOT NOT FOUND: ${UNITY_PLAN_ROOT}"
    return 1
}

# unity_find_task_line <script-path>
#
# Emits the declaring task line plus its indented body, or nothing.
# Suffix matching runs both ways so an absolute write-time path matches a
# repo-relative plan entry. Basename-only matching is deliberately absent:
# two domains may hold a same-named file, and a loose match would let an
# undeclared file ride through on a declared one's task.
unity_find_task_line() {
    local target="$1"
    [ -n "$target" ] || return 0

    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        awk -v target="$target" '
          function is_match(p) {
              if (p == target) return 1
              # target ends with p  (plan is repo-relative, target absolute) —
              # anchored: the char before the matched suffix must be a "/",
              # otherwise "OtherConcretes/..." would falsely match "Concretes/...".
              if (length(target) > length(p) && substr(target, length(target) - length(p) + 1) == p) {
                  if (substr(target, length(target) - length(p), 1) == "/") return 1
                  return 0
              }
              # p ends with target  (plan absolute, target repo-relative) — same anchor.
              if (length(p) > length(target) && substr(p, length(p) - length(target) + 1) == target) {
                  if (substr(p, length(p) - length(target), 1) == "/") return 1
                  return 0
              }
              return 0
          }
          /^[[:space:]]*```/ { fence = !fence; next }
          fence && capturing { next }
          fence { next }
          /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {
              if (capturing) exit
              if (match($0, /`[^`]*\.(cs|asmdef)`/)) {
                  p = substr($0, RSTART + 1, RLENGTH - 2)
                  if (is_match(p)) { capturing = 1; print; next }
              }
              next
          }
          capturing { print }
        ' "$f"
    done < <(unity_plan_task_files)
}

# unity_task_mode <script-path> — "new" if the path is absent from disk, else "edit".
#
# Never declared in the plan: this is the same IS_WRITE test gateguard.sh already
# performs, so there is nothing for an author to get wrong. The plan-internal
# rule (an earlier task in the same plan created it, so a later one is an edit)
# lives in validate-plan-facts.sh, which is the only caller that iterates tasks
# in order.
unity_task_mode() {
    [ -f "$1" ] && echo "edit" || echo "new"
}

# _unity_has_field <body> <FieldName> — non-empty "- FieldName: value" sub-bullet?
_unity_has_field() {
    printf '%s\n' "$1" | grep -qE "^[[:space:]]*-[[:space:]]*$2:[[:space:]]*[^[:space:]]"
}

# unity_validate_task_facts <script-path> <new|edit>
#
# 0 = pass. 2 = fail, with a one-line reason on stdout.
#
# NEW  : Callers: and Wiring: are both required. Files under Tests/ are exempt —
#        the question is structurally empty for them (no callers, no wiring).
# EDIT : fields are not required. FormerlySerializedAs: becomes required only
#        when the task's TITLE LINE signals a rename AND the target file contains
#        [SerializeField]. Known gap, documented in the spec: a rename nobody
#        wrote into the task title is not detectable at plan time.
unity_validate_task_facts() {
    local target="$1" mode="$2" body
    body=$(unity_find_task_line "$target")

    if [ -z "$body" ]; then
        echo "no task in any tasks.md declares this path"
        return 2
    fi

    case "$target" in
        */Tests/*) return 0 ;;
    esac

    if [ "$mode" = "new" ]; then
        _unity_has_field "$body" "Callers" || { echo "task declares no 'Callers:' field"; return 2; }
        _unity_has_field "$body" "Wiring"  || { echo "task declares no 'Wiring:' field";  return 2; }
        return 0
    fi

    # Rename detection reads the task's TITLE LINE ONLY, and no longer treats "→"
    # as a signal. Both narrowings fix the same false positive, measured 2026-09-09:
    # the body capture includes every sub-bullet, and this project's own task
    # template mandates a `Wiring:` field shaped
    #   Wiring: registered in `XModule.cs` via `Install()` → `Register<X>()...`
    # so the arrow alternative matched the template's own required field. Result:
    # EVERY edit task written from the template, targeting a file that contains
    # [SerializeField], demanded FormerlySerializedAs — not an edge case, the
    # default shape. The arrow is ordinary prose punctuation in this repo, never a
    # rename signal. Restricting to the title line closes the second half: an
    # acceptance criterion mentioning an unrelated rename ("level_1.npy temporarily
    # renamed") describes the test setup, not a field rename, and a field rename is
    # by definition what the task DOES — which is the title.
    #
    # Why this survived: the rule fires only at mode=edit, and plan-time validation
    # runs before any target exists, so every task is `new` there. It first fires
    # during the fix pass — after the file is on disk — which made a newly created
    # file uneditable by its own creation. Same class as the PreToolUse
    # effective-content bug in CLAUDE.md, one layer up. All four existing bats tests
    # used a body whose title was a real field rename, so the branch was green with
    # this hole in it; the arrow case now has its own regression guard.
    if printf '%s\n' "$body" | head -n 1 | grep -qiE 'rename|yeniden adlandır|eski ad'; then
        if grep -q '\[SerializeField\]' "$target" 2>/dev/null; then
            _unity_has_field "$body" "FormerlySerializedAs" || {
                echo "task signals a rename on a file containing [SerializeField] but declares no 'FormerlySerializedAs:' field — without it every configured value in every scene, prefab and ScriptableObject silently resets to default"
                return 2
            }
        fi
    fi
    return 0
}

# unity_gateguard_facts_summary — one-line provenance receipt.
# Printed by validate-plan-facts.sh only. The write-time hooks compute the same
# rules but emit their own block-message wording instead of calling this.
unity_gateguard_facts_summary() {
    echo "rules         : lib-gateguard-facts.sh (plan root: ${UNITY_PLAN_ROOT})"
}
