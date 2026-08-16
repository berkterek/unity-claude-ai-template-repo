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

# unity_plan_task_files — every plan tasks.md, templates excluded.
unity_plan_task_files() {
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
          function is_match(p,   t) {
              if (p == target) return 1
              # target ends with p  (plan is repo-relative, target absolute)
              if (length(target) > length(p) && substr(target, length(target) - length(p) + 1) == p) return 1
              # p ends with target  (plan absolute, target repo-relative)
              if (length(p) > length(target) && substr(p, length(p) - length(target) + 1) == target) return 1
              return 0
          }
          /^[[:space:]]*```/ { fence = !fence; next }
          fence && capturing { next }
          fence { next }
          /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {
              if (capturing) exit
              if (match($0, /`[^`]*\.cs`/)) {
                  p = substr($0, RSTART + 1, RLENGTH - 2)
                  if (is_match(p)) { capturing = 1; print; next }
              }
              next
          }
          capturing { print }
        ' "$f"
    done < <(unity_plan_task_files)
}
