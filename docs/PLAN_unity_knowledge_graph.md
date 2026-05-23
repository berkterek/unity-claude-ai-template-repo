# PLAN — Unity Knowledge Graph (Graphify-Inspired)

> **Version:** v1 — 2026-05-23
> **Status:** Active
> **Scope:** `.claude/graph/` (new), `.claude/hooks/` (new hook scripts — user adds entries to settings.json manually), `.claude/commands/` (2 new + 3 existing rewrites), `.claude/CLAUDE.md`, `README.md`, `docs/engine-reference/` (informational), `.gitignore`

---

## Complexity Score

| Signal | Weight | Hit? |
|--------|--------|------|
| New module folder (`.claude/graph/`) | +0.3 | YES |
| Touches multiple existing commands (`/catch-up`, `/orchestrate`, `/context-prime`) | +0.3 | YES |
| New hook scripts (user manually adds entries to `settings.json`) | +0.2 | YES |
| Git hook + watch mechanism | +0.1 | YES |

**Score: 0.9 — XL (Architecture-Critical)**

This is the highest-impact change to the template since `/setup-project`: every "what is in this codebase" path is being replaced. Treat every task that touches `/catch-up`, `/orchestrate`, or `/context-prime` as load-bearing — they are read at session start by every downstream command.

---

## Context

The template currently learns about the codebase in three independent, file-based ways: `/catch-up` Globs `.cs` files, `/orchestrate` shell-`find`s `_Framework/`, `Games/Abstracts/`, `Games/Concretes/`, and `/context-prime` reads three or four markdown files. None of them have any runtime, scene, prefab, asmdef, or VContainer-graph awareness. Each command re-discovers the project from zero on every invocation, and none of them can answer "what implements `IDamageReceiver`?", "which installer registers `IAudioService`?", or "which prefabs reference this script?".

