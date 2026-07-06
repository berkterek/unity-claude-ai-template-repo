# Plan: Graph Incremental Update — Ghost Purge Collapse Fix

**Status:** IMPLEMENTED ✅ — template: `14cc640` (purge decouple + collapse guard + health warning), `57c9340` (path normalization), `e3549a4` (bats sync); nile: `a40d18bb` (sync + full rebuild, 1 → 174 classes). Verified in production: 3 hook-triggered incremental updates post-fix, zero duplicates, count preserved.

**Implementation addendum (gap found during rollout):** the original plan missed that the hook passes *absolute* `--changed-files` paths while the full walk and extractor emit *relative* ones — mixed formats caused silent duplicate/decay instead of collapse. Fixed in `57c9340` via `os.path.relpath(os.path.realpath(f), realpath("."))` (realpath resolves macOS `/var → /private/var` aliasing). Lesson: any future path set-lookup in the graph pipeline must normalize to repo-root-relative form first.
**Affected repos:** `unity-claude-ai-template-repo` (source of truth) + `nile_hole_incremental_repo` (copy + corrupted data)
**Severity:** CRITICAL — silently destroys the knowledge graph, which CLAUDE.md declares "primary source of truth"

---

## 1. Problem

### 1.1 Symptom (observed in nile_hole_incremental_repo)

| | `graph.json.bak` (2026-06-25, full build) | `graph.json` (2026-07-02, after auto-update) |
|---|---|---|
| classes | **173** | **1** |
| calls | ~2187 | 2187 (retained — internally inconsistent) |
| stats.scanned_files | ~177 | 1 |

After a single `.cs` edit, the incremental auto-update wiped 172 of 173 classes. Events, interfaces, and installers collapse with them (they are derived from / purged alongside classes).

### 1.2 Root cause

Chain of calls when `graph-auto-update.sh` (PostToolUse hook) fires on a `.cs` edit:

1. **`graph-auto-update.sh:86`** → calls `graph-builder.py --incremental --changed-files "<the one edited file>"`
2. **`graph-builder.py: scan_files()` (~line 156)** — when `changed_files_str` is provided, it **short-circuits** and returns *only* the changed file list. The full `rglob` directory scan is skipped.
3. **`~line 837`** — `current_paths = cs_paths + asm_paths` → now contains **1 file**.
4. **`purge_ghosts()` (~line 302) called at ~line 866** — deletes every retained class whose `source_file` is not in `current_paths`. Ghost purge is designed to remove entries for *deleted files*, but with a 1-file `current_paths` it treats **every other file in the project as deleted**.

The `if not current_paths: return entries` guard only protects the *empty* case, not the single-file case.

### 1.3 Why nothing caught it

- **`merge_call_edges()`** filters only by `changed_cs`, not by `current_paths` → calls survive while classes vanish. The graph passes its own validation (`errors: []`) despite being internally inconsistent.
- **`graph-auto-update.sh` empty-graph warning** checks `scanned_files == 0`. The collapsed graph reports `scanned_files = 1` → warning never fires. The sentinel (`graph-empty-warned`) also only warns once, ever.
- **No post-build sanity check** compares new entity counts against the previous build.

### 1.4 Impact

CLAUDE.md instructs: *"graph.json is the primary source of truth... Do NOT manually scan source folders if the graph is available and fresh (< 24h)."* A collapsed graph has a fresh timestamp, so every session, `/catch-up`, `/orchestrate`, `/context-prime`, and all `/knowledge-graph` queries confidently return wrong answers (missing interfaces, no event publishers, no installers). This is worse than having no graph.

---

## 2. Solution

### 2.1 Design decision

**Chosen: Fix B — always build `current_paths` from a full directory scan, even in `--changed-files` mode.** Extraction/hashing still happens only for the changed file; only the cheap path listing (`rglob`, no file reads) runs fully.

Rationale over alternatives:

