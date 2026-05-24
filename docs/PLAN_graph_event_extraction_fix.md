# PLAN — Fix Graph Event Extraction (Constructor-Call Pattern)

> **Version:** v1 — 2026-05-24
> **Status:** Active
> **Scope:** `.claude/graph/extractors/csharp-extractor.sh` — `extract_events_published()` function only. Downstream graph builder, schema, and consumers are unchanged.

> **Complexity:** **1/10 — Trivial.** Single bash function, single file, no schema impact, no Unity compile, no test harness required. Reversible in one line.

## Context

The knowledge-graph C# extractor at `.claude/graph/extractors/csharp-extractor.sh` currently detects events published via the angle-bracket generic form `_eventBus.Publish<EventName>()` (line 86, regex `\.(Publish)<([A-Z][A-Za-z0-9_]*)>`). However, the actual codebase exclusively uses the constructor-call form `_eventBus.Publish(new EventName(...))`. Real call sites include `UpgradeService.cs:76` (`_eventBus.Publish(new UpgradePurchasedEvent(...))`), `WalletService.cs:63` (`_eventBus.Publish(new GoldChangedEvent(...))`), and various `LaunchEvent` publishers.

The downstream effect is that `events_published: []` is emitted for every class in `graph.json`. The event-publisher graph is effectively empty, breaking `/knowledge-graph publishers`, `/catch-up` event-flow reports, and `/orchestrate` pre-scan event matching. Subscribers are unaffected because `extract_events_subscribed()` targets `.Subscribe<T>()` — and that angle-bracket form IS used in practice.

The fix is additive: keep the existing angle-bracket regex and add a second `grep -oE` pass for the `\.Publish\(\s*new\s+EventName` constructor pattern, then merge both results through `sort -u` before JSON-encoding. POSIX ERE only — `grep -P` is forbidden on macOS BSD grep. `set -euo pipefail` is active, so the `result=$(...) || result=""` capture pattern must be preserved.

## Background — Bugs Fixed This Session (already applied)

These three issues were discovered and fixed during the graphify sync session on 2026-05-24. Documented here for reference.

| # | File | Bug | Fix Applied |
|---|------|-----|-------------|
| 1 | `csharp-extractor.sh` | `\|\| echo "[]"` double-output: under `set -euo pipefail`, when grep fails `jq -sc .` outputs `[]` AND `echo "[]"` also runs → `[]\n[]` invalid JSON | `result=$(...) \|\| result=""` + `${result:-[]}` |
| 2 | `csharp-extractor.sh` | Python stdin conflict: `python3 - <<'PYEOF' ) <<< "$VAR"` — Python reads script from stdin, `sys.stdin.read()` returns empty, JSON parse fails | Env var injection: `GRAPH_CLASSES="$VAR" python3 -` |
| 3 | `graph-builder.sh` | Same Python pattern: `"""$ALL_CLASSES"""` inline bash injection — unsafe with backslash/triple-quote in JSON | Env var injection: `GRAPH_CLASSES="$ALL_CLASSES" python3 -` |

## Goals