This plan introduces a **Graphify-inspired knowledge graph** as the single source of truth for codebase introspection. A pipeline of extractors (C# via tree-sitter+regex, .asmdef via JSON, scene/prefab via MCP) emits a `graph.json` artifact. Hooks keep it fresh on every Write/Edit and on every git commit. Three existing commands lose their ad-hoc scanning logic and instead query the graph. Codex independently validates the graph against the actual project to guard against extractor drift.

Documentation (`CLAUDE.md`, `README.md`) is updated only at the end, after the system is stable, so docs never describe a half-built feature.

## Goals

- [ ] Define a versioned `graph.json` schema and reserve `.claude/graph/` as the system's home.
- [ ] Ship three extractors: C# (tree-sitter + regex), .asmdef (JSON), scene/prefab (MCP).
- [ ] Ship `graph-builder.sh` that aggregates extractor output, deduplicates, and writes `graph.json` with a SHA256-keyed file cache so unchanged files are skipped.
- [ ] Ship `graph-validator.sh` that checks the graph against `.claude/rules/architecture.md` invariants (no singletons, all events have publisher+subscriber, every concrete is registered).
- [ ] Ship `/build-knowledge-graph` (full or incremental build) and `/knowledge-graph` (query) slash commands.
- [ ] Ship `graph-auto-update.sh` PostToolUse hook (incremental, file-scoped, fast) and a git `post-commit` hook (full rebuild) — both opt-in via `.claude/project-features.json`.
- [ ] Use Codex to cross-check `graph.json` accuracy against ground-truth file scans.
- [ ] Replace the file-scan logic inside `/catch-up`, `/orchestrate` pre-scan, and `/context-prime` with graph queries.
- [ ] Wire `setup-project → GDD → TDD → orchestrate` so each step both consumes and feeds the graph.
- [ ] Update `.claude/CLAUDE.md` and `README.md` last, documenting the final shape.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Define `graph.json` schema + folder layout + `.gitignore` | Pending | — |
| 2 | Task 2 — `.asmdef` extractor (`asmdef-extractor.sh`) | Pending | A |
| 2 | Task 3 — C# extractor (`csharp-extractor.sh`) — tree-sitter + regex fallback | Pending | A |
| 2 | Task 4 — MCP scene/prefab extractor (`mcp-extractor.md` skill) **[EDITOR/MCP — Unity Editor must be open]** | Pending | A |
| 3 | Task 5 — `graph-builder.sh` aggregator + SHA256 cache | Pending | — |
| 4 | Task 6 — `graph-validator.sh` (architecture invariants) | Pending | B |
| 4 | Task 7 — Codex graph-accuracy validator (skill + invocation) | Pending | B |
| 5 | Task 8 — `/build-knowledge-graph` slash command | Pending | C |
| 5 | Task 9 — `/knowledge-graph` query slash command | Pending | C |
| 6 | Task 10 — `graph-auto-update.sh` PostToolUse hook | Pending | D |
| 6 | Task 11 — Git `post-commit` hook installer script | Pending | D |
| 6 | Task 12 — Watch helper (`graph-watch.sh`, optional fswatch wrapper) | Pending | D |
| 7 | Task 13 — Rewrite `/catch-up` to read graph **[BLOCKED — needs investigation]** | Pending | E |
| 7 | Task 14 — Rewrite `/orchestrate` pre-scan (lines 88–102) to call graph | Pending | E |
| 7 | Task 15 — Rewrite `/context-prime` to load graph summary | Pending | E |
| 8 | Task 16 — Wire `/setup-project` → graph init + `project-features.json` flag | Pending | F |
| 8 | Task 17 — Reference graph from GDD-refine / TDD-refine / architect | Pending | F |
| 9 | Task 18 — Update `.claude/CLAUDE.md` with graph system section | Pending | G |
| 9 | Task 19 — Update `README.md` with graph system section + Slash Commands table rows | Pending | G |

**Parallel groups:**
- **A** (Phase 2 — three extractors): different files, no type dependency, each consumes Task 1's schema only.
- **B** (Phase 4 — two validators): different files; both consume the graph but neither produces the other's input.
- **C** (Phase 5 — two commands): different files; both depend on Task 5's `graph-builder.sh` and Task 1's schema — no type dependency between them.
- **D** (Phase 6 — three trigger mechanisms): different files; all call `.claude/graph/graph-builder.sh` directly (hooks bypass the slash command layer for speed).
- **E** (Phase 7 — three command rewrites): different files; each independently consumes the now-stable `graph.json`.
- **F** (Phase 8 — workflow integration): different command files.
- **G** (Phase 9 — docs): different files, must run last.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/README.md` | Create | One-page primer on what this folder is. |
| `.claude/graph/schema.json` | Create | JSON-Schema for `graph.json` v1. |
| `.claude/graph/graph.json` | Generated | Living artifact. Listed in `.gitignore`. |
| `.claude/graph/cache/file-hashes.json` | Generated | SHA256 cache keyed by relative path. |
| `.claude/graph/extractors/asmdef-extractor.sh` | Create | Parses every `*.asmdef`. |
| `.claude/graph/extractors/csharp-extractor.sh` | Create | tree-sitter primary, ripgrep+sed fallback. |
| `.claude/graph/extractors/mcp-extractor.md` | Create | Skill consumed by `/build-knowledge-graph` to drive MCP calls. |
| `.claude/graph/graph-builder.sh` | Create | Top-level orchestrator script. |
| `.claude/graph/graph-validator.sh` | Create | Architecture-invariant checks. |
| `.claude/graph/codex-validator.md` | Create | Prompt template handed to Codex for accuracy validation. |
| `.claude/hooks/graph-auto-update.sh` | Create | PostToolUse hook — incremental, file-scoped. |
| `.claude/hooks/install-git-hooks.sh` | Create | User runs once to install `.git/hooks/post-commit`. |
| `.claude/commands/build-knowledge-graph.md` | Create | New slash command. |
| `.claude/commands/knowledge-graph.md` | Create | New query command. |
| `.claude/commands/catch-up.md` | Edit | Replace Steps 1–4 (Glob + categorize + scope walk + message walk) with graph queries. Keep WHY/Feature-Guide sections unchanged. |
| `.claude/commands/orchestrate.md` | Edit | Replace lines 88–102 (Codebase Pre-Scan) with a graph-query block; keep the Pre-Scan Report shape. |
| `.claude/commands/context-prime.md` | Edit | Insert a new Step 2.5 that loads a graph summary; keep the existing 5 steps numbering intact otherwise. |
| `.claude/commands/setup-project.md` | Edit | Append a `graph` feature flag question and a Step 5.5 — Initial Graph Build. |
| `.claude/commands/refine-gdd.md` | Edit | One sentence: read graph summary for "existing module" context. |
| `.claude/commands/refine-tdd.md` | Edit | One sentence: read graph for affected-module impact. |
| `.claude/commands/architect.md` | Edit | Step where architect reads `_Framework/`: replace `find` with graph query. |
| `.claude/project-features.json` | Edit (downstream of `/setup-project`) | New `"graph": true` flag. |
| `.claude/settings.json` | **User edits manually** | Add PostToolUse `graph-auto-update.sh` entry. Plan provides the JSON block. |
| `.gitignore` | Edit | Add `.claude/graph/graph.json`, `.claude/graph/cache/`, `.claude/graph/.last-build`. |
| `.claude/CLAUDE.md` | Edit | New `## Knowledge Graph` section near top, plus row in Hooks blocking/warning tables. |
| `.claude/docs/hooks-warning.md` | Edit | Add `graph-auto-update.sh` row to Warning hooks table. |
| `README.md` | Edit | New `## Knowledge Graph` section + two rows in the `## Slash Commands` table + entry in Configuration File Map. |

---

## Task 1 — Define graph.json Schema + Folder Layout + .gitignore

**Files:**
- Create: `.claude/graph/README.md`
- Create: `.claude/graph/schema.json`
- Create: `.claude/graph/cache/.gitkeep`
- Edit: `.gitignore`

**Steps:**

1. [ ] Create `.claude/graph/README.md` with: purpose ("Graphify-inspired Unity knowledge graph"), pipeline diagram (detect → extract → build → cluster → analyze → report → export), pointer to `schema.json`, pointer to `/build-knowledge-graph`, lifecycle note ("graph.json is generated — do not edit by hand"), and a per-confidence legend (`EXTRACTED` / `INFERRED` / `AMBIGUOUS`).
2. [ ] Create `.claude/graph/schema.json` — JSON-Schema (draft-07) describing the full graph. Top-level keys:
   - `schema_version` (semver, start `"1.0.0"`)
   - `generated_at` (ISO8601 UTC)
   - `generator` (`"graph-builder.sh@<git-sha>"`)
   - `confidence_legend` (object explaining the three levels)
   - `codebase.classes[]` — `{ name, namespace, file, source_file (same as file — used as cache merge key), line, base_types[] (raw base list from parser), is_mono_behaviour (bool), implements[], dependencies[], events_published[], events_subscribed[], has_static_instance (bool), confidence }`
   - `codebase.interfaces[]` — `{ name, namespace, file, line, implementers[], confidence }`
   - `codebase.events[]` — `{ name, file, publishers[], subscribers[], confidence }`
   - `codebase.vcontainer.installers[]` — `{ name, file, registrations[{type, lifetime, scope}] }`
   - `codebase.vcontainer.scopes[]` — `{ name, parent, installers[] }`
   - `codebase.assemblies[]` — `{ name, file, references[], platforms, allowUnsafeCode, defines[] }`
   - `codebase.scenes[]` — `{ name, path, source_file (=path), confidence, gameobjects[{ name, components[], children[] }] }`
   - `codebase.prefabs[]` — `{ name, path, source_file (=path), domain, confidence, components[], isVariant, basePrefab }`
   - `codebase.mcp_extraction` — `{ status: "ok"|"skipped"|"error", skipped_reason?, extracted_at? }` (top-level metadata — not per-item)
   - `validation.errors[]` / `validation.warnings[]` — `{ rule_id, file, line, message, severity }`
   - `stats` — `{ scanned_files, cache_hits, build_ms }`
3. [ ] Create `.claude/graph/cache/.gitkeep` (empty file so the directory is committed; actual cache entries are ignored).
4. [ ] Add to `.gitignore`:
   ```
   # Knowledge graph (generated)
   .claude/graph/graph.json
   .claude/graph/graph.json.bak
   .claude/graph/*.tmp
   .claude/graph/cache/*
   !.claude/graph/cache/.gitkeep
   .claude/graph/.last-build
   ```

**Test Type:** Manual — `jq empty .claude/graph/schema.json` succeeds; `git status` shows the four files staged but not the cache contents.

**Code Skeleton (`schema.json` sketch):**
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://unity-claude-template/graph/schema.json",
  "title": "UnityKnowledgeGraph",
  "type": "object",
  "required": ["schema_version", "generated_at", "codebase"],
  "properties": {
    "schema_version": { "type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$" },
    "generated_at": { "type": "string", "format": "date-time" },
    "codebase": { "$ref": "#/definitions/codebase" }
  },
  "definitions": { "codebase": { "type": "object", "properties": { "classes": { "type": "array" } } } }
}
```

**Acceptance Criteria:**
- `schema.json` validates as JSON-Schema draft-07.
- README explains the seven-step Graphify pipeline.
- `.gitignore` excludes generated artifacts but keeps `cache/.gitkeep`.

---

## Task 2 — .asmdef Extractor

**Files:**
- Create: `.claude/graph/extractors/asmdef-extractor.sh`

**Steps:**

1. [ ] Write a Bash script: `find Assets -name '*.asmdef' -print0 | while IFS= read -r -d '' f; do …`.
2. [ ] For each `.asmdef`, use `jq` to extract `name`, `references[]`, `includePlatforms[]`, `excludePlatforms[]`, `allowUnsafeCode`, `defineConstraints[]`.
3. [ ] Emit a JSON array on stdout — one object per asmdef — matching `codebase.assemblies[]` in the schema.
4. [ ] Add `--changed-files <list>` flag: if provided, skip asmdefs not in the list (used by incremental hook).
5. [ ] Always set `confidence: "EXTRACTED"` (asmdef is explicit machine-readable data).
6. [ ] Exit 0 on success; non-zero with a single-line `ERR_*` token on failure.

**Test Type:** Manual — run against this repo's `Assets/` (empty here, so should emit `[]`); spot-check against a Unity project that does have asmdefs.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
emit_one() {
  local f="$1"
  jq -c '{
    name: .name,
    file: $f,
    references: (.references // []),
    platforms: { include: (.includePlatforms // []), exclude: (.excludePlatforms // []) },
    allowUnsafeCode: (.allowUnsafeCode // false),
    defines: (.defineConstraints // []),
    confidence: "EXTRACTED"
  }' --arg f "$f" "$f"
}
echo "["
first=1
find Assets -name '*.asmdef' 2>/dev/null | while read -r f; do
  [[ $first -eq 0 ]] && echo ","
  emit_one "$f"
  first=0
done
echo "]"
```

**Acceptance Criteria:**
- Output is valid JSON (`jq empty` passes).
- Schema-conformant for `codebase.assemblies[]`.
- `--changed-files` correctly narrows the scan.

---

## Task 3 — C# Extractor (tree-sitter + regex fallback)

**Files:**
- Create: `.claude/graph/extractors/csharp-extractor.sh`

**Steps:**

1. [ ] At script start, detect tree-sitter: `command -v tree-sitter >/dev/null && tree-sitter --version | grep -q '^tree-sitter '`. If absent, set `MODE=regex` and warn to stderr.
2. [ ] Build the file list: either all `.cs` files under `Assets/_Framework/`, `Assets/_GameFolders/Scripts/`, and `Packages/` (skip `*.Tests.*` asmdef paths unless `--include-tests`), or just `--changed-files`.
3. [ ] **In tree-sitter mode**, for each file run a small query (committed under `.claude/graph/extractors/queries/csharp.scm`) that captures:
   - `(class_declaration name: (identifier) @class.name (base_list (identifier) @class.implements)?)`
   - `(interface_declaration name: (identifier) @iface.name)`
   - constructor parameters (for VContainer ctor-injection → `dependencies[]`)
   - `[Inject]` method/property attributes
   - `builder.Register<T>` / `Register<T>().As<U>()` calls → `vcontainer.installers[].registrations[]`
   - `IEventBus.Publish<T>` / `Subscribe<T>` calls → `events[]` + `events_published/subscribed`