- **Fix A (rejected): skip ghost purge when `--changed-files` is set.** Two-line change, zero risk — but the auto-update hook *always* passes `--changed-files`, so in practice ghost purge would never run again. Deleted classes would accumulate as stale entries until someone manually runs `/build-knowledge-graph`, reintroducing the "fresh-but-wrong graph" problem in the opposite direction.
- **Fix B (chosen):** keeps ghost purge semantics correct in every mode. Cost is one `rglob` per edit in an already-background, non-blocking hook — negligible.

### 2.2 Defense in depth (both also implemented)

1. **Post-build sanity guard in `graph-builder.py`:** in incremental mode, if the new total class count is `< 50%` of the existing graph's class count (and existing count ≥ 10), **abort the write**, keep the old graph, and print a loud stderr warning telling the user to run `/build-knowledge-graph`. A collapse bug of any future origin then fails safe instead of destroying data.
2. **Fix the hook's health check in `graph-auto-update.sh`:** warn when `classes` count is suspiciously low relative to project size — not only when `scanned_files == 0`. Re-warn per session instead of once-ever (key the sentinel by session or date).

---

## 3. Implementation Steps

### Step 1 — `graph-builder.py`: decouple `current_paths` from `--changed-files`

- In `scan_files()`: when `changed_files_str` is provided, *additionally* perform the full directory walk and return both lists — `(changed_candidates, all_project_files)`. Signature/call-site updated accordingly (~lines 156–185, 825–837).
- `current_paths` is always derived from `all_project_files`.
- Hash-cache update (`update_hash_cache`, ~line 933) keeps current behavior (only hashed files updated) — verify no regression.

### Step 2 — `graph-builder.py`: post-build collapse guard

- Immediately before the atomic write: compare `len(all_classes)` vs `len(existing classes)`.
- Condition: `mode != "full"` and `existing >= 10` and `new < existing * 0.5` → print stderr error, exit non-zero, **do not write**.
- `--force` flag to bypass (for genuinely large deletions).

### Step 3 — `graph-auto-update.sh`: smarter health warning

- Replace `scanned_files == 0` check with: `classes == 0` OR (`classes < 5` while project has ≥ 20 `.cs` files under the configured `unity_project_folder`).
- Sentinel becomes session-scoped (compare against `.claude/state/session-start-time`) so the warning re-fires in new sessions.

### Step 4 — Regression test in `.claude/graph/test/verify-graphify.sh`

New test case: seed a fixture graph with N classes → run `graph-builder.py --incremental --changed-files <one file>` → assert class count is still ≥ N (merged, not purged). Also assert the Step 2 guard triggers on a crafted collapse scenario.

### Step 5 — Sync + repair

1. Apply Steps 1–4 in **template repo** (source of truth), commit.
2. Copy the three changed files to **nile_hole_incremental_repo** (`.claude/graph/graph-builder.py`, `.claude/hooks/graph-auto-update.sh`, test file).
3. Repair the corrupted graph in nile: run `/build-knowledge-graph` (full) — or directly: `python3 .claude/graph/graph-builder.py --full` from repo root.
4. Verify: `classes ≈ 173+`, then edit any `.cs` file, confirm auto-update preserves the count.

---

## 4. Acceptance Criteria

- [x] After a full build followed by a single-file incremental update, class/interface/installer counts are preserved (±1 for the edited file's own contents). *(verified with absolute-path input — 10b.1)*
- [x] Deleting a `.cs` file and running incremental (non-changed-files) build purges its entries (ghost purge still works).
- [x] A simulated collapse (forced tiny `current_paths`) does NOT overwrite graph.json and prints a warning. *(10b.2)*
- [x] verify-graphify.sh passes including the new test case.
- [x] nile_hole graph rebuilt: 174 classes, survived 3 real hook-triggered edits with zero duplicates.

## 5. Out of Scope (separate discussions)

- Folder-placement / suffix enforcement gap (rules exist, no hook checks them).
- Session-start context weight (~55k tokens).
- BSD sed portability of content-checking hooks on macOS.
- `calls[]` purge consistency (calls are never ghost-purged for deleted files — minor, can ride along with Step 1 if desired).
