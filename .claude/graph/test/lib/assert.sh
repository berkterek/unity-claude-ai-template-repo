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