4. [ ] **In regex mode**, use `grep -nE` patterns as a fallback:
   - Classes: `^\s*(public|internal)?\s*(sealed|abstract)?\s*class\s+(\w+)(\s*:\s*([\w<>,\s]+))?`
   - Interfaces: `^\s*(public|internal)?\s*interface\s+(I\w+)`
   - VContainer: `builder\.Register<([^>]+)>\(\s*Lifetime\.(\w+)\s*\)(?:\.As<([^>]+)>\(\))?`
   - EventBus pub: `\.Publish<([A-Za-z_][A-Za-z0-9_]*)>\(`
   - EventBus sub: `\.Subscribe<([A-Za-z_][A-Za-z0-9_]*)>\(`
   - Mark every regex-mode result `confidence: "INFERRED"` (not EXTRACTED — regex misses generics, partial classes, etc.).
   - Singleton detection: `static\s+(readonly\s+)?\w+\s+(Instance|Current|Shared|Main|Default)\b` or `static\s+\w+\s+_instance\b` → set `has_static_instance: true`.
   - Base type list: capture raw base list from class declaration → `base_types[]`. Set `is_mono_behaviour: true` if `"MonoBehaviour"` appears in `base_types[]`.
5. [ ] Detect `Installer` classes: name ends with `Installer` AND implements `IInstaller` (or inherits `LifetimeScope`). Group their `Register<…>` calls under `vcontainer.installers[name].registrations`.
6. [ ] Resolve event publishers/subscribers across files in a second pass: pivot the per-file list into the schema's `events[]` shape.
7. [ ] Emit one JSON object on stdout with keys `classes`, `interfaces`, `events`, `vcontainer` — match the schema exactly.
8. [ ] Honor `--changed-files`: only re-extract those files, then on stdout emit a **partial** payload tagged `"partial": true` for the builder to merge.

**Test Type:** Manual — run against this template's own `Assets/` (likely sparse), then against the user's Unity Delivery Loop project (the canonical test target).

**Code Skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
MODE="regex"
command -v tree-sitter >/dev/null 2>&1 && MODE="tree-sitter"

scan_file_regex() {
  local f="$1"
  # classes
  grep -nE '^[[:space:]]*(public|internal)?[[:space:]]*(sealed|abstract)?[[:space:]]*class[[:space:]]+([A-Z]\w*)' "$f" || true
  # Publish/Subscribe
  grep -nE '\.(Publish|Subscribe)<([A-Z]\w*)>' "$f" || true
}

# … emit JSON …
```

**Acceptance Criteria:**
- Tree-sitter mode produces `confidence: "EXTRACTED"`; regex mode produces `confidence: "INFERRED"`.
- Output validates against `schema.json`'s `codebase` definition.
- Idempotent: running twice on the same files produces byte-identical output (sort keys before emit).
- Handles partial classes by merging entries with the same `namespace.name`.

---

## Task 4 — MCP Scene/Prefab Extractor **[EDITOR/MCP — Unity Editor must be open]**

**Execution context:** Unity Editor via MCP. This extractor CANNOT run when the Editor is closed. `/build-knowledge-graph` skips this step automatically if MCP is unavailable and logs a warning.

**Files:**
- Create: `.claude/graph/extractors/mcp-extractor.md`

**Steps:**

1. [ ] Write this as a **skill / agent prompt** (not a shell script) because MCP tools are only available inside Claude. The file lives under `.claude/graph/extractors/` so it co-locates with the other extractors but is invoked by `/build-knowledge-graph`, not by `graph-builder.sh` directly.
2. [ ] Frontmatter: `name: mcp-extractor`, `description: "Extracts scenes/prefabs/components into graph.json via MCP. EDITOR/MCP — Unity Editor must be open."`.
3. [ ] Body sections:
   - **Inputs:** optional `--scenes <path,path>` and `--prefabs <dir>` filters; otherwise full project.
   - **Process** (must batch via `batch_execute` per the `unity-mcp-patterns` skill):
     1. **[PRE-CONDITION GATE — run first before any other step]** Read `.claude/skills/core/unity-mcp-patterns/SKILL.md`. Confirm which actions exist for scene hierarchy (`get_hierarchy` or equivalent), prefab info (`get_info`/`get_hierarchy`), and component reads. If any required action is absent, mark Task 4 `[BLOCKED — MCP action unconfirmed]` and stop.
     2. Scene extraction: use the confirmed `manage_scene` hierarchy action → list root GameObjects with components per scene.
     3. Component reads: use the confirmed component resource or `manage_components` read action → component type list per GameObject.
     4. Prefab listing: enumerate `.prefab` files via `find Assets -name '*.prefab'` (Bash), then use confirmed `manage_prefabs` info/hierarchy action to read component state per prefab.
     5. Detect Prefab Variants by checking `.prefab` YAML `m_PrefabParent` field via Bash grep — MCP does not expose variant metadata directly.
     5. Detect Prefab Variants by checking `.prefab` YAML `m_PrefabParent` field via Bash grep — MCP does not expose variant metadata directly.
     6. Classify each prefab into a `domain` using the path heuristic from `unity-prefabs.md`: `UI`, `VFX`, `Enemies`, `Environment`, `Audio`, `Tools`, or `ThirdParty`.
     7. After all MCP calls complete, remove the now-redundant numbered step 4 from the PRE-CONDITION GATE duplicate (see Step 1 above — gate was moved to Step 1).
   - **Output:** a JSON object with keys `scenes[]` and `prefabs[]` matching the schema, written to `.claude/graph/cache/mcp-extract.json` so the shell builder can pick it up.
   - **Failure modes:** if Unity Editor is not connected, exit 0 with empty `scenes: []` and `prefabs: []` output — the rest of the build still proceeds. Builder sets `codebase.mcp_extraction.status: "skipped"` and `skipped_reason: "MCP_UNAVAILABLE"` on the top-level metadata object. Do NOT set per-item confidence fields for MCP failures.
4. [ ] Cross-reference `.claude/skills/core/unity-mcp-patterns/SKILL.md` (Rule 1 — batch_execute, Rule 2 — read_console) explicitly: the skill MUST be read before invocation.
5. [ ] Mark **[EDITOR/MCP — Unity Editor must be open]** prominently — this is the only extractor that needs a live Unity Editor.

**Test Type:** Manual MCP smoke test — open a Unity project with one scene + three prefabs and run `/build-knowledge-graph --mcp-only`; verify `cache/mcp-extract.json` is populated and schema-valid.

**Code Skeleton (frontmatter + Process header only):**
```markdown
---
name: mcp-extractor
description: "RUNTIME ONLY — Extracts scenes/prefabs/components via MCP into graph cache. Read this skill before extracting."
alwaysApply: false
---
# MCP Extractor

## Inputs
- (optional) --scenes <path1>,<path2>
- (optional) --prefabs <dir>

