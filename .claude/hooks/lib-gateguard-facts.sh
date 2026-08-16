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
#        when the task text signals a rename AND the target file contains
#        [SerializeField]. Known gap, documented in the spec: a rename nobody
#        wrote into the task text is not detectable at plan time.
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

    if printf '%s\n' "$body" | grep -qiE 'rename|yeniden adlandır|eski ad|→'; then
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