- [ ] Detect `_eventBus.Publish(new EventName(...))` constructor-call pattern in `extract_events_published()`.
- [ ] Preserve detection of legacy `.Publish<EventName>()` angle-bracket pattern (additive, no regression).
- [ ] Maintain identical output schema — JSON array of unique event-type strings.
- [ ] Stay POSIX ERE / BSD-grep compatible (no `-P`, no PCRE).
- [ ] Honor `set -euo pipefail` — use `result=$(...) || result=""` capture pattern.
- [ ] Do **not** modify `extract_events_subscribed()` — it is correct.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Patch `extract_events_published()` with dual-pattern detection | ⏳ Pending | — |
| 2 | Manual verification on real call sites + graph rebuild | ⏳ Pending | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/extractors/csharp-extractor.sh` | **Modify** | Replace function body at lines 84-88 (~5 lines → 8 lines) |
| `.claude/graph/graph.json` | **Regenerate** | Run `/build-knowledge-graph --full` after fix; not hand-edited |

---

## Task 1 — Patch `extract_events_published()` with dual-pattern detection

**Files:**
- `.claude/graph/extractors/csharp-extractor.sh` (lines 84-88)

**Steps:**
1. [ ] Locate `extract_events_published()` at line 84.
2. [ ] Replace the single-pass body with the dual-pass implementation below.
3. [ ] Verify `extract_events_subscribed()` immediately after is untouched.
4. [ ] Run `bash -n .claude/graph/extractors/csharp-extractor.sh` — must exit 0.
5. [ ] Run all 7 acceptance criteria test commands.

**Test Type:** NoTest (shell script — manual verification only)

**Code Skeleton:**

```bash
extract_events_published() {
  local f="$1" result a b combined
  # Pass A: legacy generic form  _eventBus.Publish<EventName>()
  a=$(grep -oE '\.(Publish)<([A-Z][A-Za-z0-9_]*)>' "$f" 2>/dev/null | grep -oE '<([A-Z][A-Za-z0-9_]*)>' | tr -d '<>') || a=""
  # Pass B: constructor-call form  _eventBus.Publish(new EventName(...))
  b=$(grep -oE '\.Publish\([[:space:]]*new[[:space:]]+[A-Z][A-Za-z0-9_]*' "$f" 2>/dev/null | sed -E 's/^\.Publish\([[:space:]]*new[[:space:]]+//') || b=""
  combined=$(printf '%s\n%s\n' "$a" "$b" | grep -v '^$' | sort -u)
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

2. **Constructor-call — UpgradeService.cs:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   extract_events_published "$(find . -name UpgradeService.cs -not -path '*/Library/*' | head -1)"
   ```
   Expected: array containing `"UpgradePurchasedEvent"`

3. **Constructor-call — WalletService.cs:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   extract_events_published "$(find . -name WalletService.cs -not -path '*/Library/*' | head -1)"
   ```
   Expected: array containing `"GoldChangedEvent"`

4. **Angle-bracket regression — synthetic:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp); printf '_eventBus.Publish<MyLegacyEvent>();\n' > "$tmp"
   extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `["MyLegacyEvent"]`

5. **Both forms merge + deduplicate — synthetic:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp)
   printf '_eventBus.Publish<EventA>();\n_eventBus.Publish(new EventA());\n_eventBus.Publish(new EventB(42));\n' > "$tmp"
   extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `["EventA","EventB"]`

6. **Empty file returns `[]`:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp); extract_events_published "$tmp"; rm "$tmp"
   ```
   Expected: `[]`

7. **pipefail safety:**
   ```bash
   bash -c 'set -euo pipefail; source .claude/graph/extractors/csharp-extractor.sh; tmp=$(mktemp); extract_events_published "$tmp"; rm "$tmp"; echo SURVIVED'
   ```
   Expected: `[]` then `SURVIVED`

---

## Task 2 — Manual verification + graph rebuild

**Files:**
- `.claude/graph/graph.json` (regenerated)

**Steps:**
1. [ ] Run `bash .claude/graph/graph-builder.sh --full --skip-mcp`
2. [ ] Verify `UpgradeService` has `UpgradePurchasedEvent` in `events_published`
3. [ ] Verify `WalletService` has `GoldChangedEvent` in `events_published`
4. [ ] Run `/knowledge-graph publishers` — confirm non-empty lists
5. [ ] Verify `extract_events_subscribed` output unchanged

**Test Type:** NoTest

**Acceptance Criteria:**

1. **Graph rebuilds cleanly:**
   ```bash
   bash .claude/graph/graph-builder.sh --full --skip-mcp
   ```
   Expected: exits 0

2. **UpgradeService in graph.json:**
   ```bash
   jq '.codebase.classes[] | select(.name=="UpgradeService") | .events_published' .claude/graph/graph.json
   ```
   Expected: array containing `"UpgradePurchasedEvent"`

3. **WalletService in graph.json:**
   ```bash
   jq '.codebase.classes[] | select(.name=="WalletService") | .events_published' .claude/graph/graph.json
   ```
   Expected: array containing `"GoldChangedEvent"`

4. **Event graph has publishers:**
   ```bash
   jq '.codebase.events[] | select(.publishers | length > 0) | .name' .claude/graph/graph.json
   ```
   Expected: non-empty list

5. **Subscribed unchanged — synthetic:**
   ```bash
   source .claude/graph/extractors/csharp-extractor.sh
   tmp=$(mktemp); printf '_eventBus.Subscribe<RunStartedEvent>(OnRun);\n' > "$tmp"
   extract_events_subscribed "$tmp"; rm "$tmp"
   ```
   Expected: `["RunStartedEvent"]`

---

## Rollback

Restore the original 5-line `extract_events_published()` body (single grep pass) and re-run `/build-knowledge-graph --full`.

## Known Limitations (acceptable)

- Multi-line `Publish(new EventName\n(...))` calls not detected — none exist in this codebase.
- `Publish(new Event<T>())` generic event structs not detected — none exist in this codebase.
- Comment lines containing `// _eventBus.Publish(new X())` may produce false positives — low-risk, cosmetic.