## Process
1. Read `.claude/skills/core/unity-mcp-patterns/SKILL.md` for batch_execute rules.
2. batch_execute([ manage_scene(load), manage_components(get) ]) — verify exact actions from unity-mcp-patterns SKILL.md before use
3. For each scene → load → walk root GameObjects.
4. For each prefab → get_components, detect isVariant.
5. Write JSON to `.claude/graph/cache/mcp-extract.json`.
```

**Acceptance Criteria:**
- File is structured as a skill (frontmatter + body), readable by Claude.
- All MCP calls are batched.
- Graceful degradation when MCP is unavailable (no crash; sets `codebase.mcp_extraction.status: "skipped"` with `skipped_reason: "MCP_UNAVAILABLE"`; no per-item confidence or skipped_reason fields on scene/prefab entries).
- Output file is schema-conformant for `scenes[]` and `prefabs[]`.

---

## Task 5 — graph-builder.sh Aggregator + SHA256 Cache

**Files:**
- Create: `.claude/graph/graph-builder.sh`

**Steps:**

1. [ ] Accept flags: `--full` (rebuild from scratch, ignore cache), `--incremental` (default — use cache), `--changed-files <comma-list>` (passed through to extractors), `--skip-mcp` (don't wait for Task 4 output), `--output <path>` (default `.claude/graph/graph.json`).
2. [ ] Detect SHA256 tool: prefer `sha256sum`, fall back to `shasum -a 256` (mac).
3. [ ] Load `.claude/graph/cache/file-hashes.json` (or start `{}`). Load existing `graph.json` into memory (or `{}` on first run). Build a set `current_paths` of all candidate files on disk (`.cs`, `.asmdef`, `.prefab`, `.unity`). For every candidate file:
   - Compute current hash.
   - If hash matches cache AND `--full` not set → **copy prior extracted entries for that file from existing `graph.json`** (keyed by `source_file` field on each node) into the new graph. Do NOT re-run the extractor.
   - Otherwise → mark for re-extraction. Remove stale entries for that file from the merge buffer.
   - **Purge ghost entries:** after processing all candidate files, remove any entries in the merge buffer whose `source_file` is NOT in `current_paths` (handles deleted and renamed files). Also remove their hashes from the hash cache.
4. [ ] Invoke extractors:
   - `asmdef-extractor.sh --changed-files "$CHANGED_ASMDEFS"` → capture stdout.
   - `csharp-extractor.sh --changed-files "$CHANGED_CS"` → capture stdout.
   - For MCP: if `cache/mcp-extract.json` is fresher than 1 hour, reuse it; otherwise note "MCP refresh recommended" in stats (the actual run happens through `/build-knowledge-graph` — the shell builder cannot itself drive MCP).
5. [ ] Merge per-file extractor output with retained cache entries → assemble the full `codebase` object.
6. [ ] Compute `events[]` by pivoting publishers/subscribers across all class entries.
7. [ ] Compute `validation.errors[]` placeholder (filled by Task 6 separately).
8. [ ] Compute `stats`: `scanned_files`, `cache_hits`, `build_ms` (use `$SECONDS` or `date +%s%N`).
9. [ ] Atomically write `.claude/graph/graph.json`: write to `graph.json.tmp`, `jq empty graph.json.tmp` to validate, then `mv` over.
10. [ ] Update `.claude/graph/cache/file-hashes.json` (also atomic).
11. [ ] Touch `.claude/graph/.last-build` with ISO timestamp.
12. [ ] Print a one-line summary to stderr: `graph: 312 classes, 87 events, 12 installers (24 cached, 8 reparsed) in 412ms`.

**Test Type:** Unit-ish — run `--full`, capture output, re-run `--incremental` with no changes, verify all files marked as cache hits and runtime drops by >10×.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHA_CMD="sha256sum"
command -v sha256sum >/dev/null 2>&1 || SHA_CMD="shasum -a 256"

hash_file() { $SHA_CMD "$1" | awk '{print $1}'; }

CACHE=".claude/graph/cache/file-hashes.json"
[[ -f "$CACHE" ]] || echo '{}' > "$CACHE"

# 1. Detect changed files
# 2. Run extractors on changed subset
# 3. Merge with cached entries
# 4. Pivot events
# 5. Atomic write
```

**Acceptance Criteria:**
- Idempotent: two consecutive `--incremental` runs produce identical `graph.json` (compare via `jq -S . graph.json | sha256sum`).
- Cache hit rate >90% on a no-op rebuild.
- Output validates against `schema.json` (use `python3 -c "import jsonschema, json; jsonschema.validate(json.load(open('.claude/graph/graph.json')), json.load(open('.claude/graph/schema.json')))"`).
- Atomic write: an interrupted build never leaves a partial `graph.json`.

---

## Task 6 — graph-validator.sh (Architecture Invariants)

**Files:**
- Create: `.claude/graph/graph-validator.sh`

**Steps:**

1. [ ] Read `.claude/graph/graph.json`. If missing, exit 0 with a warning (the graph hasn't been built yet — this is informational, not a hard block).
2. [ ] Run these checks via `jq`:
   - **R1: No singletons.** For each class in `codebase.classes[]`, fail if it has any of: a public `Instance` static property, `_instance` static field, `Current/Shared/Main/Default` static property, or `DontDestroyOnLoad` call. (Matches the rule already used by `check-vcontainer-singleton.sh`.) Source from the extractor's `events_published/subscribed` lists is NOT sufficient — this check requires extractor to also surface "has_static_instance" flag (extend Task 3's regex).
   - **R2: Every event has at least one publisher AND one subscriber.** Otherwise emit `validation.warnings[]` with `rule_id: "EVENT_DANGLING"`.
   - **R3: Every concrete class in `_GameFolders/Scripts/Games/Concretes/` is registered in at least one `vcontainer.installers[].registrations[]`.** If not, warning `CONCRETE_UNREGISTERED`.
   - **R4: No interface lives outside `_Framework/` or `Games/Abstracts/`.** Error `INTERFACE_MISPLACED`.
   - **R5: Every `.asmdef` references must be a known asmdef in the graph.** Error `ASMDEF_UNRESOLVED`.
   - **R6: No `_Framework/` asmdef references a `Games/` asmdef.** Error `LAYER_VIOLATION`.
3. [ ] Write findings back into `graph.json` under `validation.errors[]` and `validation.warnings[]` (use a temp file + atomic mv).
4. [ ] Exit 0 if only warnings; exit 1 if any error (so hooks can pick it up).

**Test Type:** Unit — craft a fixture `graph.json` containing one of each violation under `.claude/graph/test-fixtures/` and assert `validator` reports each one.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
GRAPH="${1:-.claude/graph/graph.json}"
[[ -f "$GRAPH" ]] || { echo "graph-validator: $GRAPH not found, skipping" >&2; exit 0; }

errors=()
warnings=()

# R2: dangling events
while IFS= read -r ev; do
  warnings+=("{\"rule_id\":\"EVENT_DANGLING\",\"message\":\"$ev has no publisher or subscriber\"}")
done < <(jq -r '.codebase.events[] | select((.publishers|length)==0 or (.subscribers|length)==0) | .name' "$GRAPH")

# … etc …

# Merge findings into graph.json (atomic)
```

**Acceptance Criteria:**
- All six rules implemented and individually testable.
- Findings persisted into `graph.json.validation.*`.
- Exit code reflects error/warning split.

---

## Task 7 — Codex Graph-Accuracy Validator

**Files:**
- Create: `.claude/graph/codex-validator.md`

**Steps:**

1. [ ] Write a prompt template that the user (or `/build-knowledge-graph --validate-with-codex`) hands to Codex via the existing `codex:codex-rescue` skill (see `/fix-codex` Step 1 for the invocation pattern).
2. [ ] Prompt structure:
   - **Task:** "Cross-check this `graph.json` against ground truth. Do NOT trust the graph — re-read the source files yourself."
   - **Inputs:** path to `graph.json`, optional list of N random classes/events/installers to spot-check (default 20, balanced across categories).
   - **Process:** For each sampled entry, Codex opens the listed file, verifies the claim (class exists, implements the listed interfaces, registers what the graph says, publishes/subscribes what the graph says).
   - **Output:** JSON report `{ "sampled": N, "agreements": K, "disagreements": [{ "entry", "claimed", "actual", "file:line" }], "missing_in_graph": [...], "extra_in_graph": [...] }`.
3. [ ] State the acceptance threshold: ≥95% agreement on a 20-sample run.
4. [ ] Note that this is **manual/on-demand** — running it on every build is too expensive. Recommend running after every schema change or extractor change.
5. [ ] Document in this file: "Run via `/fix-codex`-style invocation; see Step 1 of fix-codex.md for the Codex skill call pattern."

**Test Type:** Manual — run once against the user's real project, expect ≥95% agreement; investigate any disagreement and decide whether the graph or the source needs correction.

**Code Skeleton:** (prompt only — no executable code)
```markdown
# Codex Graph-Accuracy Validator

## Prompt to hand to codex:codex-rescue

TASK: Validate accuracy of .claude/graph/graph.json. Do NOT trust the graph;
re-read source files yourself.

INPUT: .claude/graph/graph.json
SAMPLE_SIZE: 20 (default — 5 classes, 5 events, 5 installers, 5 prefabs)

For each sampled entry:
  1. Open the file claimed in the entry.
  2. Verify every claim (name, namespace, implements[], events_published[]…).
  3. If any claim is wrong, record it under disagreements[].

