#!/usr/bin/env bash
# verify-graphify.sh — Single-script test harness for the .claude/graph/ toolchain.
# Shell-only — no Unity Editor, no C# compilation.
# Exit codes: 0 = no FAIL, 1 = at least one FAIL, 2 = prerequisite missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Auto-detect Unity project source root (nested projects resolved via unity_project_folder).
# UNITY_CONCRETES — a writable dir inside the scanned tree, for probe tests
#                   (purge_ghosts, --changed-files). Prefers Games/Concretes.
# UNITY_HAS_CS    — 1 if real C# source exists anywhere the BUILDER scans; 0 on empty repos.
#
# UNITY_HAS_CS must NOT be derived from Games/Concretes. It was, and that made the harness
# call any project whose code lives in a declared-allowlist tree an "empty template": a repo
# with 541 C# files under Scripts/Simulation/ (own .asmdef, noEngineReferences — the exact
# exception rules/architecture.md → "Adding a Top-Level Folder" sanctions) reported
# UNITY_HAS_CS=0 and silently skipped ~14 project-specific checks, i.e. half the suite, while
# still printing a green summary. Silence read as coverage.
#
# The honest definition is "does the graph have anything to index", so these roots mirror the
# ones graph-builder.py walks (its roots_cs: <assets>/_Framework and <assets>/_GameFolders/Scripts).
#
# Be precise about what this is: the list below IS a second copy, hardcoded in bash — it is not
# derived from the builder, and an earlier draft of this comment wrongly claimed it was. A second
# list is exactly how the original blind spot formed, so it is not left on trust: T0b below
# asserts the two lists agree and FAILS the suite if the builder gains or renames a root.
# Duplication with an alarm, not duplication with a promise.
_unity_assets_root() {
  local folder="."
  if [[ -f "$REPO_ROOT/.claude/project-features.json" ]]; then
    folder=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("unity_project_folder","."))' \
      "$REPO_ROOT/.claude/project-features.json" 2>/dev/null || echo ".")
  fi
  [[ "$folder" == "." ]] && echo "$REPO_ROOT/Assets" || echo "$REPO_ROOT/$folder/Assets"
}
_unity_scan_roots() {
  local assets; assets="$(_unity_assets_root)"
  printf '%s\n%s\n' "$assets/_Framework" "$assets/_GameFolders/Scripts"
}
_detect_unity_root() {
  local d
  # Preferred: the conventional Concretes/ dir.
  d=$(find "$REPO_ROOT" -maxdepth 8 -type d -name "Concretes" 2>/dev/null \
    | grep -E '_GameFolders/Scripts/Games/Concretes$' | head -1)
  # An EMPTY Games/Concretes/ is a perfectly good answer here, and requiring a .cs inside
  # was wrong: this variable's job is "a writable directory the builder scans", used by
  # purge_ghosts to drop a throwaway probe. An empty dir is arguably the better choice for
  # that — no risk of touching real source. The separate need, "an EXISTING .cs to feed
  # --changed-files", is answered by _unity_any_cs below, which searches the whole scanned
  # tree. Conflating the two is what made an empty Concretes/ starve the .cs consumers.
  if [[ -n "$d" ]]; then echo "$d"; return; fi
  # Fallback: any directory inside the scanned tree that already holds a .cs, so probe-based
  # tests still run on a project that legitimately has no Games/Concretes.
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    d=$(find "$root" -name "*.cs" 2>/dev/null | head -1)
    [[ -n "$d" ]] && { dirname "$d"; return; }
  done < <(_unity_scan_roots)
  echo ""
}
# _unity_any_cs — an EXISTING .cs anywhere the builder scans (not just Concretes/).
# Consumers that need a real file to feed --changed-files use this; consumers that need a
# place to WRITE a probe use UNITY_CONCRETES.
_unity_any_cs() {
  local root f
  if [[ -n "${UNITY_CONCRETES:-}" ]]; then
    f=$(find "$UNITY_CONCRETES" -name "*.cs" -maxdepth 3 2>/dev/null | head -1)
    [[ -n "$f" ]] && { echo "$f"; return; }
  fi
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    f=$(find "$root" -name "*.cs" 2>/dev/null | head -1)
    [[ -n "$f" ]] && { echo "$f"; return; }
  done < <(_unity_scan_roots)
  echo ""
}
UNITY_CONCRETES="$(_detect_unity_root)"
UNITY_HAS_CS=0
while IFS= read -r _root; do
  [[ -d "$_root" ]] || continue
  if find "$_root" -name "*.cs" 2>/dev/null | grep -q .; then UNITY_HAS_CS=1; break; fi
done < <(_unity_scan_roots)

PASS_COUNT=0
FAIL_COUNT=0
KNOWN_FAIL_COUNT=0

JSON_OUTPUT=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=1 ;;
  esac
done

source "$SCRIPT_DIR/lib/assert.sh"

# ── SHA tool detection ───────────────────────────────────────────────────────
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA_CMD=(shasum -a 256)
else
  echo "error: sha256sum or shasum required" >&2
  exit 2
fi
sha_of() { "${SHA_CMD[@]}" "$1" 2>/dev/null | awk '{print $1}'; }

section() { echo; echo "=== $* ==="; }

# jq_count <file> <jq-expression> — print the length of a jq query, or 0 on error.
jq_count() {
  jq "$2" "$1" 2>/dev/null || echo 0
}

# ── Prerequisite check ───────────────────────────────────────────────────────
check_prerequisites() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq required" >&2
    exit 2
  fi
  if [[ ! -f "$REPO_ROOT/.claude/graph/graph.json" ]]; then
    echo "error: graph.json not found — run /build-knowledge-graph first" >&2
    exit 2
  fi
  if ! jq empty "$REPO_ROOT/.claude/graph/graph.json" 2>/dev/null; then
    echo "error: graph.json is not valid JSON" >&2
    exit 2
  fi
}

check_prerequisites

source "$SCRIPT_DIR/lib/sandbox.sh"
sandbox_setup

WORK_GRAPH="$SCRIPT_DIR/.work/graph.json"
mkdir -p "$(dirname "$WORK_GRAPH")"

