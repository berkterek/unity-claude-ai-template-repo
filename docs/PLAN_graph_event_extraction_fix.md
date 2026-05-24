# PLAN — Fix Graph Knowledge Graph Extractor Bugs (1–4)

> **Version:** v2 — 2026-05-24
> **Status:** Complete
> **Scope:** `.claude/graph/extractors/csharp-extractor.sh`, `.claude/graph/graph-builder.sh`

## Context

Four bugs were discovered during the graphify sync session on 2026-05-24 while testing the Knowledge Graph pipeline end-to-end. All four have been fixed and committed.

**Bug 1 & 2** were in `csharp-extractor.sh`, **Bug 3** was in `graph-builder.sh`, **Bug 4** was a logic gap in `csharp-extractor.sh`. Bugs 1-3 caused runtime crashes (invalid JSON piped into `--argjson`). Bug 4 caused silently empty event data — no crash, just wrong output.

## Goals

- [x] Fix `|| echo "[]"` double-output under `set -euo pipefail` (Bug 1)
- [x] Fix Python stdin conflict in `csharp-extractor.sh` (Bug 2)
- [x] Fix Python inline bash injection in `graph-builder.sh` (Bug 3)
- [x] Detect `_eventBus.Publish(new EventName(...))` constructor-call form (Bug 4)
- [x] All fixes maintain `set -euo pipefail` safety and POSIX ERE compatibility

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Fix `\|\| echo "[]"` double-output — `csharp-extractor.sh` | ✅ Done | 1 |
| 1 | Fix Python stdin conflict — `csharp-extractor.sh` | ✅ Done | 1 |
| 1 | Fix Python inline injection — `graph-builder.sh` | ✅ Done | 1 |
| 2 | Fix constructor-call Publish pattern — `csharp-extractor.sh` | ✅ Done | — |
| 3 | Manual verification + graph rebuild | ✅ Done | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/extractors/csharp-extractor.sh` | **Modify** | Bugs 1, 2, 4 |
| `.claude/graph/graph-builder.sh` | **Modify** | Bug 3 |
| `.claude/graph/graph.json` | **Regenerate** | `/build-knowledge-graph --full` after all fixes |

---

## Task 1 — Fix `|| echo "[]"` double-output (Bug 1)

**File:** `.claude/graph/extractors/csharp-extractor.sh`

**Root Cause:** Under `set -euo pipefail`, when `grep` exits 1 (no match), `jq -sc .` still writes `[]` to stdout before the pipeline fails. Then `|| echo "[]"` also runs. Result: `[]\n[]` — invalid JSON for `jq --argjson`.

**Affected functions:** `extract_events_published`, `extract_events_subscribed`, `extract_registrations`, `extract_dependencies`, plus `base_arr` and `impl` variables in `process_file_regex`.

**Steps:**
1. [x] Replace all `result=$(...) || echo "[]"` patterns with capture pattern.
2. [x] Apply same fix to `base_arr_r` and `impl_r` local variables.
3. [x] Verify `bash -n csharp-extractor.sh` exits 0.

**Before:**
```bash
extract_events_published() {
  local f="$1"
  grep -oE '\.(Publish)<...>' "$f" 2>/dev/null | ... | jq -sc . || echo "[]"
}
```

**After:**
```bash
extract_events_published() {
  local f="$1" result
  result=$(grep -oE '\.(Publish)<...>' "$f" 2>/dev/null | ... | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}
```

**Acceptance Criteria:**
```bash
bash -c 'set -euo pipefail; source .claude/graph/extractors/csharp-extractor.sh; tmp=$(mktemp); extract_events_published "$tmp"; rm "$tmp"; echo SURVIVED'
```
Expected: `[]` then `SURVIVED` (not a crash)

---

## Task 2 — Fix Python stdin conflict in `csharp-extractor.sh` (Bug 2)

**File:** `.claude/graph/extractors/csharp-extractor.sh`

**Root Cause:** `python3 - <<'PYEOF' ) <<< "$VAR"` attempts to use stdin for both the heredoc script source AND the herestring data simultaneously. Python reads the script from stdin; `sys.stdin.read()` inside the script returns empty. JSON parse fails silently, event pivot produces `[]`.

**Steps:**
1. [x] Replace herestring data injection with environment variable injection.
2. [x] Update Python script to read from `os.environ` instead of `sys.stdin`.

**Before:**
```bash
ALL_EVENTS=$(python3 - <<'PYEOF'
import sys, json
classes = json.loads(sys.stdin.read())
...
PYEOF
) <<< "$ALL_CLASSES"
```

**After:**
```bash
ALL_EVENTS=$(GRAPH_CLASSES="$ALL_CLASSES" GRAPH_CONFIDENCE="$CONFIDENCE" python3 - <<'PYEOF'
import json, os
classes = json.loads(os.environ.get("GRAPH_CLASSES", "[]"))
confidence = os.environ.get("GRAPH_CONFIDENCE", "INFERRED")
...
PYEOF
)
```

**Acceptance Criteria:**
- Graph builder runs to completion without Python JSON parse error
- `ALL_EVENTS` is a valid JSON array after the pivot step

---

## Task 3 — Fix Python inline injection in `graph-builder.sh` (Bug 3)

**File:** `.claude/graph/graph-builder.sh`

**Root Cause:** `"""$ALL_CLASSES"""` inlines a bash variable directly into Python triple-quoted string source code. If `$ALL_CLASSES` contains backslashes, double-quotes, or triple-quotes (all valid in JSON), Python's parser crashes or silently truncates the data.

**Steps:**
1. [x] Replace all `"""$BASH_VAR"""` inline injections with env var injection pattern.
2. [x] Update both affected Python blocks (event pivot and interface implementers pivot).

**Before:**
```bash
ALL_EVENTS=$(python3 <<PYEOF
import json
classes = json.loads("""$ALL_CLASSES""")
...
PYEOF
)
```

**After:**
```bash
ALL_EVENTS=$(GRAPH_CLASSES="$ALL_CLASSES" python3 - <<'PYEOF'
import json, os
classes = json.loads(os.environ.get("GRAPH_CLASSES", "[]"))
...
PYEOF
)
```

**Acceptance Criteria:**
- `bash -n .claude/graph/graph-builder.sh` exits 0
- Graph builder completes when JSON contains backslashes or nested quotes

---

## Task 4 — Fix constructor-call Publish pattern (Bug 4)

**File:** `.claude/graph/extractors/csharp-extractor.sh`

**Root Cause:** `extract_events_published()` only matched the angle-bracket generic form `_eventBus.Publish<EventName>()`. The actual codebase exclusively uses the constructor-call form `_eventBus.Publish(new EventName(...))`. Result: `events_published: []` for every class — breaking `/knowledge-graph publishers`, `/catch-up` event-flow reports, and `/orchestrate` pre-scan event matching.

**Steps:**
1. [x] Add Pass B regex for constructor-call form alongside existing Pass A.
2. [x] Merge both passes via `sort -u` before JSON-encoding.
3. [x] Verify `extract_events_subscribed()` is untouched (angle-bracket form IS used for Subscribe).

**Before:**
```bash
extract_events_published() {
  local f="$1" result
  result=$(grep -oE '\.(Publish)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>' | sort -u | jq -R . | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}
```

**After:**
```bash
extract_events_published() {
  local f="$1" result a b combined
  # Pass A: generic form  _eventBus.Publish<EventName>()
  a=$(grep -oE '\.(Publish)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>') || a=""
  # Pass B: constructor-call form  _eventBus.Publish(new EventName(...))
  b=$(grep -oE '\.Publish\([[:space:]]*new[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null | sed -E 's/^\.Publish\([[:space:]]*new[[:space:]]+//') || b=""
  combined=$(printf '%s\n%s\n' "$a" "$b" | grep -v '^$' | sort -u) || combined=""
  result=$(printf '%s' "$combined" | jq -R . | jq -sc . 2>/dev/null) || result=""
  echo "${result:-[]}"
}
```

**Acceptance Criteria:**

1. **Syntax check:**
   ```bash
   bash -n .claude/graph/extractors/csharp-extractor.sh && echo OK
   ```
   Expected: `OK`

2. **Constructor-call form detected — synthetic:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp); printf '_eventBus.Publish(new LevelStartedEvent());\n' > "$tmp"
   extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `["LevelStartedEvent"]`

3. **Angle-bracket form preserved — synthetic:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp); printf '_eventBus.Publish<MyLegacyEvent>();\n' > "$tmp"
   extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `["MyLegacyEvent"]`

4. **Both forms merge + deduplicate — synthetic:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp)
   printf '_eventBus.Publish<EventA>();\n_eventBus.Publish(new EventA());\n_eventBus.Publish(new EventB(42));\n' > "$tmp"
   extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `["EventA","EventB"]`

5. **Empty file returns `[]`:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp); extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `[]`

6. **pipefail safety:**
   ```bash
   bash -c 'set -euo pipefail; source .claude/graph/extractors/csharp-extractor.sh; tmp=$(mktemp); extract_events_published "$tmp"; rm "$tmp"; echo SURVIVED'
   ```
   Expected: `[]` then `SURVIVED`

---

## Task 5 — Manual verification + graph rebuild

**Files:** `.claude/graph/graph.json` (regenerated)

**Steps:**
1. [x] Run `bash .claude/graph/graph-builder.sh --full --skip-mcp`
2. [x] Verify graph rebuilds without errors
3. [x] Verify `events_published` arrays are populated for publisher classes
4. [x] Verify `extract_events_subscribed` output unchanged

**Acceptance Criteria:**
```bash
bash .claude/graph/graph-builder.sh --full --skip-mcp
```
Expected: exits 0, `graph.json` contains non-empty `events_published` arrays.

---

## Rollback

- **Bug 1:** Restore `|| echo "[]"` inline pattern (introduces double-output under pipefail)
- **Bug 2:** Restore `<<< "$VAR"` herestring injection
- **Bug 3:** Restore `"""$ALL_CLASSES"""` inline injection
- **Bug 4:** Restore single-pass `extract_events_published()` (angle-bracket only)

Then re-run `/build-knowledge-graph --full`.

## Known Limitations (acceptable)

- Multi-line `Publish(new EventName\n(...))` calls not detected — none exist in this codebase.
- `Publish(new Event<T>())` generic event structs not detected — none exist in this codebase.
- Comment lines containing `// _eventBus.Publish(new X())` may produce false positives — low-risk, cosmetic.