OUTPUT: JSON with { sampled, agreements, disagreements, missing_in_graph, extra_in_graph }.
```

**Acceptance Criteria:**
- Document is self-contained and references the existing Codex invocation pattern from `/fix-codex`.
- Sample-size and threshold (95%) are explicit.
- Output format is a parseable JSON report.

---

## Task 8 — /build-knowledge-graph Slash Command

**Files:**
- Create: `.claude/commands/build-knowledge-graph.md`

**Steps:**

1. [ ] Front-matter: `# /build-knowledge-graph — Unity Knowledge Graph Builder`.
2. [ ] **Step 0 — Plugin Preflight:** check if `.claude/graph/graph-builder.sh` exists; if not, prompt user to run `/setup-project` (the graph is opt-in via `project-features.json`).
3. [ ] **Step 1 — Flags:** parse `--full`, `--incremental` (default), `--mcp-only` (skip all shell extraction — run ONLY the MCP extractor, then merge its output into the cached graph; useful when only scene/prefab data needs refresh), `--skip-mcp`, `--validate`, `--validate-with-codex`, `--quiet`.
4. [ ] **Step 2 — Shell extraction:** if `--mcp-only` is NOT set, run `.claude/graph/graph-builder.sh` with the matching flags. If `--mcp-only` IS set, skip this step entirely. Stream stderr to user.
5. [ ] **Step 3 — MCP extraction (RUNTIME):** if `--skip-mcp` not set:
   - Read `.claude/skills/core/unity-mcp-patterns/SKILL.md`.
   - Read `.claude/graph/extractors/mcp-extractor.md`.
   - Execute MCP calls per the extractor skill, writing `.claude/graph/cache/mcp-extract.json`.
   - Re-run `graph-builder.sh --incremental` so the new MCP data gets merged into `graph.json`.
6. [ ] **Step 4 — Architecture validation:** if `--validate` set, run `.claude/graph/graph-validator.sh`. Print summary.
7. [ ] **Step 5 — Codex validation:** if `--validate-with-codex` set, hand `codex-validator.md` to `codex:codex-rescue` per Task 7's pattern. Show the report.
8. [ ] **Step 6 — Summary:** print stats (`scanned_files`, `cache_hits`, `build_ms`) plus a one-line "what's new since last build" diff (compare `graph.json` to `graph.json.bak` if it exists; otherwise skip).
9. [ ] Always rotate: copy current `graph.json` to `graph.json.bak` before each build.

**Test Type:** Manual — run `/build-knowledge-graph --full` on a Unity project, verify a populated `graph.json`. Re-run incremental, verify cache hits.

**Code Skeleton:**
```markdown
# /build-knowledge-graph — Unity Knowledge Graph Builder

## Step 0 — Plugin Preflight
Check `.claude/graph/graph-builder.sh` exists.

## Step 1 — Flags
--full | --incremental (default) | --mcp-only | --skip-mcp | --validate | --validate-with-codex | --quiet

## Step 2 — Shell extraction
Run: bash .claude/graph/graph-builder.sh "$FLAGS"

## Step 3 — MCP extraction (RUNTIME)
Read: .claude/skills/core/unity-mcp-patterns/SKILL.md
Read: .claude/graph/extractors/mcp-extractor.md
Execute MCP calls, write cache/mcp-extract.json.
Re-run: bash .claude/graph/graph-builder.sh --incremental

## Step 4 — Validate architecture
If --validate: bash .claude/graph/graph-validator.sh

## Step 5 — Validate with Codex
If --validate-with-codex: invoke codex:codex-rescue with codex-validator.md

## Step 6 — Summary
Print stats + diff vs graph.json.bak
```

**Acceptance Criteria:**
- All six steps are explicit and skippable via flags.
- `--full` always reruns everything; `--incremental` is the default.
- The command never edits source files — only writes to `.claude/graph/`.
- MCP step gracefully no-ops if Unity isn't connected.

---

## Task 9 — /knowledge-graph Query Command

**Files:**
- Create: `.claude/commands/knowledge-graph.md`

**Steps:**

1. [ ] Define subcommands:
   - `/knowledge-graph summary` — print a one-screen overview: class count, interface count, event count, installer count, scope tree, top-5 most-referenced assemblies.
   - `/knowledge-graph implementers <interface>` — `jq '.codebase.classes[] | select(.implements | index($name))' graph.json`.
   - `/knowledge-graph publishers <event>` and `subscribers <event>`.
   - `/knowledge-graph registrations <interface>` — which installer registers this.
   - `/knowledge-graph scope-tree` — print the VContainer scope hierarchy.
   - `/knowledge-graph prefab <name>` — components, isVariant, basePrefab, domain.
   - `/knowledge-graph violations` — print `validation.errors[]` + `validation.warnings[]`.
   - `/knowledge-graph diff` — compare current `graph.json` with `graph.json.bak`.
2. [ ] Auto-build if stale: if `.last-build` is older than 24h, prompt user "Graph is stale — rebuild? (y/n)" before querying.
3. [ ] Each subcommand maps to a `jq` invocation specified inline in the command doc.
4. [ ] Output: human-readable table by default, `--json` flag for raw output.

**Test Type:** Manual — for each subcommand, run against a populated graph and verify the answer matches reality.

**Code Skeleton:**
```markdown
# /knowledge-graph — Query the Unity Knowledge Graph

## Subcommands

| Sub | Example | jq |
|-----|---------|----|
| summary | `/knowledge-graph summary` | `{classes: (.codebase.classes\|length), …}` |
| implementers | `/knowledge-graph implementers IDamageReceiver` | `.codebase.classes[] \| select(.implements \| index("IDamageReceiver"))` |
| publishers | `/knowledge-graph publishers PlayerDiedEvent` | `.codebase.events[] \| select(.name == "PlayerDiedEvent") \| .publishers` |
…

## Staleness check
If now() - graph.generated_at > 24h, ask before answering.
```

**Acceptance Criteria:**
- All 8 subcommands implemented and individually documented with their `jq` snippet.
- Staleness check prevents answering with day-old data without warning.
- `--json` flag passes raw output through unchanged.

---

## Task 10 — graph-auto-update.sh PostToolUse Hook

**Execution context:** Claude Code host process — NOT Unity Editor/runtime. Unity Editor is NOT required for this hook.

**Files:**
- Create: `.claude/hooks/graph-auto-update.sh`

**Steps:**

1. [ ] Hook reads `$TOOL_INPUT` from stdin, extracts `file_path` (matches the existing pattern in `auto-load-skills.sh`).
2. [ ] Filter: only proceed if the file extension is `.cs`, `.asmdef`, `.prefab`, or `.unity`. Otherwise exit 0.
3. [ ] Check feature flag: read `.claude/project-features.json`; if `.graph != true`, exit 0.
4. [ ] Check existence: if `.claude/graph/graph-builder.sh` is missing, exit 0 with stderr warning (do not block writes).
5. [ ] Run **non-blocking** in the background: `nohup bash .claude/graph/graph-builder.sh --incremental --changed-files "$FILE" --quiet --skip-mcp >/dev/null 2>&1 &`. The hook returns instantly — the user's next Write doesn't wait for the rebuild.
6. [ ] Log to `.claude/state/graph-updates.log` (one line per trigger): `<iso-ts> <file>`.
7. [ ] Exit 0 always (warn-only — the graph is advisory, never blocking).
8. [ ] **Do NOT** trigger MCP extraction from the hook — Unity Editor calls from a PostToolUse hook would be far too slow. MCP refresh happens only via `/build-knowledge-graph`.

**Test Type:** Manual — `echo '{"tool_input":{"file_path":"Assets/Foo.cs"}}' | bash .claude/hooks/graph-auto-update.sh`, verify the log line and that `graph.json` updates within ~1s.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
TOOL_INPUT=$(cat)
FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', d).get('file_path', ''))
except: print('')
")
[[ -z "$FILE_PATH" ]] && exit 0
case "$FILE_PATH" in
  *.cs|*.asmdef|*.prefab|*.unity) ;;
  *) exit 0 ;;
esac

FEATURES=".claude/project-features.json"
[[ -f "$FEATURES" ]] && [[ "$(jq -r '.graph // false' "$FEATURES")" == "true" ]] || exit 0
[[ -x ".claude/graph/graph-builder.sh" ]] || exit 0