# ──────────────────────────────────────────────────────────────────────────────
# T3 — Builder flag coverage
# ──────────────────────────────────────────────────────────────────────────────
run_builder_flag_tests() {
  section "T3 — Builder Flags"

  # 1. --full + --skip-mcp + --quiet + --output
  if python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null \
     && jq empty "$WORK_GRAPH" 2>/dev/null; then
    pass "--full --skip-mcp --quiet --output produces valid JSON"
  else
    fail "--full produced invalid output"
  fi

  # 2. --incremental cache reuse — verify cache file is populated.
  # Skip on template/empty repos — no C# files means cache is trivially empty.
  python3 "$GRAPH_DIR/graph-builder.py" --incremental --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null || true
  local cache_entries
  cache_entries=$(jq_count "$GRAPH_DIR/cache/file-hashes.json" 'length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] --incremental cache — no C# under the builder's scan roots\n"
  elif [[ "$cache_entries" -gt 0 ]]; then
    pass "--incremental populates file-hashes cache ($cache_entries entries)"
  else
    fail "--incremental left cache empty (entries=$cache_entries)"
  fi

  # 3. --changed-files (single file) — use an actual .cs file from the project, or a temp one.
  local single_file
  if [[ -n "$UNITY_CONCRETES" ]]; then
    single_file=$(_unity_any_cs)
  fi
  if [[ -z "${single_file:-}" ]]; then
    # No real file — create a temp .cs file to exercise the flag
    single_file="$(mktemp /tmp/GraphifyProbe_XXXXXX.cs)"
    printf 'namespace Probe { public class GraphifyProbe {} }\n' > "$single_file"
    local _tmp_cs="$single_file"
  fi
  if python3 "$GRAPH_DIR/graph-builder.py" --incremental --changed-files "$single_file" --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null \
     && jq empty "$WORK_GRAPH" 2>/dev/null; then
    pass "--changed-files single-file build (valid JSON)"
  else
    fail "--changed-files build produced invalid JSON"
  fi
  [[ -n "${_tmp_cs:-}" ]] && rm -f "$_tmp_cs"

  # 4. --skip-mcp status
  local mcp_status
  mcp_status=$(jq -r '.codebase.mcp_extraction.status' "$WORK_GRAPH" 2>/dev/null || echo "?")
  if [[ "$mcp_status" == "skipped" ]]; then
    pass "--skip-mcp sets mcp_extraction.status=skipped"
  else
    fail "--skip-mcp status='$mcp_status' (expected 'skipped')"
  fi

  # 5. --output isolation — live graph.json must equal the sandbox backup
  local live_sha bak_sha
  live_sha=$(sha_of "$GRAPH_DIR/graph.json")
  bak_sha=$(sha_of "$SANDBOX_BACKUP_DIR/graph.json" 2>/dev/null || echo "no-bak")
  if [[ "$live_sha" == "$bak_sha" ]]; then
    pass "--output isolates writes (live graph.json untouched)"
  else
    fail "--output mutated live graph.json (live=$live_sha bak=$bak_sha)"
  fi

  # 6. --quiet suppresses stderr
  local stderr_out
  stderr_out=$(python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>&1 1>/dev/null || true)
  if [[ -z "$stderr_out" ]]; then
    pass "--quiet suppresses stderr"
  else
    fail "--quiet leaked stderr: $stderr_out"
  fi

  echo "[SKIP] --validate-with-codex requires a live Claude API call — not testable in a headless shell harness"
}

# ──────────────────────────────────────────────────────────────────────────────
# T4 — Validator rules R1–R6
# ──────────────────────────────────────────────────────────────────────────────
assert_rule_fires() {
  local fixture="$1" rule_id="$2" severity="$3" expected_exit="$4" label="$5"
  local tmp
  tmp="$(mktemp -t graph-fixture-XXXXXX.json)"
  cp "$SCRIPT_DIR/fixtures/$fixture/graph.json" "$tmp"
  bash "$GRAPH_DIR/graph-validator.sh" "$tmp" >/dev/null 2>&1
  local actual_exit=$?
  local count
  count=$(jq --arg r "$rule_id" "[.validation.${severity}s[] | select(.rule_id == \$r)] | length" "$tmp" 2>/dev/null || echo 0)
  if [[ "$count" -gt 0 && "$actual_exit" -eq "$expected_exit" ]]; then
    pass "$label ($rule_id severity=$severity exit=$actual_exit)"
  else
    fail "$label ($rule_id) — count=$count exit=$actual_exit (expected count>0 exit=$expected_exit)"
  fi
  rm -f "$tmp"
}

run_validator_tests() {
  section "T4 — Validator Rules R1–R6"
  assert_rule_fires r1_singleton             SINGLETON_DETECTED    error   1 "R1 singleton detected"
  assert_rule_fires r2_dangling_event        EVENT_DANGLING        warning 0 "R2 dangling event"
  assert_rule_fires r3_unregistered_concrete CONCRETE_UNREGISTERED warning 0 "R3 unregistered concrete"
  assert_rule_fires r4_misplaced_interface   INTERFACE_MISPLACED   error   1 "R4 misplaced interface"
  assert_rule_fires r5_unknown_asmdef_ref    ASMDEF_UNRESOLVED     error   1 "R5 unknown asmdef ref"
  assert_rule_fires r6_layer_violation       LAYER_VIOLATION       error   1 "R6 layer violation"
}

# ──────────────────────────────────────────────────────────────────────────────
# T5 — Pivot integrity
# ──────────────────────────────────────────────────────────────────────────────
run_pivot_tests() {
  section "T5 — Pivot Integrity"

  python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null || true

  local ev inst scopes
  # The old `>=16` / `>=9` thresholds were one project's inventory hard-coded as a
  # universal expectation. What is actually portable is the PIVOT: if the project
  # declares events at all, the events[] array must be populated (a pivot that
  # silently produces nothing is the real defect these tests exist to catch).
  ev=$(jq_count "$WORK_GRAPH" '.codebase.events | length')
  if require_nodes "$ev" "events pivot" "project declares no IEvent structs yet" ":[[:space:]]*IEvent\\b"; then
    pass "events pivot populated ($ev events)"
  fi

  inst=$(jq_count "$WORK_GRAPH" '.codebase.vcontainer.installers | length')
  if require_nodes "$inst" "installers count" "project has no VContainer installers/modules yet" "Install[[:space:]]*\\([[:space:]]*IContainerBuilder"; then
    pass "installers pivot populated ($inst)"
  fi

  # Scope NAMES are project convention, not a graph invariant. AppScope/GameScope is
  # this template's convention (rules/architecture.md) but a project may legitimately
  # name or stage its scopes differently, so assert the pivot works and report the
  # convention separately instead of failing on it.
  scopes=$(jq -r '[.codebase.vcontainer.scopes[].name] | tojson' "$WORK_GRAPH" 2>/dev/null || echo "[]")
  local scope_n; scope_n=$(echo "$scopes" | jq 'length' 2>/dev/null || echo 0)
  if require_nodes "$scope_n" "scopes pivot" "project declares no LifetimeScope subclasses yet" ":[^\n]*\\bLifetimeScope\\b"; then
    pass "scopes pivot populated ($scope_n): $scopes"
    if echo "$scopes" | jq -e 'index("AppScope") and index("GameScope")' >/dev/null 2>&1; then
      pass "scopes follow the AppScope+GameScope convention"
    else
      known_fail "scopes do not follow the AppScope+GameScope convention" \
                 "found $scopes — convention per rules/architecture.md, not a graph defect"
    fi
  fi

  # .last-build freshness
  if [[ -f "$GRAPH_DIR/.last-build" ]]; then
    local lb
    lb=$(cat "$GRAPH_DIR/.last-build")
    if [[ "$lb" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
      pass ".last-build is ISO-8601 ($lb)"
    else
      fail ".last-build not ISO-8601: $lb"
    fi
  else
    fail ".last-build missing"
  fi

  # Implementers pivot — BUG#1
  local impl
  impl=$(jq_count "$WORK_GRAPH" '[.codebase.classes[] | select(.implements | length > 0)] | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] implementers pivot — no C# under the builder's scan roots\n"
  elif [[ "$impl" -gt 0 ]]; then
    echo "[REGRESSION_FIXED: BUG#1] class.implements[] populated ($impl classes)" >&2
    pass "implementers pivot — BUG#1 fixed ($impl classes)"
  else
    known_fail "implementers pivot empty — BUG#1" \
               "csharp-extractor keeps 'public sealed class X' prefix in base_types"
  fi

  # MCP prefab merge — BUG#2
  cp "$SCRIPT_DIR/fixtures/mcp-extract.fresh.json" "$GRAPH_DIR/cache/mcp-extract.json"
  touch "$GRAPH_DIR/cache/mcp-extract.json"
  python3 "$GRAPH_DIR/graph-builder.py" --full --quiet --output "$WORK_GRAPH" 2>/dev/null || true
  local prefabs
  prefabs=$(jq_count "$WORK_GRAPH" '.codebase.prefabs | length')
  if [[ "$prefabs" -gt 0 ]]; then
    echo "[REGRESSION_FIXED: BUG#2] MCP prefabs merged ($prefabs)" >&2
    pass "MCP prefab merge — BUG#2 fixed ($prefabs prefabs)"
  else
    known_fail "MCP prefab merge returns 0 — BUG#2" \
               "graph-builder.sh FINAL_GRAPH never wires .codebase.prefabs from cache"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# T6 — /knowledge-graph subcommands (9)
# ──────────────────────────────────────────────────────────────────────────────
run_knowledge_graph_tests() {
  section "T6 — /knowledge-graph subcommands"

  # 1. summary
  local n_classes
  n_classes=$(jq_count "$WORK_GRAPH" '.codebase.classes | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] summary — no C# under the builder's scan roots\n"
  elif [[ "$n_classes" -ge 1 ]]; then
    pass "summary: classes=$n_classes"
  else
    fail "summary: classes=0"
  fi

  # 2. implementers — asset-agnostic: any interface with implementers must resolve
  local impl_iface n_impl
  impl_iface=$(jq -r 'first(.codebase.classes[] | select((.implements // []) | length > 0) | .implements[0]) // empty' "$WORK_GRAPH" 2>/dev/null)
  local n_iface_classes
  n_iface_classes=$(jq_count "$WORK_GRAPH" '[.codebase.classes[]? | select((.implements // []) | length > 0)] | length')
  if require_nodes "$n_iface_classes" "implementers" "no class in this project implements an interface yet" "class[^\n]*:[[:space:]]*I[A-Z]"; then
    n_impl=$(jq --arg n "$impl_iface" '[.codebase.classes[] | select((.implements // []) | index($n) != null)] | length' "$WORK_GRAPH" 2>/dev/null || echo 0)
    pass "implementers query resolves (e.g. $impl_iface → $n_impl)"
  fi

  # 3. publishers — asset-agnostic: at least one event has a resolved publisher
  local n_pub
  n_pub=$(jq_count "$WORK_GRAPH" '[.codebase.events[]? | select((.publishers // []) | length > 0)] | length')
  if require_nodes "$n_pub" "publishers" "no event in this project has a publisher yet (or the project declares no events)" "\\.Publish[[:space:]]*\\("; then
    pass "publishers query resolves ($n_pub event(s) with publishers)"
  fi

  # 4. subscribers (parseable is enough — always run, result 0 is valid) — asset-agnostic
  local n_sub
  n_sub=$(jq '[.codebase.events[]? | (.subscribers // [])[]] | length' "$WORK_GRAPH" 2>/dev/null)
  if [[ -n "$n_sub" && "$n_sub" =~ ^[0-9]+$ ]]; then
    pass "subscribers query parseable across events ($n_sub)"
  else
    fail "subscribers query did not return a number"
  fi

  # 5. registrations — asset-agnostic: at least one installer/module registered
  local n_reg
  n_reg=$(jq_count "$WORK_GRAPH" '.codebase.vcontainer.installers | length')
  if require_nodes "$n_reg" "registrations" "project has no VContainer installers/modules yet" "Install[[:space:]]*\\([[:space:]]*IContainerBuilder"; then
    pass "registrations present ($n_reg installer(s)/module(s))"
  fi

  # 6. scope-tree
  local scope_names
  scope_names=$(jq -r '[.codebase.vcontainer.scopes[].name] | tojson' "$WORK_GRAPH" 2>/dev/null || echo "[]")
  local n_scope_names; n_scope_names=$(echo "$scope_names" | jq 'length' 2>/dev/null || echo 0)
  if require_nodes "$n_scope_names" "scope-tree" "project declares no LifetimeScope subclasses yet" ":[^\n]*\\bLifetimeScope\\b"; then
    pass "scope-tree populated ($n_scope_names): $scope_names"
  fi

  # 7. prefabs — asset-agnostic: prefab list well-formed (merge coverage is in T7/T8)
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] prefabs — no C# under the builder's scan roots\n"
  else
    # Since v1.3.0 `codebase.prefabs` may be a partition REFERENCE object
    # ({"$partition": "prefabs.json"}) rather than an inline array. `jq length` on that
    # object returns 1 — its key count — so this check used to report "1 prefab, 0 named"
    # on every partitioned graph, i.e. every graph built since v1.3.0. It never surfaced
    # because it only runs when UNITY_HAS_CS=1, which the old Concretes-only detection
    # made false on the very projects that have prefabs. Resolve the ref first.
    local n_pf n_named pf_src part
    pf_src="$WORK_GRAPH"
    part=$(jq -r '.codebase.prefabs["$partition"] // empty' "$WORK_GRAPH" 2>/dev/null)
    if [[ -n "$part" ]]; then
      pf_src="$(dirname "$WORK_GRAPH")/$part"
      if [[ ! -f "$pf_src" ]]; then
        known_fail "prefabs" "partition file $part referenced but not written"
        return 0
      fi
      n_pf=$(jq_count "$pf_src" 'length')
    else
      n_pf=$(jq_count "$WORK_GRAPH" '.codebase.prefabs | length')
    fi
    if [[ "$n_pf" -eq 0 ]]; then
      echo "[SKIP] prefabs: none in this graph (requires a Unity/MCP-connected build; merge is verified generically in T7/T8)"
    else
      if [[ -n "$part" ]]; then
        n_named=$(jq_count "$pf_src" '[.[]? | select(.name != null and .name != "")] | length')
      else
        n_named=$(jq_count "$WORK_GRAPH" '[.codebase.prefabs[]? | select(.name != null and .name != "")] | length')
      fi
      if [[ "$n_pf" -eq "$n_named" ]]; then
        pass "prefabs well-formed ($n_pf, all named)"
      else
        fail "prefabs present ($n_pf) but $((n_pf - n_named)) missing a name"
      fi
    fi
  fi

  # 8. violations
  if jq -e '.validation | has("errors") and has("warnings")' "$WORK_GRAPH" >/dev/null 2>&1; then
    pass "violations structure present (errors+warnings arrays)"
  else
    fail "violations structure missing"
  fi

  # 9. diff — compare backup vs work graph (parseable)
  local bak="$SANDBOX_BACKUP_DIR/graph.json"
  if [[ -f "$bak" ]]; then
    diff <(jq -S '.codebase.classes | map(.name) | sort' "$bak" 2>/dev/null || echo '[]') \
         <(jq -S '.codebase.classes | map(.name) | sort' "$WORK_GRAPH" 2>/dev/null || echo '[]') \
         >/dev/null 2>&1 || true
    pass "diff subcommand parseable (backup vs work)"
  else
    fail "diff: no backup graph.json found"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# T0b — Scan-root parity (the alarm on the harness's copy of the builder's roots)
# ──────────────────────────────────────────────────────────────────────────────
# _unity_scan_roots hardcodes the same two roots graph-builder.py walks. That copy is a
# liability, not a design: the blind spot this suite was just fixed for existed because a
# second list drifted from the thing it mirrored. This test is the price of keeping the
# copy — add or rename a root in graph-builder.py's roots_cs and the suite goes red here
# instead of silently under-reporting UNITY_HAS_CS on the next project.
run_scan_root_parity_tests() {
  section "T0b — Scan-root parity with graph-builder.py"

  local builder_roots harness_roots
  # The literal roots_cs block: os.path.join(assets_root, "...") entries, in order.
  builder_roots=$(awk '/roots_cs = \[/{f=1;next} f&&/\]/{exit} f' "$GRAPH_DIR/graph-builder.py" \
    | grep -oE '"[^"]+"' | tr -d '"' | paste -sd/ - | sed 's|/|,|; s|/|/|g')
  # Normalise both sides to a comma-joined, assets-relative form.
  builder_roots=$(awk '/roots_cs = \[/{f=1;next} f&&/\]/{exit} f' "$GRAPH_DIR/graph-builder.py" \
    | sed -n 's/.*os\.path\.join(assets_root, *\(.*\)).*/\1/p' \
    | tr -d '" ' | sed 's/,/\//g' | sort | paste -sd"," -)
  harness_roots=$(_unity_scan_roots | sed "s|.*/Assets/||" | sort | paste -sd"," -)

  if [[ -z "$builder_roots" ]]; then
    fail "T0b: could not parse roots_cs out of graph-builder.py — parity unverifiable"
  elif [[ "$builder_roots" == "$harness_roots" ]]; then
    pass "T0b: harness scan roots match graph-builder.py roots_cs ($harness_roots)"
  else
    fail "T0b: scan-root DRIFT — builder=[$builder_roots] harness=[$harness_roots]; update _unity_scan_roots"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# T6b — RC1-RC4 call-edge resolution (PLAN_graph_call_resolution.md, Task 6 step 5)
# ──────────────────────────────────────────────────────────────────────────────
run_call_resolution_tests() {
  section "T6b — Call-edge resolution (RC1-RC4)"

  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] T6b callers/validator — no C# under the builder's scan roots\n"
    return
  fi

  # 1. full build -> graph-traversal.py callers <concrete class> returns >=1,
  # for a class that RC1's resolve_call_targets actually resolved as a callee.
  local concrete_cls
  concrete_cls=$(jq -r '[.codebase.calls[]? | select(.callee_class != null) | .callee_class] | first // empty' "$WORK_GRAPH" 2>/dev/null)
  if [[ -z "$concrete_cls" ]]; then
    echo "[SKIP] T6b callers: no resolved callee_class present in calls[] (nothing for RC1 to have resolved in this repo)"
  else
    local callers_json n_hits
    callers_json=$(python3 "$GRAPH_DIR/graph-traversal.py" --graph "$WORK_GRAPH" callers "$concrete_cls" --json 2>/dev/null)
    # graph-traversal.py cmd_callers prints `hits` (a LIST) at the top level — there is no
    # ".hits" key. `jq '.hits | length'` therefore errors on an array, the `|| echo 0` swallows
    # it, and the check reports "returned 0 hits" while printing a JSON body full of hits.
    # Pre-existing; only reachable once UNITY_HAS_CS could be 1 outside Games/Concretes.
    n_hits=$(echo "$callers_json" | jq 'length' 2>/dev/null || echo 0)
    if [[ "$n_hits" -ge 1 ]]; then
      pass "T6b callers $concrete_cls returns $n_hits hit(s)"
    else
      fail "T6b callers $concrete_cls returned 0 hits (json=$callers_json)"
    fi
  fi

  # 2. graph_validate.py clean-exit assert; T2's repointed DANGLING_CALL branch
  # must never fire for callee_class=None edges (external/Unity/unresolved).
  local probe="$SCRIPT_DIR/.work/graph_validate_probe.json"
  cp "$WORK_GRAPH" "$probe"
  local validate_exit=0
  python3 "$GRAPH_DIR/graph_validate.py" --graph "$probe" >/dev/null 2>&1 || validate_exit=$?
  local dangling_on_null
  dangling_on_null=$(jq '[.validation.consistency.issues[]? | select(.type == "DANGLING_CALL" and (.callee == null or .callee == ""))] | length' "$probe" 2>/dev/null || echo 0)
  if [[ "$validate_exit" -eq 0 && "$dangling_on_null" -eq 0 ]]; then
    pass "T6b graph_validate.py clean exit; DANGLING_CALL never fires on callee_class=None"
  else
    fail "T6b graph_validate.py exit=$validate_exit dangling_on_null=$dangling_on_null"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# T7 — Triggers (PostToolUse hook, post-commit, watch, purge_ghosts)
# ──────────────────────────────────────────────────────────────────────────────
run_trigger_tests() {
  section "T7 — Triggers"

  local log="$REPO_ROOT/.claude/state/graph-updates.log"
  mkdir -p "$REPO_ROOT/.claude/state"
  touch "$log"

  # line_count_of <file> — print the line count, or 0 on error.
  line_count_of() { wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

  # Hook must run with CWD = REPO_ROOT so its relative paths (.claude/state/,
  # .claude/project-features.json, .claude/graph/graph-builder.sh) resolve correctly.
  _run_hook() {
    local payload="$1"
    ( cd "$REPO_ROOT" && echo "$payload" | bash ".claude/hooks/graph-auto-update.sh" ) >/dev/null 2>&1 || true
  }

  # 1. PostToolUse hook logs .cs file — use any .cs path (file need not exist; hook checks extension only)
  local cs_payload='{"tool_input":{"file_path":"Assets/_Framework/Probe.cs"}}'
  local before after
  before=$(line_count_of "$log")
  _run_hook "$cs_payload"
  after=$(line_count_of "$log")
  if [[ "$after" -gt "$before" ]]; then
    pass "PostToolUse hook logs .cs trigger"
  else
    fail "PostToolUse hook did not log .cs file (before=$before after=$after)"
  fi

  # 2. PostToolUse filters .md
  before=$(line_count_of "$log")
  _run_hook '{"tool_input":{"file_path":"README.md"}}'
  after=$(line_count_of "$log")
  if [[ "$after" -eq "$before" ]]; then
    pass "PostToolUse filters .md (no log entry)"
  else
    fail "PostToolUse logged non-.cs/.asmdef file"
  fi

  # 3. graph-watch.sh syntax smoke
  if bash -n "$REPO_ROOT/.claude/graph/graph-watch.sh" 2>/dev/null; then
    pass "graph-watch.sh syntax valid"
  else
    fail "graph-watch.sh syntax error"
  fi

  if ! command -v fswatch >/dev/null 2>&1 && ! command -v inotifywait >/dev/null 2>&1; then
    echo "[SKIP] watcher dependency missing — install fswatch (macOS) or inotify-tools (Linux)"
  fi

  # 4. post-commit hook
  local pch="$REPO_ROOT/.git/hooks/post-commit"
  if [[ -x "$pch" ]]; then
    if bash "$pch" >/dev/null 2>&1; then
      pass "post-commit hook executes (exit 0)"
    else
      fail "post-commit hook returned non-zero"
    fi
  else
    echo "[SKIP] post-commit hook not installed — run bash .claude/hooks/install-git-hooks.sh"
  fi

  # 5. purge_ghosts — probe .cs added then removed
  # Use detected Concretes/ dir; skip gracefully if no Unity project present.
  local probe_abs=""
  if [[ -n "$UNITY_CONCRETES" ]]; then
    probe_abs="$UNITY_CONCRETES/__GhostProbe__.cs"
  fi
  if [[ -z "$probe_abs" ]]; then
    printf "[SKIP        ] purge_ghosts — no writable dir found inside the builder's scan roots\n"
  elif [[ -f "$probe_abs" ]]; then
    echo "[SKIP] purge_ghosts: $probe_abs already exists — skipping to avoid side-effects"
  else
    cat > "$probe_abs" <<'CS'
namespace Game.Concretes
{
    public class __GhostProbe__
    {
    }
}
CS
    python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null || true
    local present_after_add
    present_after_add=$(jq_count "$WORK_GRAPH" '[.codebase.classes[] | select(.name == "__GhostProbe__")] | length')
    rm -f "$probe_abs"
    python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null || true
    local present_after_delete
    present_after_delete=$(jq_count "$WORK_GRAPH" '[.codebase.classes[] | select(.name == "__GhostProbe__")] | length')
    if [[ "$present_after_delete" -eq 0 ]]; then
      pass "purge_ghosts removes deleted class (was $present_after_add, now $present_after_delete)"
    else
      fail "purge_ghosts left ghost entry ($present_after_delete remaining)"
    fi
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# T8 — Known bugs (auto-promote to PASS on fix)
# ──────────────────────────────────────────────────────────────────────────────
run_known_fail_bugs() {
  section "T8 — Known Bugs (KNOWN_FAIL → auto-promote on fix)"

  # BUG#1 — class.implements[] always empty
  local n_impl
  n_impl=$(jq_count "$WORK_GRAPH" '[.codebase.classes[] | select(.implements | length > 0)] | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] BUG#1 check — no C# under the builder's scan roots\n"
  elif [[ "$n_impl" -gt 0 ]]; then
    echo "[REGRESSION_FIXED: BUG#1] class.implements[] now populated ($n_impl classes)" >&2
    pass "BUG#1 resolved — implements[] populated ($n_impl classes)"
  else
    known_fail "BUG#1 class.implements[] always empty (count=0)" \
               "csharp-extractor strips ':' but keeps 'public sealed class X' prefix in base_types"
  fi

  # BUG#2 — MCP merge drops prefabs/scenes
  # Must build WITH mcp (no --skip-mcp) to verify merge; use a separate output to avoid
  # clobbering WORK_GRAPH (which is always built --skip-mcp for flag isolation tests).
  local cache_p graph_p mcp_out
  cache_p=$(jq_count "$GRAPH_DIR/cache/mcp-extract.json" '.prefabs | length')
  mcp_out="$SCRIPT_DIR/.work/graph-mcp.json"
  python3 "$GRAPH_DIR/graph-builder.py" --full --quiet --output "$mcp_out" 2>/dev/null || true
  graph_p=$(jq_count "$mcp_out" '.codebase.prefabs | length')
  if [[ "$cache_p" -gt 0 && "$graph_p" -gt 0 ]]; then
    echo "[REGRESSION_FIXED: BUG#2] MCP prefabs merged (cache=$cache_p graph=$graph_p)" >&2
    pass "BUG#2 resolved — prefabs merged ($graph_p)"
  else
    known_fail "BUG#2 MCP merge drops prefabs (cache=$cache_p graph=$graph_p)" \
               "graph-builder.sh FINAL_GRAPH assembly does not wire .codebase.prefabs"
  fi

  # BUG#3 — base_types[] contains declaration prefix
  local polluted
  polluted=$(jq_count "$WORK_GRAPH" '[.codebase.classes[] | select(.base_types[]? | test("public |sealed |class |internal |static "))] | length')
  if [[ "$polluted" -eq 0 ]]; then
    echo "[REGRESSION_FIXED: BUG#3] base_types[] is clean (no declaration prefix)" >&2
    pass "BUG#3 resolved — base_types[] clean"
  else
    local example
    example=$(jq -r '[.codebase.classes[] | select(.base_types[]? | test("public |sealed |class |internal |static "))][0] | .name + " → " + (.base_types | tostring)' "$WORK_GRAPH" 2>/dev/null || echo "?")
    known_fail "BUG#3 base_types[] contains declaration prefix ($polluted classes)" \
               "example: $example"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# T9 — V2 Module Tests
# ──────────────────────────────────────────────────────────────────────────────
run_v2_module_tests() {
  section "T9 — V2 Modules (graph_cluster / graph_analyze / graph_validate / csharp_extractor)"

  local WORK_GRAPH="$SCRIPT_DIR/.work/graph_v2_test.json"

  # Build a fresh graph into the work file
  python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null || true

  # 9.1 — schema version
  # Read the expected value from graph-builder.py itself (the single source of truth
  # that writes this literal) rather than re-pinning a second literal here — a bare
  # `[[ "$sv" == "1.3.0" ]]` is exactly what Task 10's additive minor bump to 1.4.0
  # broke (harness went 31/0 -> 30/1). Semver comparison (>= expected) would also
  # accept a regression back to an OLDER value, so equality against the builder's
  # own literal is the correct check, not a floor.
  # The expected version is a LITERAL owned by this test, deliberately NOT read out of
  # graph-builder.py: deriving it from the file under test makes the assertion tautological —
  # it would pass even if the builder regressed to a wrong version, because both sides move
  # together. Flagged in final review. A `>=` floor is also wrong (it accepts a regression to
  # an older value). So: an independent literal, updated by hand whenever schema_version is
  # bumped. This line going red after a deliberate bump is the assertion WORKING, not rotting —
  # update it together with the bump (Task 10 bumped 1.3.0 -> 1.4.0 for `extraction_version`;
  # scope-parent resolution bumped 1.4.0 -> 1.5.0 for parent_source /
  # parent_unresolved_reason and a nullable `parent`).
  local expected_sv="1.7.0"
  local sv; sv=$(jq -r '.schema_version // "missing"' "$WORK_GRAPH" 2>/dev/null || echo "missing")
  [[ "$sv" == "$expected_sv" ]] && pass "schema_version = $expected_sv" \
                           || fail "schema_version is $sv (expected $expected_sv — if this bump was deliberate, update the literal here)"

  # 9.2 — communities present (only required when call edges exist)
  local call_count; call_count=$(jq '.codebase.calls | length' "$WORK_GRAPH" 2>/dev/null || echo 0)
  if [[ "$call_count" -gt 0 ]]; then
    local comm_count; comm_count=$(jq '(.codebase.communities // []) | length' "$WORK_GRAPH" 2>/dev/null || echo 0)
    [[ "$comm_count" -ge 1 ]] && pass "communities[] has $comm_count entries" \
                               || fail "expected ≥1 community, got $comm_count"
  else
    pass "no call edges — communities[] skip expected (graceful)"
  fi

  # 9.3 — analysis block present (graceful on empty repo)
  if jq -e '.analysis' "$WORK_GRAPH" >/dev/null 2>&1; then
    pass "analysis{} block present"
  else
    known_fail "analysis{} missing" "no call edges in repo — graph_analyze writes empty block only when communities exist"
  fi

  # 9.4 — graph_validate.py is deterministic with --seed 42
  python3 "$GRAPH_DIR/graph_validate.py" --graph "$WORK_GRAPH" --sample 5 --seed 42 2>/dev/null || true
  local p1; p1=$(jq -r '.validation.accuracy.agreement_pct // "missing"' "$WORK_GRAPH" 2>/dev/null || echo "missing")
  python3 "$GRAPH_DIR/graph_validate.py" --graph "$WORK_GRAPH" --sample 5 --seed 42 2>/dev/null || true
  local p2; p2=$(jq -r '.validation.accuracy.agreement_pct // "missing"' "$WORK_GRAPH" 2>/dev/null || echo "missing")
  [[ "$p1" == "$p2" ]] && pass "graph_validate.py deterministic ($p1%)" \
                        || fail "non-deterministic: $p1 vs $p2"

  # 9.5 — csharp_extractor.py exits 2 when tree-sitter unavailable.
  # Precondition: tree-sitter must be genuinely ABSENT. A PYTHONPATH override cannot
  # hide a site-packages install, so when the deps import fine we SKIP (untestable here)
  # rather than record a misleading KNOWN_FAIL. On a tree-sitter-free CI this runs for real.
  if python3 -c "import tree_sitter_c_sharp, tree_sitter" >/dev/null 2>&1; then
    echo "[SKIP] csharp_extractor exit-2 test: tree-sitter is installed — the 'absent' precondition cannot be simulated in this environment (runs on tree-sitter-free CI)"
  else
    local ts_exit=0
    PYTHONPATH=/nonexistent python3 "$GRAPH_DIR/extractors/csharp_extractor.py" \
      --changed-files "x.cs" 2>/dev/null || ts_exit=$?
    if [[ "$ts_exit" -eq 2 ]]; then
      pass "csharp_extractor.py exits 2 when tree-sitter absent"
    else
      fail "csharp_extractor.py exit $ts_exit (expected 2 when tree-sitter absent)"
    fi
  fi

  # 9.6 — builder exits 0 even when graph_cluster.py is missing (graceful degradation)
  local SANDBOX_DIR; SANDBOX_DIR=$(mktemp -d)
  local work2="$SCRIPT_DIR/.work/graph_v2_missing_cluster.json"
  cp "$GRAPH_DIR"/*.py "$SANDBOX_DIR/" 2>/dev/null || true
  cp -R "$GRAPH_DIR/extractors" "$SANDBOX_DIR/" 2>/dev/null || true
  cp "$GRAPH_DIR/schema.json" "$SANDBOX_DIR/" 2>/dev/null || true
  # Intentionally omit graph_cluster.py — graph_analyze and graph_validate still present
  rm -f "$SANDBOX_DIR/graph_cluster.py"
  local rc=0
  python3 "$SANDBOX_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$work2" 2>/dev/null || rc=$?
  rm -rf "$SANDBOX_DIR"
  [[ "$rc" -eq 0 ]] && pass "builder exits 0 when graph_cluster.py absent (graceful degradation)" \
                      || fail "builder must exit 0 even without v2 modules (got rc=$rc)"
}

# ──────────────────────────────────────────────────────────────────────────────
# T11 — graph-viz.py smoke test
# ──────────────────────────────────────────────────────────────────────────────
run_viz_smoke_tests() {
  section "T11 — graph-viz.py Smoke Test"

  local sample_graph="$SCRIPT_DIR/fixtures/viz_sample/graph.json"
  if [[ ! -f "$sample_graph" ]]; then
    echo "[SKIP] T11: no sample graph fixture at fixtures/viz_sample/graph.json"
    return
  fi

  local viz_out
  viz_out="$SCRIPT_DIR/.work/graph_viz_sample.html"
  mkdir -p "$(dirname "$viz_out")"

  # The vis-network viz refuses to run unless the vendored vis-network.min.js
  # sits next to the output (it emits <script src="vis-network.min.js">, never a
  # CDN URL). Stage the vendored copy beside the temp output for the smoke test.
  if [[ -f "$GRAPH_DIR/vis-network.min.js" ]]; then
    cp "$GRAPH_DIR/vis-network.min.js" "$(dirname "$viz_out")/vis-network.min.js"
  fi

  if ! python3 "$GRAPH_DIR/graph-viz.py" --graph "$sample_graph" --out "$viz_out" >/dev/null 2>&1; then
    fail "T11: graph-viz.py exited non-zero against sample fixture"
    return
  fi

  if [[ -s "$viz_out" ]]; then
    pass "T11: graph.html generated and non-empty ($(wc -c < "$viz_out" | tr -d ' ') bytes)"
  else
    fail "T11: graph.html missing or empty"
    return
  fi

  # vis-network renders into the id="graph" container (it creates its own canvas
  # at runtime — there is no static <canvas> tag) and reads the inline
  # id="graph-data" JSON island. Both must be present.
  if grep -q 'id="graph"' "$viz_out" && grep -q 'id="graph-data"' "$viz_out"; then
    pass "T11: output contains the vis-network container and inline data island"
  else
    fail "T11: output missing id=\"graph\" container or data island"
  fi

  # No external resource URL — strict: any match fails (favicon/comment text mentioning
  # "http" in plain prose is not present in this template, so zero tolerance is safe here).
  local ext_hits
  ext_hits=$(grep -nEi 'https?://|src="//|cdn' "$viz_out" || true)
  if [[ -z "$ext_hits" ]]; then
    pass "T11: no external resource URL in generated HTML"
  else
    fail "T11: external resource reference found — $ext_hits"
  fi
}

# T10 — Report
# ──────────────────────────────────────────────────────────────────────────────
emit_report() {
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    printf '{"pass":%d,"fail":%d,"known_fail":%d,"elapsed_seconds":%d}\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$KNOWN_FAIL_COUNT" "$SECONDS"
  else
    echo
    echo "======================================================================="
    echo "  Graphify Verify — Summary"
    echo "======================================================================="
    printf "  PASS:       %d\n" "$PASS_COUNT"
    printf "  KNOWN_FAIL: %d   (real project-only checks — resolve on a full build with Unity/MCP connected)\n" "$KNOWN_FAIL_COUNT"
    printf "  FAIL:       %d\n" "$FAIL_COUNT"
    printf "  Elapsed:    %ds\n" "$SECONDS"
    echo "======================================================================="
  fi
  [[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# T10b — Incremental Purge Fix (regression for ghost-purge collapse bug)
# ──────────────────────────────────────────────────────────────────────────────
run_incremental_purge_tests() {
  section "T10b — Incremental Purge Fix"

  # Skip entirely on template repos with no C# source.
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    printf "[SKIP        ] T10b — no C# under the builder's scan roots (needs a populated project)\n"
    return
  fi

  # ── 10b.1: Full build then single-file incremental (with ABSOLUTE path, as the
  #    hook actually sends) must preserve class count without duplicates.
  #    This tests the path-normalization fix: relative source_file entries from
  #    the full build must round-trip through an absolute --changed-files input.
  local full_out incr_out single_file single_file_abs
  full_out="$SCRIPT_DIR/.work/graph_purge_full.json"
  incr_out="$SCRIPT_DIR/.work/graph_purge_incr.json"

  python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$full_out" 2>/dev/null || true
  local full_classes
  full_classes=$(jq_count "$full_out" '.codebase.classes | length')

  # Pick any .cs file — use an ABSOLUTE path to mirror the hook's behaviour.
  if [[ -n "$UNITY_CONCRETES" ]]; then
    single_file=$(_unity_any_cs)
    [[ -n "$single_file" ]] && single_file_abs="$(cd "$(dirname "$single_file")" && pwd)/$(basename "$single_file")"
  fi
  if [[ -z "${single_file_abs:-}" ]]; then
    echo "[SKIP] 10b.1: no .cs file found for changed-files probe"
  else
    # Seed the work graph with the full result so incremental can retain from it.
    cp "$full_out" "$incr_out"
    python3 "$GRAPH_DIR/graph-builder.py" \
      --incremental --changed-files "$single_file_abs" \
      --skip-mcp --quiet --output "$incr_out" 2>/dev/null || true
    local incr_classes
    incr_classes=$(jq_count "$incr_out" '.codebase.classes | length')
    # Allow ±1 for the edited file's own class count potentially changing.
    local lower_bound=$(( full_classes - 1 ))
    if [[ "$incr_classes" -ge "$lower_bound" ]]; then
      pass "10b.1: absolute-path incremental preserves class count (full=$full_classes incr=$incr_classes)"
    else
      fail "10b.1: path-norm regression — class count dropped with abs path (full=$full_classes incr=$incr_classes)"
    fi
    # Also verify no duplicates.  The key is (namespace, name, source_file), NOT the
    # bare class name: C# lets one partial class span several files, and lets two
    # namespaces each hold a class of the same name — both are legal and both would
    # trip a name-only check.  What this test is actually looking for is one FILE
    # recorded twice under two path forms (abs + rel), which the full key catches and
    # the name-only key could only guess at.  Measured 2026-09-03 in a project built
    # from this template: the name-only version failed CI on `BoardDecorProvider`, a
    # partial class split across BoardDecorProvider.cs and BoardDecorProvider.Debug.cs
    # — a false positive, and it reported it as "path normalization failed", pointing
    # at the wrong subsystem.
    local dup_count
    dup_count=$(jq '[.codebase.classes[] | "\(.namespace)|\(.name)|\(.source_file)"] | group_by(.) | map(select(length > 1)) | length' "$incr_out" 2>/dev/null || echo 0)
    if [[ "$dup_count" -eq 0 ]]; then
      pass "10b.1: no duplicate class entries after absolute-path incremental"
    else
      fail "10b.1: $dup_count class record(s) duplicated on (namespace, name, source_file) — path normalization failed"
    fi
  fi

  # ── 10b.2: Collapse guard blocks a write when new count < 50% of existing ──
  # Create a temporary Assets/_Framework tree with one real .cs file so that the
  # full directory walk produces a non-empty current_paths.  The seeded graph has
  # 20 "ghost" classes whose source_file paths don't exist in that tree — after
  # purge_ghosts drops them all, all_classes = 0 < 20*0.5 = 10, triggering the guard.
  local guard_out guard_assets
  guard_out="$SCRIPT_DIR/.work/graph_collapse_guard.json"
  guard_assets=$(mktemp -d)
  mkdir -p "$guard_assets/Assets/_Framework"
  echo "namespace Probe { public class ProbeAnchor {} }" > "$guard_assets/Assets/_Framework/ProbeAnchor.cs"

  # Build a fake graph with 20 ghost classes (source paths that do NOT exist in the temp tree).
  # The fixture MUST carry the builder's current extraction_version. Without it the
  # builder sees a mismatch (stored 0 vs current N), promotes this --incremental run
  # to --full, and the collapse guard never gets a chance to fire — the test then
  # reports "graph overwritten" and looks like a guard regression when nothing is
  # wrong with the guard. Derived from the builder rather than hard-coded: this is
  # fixture SETUP, not an assertion, so tracking the subject is correct here (the
  # opposite of the schema_version check, which must own its expected value).
  local _ev
  _ev=$(grep -oE '^EXTRACTION_VERSION[[:space:]]*=[[:space:]]*[0-9]+' "$GRAPH_DIR/graph-builder.py" \
        | grep -oE '[0-9]+$' | head -1)
  python3 - "${_ev:-0}" <<'PYEOF' > "$guard_out"
import json, sys
classes = [{"name": f"GhostClass{i}", "source_file": f"/tmp/ghost_path_{i}.cs"} for i in range(20)]
g = {"schema_version": "1.3.0", "extraction_version": int(sys.argv[1]),
     "codebase": {"classes": classes, "interfaces": [], "events": [], "vcontainer": {"installers": [], "scopes": []}, "assemblies": [], "calls": []}}
print(json.dumps(g))
PYEOF

  local sha_before sha_after guard_exit=0
  sha_before=$(sha_of "$guard_out")

  # Pin cwd to the temp tree so scan_files finds Assets/_Framework/ProbeAnchor.cs.
  # current_paths = [that real file]; ghost source paths not in current_paths → purged.
  # all_classes = 0, guard threshold = 10 → guard fires, write aborted.
  ( cd "$guard_assets" && python3 "$GRAPH_DIR/graph-builder.py" \
    --incremental --changed-files "/tmp/NonExistentProbe_XXXXX.cs" \
    --skip-mcp --quiet --output "$guard_out" 2>/dev/null ) || guard_exit=$?
  rm -rf "$guard_assets"

  sha_after=$(sha_of "$guard_out")

  if [[ "$sha_before" == "$sha_after" ]]; then
    pass "10b.2: collapse guard preserved graph (SHA unchanged, exit=$guard_exit)"
  else
    fail "10b.2: collapse guard failed — graph overwritten (classes after: $(jq_count "$guard_out" '.codebase.classes | length'))"
  fi

  # ── 10b.3: --force bypasses collapse guard ──
  local force_assets force_out force_exit=0
  force_assets=$(mktemp -d)
  mkdir -p "$force_assets/Assets/_Framework"
  echo "namespace Probe { public class ForceAnchor {} }" > "$force_assets/Assets/_Framework/ForceAnchor.cs"
  force_out="$SCRIPT_DIR/.work/graph_collapse_force.json"
  cp "$guard_out" "$force_out"  # still has the 20-ghost graph (SHA unchanged from guard test)

  ( cd "$force_assets" && python3 "$GRAPH_DIR/graph-builder.py" \
    --incremental --changed-files "/tmp/NonExistentForce_XXXXX.cs" \
    --force --skip-mcp --quiet --output "$force_out" 2>/dev/null ) || force_exit=$?
  rm -rf "$force_assets"

  # With --force the write should succeed (valid JSON written, even if classes=0).
  if jq empty "$force_out" 2>/dev/null; then
    pass "10b.3: --force bypasses collapse guard (valid JSON written, exit=$force_exit)"
  else
    fail "10b.3: --force build produced invalid JSON"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Task 8 — Harness Assertions (registration semantics / validator / reconciliation /
#          extraction_version). All probes live under $SCRIPT_DIR/.work/ only.
# ──────────────────────────────────────────────────────────────────────────────

run_registration_semantics_tests() {
  section "Registration semantics (Defect 1)"
  local work="$SCRIPT_DIR/.work/reg"; mkdir -p "$work"
  # Class name ends in "Installer" so BOTH extractors recognize it as an installer:
  # csharp_extractor.py's is_installer = name.endswith("Installer") OR (name.endswith("Module")
  # AND is_static); csharp-extractor.sh's regex path gates on the FILENAME containing
  # "Installer" (line ~621: `echo "$f" | grep -q 'Installer'`) — a *Module-suffixed, non-static
  # probe (as an earlier draft used) satisfies neither and silently produces an empty
  # registrations array on both sides, which made every downstream assertion here vacuously
  # fail (empty-vs-expected), not a real extractor defect.
  # Ordering is LOAD-BEARING and deliberately hostile: the chainless `Register<Bar>` sits
  # IMMEDIATELY BEFORE the chained `Register<Baz>(...).As<IBaz>()`. csharp-extractor.sh's Form 1
  # tail-scans forward from its own match for a trailing `.As<T>()`; when that scan was bounded
  # only by a fixed 400-char window (no statement terminator), Bar's scan ran straight into Baz's
  # chain on the next line and reported {"type":"Bar","as":"IBaz"} — wrong data in the key this
  # plan makes load-bearing, and a parity break (tree-sitter correctly emits ""). Found while
  # building this probe, fixed by cutting the tail at the first `;`. Do NOT "simplify" this probe
  # by moving the chained registration first: that ordering passes either way and stops testing
  # the fix. reg.1/reg.3/reg.4 below all depend on this ordering to bite.
  cat > "$work/ProbeInstaller.cs" <<'CS'
public class ProbeInstaller {
  private Foo _fooField;
  void Configure(IContainerBuilder builder) {
    builder.RegisterInstance<ITapResolver>(new TapResolver(1));
    builder.RegisterInstance<IFoo>(_fooField);
    builder.Register<Bar>(Lifetime.Singleton);
    builder.Register<Baz>(Lifetime.Singleton).As<IBaz>().As<IQux>();  // multi-As: `as` must be the STRING "IBaz"
    builder.RegisterInstance(SomeStatic.Opaque());
  }
}
CS

  local py sh
  py=$(python3 "$GRAPH_DIR/extractors/csharp_extractor.py" --changed-files "$work/ProbeInstaller.cs" 2>/dev/null)
  if [[ -z "$py" ]]; then
    known_fail "reg.1: tree-sitter unavailable — python extractor skipped" "csharp_extractor.py exited empty"
  else
    echo "$py" | jq -e '[.vcontainer.installers[].registrations[].type]
                         | map(select(test("^I[A-Z]"))) | length == 0' >/dev/null \
      && pass "reg.1: no interface recorded as concrete (tree-sitter)" \
      || fail "reg.1: interface recorded as concrete (tree-sitter)"

    # reg.1b: the chain reader from Task 1 step 4 — Baz must expose IBaz, not ""
    echo "$py" | jq -e '[.vcontainer.installers[].registrations[]
                         | select(.type=="Baz") | .as] == ["IBaz"]' >/dev/null \
      && pass "reg.1b: .As<T>() chain read on the tree-sitter side" \
      || fail "reg.1b: .As<T>() chain NOT read (tree-sitter) — parity gate reg.4 cannot pass"
  fi

  # csharp-extractor.sh:70-82 proxies straight to csharp_extractor.py FIRST and only runs
  # its own regex code when that subprocess exits non-zero — so when tree-sitter is
  # installed (as it is here), `bash csharp-extractor.sh` returns the SAME tree-sitter
  # output as $py, not the regex fallback, and every "fallback" assertion below would
  # silently test tree-sitter twice. A bare `PYTHONPATH=/nonexistent` override (T9's
  # documented trick for csharp_extractor.py directly) does NOT work here either: the
  # deps are on the real site-packages path, not reached via PYTHONPATH. Force the
  # fallback surgically instead — a `python3` shim on PATH that fails ONLY the inner
  # `csharp_extractor.py` subprocess call, leaving every other python3 call inside
  # csharp-extractor.sh's own regex helpers untouched.
  local fakebin="$work/fakebin"
  mkdir -p "$fakebin"
  local real_python3; real_python3=$(command -v python3)
  cat > "$fakebin/python3" <<SHIM
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    *csharp_extractor.py) exit 2 ;;
  esac
done
exec "$real_python3" "\$@"
SHIM
  chmod +x "$fakebin/python3"
  sh=$(PATH="$fakebin:$PATH" bash "$GRAPH_DIR/extractors/csharp-extractor.sh" --changed-files "$work/ProbeInstaller.cs" 2>/dev/null)

  # reg.2: same interface-as-concrete assertion on the fallback
  if [[ -n "$sh" ]]; then
    echo "$sh" | jq -e '[.vcontainer.installers[].registrations[].type]
                         | map(select(test("^I[A-Z]"))) | length == 0' >/dev/null \
      && pass "reg.2: no interface recorded as concrete (fallback)" \
      || fail "reg.2: interface recorded as concrete (fallback)"
  else
    fail "reg.2: fallback extractor produced no output"
  fi

  # reg.3: `as` is always a string in BOTH outputs — a non-string `as` (e.g. a JSON
  # array from an un-collapsed .As<T>() chain) breaks every downstream jq consumer
  # that expects a scalar.
  if [[ -n "$py" ]]; then
    echo "$py" | jq -e '[.vcontainer.installers[].registrations[].as] | map(type) | unique == ["string"]' >/dev/null \
      && pass "reg.3: every 'as' is a JSON string (tree-sitter)" \
      || fail "reg.3: a non-string 'as' found (tree-sitter)"
  fi
  if [[ -n "$sh" ]]; then
    echo "$sh" | jq -e '[.vcontainer.installers[].registrations[].as] | map(type) | unique == ["string"]' >/dev/null \
      && pass "reg.3: every 'as' is a JSON string (fallback)" \
      || fail "reg.3: a non-string 'as' found (fallback)"
  fi

  # reg.4: parity — sorted {type,as} multisets must be equal, INCLUDING the .As<T>()
  # record, but scoped to records where a type was actually RESOLVED on that side
  # (select(.type != "")). This is not a weakening: builder.RegisterInstance(SomeStatic.Opaque())
  # is representable by only ONE side (tree-sitter emits {"type":"",...,unresolved:true} per
  # Task 1 step 7 "never skip"; the fallback's Form 2 regex at csharp-extractor.sh:384 cannot
  # match an argument containing `()` and emits nothing at all for that shape). An unfiltered
  # multiset compare is therefore unsatisfiable by construction, not by a missing fix — the
  # asymmetry is pinned per-extractor by reg.6 instead of being hidden here.
  if [[ -n "$py" && -n "$sh" ]]; then
    local py_set sh_set
    py_set=$(echo "$py" | jq -c '[.vcontainer.installers[].registrations[]
                                    | select(.type != "") | {type, as}] | sort')
    sh_set=$(echo "$sh" | jq -c '[.vcontainer.installers[].registrations[]
                                    | select(.type != "") | {type, as}] | sort')
    [[ "$py_set" == "$sh_set" ]] \
      && pass "reg.4: resolved {type,as} multiset parity (tree-sitter vs fallback)" \
      || fail "reg.4: parity mismatch — tree-sitter=$py_set fallback=$sh_set"
  fi

  # reg.5: no Register<T> record carries interface_only (guards Task 5's blast radius) —
  # a false-positive interface_only on an ordinary Register<T> would silently disable
  # INSTALLER_MISSING_CLASS for that record project-wide.
  if [[ -n "$py" ]]; then
    echo "$py" | jq -e '[.vcontainer.installers[].registrations[]
                          | select(.type=="Bar" or .type=="Baz") | .interface_only] | unique == [null]' >/dev/null \
      && pass "reg.5: Register<T> records never carry interface_only (tree-sitter)" \
      || fail "reg.5: a Register<T> record carries interface_only (tree-sitter)"
  fi
  if [[ -n "$sh" ]]; then
    echo "$sh" | jq -e '[.vcontainer.installers[].registrations[]
                          | select(.type=="Bar" or .type=="Baz") | .interface_only] | unique == [null]' >/dev/null \
      && pass "reg.5: Register<T> records never carry interface_only (fallback)" \
      || fail "reg.5: a Register<T> record carries interface_only (fallback)"
  fi

  # reg.6: the unresolvable form is asserted PER-EXTRACTOR, never as parity — if either
  # side's behaviour on this shape ever changes, reg.6 fails and the divergence is
  # re-decided deliberately, which is the outcome reg.4's select() must not swallow.
  if [[ -n "$py" ]]; then
    echo "$py" | jq -e '[.vcontainer.installers[].registrations[]
                          | select(.unresolved == true)] | length == 1' >/dev/null \
      && pass "reg.6: tree-sitter emits exactly one unresolved record for RegisterInstance(SomeStatic.Opaque())" \
      || fail "reg.6: tree-sitter unresolved-record count changed"
  fi
  if [[ -n "$sh" ]]; then
    echo "$sh" | jq -e '[.vcontainer.installers[].registrations[]
                          | select(.type == "")] | length == 0' >/dev/null \
      && pass "reg.6: fallback emits no record for RegisterInstance(SomeStatic.Opaque()) (asymmetry pinned)" \
      || fail "reg.6: fallback started emitting a record for the unresolvable RegisterInstance shape"
  fi

  rm -rf "$work"
}

run_validator_interface_tests() {
  section "Validator interface_only guard (Defect 5)"
  local work="$SCRIPT_DIR/.work/validator"; mkdir -p "$work"
  local fixture="$work/graph.json"

  # (i) interface_only: true naming an interface — must NOT fire.
  # (ii) plain registration naming a genuinely absent class — MUST fire.
  # (iii) plain Register<T>-shaped record with NO interface_only — MUST fire. This is
  #       the guard-not-too-loose assertion: it fails loudly if interface_only is ever
  #       set too broadly on ordinary Register<T> registrations, which would silently
  #       disable the check project-wide.
  cat > "$fixture" <<'JSON'
{
  "schema_version": "1.4.0",
  "generated_at": "2026-01-01T00:00:00Z",
  "codebase": {
    "classes": [{"name": "Dummy", "file": "Dummy.cs", "source_file": "Dummy.cs"}],
    "interfaces": [],
    "events": [],
    "assemblies": [],
    "calls": [],
    "vcontainer": {
      "installers": [{
        "name": "ProbeInstaller",
        "file": "ProbeInstaller.cs",
        "source_file": "ProbeInstaller.cs",
        "registrations": [
          {"type": "ISomeInterface", "as": "", "lifetime": "", "interface_only": true},
          {"type": "MissingClass", "as": "", "lifetime": ""},
          {"type": "UnknownClass", "as": "", "lifetime": ""}
        ]
      }],
      "scopes": []
    }
  }
}
JSON

  python3 "$GRAPH_DIR/graph_validate.py" --graph "$fixture" >/dev/null 2>&1

  jq -e '[.validation.consistency.issues[]
           | select(.type == "INSTALLER_MISSING_CLASS" and .class == "ISomeInterface")] | length == 0' \
     "$fixture" >/dev/null \
    && pass "validator (i): interface_only registration does NOT raise INSTALLER_MISSING_CLASS" \
    || fail "validator (i): interface_only registration incorrectly raised INSTALLER_MISSING_CLASS"

  jq -e '[.validation.consistency.issues[]
           | select(.type == "INSTALLER_MISSING_CLASS" and .class == "MissingClass")] | length == 1' \
     "$fixture" >/dev/null \
    && pass "validator (ii): plain registration naming an absent class raises INSTALLER_MISSING_CLASS" \
    || fail "validator (ii): absent-class registration did not raise INSTALLER_MISSING_CLASS"

  jq -e '[.validation.consistency.issues[]
           | select(.type == "INSTALLER_MISSING_CLASS" and .class == "UnknownClass")] | length == 1' \
     "$fixture" >/dev/null \
    && pass "validator (iii): plain Register<T>-shaped record with no interface_only still raises INSTALLER_MISSING_CLASS" \
    || fail "validator (iii): interface_only guard is too broad — ordinary Register<UnknownClass> no longer flagged"

  rm -rf "$work"
}

run_reconciliation_tests() {
  section "Disk/graph reconciliation (Task 6)"
  local work="$SCRIPT_DIR/.work/reconcile"; mkdir -p "$work"

  # (i) healthy build — no GRAPH_DISK_MISMATCH expected. Meaningful only when real
  # Unity C# exists to compare against; on the bare template repo both the disk-path
  # set and the graph-path set are empty, so the comparison never has anything to
  # disagree about and the assertion would be trivially (not meaningfully) green.
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    known_fail "reconciliation (i): healthy-build silence on GRAPH_DISK_MISMATCH" \
               "no C# under the builder's scan roots (<assets>/_Framework, <assets>/_GameFolders/Scripts) — nothing to reconcile"
  else
    local healthy_out healthy_err
    healthy_out="$work/graph_healthy.json"
    healthy_err=$(python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --output "$healthy_out" 2>&1 >/dev/null)
    if echo "$healthy_err" | grep -q "GRAPH_DISK_MISMATCH"; then
      fail "reconciliation (i): unexpected GRAPH_DISK_MISMATCH on a healthy build"
    else
      pass "reconciliation (i): healthy build is silent on GRAPH_DISK_MISMATCH"
    fi
  fi

  # (ii) induced omission — call reconcile_graph_with_disk() directly as a pure
  # function (it needs a graph dict + a disk file list, not a whole Unity project),
  # so this half of the test runs regardless of UNITY_HAS_CS. A real .cs file that
  # DECLARES a class is required (_DECL_RE), and a graph with NO matching node.
  local ghost_cs="$work/GhostClass.cs"
  cat > "$ghost_cs" <<'CS'
namespace Probe { public class GhostClass {} }
CS
  local probe_py="$work/probe_reconcile.py"
  cat > "$probe_py" <<PYEOF
import importlib.util, sys, json
spec = importlib.util.spec_from_file_location("graph_builder", "$GRAPH_DIR/graph-builder.py")
gb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gb)
graph = {"codebase": {"classes": [], "interfaces": []}}
gb.reconcile_graph_with_disk(graph, ["$ghost_cs"], quiet=False)
PYEOF
  local recon_stderr recon_exit=0
  recon_stderr=$(python3 "$probe_py" 2>&1 1>/dev/null) || recon_exit=$?

  if echo "$recon_stderr" | grep -q "GRAPH_DISK_MISMATCH"; then
    pass "reconciliation (ii): induced omission warns via GRAPH_DISK_MISMATCH"
  else
    fail "reconciliation (ii): induced omission did NOT warn (stderr='$recon_stderr')"
  fi
  [[ "$recon_exit" -eq 0 ]] \
    && pass "reconciliation (ii): reconciliation is non-fatal (exit 0)" \
    || fail "reconciliation (ii): reconciliation raised (exit $recon_exit) instead of warning"

  rm -rf "$work"
}

run_extraction_version_tests() {
  section "extraction_version staleness promotion (Task 10)"
  local work="$SCRIPT_DIR/.work/extver"; mkdir -p "$work"
  local wg="$work/graph.json"

  # extraction_version is a top-level field written on every build regardless of
  # whether any real Unity C# exists (see assemble_graph()) — unlike reconciliation,
  # which needs real disk paths to compare, this does not need UNITY_HAS_CS gating
  # to produce a meaningful assertion; run_v2_module_tests already builds unconditionally
  # into .work/ the same way.
  local expected_ev
  expected_ev=$(grep -oE '^EXTRACTION_VERSION = [0-9]+' "$GRAPH_DIR/graph-builder.py" | grep -oE '[0-9]+$')

  python3 "$GRAPH_DIR/graph-builder.py" --full --skip-mcp --quiet --output "$wg" 2>/dev/null || true

  # (i) field equals the builder constant
  assert_jq "$wg" '.extraction_version' "$expected_ev" \
    "extver (i): extraction_version equals builder's EXTRACTION_VERSION ($expected_ev)"

  # (ii) rewrite the stored value backwards, run --incremental, assert the promotion
  # is logged AND the graph carries the new value again (self-clearing).
  local stale=$(( expected_ev - 1 ))
  jq --argjson v "$stale" '.extraction_version = $v' "$wg" > "$wg.tmp" && mv "$wg.tmp" "$wg"
  local promo_stderr
  promo_stderr=$(python3 "$GRAPH_DIR/graph-builder.py" --incremental --skip-mcp --output "$wg" 2>&1 1>/dev/null)
  if echo "$promo_stderr" | grep -q "extraction_version mismatch" && echo "$promo_stderr" | grep -qi "promoting"; then
    pass "extver (ii): stale extraction_version promotion is logged"
  else
    fail "extver (ii): no promotion message on stale extraction_version (stderr='$promo_stderr')"
  fi
  assert_jq "$wg" '.extraction_version' "$expected_ev" \
    "extver (ii): graph self-clears back to current EXTRACTION_VERSION after promotion"

  # (iii) delete the key entirely — must promote (not raise), same as an unreadable/
  # missing value (_stored_extraction_version's except-branch defaults to 0).
  jq 'del(.extraction_version)' "$wg" > "$wg.tmp" && mv "$wg.tmp" "$wg"
  local del_stderr del_exit=0
  del_stderr=$(python3 "$GRAPH_DIR/graph-builder.py" --incremental --skip-mcp --output "$wg" 2>&1 1>/dev/null) || del_exit=$?
  [[ "$del_exit" -eq 0 ]] \
    && pass "extver (iii): deleting extraction_version promotes rather than raising (exit 0)" \
    || fail "extver (iii): missing extraction_version key crashed the build (exit $del_exit)"
  assert_jq "$wg" '.extraction_version' "$expected_ev" \
    "extver (iii): graph carries current EXTRACTION_VERSION after promoting from a missing key"

  rm -rf "$work"
}

# ──────────────────────────────────────────────────────────────────────────────
# Main pipeline
# ──────────────────────────────────────────────────────────────────────────────
run_scan_root_parity_tests
run_builder_flag_tests
run_validator_tests
run_pivot_tests
run_knowledge_graph_tests
run_call_resolution_tests
run_trigger_tests
run_known_fail_bugs
run_v2_module_tests
run_incremental_purge_tests
run_viz_smoke_tests
run_registration_semantics_tests
run_validator_interface_tests
run_reconciliation_tests
run_extraction_version_tests
emit_report
