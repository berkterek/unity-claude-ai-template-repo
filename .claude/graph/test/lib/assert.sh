#!/usr/bin/env bash
# assert.sh — Test assertion helpers for verify-graphify.sh.
# Requires PASS_COUNT, FAIL_COUNT, KNOWN_FAIL_COUNT to be declared by the caller.

pass() {
  ((PASS_COUNT++)) || true
  printf "[PASS        ] %s\n" "$*"
}

fail() {
  ((FAIL_COUNT++)) || true
  printf "[FAIL        ] %s\n" "$*"
}

known_fail() {
  ((KNOWN_FAIL_COUNT++)) || true
  printf "[KNOWN_FAIL  ] %s — root: %s\n" "$1" "${2:-?}"
}

# require_nodes <count> <label> <reason-when-absent>
#
# Three-state gate for every PROJECT-MODE assertion. Returns 0 only when a real
# assertion is meaningful; the caller must `|| return`/`||` out otherwise.
#
#   no C# at all            -> SKIP    (empty/template repo; nothing to assert)
#   C# present, 0 of a kind -> KNOWN_FAIL (the project genuinely has none yet)
#   C# present, >0          -> caller asserts for real
#
# Why this exists: the project-mode checks used to be gated ONLY on UNITY_HAS_CS and
# then compared against counts calibrated to one specific repo (>=16 events, >=9
# installers, AppScope+GameScope by name). Any other real project — one that has C#
# but no VContainer wiring yet, or different scope names — got a wall of red for
# things that are legitimately absent. A test that fails on a healthy project is
# noise, and noise is how the skipped-check problem started.
#
# "0 of a kind" is deliberately KNOWN_FAIL, not PASS: absent data must stay visible.
# It is deliberately not FAIL either: absence is not a defect until the project
# actually declares one of these, and only the human knows which.
# The optional 4th arg is a SOURCE probe (an ERE matched against the project's .cs
# files). It is what keeps this gate from becoming a silencer: without it, a count of
# 0 is always excused as "the project has none", so a genuinely broken pivot — 16
# IEvent structs on disk, events[] empty in the graph — would be quietly downgraded
# from FAIL to KNOWN_FAIL. That trades a false alarm for a silent miss, which is the
# worse of the two and precisely the failure this whole exercise started from. With
# the probe, absence in the graph is only excused when the SOURCE is also absent.
require_nodes() {
  local n="${1:-0}" label="$2" reason="$3" src_re="${4:-}"
  if [[ "${UNITY_HAS_CS:-0}" -eq 0 ]]; then
    printf "[SKIP        ] %s — no C# under the builder's scan roots\n" "$label"
    return 1
  fi
  if [[ "$n" -eq 0 ]]; then
    if [[ -n "$src_re" ]] && _src_declares "$src_re"; then
      fail "$label: graph has 0 but the source declares them (pattern: $src_re) — extraction is broken"
      return 1
    fi
    known_fail "$label" "$reason"
    return 1
  fi
  return 0
}

# _src_declares <ere> — does any .cs under the builder's scan roots match?
# Uses the same roots as UNITY_HAS_CS so the two can never disagree about scope.
_src_declares() {
  local re="$1" root
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    if grep -rlE --include="*.cs" "$re" "$root" >/dev/null 2>&1; then return 0; fi
  done < <(_unity_scan_roots)
  return 1
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (expected='$expected' actual='$actual')"
  fi
}

assert_jq() {
  local file="$1" query="$2" expected="$3" label="$4"
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null || echo "<jq-error>")
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label (jq '$query' expected='$expected' actual='$actual')"
  fi
}