mkdir -p .claude/state
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $FILE_PATH" >> .claude/state/graph-updates.log
nohup bash .claude/graph/graph-builder.sh --incremental --changed-files "$FILE_PATH" --quiet --skip-mcp >/dev/null 2>&1 &
exit 0
```

**Acceptance Criteria:**
- Hook is non-blocking (background process, returns <50ms).
- Respects the `graph` feature flag.
- Logs every trigger to `.claude/state/graph-updates.log`.
- Settings.json instructions for the user are in Task 18.

---

## Task 11 — Git post-commit Hook Installer

**Files:**
- Create: `.claude/hooks/install-git-hooks.sh`

**Steps:**

1. [ ] Script the user runs manually after `/setup-project`: `bash .claude/hooks/install-git-hooks.sh`.
2. [ ] Write `.git/hooks/post-commit` with contents:
   ```bash
   #!/usr/bin/env bash
   # Auto-installed by Unity Claude AI Template — full graph rebuild on commit.
   [[ -x .claude/graph/graph-builder.sh ]] || exit 0
   nohup bash .claude/graph/graph-builder.sh --full --skip-mcp >/dev/null 2>&1 &
   exit 0
   ```
3. [ ] `chmod +x .git/hooks/post-commit`.
4. [ ] If a `post-commit` hook already exists, refuse and tell the user to merge manually.
5. [ ] Also offer to install a `pre-commit` hook that runs `graph-validator.sh` and fails commit on `validation.errors[]` (opt-in via flag `--strict`).
6. [ ] Note in this file: "This is a one-time setup step run by the developer. Claude must NOT run it automatically."

**Test Type:** Manual — `git commit --allow-empty -m test` and watch `.last-build` update within a few seconds.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
HOOK=".git/hooks/post-commit"
if [[ -e "$HOOK" ]]; then
  echo "post-commit hook already exists — merge manually" >&2
  exit 1
fi
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
[[ -x .claude/graph/graph-builder.sh ]] || exit 0
nohup bash .claude/graph/graph-builder.sh --full --skip-mcp >/dev/null 2>&1 &
exit 0
EOF
chmod +x "$HOOK"
echo "Installed post-commit hook."
```

**Acceptance Criteria:**
- Refuses to clobber an existing hook.
- Background-only — never blocks `git commit`.
- `--strict` flag installs a pre-commit hook that fails on `validation.errors[]`.

---

## Task 12 — Watch Helper (fswatch wrapper)

**Files:**
- Create: `.claude/graph/graph-watch.sh`

**Steps:**

1. [ ] Wrapper around `fswatch` (mac) / `inotifywait` (linux) for developers who want continuous graph updates without relying on PostToolUse hooks.
2. [ ] On change in `Assets/**` matching `.cs|.asmdef|.prefab|.unity`, debounce 500ms, then run `graph-builder.sh --incremental --changed-files "$FILE"`.
3. [ ] Detect the watcher tool: `command -v fswatch || command -v inotifywait || (echo "Install fswatch or inotify-tools" && exit 1)`.
4. [ ] Run in foreground; user kills with Ctrl-C.
5. [ ] This is **optional infrastructure** — most users will rely on the PostToolUse hook + git post-commit hook combination from Tasks 10 and 11.

**Test Type:** Manual — start the watcher, touch a `.cs` file, verify graph updates within ~1s.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
set -euo pipefail
WATCHER=""
command -v fswatch >/dev/null && WATCHER="fswatch"
command -v inotifywait >/dev/null && WATCHER="${WATCHER:-inotifywait}"
[[ -z "$WATCHER" ]] && { echo "Install fswatch or inotify-tools" >&2; exit 1; }

# … debounce + invoke graph-builder.sh …
```

**Acceptance Criteria:**
- Works on macOS (fswatch) and Linux (inotifywait).
- 500ms debounce to avoid rebuild-storms during a save-all.
- Updates within ~1s of a file change.

---

## Task 13 — Rewrite /catch-up to Use Graph **[BLOCKED — needs investigation]**

**Files:**
- Edit: `.claude/commands/catch-up.md`

**[BLOCKED — needs investigation]** — the current `/catch-up` produces a 270-line markdown document with rich WHY/feature-guide narrative that the graph alone cannot generate. We must keep the narrative sections (Design Decisions, Feature Guide, Complexity Hotspots) and only replace the **discovery** steps (1–4). Before this task, a sub-investigation is needed:

- Q1: Does the graph contain enough to populate "Systems → Models → Views" table? **A:** Yes for Systems & Interfaces; partial for Models (need to extend Task 3 to flag any `class … : MonoBehaviour` or `class …Model` as a Model). May require extractor extension.
- Q2: Can `Feature Guide` (group-by-feature) be generated from the graph? **A:** Probably not — features come from GDD/TDD, not code. Keep this section file-based (read `docs/GDD.md`).
- Q3: Where does "Design Decisions" content come from? **A:** TDD + inference. Keep as-is.

**Steps:**

1. [ ] **Pre-Task investigation** (4-hour timebox): list every piece of data `/catch-up` currently emits, classify each as "graph-derivable" or "narrative-only".
2. [ ] **Replace Step 1 (Discover the Codebase)** with: "Check `project-features.json.graph`. If `false` → run original Glob file-scan (keep old path unchanged). If `true` → Read `.claude/graph/graph.json`. If graph missing, run `/build-knowledge-graph --full --skip-mcp` first."
3. [ ] **Replace Step 2 (Map the Architecture)** with: a jq snippet that pivots `vcontainer.installers` + `classes.implements` into the Systems → Models → Views table. Use confidence levels — flag any `AMBIGUOUS` entry inline.
4. [ ] **Replace Step 3 (Trace the Message Flow)** with: `jq '.codebase.events[]'` (the graph already has full publisher/subscriber lists).
5. [ ] **Replace Step 4 (Map the DI Container)** with: `jq '.codebase.vcontainer.scopes'` (already a hierarchy).
6. [ ] **Keep Steps 5–7 unchanged** (Design Decisions, Complexity & Risk, Feature Guide).
7. [ ] Add a new pre-step: "Step 0 — Verify Graph: if `.claude/graph/.last-build` is older than 24h, ask the user to rebuild."
8. [ ] Update the front-matter to mention graph dependency.

**Test Type:** Manual diff — run `/catch-up` against a real Unity project before and after, confirm the new output is no worse (and faster).

**Code Skeleton (sketch of replaced Steps 1–4):**
```markdown
### Step 1 — Read the Knowledge Graph

Read `.claude/graph/graph.json`. If missing or stale (>24h), tell the user:
"Graph missing or stale. Run `/build-knowledge-graph --full` first."

### Step 2 — Build the Architecture Map (from graph)

Pivot `.codebase.classes[]` × `.codebase.vcontainer.installers[]`:
```jq
.codebase.classes[]
| select(.name | endswith("System"))
| { System: .name, Implements: .implements, …}
```

### Step 3 — Trace Message Flow (from graph)

```jq
.codebase.events[] | { Message: .name, Publishers: .publishers, Subscribers: .subscribers }
```

### Step 4 — Map DI Container (from graph)

```jq
.codebase.vcontainer.scopes
```
```

**Acceptance Criteria:**
- Steps 1–4 each replaced with a single `jq` query.
- Steps 5–7 (narrative) unchanged.
- A 100-file project's `/catch-up` runtime drops from "scan everything" (~30s) to "read one JSON" (<2s).
- Confidence levels surface inline — `AMBIGUOUS` entries flagged in the output document.

---

## Task 14 — Rewrite /orchestrate Pre-Scan (lines 88–102)

**Files:**
- Edit: `.claude/commands/orchestrate.md`

**Steps:**

1. [ ] Locate lines 88–102 (the "Codebase Pre-Scan" block under Initialization step 5).
2. [ ] Replace the three `find` shell commands with a feature-flag guard:
   ```
   5. **Codebase Pre-Scan**:
      - Check `project-features.json.graph`. If `false` → run original `find`-based scan unchanged (keep old path).
      - If `true` → read `.claude/graph/graph.json`. If missing, run `/build-knowledge-graph --full --skip-mcp` first.
      - Query existing `_Framework/` content: `jq '.codebase.assemblies[] | select(.file | startswith("Assets/_Framework"))' graph.json`
      - Query existing Abstracts: `jq '.codebase.interfaces[] | select(.file | contains("/Games/Abstracts/"))' graph.json`
      - Query existing Concretes: `jq '.codebase.classes[] | select(.file | contains("/Games/Concretes/"))' graph.json`
      - Cross-reference each WORKFLOW.md task `outputs` against the graph. If a file already exists AND its class is properly registered (in some installer), mark the task as candidate to skip.
   ```
3. [ ] Keep the "Pre-Scan Report" output shape identical — same five lines (`_Framework:`, `Existing Abstracts:`, `Existing Concretes:`, `Conflicts with WORKFLOW.md:`, `Architecture issues found:`).
4. [ ] Add a new line at the end of Pre-Scan Report: `Graph confidence: [EXTRACTED / mostly_INFERRED]` — surfaces extractor mode to the developer.
5. [ ] Update step 6 (`EVENTS.jsonl`) to also append `"graph_generated_at":"<from graph.json>"`.

**Test Type:** Manual — run `/orchestrate` on a real WORKFLOW.md, confirm the Pre-Scan Report still appears and is now sourced from the graph.

**Code Skeleton:**
```markdown
5. **Codebase Pre-Scan** — read the knowledge graph:
   - Read `.claude/graph/graph.json`. If missing, stop and run `/build-knowledge-graph --full --skip-mcp` first.
   - Existing _Framework: `jq '.codebase.assemblies[] | select(.file | startswith("Assets/_Framework"))' graph.json`
   - Existing Abstracts:  `jq '.codebase.interfaces[] | select(.file | contains("/Games/Abstracts/"))' graph.json`
   - Existing Concretes:  `jq '.codebase.classes[]    | select(.file | contains("/Games/Concretes/"))' graph.json`
   - Print the Pre-Scan Report (5 lines unchanged + 1 new Graph confidence line).
