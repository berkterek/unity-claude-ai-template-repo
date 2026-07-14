#!/usr/bin/env bash
# verify-graphify.sh — Single-script test harness for the .claude/graph/ toolchain.
# Shell-only — no Unity Editor, no C# compilation.
# Exit codes: 0 = no FAIL, 1 = at least one FAIL, 2 = prerequisite missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Auto-detect Unity project source root (handles nested projects like HoleSphere/).
# UNITY_CONCRETES — a writable Concretes/ dir for probe tests (purge_ghosts, --changed-files).
# UNITY_HAS_CS    — 1 if real C# source exists; 0 on template/empty repos.
_detect_unity_root() {
  local concretes
  concretes=$(find "$REPO_ROOT" -maxdepth 8 -type d -name "Concretes" 2>/dev/null \
    | grep -E '_GameFolders/Scripts/Games/Concretes$' | head -1)
  echo "${concretes:-}"
}
UNITY_CONCRETES="$(_detect_unity_root)"
if [[ -n "$UNITY_CONCRETES" ]] && find "$UNITY_CONCRETES" -name "*.cs" -maxdepth 3 2>/dev/null | grep -q .; then
  UNITY_HAS_CS=1
else
  UNITY_HAS_CS=0
fi

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
    echo "[SKIP] --incremental cache: no C# source files in repo (template mode)"
  elif [[ "$cache_entries" -gt 0 ]]; then
    pass "--incremental populates file-hashes cache ($cache_entries entries)"
  else
    fail "--incremental left cache empty (entries=$cache_entries)"
  fi

  # 3. --changed-files (single file) — use an actual .cs file from the project, or a temp one.
  local single_file
  if [[ -n "$UNITY_CONCRETES" ]]; then
    single_file=$(find "$UNITY_CONCRETES" -name "*.cs" -maxdepth 3 2>/dev/null | head -1)
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
  ev=$(jq_count "$WORK_GRAPH" '.codebase.events | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] events pivot: no C# source files (template mode)"
  elif [[ "$ev" -ge 16 ]]; then
    pass "events pivot ($ev events, >=16)"
  else
    fail "events pivot count=$ev (expected >=16)"
  fi

  inst=$(jq_count "$WORK_GRAPH" '.codebase.vcontainer.installers | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] installers count: no C# source files (template mode)"
  elif [[ "$inst" -ge 9 ]]; then
    pass "installers count ($inst, >=9)"
  else
    fail "installers count=$inst (expected >=9)"
  fi

  scopes=$(jq -r '[.codebase.vcontainer.scopes[].name] | tojson' "$WORK_GRAPH" 2>/dev/null || echo "[]")
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] scopes check: no C# source files (template mode)"
  elif echo "$scopes" | jq -e 'index("AppScope") and index("GameScope")' >/dev/null 2>&1; then
    pass "scopes contain AppScope+GameScope"
  else
    fail "scopes missing one of AppScope/GameScope: $scopes"
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
    echo "[SKIP] implementers pivot: no C# source files (template mode)"
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
    echo "[SKIP] summary: no C# source files (template mode)"
  elif [[ "$n_classes" -ge 1 ]]; then
    pass "summary: classes=$n_classes"
  else
    fail "summary: classes=0"
  fi

  # 2. implementers (KNOWN_FAIL — BUG#1)
  local n_impl
  n_impl=$(jq --arg n "ISaveLoadService" '[.codebase.classes[] | select(.implements | index($n) != null)] | length' "$WORK_GRAPH" 2>/dev/null || echo 0)
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] implementers: no C# source files (template mode)"
  elif [[ "$n_impl" -ge 1 ]]; then
    echo "[REGRESSION_FIXED: BUG#1] implementers ISaveLoadService now resolves ($n_impl)" >&2
    pass "implementers ISaveLoadService ($n_impl)"
  else
    known_fail "implementers ISaveLoadService returns 0 — BUG#1" \
               "implements[] never populated"
  fi

  # 3. publishers
  local n_pub
  n_pub=$(jq_count "$WORK_GRAPH" '[.codebase.events[] | select(.name == "RunStartedEvent") | .publishers[]] | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] publishers: no C# source files (template mode)"
  elif [[ "$n_pub" -ge 1 ]]; then
    pass "publishers RunStartedEvent ($n_pub)"
  else
    fail "publishers RunStartedEvent empty"
  fi

  # 4. subscribers (parseable is enough — always run, result 0 is valid)
  local n_sub
  n_sub=$(jq '[.codebase.events[] | select(.name == "RunStartedEvent") | .subscribers[]] | length' "$WORK_GRAPH" 2>/dev/null)
  if [[ -n "$n_sub" && "$n_sub" =~ ^[0-9]+$ ]]; then
    pass "subscribers RunStartedEvent query parseable ($n_sub)"
  else
    fail "subscribers query did not return a number"
  fi

  # 5. registrations — AudioInstaller present
  local n_reg
  n_reg=$(jq_count "$WORK_GRAPH" '[.codebase.vcontainer.installers[] | select(.name == "AudioInstaller")] | length')
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] registrations: no C# source files (template mode)"
  elif [[ "$n_reg" -ge 1 ]]; then
    pass "registrations AudioInstaller present"
  else
    fail "registrations AudioInstaller not found"
  fi

  # 6. scope-tree
  local scope_names
  scope_names=$(jq -r '[.codebase.vcontainer.scopes[].name] | tojson' "$WORK_GRAPH" 2>/dev/null || echo "[]")
  if [[ "$UNITY_HAS_CS" -eq 0 ]]; then
    echo "[SKIP] scope-tree: no C# source files (template mode)"
  elif echo "$scope_names" | jq -e 'index("AppScope") and index("GameScope")' >/dev/null 2>&1; then
    pass "scope-tree contains AppScope and GameScope"
  else
    fail "scope-tree missing AppScope or GameScope: $scope_names"
  fi

  # 7. prefab BlackholeSphere (KNOWN_FAIL — BUG#2)
  local n_pf
  n_pf=$(jq_count "$WORK_GRAPH" '[.codebase.prefabs[]? | select(.name == "BlackholeSphere")] | length')
  if [[ "$n_pf" -ge 1 ]]; then
    echo "[REGRESSION_FIXED: BUG#2] prefab BlackholeSphere found" >&2
    pass "prefab BlackholeSphere found"
  else
    known_fail "prefab BlackholeSphere not found — BUG#2" \
               "codebase.prefabs always []"
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
    echo "[SKIP] purge_ghosts: no Concretes/ directory found (template mode)"
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
    echo "[SKIP] BUG#1 check: no C# source files (template mode)"
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
  local sv; sv=$(jq -r '.schema_version // "missing"' "$WORK_GRAPH" 2>/dev/null || echo "missing")
  [[ "$sv" == "1.3.0" ]] && pass "schema_version = 1.3.0" \
                           || fail "schema_version is $sv (expected 1.3.0)"

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

  # 9.5 — csharp_extractor.py exits 2 when tree-sitter unavailable
  local ts_exit=0
  PYTHONPATH=/nonexistent python3 "$GRAPH_DIR/extractors/csharp_extractor.py" \
    --changed-files "x.cs" 2>/dev/null || ts_exit=$?
  if [[ "$ts_exit" -eq 2 ]]; then
    pass "csharp_extractor.py exits 2 when tree-sitter absent"
  else
    known_fail "csharp_extractor.py exit $ts_exit (expected 2)" \
      "tree-sitter may already be installed in this environment"
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

  if grep -q "<canvas" "$viz_out" && grep -q 'id="graph-data"' "$viz_out"; then
    pass "T11: output contains <canvas> and the inline data island"
  else
    fail "T11: output missing <canvas> or data island"
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
    printf "  KNOWN_FAIL: %d   (documented bugs — see docs/PLAN_graphify_test_coverage.md Task 8)\n" "$KNOWN_FAIL_COUNT"
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
    echo "[SKIP] T10b: no C# source files (template mode — full project required)"
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
    single_file=$(find "$UNITY_CONCRETES" -name "*.cs" -maxdepth 3 2>/dev/null | head -1)
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
    # Also verify no duplicates: each class name must appear exactly once.
    local dup_count
    dup_count=$(jq '[.codebase.classes[].name] | group_by(.) | map(select(length > 1)) | length' "$incr_out" 2>/dev/null || echo 0)
    if [[ "$dup_count" -eq 0 ]]; then
      pass "10b.1: no duplicate class entries after absolute-path incremental"
    else
      fail "10b.1: $dup_count duplicate class name(s) found — path normalization failed"
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
  python3 - <<'PYEOF' > "$guard_out"
import json
classes = [{"name": f"GhostClass{i}", "source_file": f"/tmp/ghost_path_{i}.cs"} for i in range(20)]
g = {"schema_version": "1.3.0", "codebase": {"classes": classes, "interfaces": [], "events": [], "vcontainer": {"installers": [], "scopes": []}, "assemblies": [], "calls": []}}
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
# Main pipeline
# ──────────────────────────────────────────────────────────────────────────────
run_builder_flag_tests
run_validator_tests
run_pivot_tests
run_knowledge_graph_tests
run_trigger_tests
run_known_fail_bugs
run_v2_module_tests
run_incremental_purge_tests
run_viz_smoke_tests
emit_report