```

**Acceptance Criteria:**
- No `find` invocations remain in lines 88–102.
- Pre-Scan Report format preserved (5 original lines + 1 added).
- Orchestrate fails gracefully if the graph doesn't exist (clear error pointing to `/build-knowledge-graph`).

---

## Task 15 — Rewrite /context-prime to Load Graph Summary

**Files:**
- Edit: `.claude/commands/context-prime.md`

**Steps:**

1. [ ] Insert a new **Step 2.5** between current steps 2 and 3:
   ```
   2.5. If `.claude/graph/graph.json` exists, read its summary:
        - Class count, interface count, event count, installer count
        - Scope tree (top-2 levels only)
        - `validation.errors` count + `validation.warnings` count
        Report these to the user in the summary block.
        If the graph is older than 24h, suggest `/build-knowledge-graph` before proceeding.
   ```
2. [ ] Keep existing Steps 1–5 numbering intact (just inserting 2.5).
3. [ ] Update the **Output** section: add a line "Graph: N classes, M events, K installers — generated <X> ago".
4. [ ] Note: the graph is **opt-in** via `project-features.json` — if `.graph != true`, skip Step 2.5 entirely.

**Test Type:** Manual — `/context-prime` should still work on a project without a graph (gracefully skipping 2.5), and report graph stats on a project that has one.

**Code Skeleton:**
```markdown
2.5. (optional, if graph feature enabled) Read `.claude/graph/graph.json` summary:
     - `jq '{ classes: (.codebase.classes|length), events: (.codebase.events|length), installers: (.codebase.vcontainer.installers|length), generated_at, errors: (.validation.errors|length) }'`
     - Surface to user.
     - If generated_at >24h old, suggest /build-knowledge-graph.
```

**Acceptance Criteria:**
- Step 2.5 inserted without renumbering existing steps.
- Gracefully skipped when graph feature is disabled.
- Adds ≤200ms to context-prime runtime.

---

## Task 16 — Wire /setup-project to Graph Feature Flag

**Files:**
- Edit: `.claude/commands/setup-project.md`

**Steps:**

1. [ ] In Step 1 (Gather Info), add a new question after the testing/addressables/ecs prompts: `"Enable Unity Knowledge Graph? (y/n, default: y) — auto-indexes codebase for /catch-up, /orchestrate, /context-prime."`.
2. [ ] In the feature-flag write step, persist the answer to `.claude/project-features.json` as `"graph": true|false`.
3. [ ] In the boilerplate-generation step, when `graph=true`:
   - Create `.claude/graph/` skeleton (already committed in template, just ensure not deleted).
   - Add a **Step 5.5 — Initial Graph Build:** print "Running initial graph build…" and execute `bash .claude/graph/graph-builder.sh --full --skip-mcp`.
   - Print "Initial graph: X classes, Y events. Run `/build-knowledge-graph --validate-with-codex` to cross-check accuracy."
4. [ ] In the manual-setup checklist output (Step 6 / final), add three lines:
   ```
   1. Add the settings.json PostToolUse entry — see Task 18 Step 7 for the exact JSON block.
   2. Install git post-commit hook: bash .claude/hooks/install-git-hooks.sh
   3. (optional) Run watch loop: bash .claude/graph/graph-watch.sh
   ```
5. [ ] When `graph=false`, skip all of the above.

**Test Type:** Manual — run `/setup-project` on a fresh project, confirm graph builds on completion and instructions print.

**Code Skeleton:**
```markdown
Q: Enable Unity Knowledge Graph? (y/n, default: y)

If y → set `project-features.graph = true`, run initial build, print pointer to Task 18 Step 7 for settings.json entry + git hook install command.
If n → set `project-features.graph = false`, skip.
```

**Acceptance Criteria:**
- New feature flag question appears in Step 1.
- `project-features.json` gets a `graph` key.
- Initial build runs successfully on a project with C# scripts.
- Manual setup checklist includes the three graph items.

---

## Task 17 — Reference Graph from refine-gdd / refine-tdd / architect

**Files:**
- Edit: `.claude/commands/refine-gdd.md`
- Edit: `.claude/commands/refine-tdd.md`
- Edit: `.claude/commands/architect.md`

**Steps:**

1. [ ] **`refine-gdd.md`** — add one bullet under existing context-loading: "If `project-features.json.graph = true` AND `.claude/graph/graph.json` exists, read its `assemblies[]` + scope tree for 'existing module' context. Otherwise proceed as before."
2. [ ] **`refine-tdd.md`** — add one bullet: "If `project-features.json.graph = true`, query `.claude/graph/graph.json` for existing implementers before specifying new ones. Otherwise proceed as before."
3. [ ] **`architect.md`** — find the step where the architect surveys `_Framework/`; prepend a feature-flag check: "If `project-features.json.graph = true`, read `.claude/graph/graph.json` instead of running `find`. Otherwise proceed with the existing `find` command."
4. [ ] No structural rewrites — each is a 1–3 line addition + one removed `find` reference where applicable.

**Test Type:** Manual — run `/refine-gdd` / `/refine-tdd` / `/architect` on a project with an existing graph, verify they cite graph data.

**Acceptance Criteria:**
- Each of the three commands references the graph in exactly one place.
- No duplicate-scanning logic remains in `architect.md`.
- Each addition is ≤3 lines.

---

## Task 18 — Update .claude/CLAUDE.md

**Files:**
- Edit: `.claude/CLAUDE.md`
- Edit: `.claude/docs/hooks-warning.md`

**Steps:**

1. [ ] **This is the very last code/doc change before Task 19.** Do NOT run earlier — CLAUDE.md describes the final state.
2. [ ] Add a new top-level section after `## Required Stack` (around line 25):
   ```
   ## Knowledge Graph

   The template ships with a Graphify-inspired knowledge graph at `.claude/graph/graph.json`.
   It is opt-in via `project-features.json.graph` and is the single source of truth for
   `/catch-up`, `/orchestrate` pre-scan, and `/context-prime`.

   Pipeline: detect → extract (C# / asmdef / MCP) → build → cluster → analyze → report → export.

   Commands:
   - `/build-knowledge-graph [--full|--incremental] [--validate-with-codex]`
   - `/knowledge-graph <summary|implementers|publishers|…>`

   See `.claude/graph/README.md` for schema and confidence levels.
   ```
3. [ ] In `## Hooks (auto-enforced on every Write/Edit)`, add a new row to the **Warning** subsection of `.claude/docs/hooks-warning.md`:
   ```
   | `graph-auto-update.sh` | Write/Edit | Triggers incremental graph rebuild in background — never blocks. |
   ```
4. [ ] In `## Optional Features`, add a row:
   ```
   | **Unity Knowledge Graph** | Built-in | `graph` | Skip extractors and hooks. The four graph-consuming commands (`/catch-up`, `/orchestrate`, `/context-prime`, `/architect`) retain their original file-scan paths unchanged — no graph queries, no regression. |
   ```
5. [ ] In the **Session Start** section, add: "If `.claude/graph/graph.json` exists, read its summary (use `/knowledge-graph summary`)."
6. [ ] Add a row to the `## Important Constraints` list: "`.claude/graph/graph.json` is generated — never edit by hand. Use `/build-knowledge-graph` to refresh."
7. [ ] Provide the manual `settings.json` snippet the user must add (Claude cannot edit `settings.json`):
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Write|Edit",
           "hooks": [
             { "type": "command", "command": "bash .claude/hooks/graph-auto-update.sh" }
           ]
         }
       ]
     }
   }
   ```
   Print this block in a code fence with the instruction: "Add this entry to `.claude/settings.json` under your existing PostToolUse hooks. Run `bash .claude/hooks/install-git-hooks.sh` once to also install the git post-commit hook."

**Test Type:** Manual review — every new section reads cleanly next to neighbours.

**Acceptance Criteria:**
- New `## Knowledge Graph` section is present and concise (<200 words).
- Hooks tables and Optional Features tables both updated.
- Constraints note added.
- settings.json snippet is present and correct.

---

## Task 19 — Update README.md

**Files:**
- Edit: `README.md`

**Steps:**

1. [ ] Add a new top-level section after `## Stack` (around line 157), titled `## Knowledge Graph`:
   ```
   ## Knowledge Graph

   `.claude/graph/` ships a Graphify-inspired Unity-specific knowledge graph.
   When enabled (default in `/setup-project`), the graph indexes every class,
   interface, event, installer, scope, asmdef, scene, and prefab into a single
   `graph.json` artifact. /catch-up, /orchestrate, and /context-prime all read
   this graph instead of scanning files from scratch.

   ### Quick commands
   | Command | Purpose |
   |---------|---------|
   | `/build-knowledge-graph [--full|--incremental]` | Build/refresh the graph |
   | `/build-knowledge-graph --validate-with-codex` | Spot-check graph accuracy with Codex |
   | `/knowledge-graph summary` | One-screen project overview |
   | `/knowledge-graph implementers <I>` | List concrete classes implementing an interface |
   | `/knowledge-graph publishers <E>` | List event publishers |

   ### Triggers (kept in sync automatically)
   - Every Write/Edit → PostToolUse `graph-auto-update.sh` (incremental, background)
   - Every `git commit` → post-commit hook (full rebuild)
   - Manual: `/build-knowledge-graph`

   ### Confidence levels
   `EXTRACTED` (explicit code), `INFERRED` (regex-mode or call-graph guess), `AMBIGUOUS` (needs human review).
   ```
2. [ ] In the `## Slash Commands` table (around line 359, under appropriate category):
   - Add a new category `### Knowledge Graph` (or place under `### Quality`):
     ```
     | `/build-knowledge-graph [flags]` | Manual or auto (hook+git) | Build the knowledge graph; `--validate-with-codex` cross-checks accuracy |
     | `/knowledge-graph <sub> [args]`  | Manual                    | Query the knowledge graph (summary/implementers/publishers/scope-tree/…)  |
     ```
3. [ ] In `## Configuration File Map` (around line 96), add:
   ```
   ### `.claude/graph/` — Knowledge graph
   - `schema.json` — JSON-Schema for `graph.json`
   - `graph.json` (generated) — living index of the codebase
   - `extractors/` — C# / asmdef / MCP extractors
   - `graph-builder.sh`, `graph-validator.sh`, `codex-validator.md`
   ```
4. [ ] In `## Hooks — Auto-Enforced on Every Write` (warning subsection), add a row for `graph-auto-update.sh`.
5. [ ] In the Table of Contents, add `- [Knowledge Graph](#knowledge-graph)` after `- [Stack](#stack)`.

**Test Type:** Manual — render README locally, verify TOC links, table formatting.

**Acceptance Criteria:**
- New `## Knowledge Graph` section ≤300 words, with one quick-command table + one triggers list.
- Two new rows in `## Slash Commands`.
- TOC updated.
- Configuration File Map updated.

---

## What Gets Removed / Replaced — Summary

| Location | Old behavior | New behavior |
|----------|--------------|--------------|
| `/catch-up.md` Steps 1–4 (file Glob + categorize + scope/message walk) | `Glob '*.cs'`, then read each file | One `jq` per step against `graph.json` |
| `/orchestrate.md` lines 88–102 (Codebase Pre-Scan) | Three `find` shell commands | Three `jq` queries against `graph.json` |
| `/context-prime.md` Steps 1–5 | Reads three markdown files | Same + new Step 2.5 reads graph summary |
| `/architect.md` `_Framework/` survey step | `find _Framework -type f` | `jq '.codebase.assemblies[]'` |
| Per-command, ad-hoc file scanning | Repeated on every command invocation | Centralized; happens once on Write/Edit + commit |

---

## Execution Ordering Dependencies

- **Phase 1 (Task 1)** must complete before any extractor work — every extractor consumes the schema.
- **Phase 2 (Tasks 2/3/4)** can run in parallel — each writes to a different file with no shared types.
- **Phase 3 (Task 5)** depends on all of Phase 2 — `graph-builder.sh` imports all extractor outputs.
- **Phase 4 (Tasks 6/7)** depends on Task 5 — both validators read `graph.json`.
- **Phase 5 (Tasks 8/9)** depends on Task 5 — both commands invoke the builder by reference.
- **Phase 6 (Tasks 10/11/12)** depends on Task 8 — all three triggers invoke `/build-knowledge-graph` by name.
- **Phase 7 (Tasks 13/14/15)** depends on Phase 6 — graph must be stable AND auto-refreshing before existing commands stop scanning.
- **Phase 8 (Tasks 16/17)** depends on Phase 7 — wiring setup/refine/architect requires the commands to already query the graph.
- **Phase 9 (Tasks 18/19)** must be LAST — docs describe the final state, never a half-built one.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| tree-sitter not installed → all C# data is `INFERRED` | Document install (`brew install tree-sitter`); regex mode is correct on common cases, just lower confidence |
| MCP not connected when builder runs | `--skip-mcp` flag + graceful no-op + `codebase.mcp_extraction.status: "skipped"` metadata |
| Graph drift (extractor bug → wrong claims) | Task 7 (Codex validation) catches it; run on every extractor change |
| Hook slows down Write/Edit | Background invocation (`nohup … &`); hook returns <50ms |
| Settings.json edits blocked by `check-config-protection.sh` | Task 16 prints exact JSON for the user to paste manually |
| Existing `.git/hooks/post-commit` clobbered | Task 11 refuses if file exists |
| `/catch-up` quality regression (Task 13) | **[BLOCKED — needs investigation]** sub-task confirms what is graph-derivable before rewriting |
| Cache corruption (file-hashes.json out of sync with graph) | Atomic writes; `--full` flag rebuilds from scratch |

---

## Out of Scope (deliberately)

- Web UI / visualization of the graph (Graphify has one; we don't need it yet — `/knowledge-graph` CLI queries suffice).
- Cross-project graphs (the graph is per-project).
- ECS-specific extraction (ISystem, IJobEntity registration) — punted to a follow-up plan once a project actually uses ECS.
- Embeddings / semantic search over the graph — punted.
- Real-time MCP-driven scene watching — runtime cost too high; we refresh MCP data only on explicit `/build-knowledge-graph`.

---

## Definition of Done

- [ ] `graph.json` exists, validates against `schema.json`, has non-empty `codebase.classes[]` on a real Unity project.
- [ ] `/build-knowledge-graph --full` completes in <30s on a 200-file project.
- [ ] `/build-knowledge-graph --incremental` after a one-file change completes in <2s.
- [ ] `/knowledge-graph summary` prints in <500ms.
- [ ] Codex validation (Task 7) reports ≥95% agreement on a 20-sample run.
- [ ] `/catch-up`, `/orchestrate`, `/context-prime` all read graph data and contain no `find` / `Glob '*.cs'` references for codebase discovery.
- [ ] `CLAUDE.md` and `README.md` both have a Knowledge Graph section.
- [ ] `.gitignore` correctly excludes generated artifacts.
- [ ] All hooks are non-blocking (exit 0, background invocation).
