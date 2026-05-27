
# PLAN — Unity Knowledge Graph (Graphify-Inspired)

> **Version:** v2 — 2026-05-25
> **Status:** v1 Complete (Tasks 1–19) — extending with Tasks 20–24 (Call Graph + Impact Analysis + Methods + Path + God-Nodes)
> **Scope:** `.claude/graph/` (extend), `.claude/commands/knowledge-graph.md` (extend)

> **v2 Revision Note — 2026-05-25**
>
> Adds the next layer of Graphify parity that the v1 build did not cover: a true **call graph** (caller→callee edges), **per-class method inventory**, **impact analysis** (multi-hop affected-node traversal), **shortest-path** search between two nodes, and **god-node** ranking (top N most-connected entities). Four new `/knowledge-graph` subcommands surface these (`callers`, `impact`, `path`, `god-nodes`). All five new tasks are **additive** — they extend the existing schema (`classes[].methods[]` + top-level `codebase.calls[]`), add a new Python traversal script (`.claude/graph/graph-traversal.py`), and append subcommands to the existing query command. No v1 behaviour changes; existing graphs upgrade in-place on the next `--full` build.

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

- [x] Define a versioned `graph.json` schema and reserve `.claude/graph/` as the system's home.
- [x] Ship three extractors: C# (tree-sitter + regex), .asmdef (JSON), scene/prefab (MCP).
- [x] Ship `graph-builder.sh` that aggregates extractor output, deduplicates, and writes `graph.json` with a SHA256-keyed file cache so unchanged files are skipped.
- [x] Ship `graph-validator.sh` that checks the graph against `.claude/rules/architecture.md` invariants (no singletons, all events have publisher+subscriber, every concrete is registered).
- [x] Ship `/build-knowledge-graph` (full or incremental build) and `/knowledge-graph` (query) slash commands.
- [x] Ship `graph-auto-update.sh` PostToolUse hook (incremental, file-scoped, fast) and a git `post-commit` hook (full rebuild) — both opt-in via `.claude/project-features.json`.
- [x] Use Codex to cross-check `graph.json` accuracy against ground-truth file scans.
- [x] Replace the file-scan logic inside `/catch-up`, `/orchestrate` pre-scan, and `/context-prime` with graph queries.
- [x] Wire `setup-project → GDD → TDD → orchestrate` so each step both consumes and feeds the graph.
- [x] Update `.claude/CLAUDE.md` and `README.md` last, documenting the final shape.
- [ ] **v2:** Extract a **call graph** (`calls[]` edges between classes/methods) with EXTRACTED (tree-sitter) and INFERRED (regex) confidence.
- [ ] **v2:** Extract a **methods[]** inventory per `classEntry` (name, signature, line, accessibility, is_async).
- [ ] **v2:** Ship `graph-traversal.py` for BFS impact analysis, shortest-path between two nodes, and god-node ranking.
- [ ] **v2:** Add 4 `/knowledge-graph` subcommands (`callers`, `impact`, `path`, `god-nodes`).

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Define `graph.json` schema + folder layout + `.gitignore` | Done | — |
| 2 | Task 2 — `.asmdef` extractor (`asmdef-extractor.sh`) | Done | A |
| 2 | Task 3 — C# extractor (`csharp-extractor.sh`) — tree-sitter + regex fallback | Done | A |
| 2 | Task 4 — MCP scene/prefab extractor (`mcp-extractor.md` skill) **[EDITOR/MCP — Unity Editor must be open]** | Done | A |
| 3 | Task 5 — `graph-builder.sh` aggregator + SHA256 cache | Done | — |
| 4 | Task 6 — `graph-validator.sh` (architecture invariants) | Done | B |
| 4 | Task 7 — Codex graph-accuracy validator (skill + invocation) | Done | B |
| 5 | Task 8 — `/build-knowledge-graph` slash command | Done | C |
| 5 | Task 9 — `/knowledge-graph` query slash command | Done | C |
| 6 | Task 10 — `graph-auto-update.sh` PostToolUse hook | Done | D |
| 6 | Task 11 — Git `post-commit` hook installer script | Done | D |
| 6 | Task 12 — Watch helper (`graph-watch.sh`, optional fswatch wrapper) | Done | D |
| 7 | Task 13 — Rewrite `/catch-up` to read graph **[BLOCKED — needs investigation]** | Done | E |
| 7 | Task 14 — Rewrite `/orchestrate` pre-scan (lines 88–102) to call graph | Done | E |
| 7 | Task 15 — Rewrite `/context-prime` to load graph summary | Done | E |
| 8 | Task 16 — Wire `/setup-project` → graph init + `project-features.json` flag | Done | F |
| 8 | Task 17 — Reference graph from GDD-refine / TDD-refine / architect | Done | F |
| 9 | Task 18 — Update `.claude/CLAUDE.md` with graph system section | Done | G |
| 9 | Task 19 — Update `README.md` with graph system section + Slash Commands table rows | Done | G |
| **10 (v2)** | **Task 20 — Extend `schema.json` with `methods[]` + top-level `calls[]`** | **Pending** | **—** |
| **10 (v2)** | **Task 21 — Extend `csharp-extractor.sh` to emit `methods[]` + per-file `calls[]`** | **Pending** | **H** |
| **10 (v2)** | **Task 22 — `graph-traversal.py` — BFS, impact, shortest-path, god-nodes** | **Pending** | **H** |
| **10 (v2)** | **Task 23 — `graph-builder.sh` — invoke `graph-traversal.py` to finalize `calls[]`** | **Pending** | **—** |
| **10 (v2)** | **Task 24 — Add `callers`/`impact`/`path`/`god-nodes` subcommands to `/knowledge-graph`** | **Pending** | **—** |

**Parallel groups:**
- **A** (Phase 2 — three extractors): different files, no type dependency, each consumes Task 1's schema only.
- **B** (Phase 4 — two validators): different files; both consume the graph but neither produces the other's input.
- **C** (Phase 5 — two commands): different files; both depend on Task 5's `graph-builder.sh` and Task 1's schema — no type dependency between them.
- **D** (Phase 6 — three trigger mechanisms): different files; all call `.claude/graph/graph-builder.sh` directly (hooks bypass the slash command layer for speed).
- **E** (Phase 7 — three command rewrites): different files; each independently consumes the now-stable `graph.json`.
- **F** (Phase 8 — workflow integration): different command files.
- **G** (Phase 9 — docs): different files, must run last.
- **H (v2)** (Phase 10 — extractor extension + traversal script): different files (`csharp-extractor.sh` vs `graph-traversal.py`); both consume Task 20's schema only — no inter-task imports. Task 23 (builder wiring) is **sequential** (depends on both H members) and Task 24 (subcommands) is **sequential** (depends on Task 23).

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
| **`.claude/graph/schema.json`** | **Edit (v2 — Task 20)** | **Add `methods[]` to `classEntry`; add top-level `codebase.calls[]`. Bump `schema_version` to `1.1.0`.** |
| **`.claude/graph/extractors/csharp-extractor.sh`** | **Edit (v2 — Task 21)** | **Extend `extract_class_info()` Python block to also capture methods + emit per-file `calls[]` (INFERRED in regex mode, EXTRACTED in tree-sitter mode).** |
| **`.claude/graph/graph-traversal.py`** | **Create (v2 — Task 22)** | **NEW: BFS impact/affected-nodes, shortest-path, god-node ranking. Pure Python 3 stdlib (no extra deps).** |
| **`.claude/graph/graph-builder.sh`** | **Edit (v2 — Task 23)** | **After merging extractor output, invoke `graph-traversal.py --finalize-calls` to dedupe & sort the top-level `calls[]` array.** |
| **`.claude/commands/knowledge-graph.md`** | **Edit (v2 — Task 24)** | **Append 4 new subcommands: `callers <Class.Method>`, `impact <ClassName> [--hops N]`, `path <NodeA> <NodeB>`, `god-nodes [--top N]`.** |

---

## Task 1 — Define graph.json Schema + Folder Layout + .gitignore

**Files:**
- Create: `.claude/graph/README.md`
- Create: `.claude/graph/schema.json`
- Create: `.claude/graph/cache/.gitkeep`
- Edit: `.gitignore`

**Steps:**

1. [x] Create `.claude/graph/README.md` with: purpose ("Graphify-inspired Unity knowledge graph"), pipeline diagram (detect → extract → build → cluster → analyze → report → export), pointer to `schema.json`, pointer to `/build-knowledge-graph`, lifecycle note ("graph.json is generated — do not edit by hand"), and a per-confidence legend (`EXTRACTED` / `INFERRED` / `AMBIGUOUS`).
2. [x] Create `.claude/graph/schema.json` — JSON-Schema (draft-07) describing the full graph. Top-level keys:
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
3. [x] Create `.claude/graph/cache/.gitkeep` (empty file so the directory is committed; actual cache entries are ignored).
4. [x] Add to `.gitignore`:
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

1. [x] Write a Bash script: `find Assets -name '*.asmdef' -print0 | while IFS= read -r -d '' f; do …`.
2. [x] For each `.asmdef`, use `jq` to extract `name`, `references[]`, `includePlatforms[]`, `excludePlatforms[]`, `allowUnsafeCode`, `defineConstraints[]`.
3. [x] Emit a JSON array on stdout — one object per asmdef — matching `codebase.assemblies[]` in the schema.
4. [x] Add `--changed-files <list>` flag: if provided, skip asmdefs not in the list (used by incremental hook).
5. [x] Always set `confidence: "EXTRACTED"` (asmdef is explicit machine-readable data).
6. [x] Exit 0 on success; non-zero with a single-line `ERR_*` token on failure.

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

1. [x] At script start, detect tree-sitter: `command -v tree-sitter >/dev/null && tree-sitter --version | grep -q '^tree-sitter '`. If absent, set `MODE=regex` and warn to stderr.
2. [x] Build the file list: either all `.cs` files under `Assets/_Framework/`, `Assets/_GameFolders/Scripts/`, and `Packages/` (skip `*.Tests.*` asmdef paths unless `--include-tests`), or just `--changed-files`.
3. [x] **In tree-sitter mode**, for each file run a small query (committed under `.claude/graph/extractors/queries/csharp.scm`) that captures:
   - `(class_declaration name: (identifier) @class.name (base_list (identifier) @class.implements)?)`
   - `(interface_declaration name: (identifier) @iface.name)`
   - constructor parameters (for VContainer ctor-injection → `dependencies[]`)
   - `[Inject]` method/property attributes
   - `builder.Register<T>` / `Register<T>().As<U>()` calls → `vcontainer.installers[].registrations[]`
   - `IEventBus.Publish<T>` / `Subscribe<T>` calls → `events[]` + `events_published/subscribed`
4. [x] **In regex mode**, use `grep -nE` patterns as a fallback:
   - Classes: `^\s*(public|internal)?\s*(sealed|abstract)?\s*class\s+(\w+)(\s*:\s*([\w<>,\s]+))?`
   - Interfaces: `^\s*(public|internal)?\s*interface\s+(I\w+)`
   - VContainer: `builder\.Register<([^>]+)>\(\s*Lifetime\.(\w+)\s*\)(?:\.As<([^>]+)>\(\))?`
   - EventBus pub: `\.Publish<([A-Za-z_][A-Za-z0-9_]*)>\(`
   - EventBus sub: `\.Subscribe<([A-Za-z_][A-Za-z0-9_]*)>\(`
   - Mark every regex-mode result `confidence: "INFERRED"` (not EXTRACTED — regex misses generics, partial classes, etc.).
   - Singleton detection: `static\s+(readonly\s+)?\w+\s+(Instance|Current|Shared|Main|Default)\b` or `static\s+\w+\s+_instance\b` → set `has_static_instance: true`.
   - Base type list: capture raw base list from class declaration → `base_types[]`. Set `is_mono_behaviour: true` if `"MonoBehaviour"` appears in `base_types[]`.
5. [x] Detect `Installer` classes: name ends with `Installer` AND implements `IInstaller` (or inherits `LifetimeScope`). Group their `Register<…>` calls under `vcontainer.installers[name].registrations`.
6. [x] Resolve event publishers/subscribers across files in a second pass: pivot the per-file list into the schema's `events[]` shape.
7. [x] Emit one JSON object on stdout with keys `classes`, `interfaces`, `events`, `vcontainer` — match the schema exactly.
8. [x] Honor `--changed-files`: only re-extract those files, then on stdout emit a **partial** payload tagged `"partial": true` for the builder to merge.

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

1. [x] Write this as a **skill / agent prompt** (not a shell script) because MCP tools are only available inside Claude. The file lives under `.claude/graph/extractors/` so it co-locates with the other extractors but is invoked by `/build-knowledge-graph`, not by `graph-builder.sh` directly.
2. [x] Frontmatter: `name: mcp-extractor`, `description: "Extracts scenes/prefabs/components into graph.json via MCP. EDITOR/MCP — Unity Editor must be open."`.
3. [x] Body sections:
   - **Inputs:** optional `--scenes <path,path>` and `--prefabs <dir>` filters; otherwise full project.
   - **Process** (must batch via `batch_execute` per the `unity-mcp-patterns` skill):
     1. **[PRE-CONDITION GATE — run first before any other step]** Read `.claude/skills/core/unity-mcp-patterns/SKILL.md`. Confirm which actions exist for scene hierarchy (`get_hierarchy` or equivalent), prefab info (`get_info`/`get_hierarchy`), and component reads. If any required action is absent, mark Task 4 `[BLOCKED — MCP action unconfirmed]` and stop.
     2. Scene extraction: use the confirmed `manage_scene` hierarchy action → list root GameObjects with components per scene.
     3. Component reads: use the confirmed component resource or `manage_components` read action → component type list per GameObject.
     4. Prefab listing: enumerate `.prefab` files via `find Assets -name '*.prefab'` (Bash), then use confirmed `manage_prefabs` info/hierarchy action to read component state per prefab.
     5. Detect Prefab Variants by checking `.prefab` YAML `m_PrefabParent` field via Bash grep — MCP does not expose variant metadata directly.
     6. Classify each prefab into a `domain` using the path heuristic from `unity-prefabs.md`: `UI`, `VFX`, `Enemies`, `Environment`, `Audio`, `Tools`, or `ThirdParty`.
   - **Output:** a JSON object with keys `scenes[]` and `prefabs[]` matching the schema, written to `.claude/graph/cache/mcp-extract.json` so the shell builder can pick it up.
   - **Failure modes:** if Unity Editor is not connected, exit 0 with empty `scenes: []` and `prefabs: []` output — the rest of the build still proceeds. Builder sets `codebase.mcp_extraction.status: "skipped"` and `skipped_reason: "MCP_UNAVAILABLE"` on the top-level metadata object. Do NOT set per-item confidence fields for MCP failures.
4. [x] Cross-reference `.claude/skills/core/unity-mcp-patterns/SKILL.md` (Rule 1 — batch_execute, Rule 2 — read_console) explicitly: the skill MUST be read before invocation.
5. [x] Mark **[EDITOR/MCP — Unity Editor must be open]** prominently — this is the only extractor that needs a live Unity Editor.

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

1. [x] Accept flags: `--full` (rebuild from scratch, ignore cache), `--incremental` (default — use cache), `--changed-files <comma-list>` (passed through to extractors), `--skip-mcp` (don't wait for Task 4 output), `--output <path>` (default `.claude/graph/graph.json`).
2. [x] Detect SHA256 tool: prefer `sha256sum`, fall back to `shasum -a 256` (mac).
3. [x] Load `.claude/graph/cache/file-hashes.json` (or start `{}`). Load existing `graph.json` into memory (or `{}` on first run). Build a set `current_paths` of all candidate files on disk (`.cs`, `.asmdef`, `.prefab`, `.unity`). For every candidate file:
   - Compute current hash.
   - If hash matches cache AND `--full` not set → **copy prior extracted entries for that file from existing `graph.json`** (keyed by `source_file` field on each node) into the new graph. Do NOT re-run the extractor.
   - Otherwise → mark for re-extraction. Remove stale entries for that file from the merge buffer.
   - **Purge ghost entries:** after processing all candidate files, remove any entries in the merge buffer whose `source_file` is NOT in `current_paths` (handles deleted and renamed files). Also remove their hashes from the hash cache.
4. [x] Invoke extractors:
   - `asmdef-extractor.sh --changed-files "$CHANGED_ASMDEFS"` → capture stdout.
   - `csharp-extractor.sh --changed-files "$CHANGED_CS"` → capture stdout.
   - For MCP: if `cache/mcp-extract.json` is fresher than 1 hour, reuse it; otherwise note "MCP refresh recommended" in stats (the actual run happens through `/build-knowledge-graph` — the shell builder cannot itself drive MCP).
5. [x] Merge per-file extractor output with retained cache entries → assemble the full `codebase` object.
6. [x] Compute `events[]` by pivoting publishers/subscribers across all class entries.
7. [x] Compute `validation.errors[]` placeholder (filled by Task 6 separately).
8. [x] Compute `stats`: `scanned_files`, `cache_hits`, `build_ms` (use `$SECONDS` or `date +%s%N`).
9. [x] Atomically write `.claude/graph/graph.json`: write to `graph.json.tmp`, `jq empty graph.json.tmp` to validate, then `mv` over.
10. [x] Update `.claude/graph/cache/file-hashes.json` (also atomic).
11. [x] Touch `.claude/graph/.last-build` with ISO timestamp.
12. [x] Print a one-line summary to stderr: `graph: 312 classes, 87 events, 12 installers (24 cached, 8 reparsed) in 412ms`.

**Test Type:** Unit-ish — run `--full`, capture output, re-run `--incremental` with no changes, verify all files marked as cache hits and runtime drops by >10×.

**Code Skeleton:** *(see v1 source)*

**Acceptance Criteria:**
- Idempotent; cache hit rate >90% on a no-op rebuild; output schema-valid; atomic writes.

---

## Task 6 — graph-validator.sh (Architecture Invariants)

*(Unchanged from v1 — Done.)*

---

## Task 7 — Codex Graph-Accuracy Validator

*(Unchanged from v1 — Done.)*

---

## Task 8 — /build-knowledge-graph Slash Command

*(Unchanged from v1 — Done.)*

---

## Task 9 — /knowledge-graph Query Command

*(Unchanged from v1 — Done. v2 extends this command in Task 24.)*

---

## Task 10 — graph-auto-update.sh PostToolUse Hook

*(Unchanged from v1 — Done.)*

---

## Task 11 — Git post-commit Hook Installer

*(Unchanged from v1 — Done.)*

---

## Task 12 — Watch Helper (fswatch wrapper)

*(Unchanged from v1 — Done.)*

---

## Task 13 — Rewrite /catch-up to Use Graph **[BLOCKED — needs investigation]**

*(Unchanged from v1 — Done.)*

---

## Task 14 — Rewrite /orchestrate Pre-Scan (lines 88–102)

*(Unchanged from v1 — Done.)*

---

## Task 15 — Rewrite /context-prime to Load Graph Summary

*(Unchanged from v1 — Done.)*

---

## Task 16 — Wire /setup-project to Graph Feature Flag

*(Unchanged from v1 — Done.)*

---

## Task 17 — Reference Graph from refine-gdd / refine-tdd / architect

*(Unchanged from v1 — Done.)*

---

## Task 18 — Update .claude/CLAUDE.md

*(Unchanged from v1 — Done.)*

---

## Task 19 — Update README.md

*(Unchanged from v1 — Done.)*

---

# Phase 10 (v2) — Call Graph + Methods + Impact + Path + God-Nodes

> The five tasks below are the **v2 addition**. They are **additive only** — no v1 task is rewritten. Bump `schema_version` from `1.0.0` to `1.1.0`. Old graphs continue to validate (the new fields are optional). The first `--full` build after this phase ships will populate `methods[]` and `calls[]`.

---

## Task 20 — Extend schema.json with methods[] + top-level calls[]

**Files:**
- Edit: `.claude/graph/schema.json`

**Steps:**

1. [ ] Bump `schema_version` default from `"1.0.0"` to `"1.1.0"`. Add a changelog note in the schema's top-level `description` field: `"v1.1.0 — Adds classEntry.methods[] and codebase.calls[] for call-graph + impact analysis."`.
2. [ ] Extend `classEntry` (under `definitions.classEntry.properties`) with an optional `methods` array:
   ```json
   "methods": {
     "type": "array",
     "description": "Methods declared on this class. Optional — populated by csharp-extractor.sh from v1.1.0+.",
     "items": {
       "type": "object",
       "required": ["name"],
       "properties": {
         "name":          { "type": "string" },
         "signature":     { "type": "string", "description": "Full signature minus body, e.g. 'public async UniTask Foo(int x)'." },
         "line":          { "type": "integer" },
         "accessibility": { "type": "string", "enum": ["public", "internal", "private", "protected"] },
         "is_async":      { "type": "boolean" },
         "is_static":     { "type": "boolean" },
         "return_type":   { "type": "string" }
       }
     }
   }
   ```
3. [ ] Add a new top-level `calls` array under `definitions.codebase.properties`:
   ```json
   "calls": {
     "type": "array",
     "description": "Call edges between methods. Top-level so traversal is O(edges) without scanning classes[].",
     "items": { "$ref": "#/definitions/callEdge" }
   }
   ```
4. [ ] Add a new `callEdge` definition under `definitions`:
   ```json
   "callEdge": {
     "type": "object",
     "required": ["caller", "callee", "confidence"],
     "properties": {
       "caller":     { "type": "string", "description": "Qualified caller — 'ClassName.MethodName' or 'Namespace.ClassName.MethodName'." },
       "callee":     { "type": "string", "description": "Qualified callee — same format. May be unqualified ('MethodName') for INFERRED edges where the receiver type can't be resolved." },
       "file":       { "type": "string", "description": "Source file containing the call site." },
       "line":       { "type": "integer" },
       "confidence": { "$ref": "#/definitions/confidence" }
     }
   }
   ```
5. [ ] Both new fields are **optional** — `required` arrays are unchanged. Old `graph.json` files (without `methods[]` or `calls[]`) continue to validate.
6. [ ] Run `jq empty .claude/graph/schema.json` to confirm valid JSON. Run `python3 -c "import jsonschema; jsonschema.Draft7Validator.check_schema(__import__('json').load(open('.claude/graph/schema.json')))"` to confirm draft-07 conformance.

**Test Type:** NoTest — schema-only edit (`.claude/graph/` JSON file, per the Test Type Decision Matrix). Manual validation: schema parses and existing v1.0.0 graph.json still validates against v1.1.0 schema.

**Code Skeleton (insertion sketch):**
```json
"classEntry": {
  "properties": {
    "name": { "type": "string" },
    "...existing fields...": "...",
    "methods": {
      "type": "array",
      "items": { "$ref": "#/definitions/methodEntry" }
    },
    "confidence": { "$ref": "#/definitions/confidence" }
  }
},
"methodEntry": { "type": "object", "required": ["name"], "properties": { ... } },
"callEdge":   { "type": "object", "required": ["caller","callee","confidence"], "properties": { ... } }
```

**Acceptance Criteria:**
- `schema_version` is `"1.1.0"`.
- Both `methods[]` and `calls[]` are optional fields — old graphs still validate.
- `jq empty` and `jsonschema.Draft7Validator.check_schema` both pass on the updated file.
- Confidence enum (`EXTRACTED` / `INFERRED` / `AMBIGUOUS`) reused — no new confidence values introduced.

---

## Task 21 — Extend csharp-extractor.sh to Emit methods[] + Per-File calls[]

**Files:**
- Edit: `.claude/graph/extractors/csharp-extractor.sh`
- Edit (if tree-sitter mode is implemented in v1): `.claude/graph/extractors/queries/csharp.scm`

**Steps:**

1. [ ] Locate the existing `extract_class_info()` Python block inside `csharp-extractor.sh` (v1 emits classes/interfaces/events). Extend it to also capture method declarations. Use a regex pass over the file's content lines:
   ```python
   # Method declaration regex (regex mode — INFERRED confidence)
   METHOD_RE = re.compile(
       r'^\s*(?P<acc>public|internal|private|protected)?\s*'
       r'(?P<mods>(?:static\s+|virtual\s+|override\s+|abstract\s+|sealed\s+|async\s+)*)'
       r'(?P<ret>[A-Za-z_][\w<>,\s\[\]\?\.]*?)\s+'
       r'(?P<name>[A-Z]\w*)\s*\([^)]*\)\s*(?:\{|=>|;)',
       re.MULTILINE
   )
   ```
   For each match, emit `{ "name": ..., "signature": <line trimmed>, "line": <1-based>, "accessibility": <acc or "private">, "is_async": "async" in mods, "is_static": "static" in mods, "return_type": <ret stripped> }`. Skip matches whose `name` is a known C# keyword (`if`, `while`, `for`, `switch`, `using`, `new`, `return`, `throw`, `catch`).
2. [ ] Attach the resulting `methods[]` array to the current class entry. If a file contains multiple classes, scope methods by tracking the most recent `class_declaration` line via simple bracket-depth counting.
3. [ ] Add a **second regex pass** for call sites — emit per-file partial `calls[]` entries (INFERRED confidence in regex mode):
   ```python
   # Call site regex — captures `Foo(` or `this.Foo(` or `obj.Foo(`
   CALL_RE = re.compile(
       r'(?:(?P<recv>[A-Za-z_][\w\.]*)\s*\.\s*)?(?P<callee>[A-Z]\w*)\s*\(',
       re.MULTILINE
   )
   ```
   For each call site, the "caller" is the **enclosing method** at that line (track via the bracket-depth counter from Step 2). Emit `{ "caller": "<ClassName>.<MethodName>", "callee": "<recv>.<callee>" or "<callee>", "file": rel_path, "line": line_no, "confidence": "INFERRED" }`.
4. [ ] **Filter noise** before emitting `calls[]`:
   - Skip control flow keywords (`if`, `while`, `for`, `foreach`, `switch`, `return`, `using`, `typeof`, `nameof`, `lock`, `fixed`, `await`).
   - Skip generic-type-parameter false positives (e.g. `List<Foo>(` matches `Foo(` — filter when preceded by `<`).
   - Skip primitive constructors and well-known BCL types (`int`, `string`, `bool`, `Vector3`, `Quaternion`, `Color`, `Debug`, `Math`, `Mathf`) unless explicitly enabled via `--include-bcl-calls`.
   - Skip self-references where caller == callee (probably recursion in regex mode is rarely useful).
5. [ ] **In tree-sitter mode** (when v1 already uses it), extend `.claude/graph/extractors/queries/csharp.scm` with method + call-site captures:
   ```scheme
   ; Method declarations
   (method_declaration
     name: (identifier) @method.name
     parameters: (parameter_list) @method.params) @method.decl
   ; Call expressions
   (invocation_expression
     function: [(identifier) @call.callee
                (member_access_expression name: (identifier) @call.callee)]) @call.site
   ```
   Mark tree-sitter-derived edges `confidence: "EXTRACTED"`. Regex-derived edges remain `"INFERRED"`.
6. [ ] Add a top-level `partial_calls` key to the extractor's stdout JSON when running in `--changed-files` mode so `graph-builder.sh` can merge per-file rebuilds without re-deriving the whole call graph:
   ```json
   { "partial": true, "classes": [...], "events": [...], "partial_calls": [ ... per-file edges ... ] }
   ```
7. [ ] Sort `methods[]` by `line` ascending and `calls[]` by `caller` then `line` before emit for idempotency.

**Test Type:** NoTest — extractor is a shell script under `.claude/graph/` (per the Test Type Decision Matrix). Manual validation:
- Run `bash .claude/graph/extractors/csharp-extractor.sh` against a Unity project with known classes; spot-check that every public method appears in `methods[]` and at least one `calls[]` edge appears per method that invokes another method.
- Verify regex mode never produces a `calls[]` entry whose callee is a C# keyword.

**Code Skeleton (Python block extension inside the extractor):**
```python
# Inside extract_class_info() — after class/event extraction:

# Method extraction
methods_for_class = []
for m in METHOD_RE.finditer(class_body):
    name = m.group('name')
    if name in CSHARP_KEYWORDS:
        continue
    methods_for_class.append({
        "name": name,
        "signature": m.group(0).strip().rstrip('{=>;').strip(),
        "line": line_of(m.start()),
        "accessibility": m.group('acc') or "private",
        "is_async": "async" in (m.group('mods') or ""),
        "is_static": "static" in (m.group('mods') or ""),
        "return_type": (m.group('ret') or "").strip()
    })

# Call-site extraction (per file, post-method-scope assignment)
calls_for_file = []
for c in CALL_RE.finditer(file_content):
    callee = c.group('callee')
    if callee in CSHARP_KEYWORDS or callee in BCL_NOISE:
        continue
    enclosing_method = method_at_line(line_of(c.start()), methods_for_class)
    if not enclosing_method:
        continue
    calls_for_file.append({
        "caller": f"{class_name}.{enclosing_method}",
        "callee": (f"{c.group('recv')}.{callee}" if c.group('recv') else callee),
        "file": rel_path,
        "line": line_of(c.start()),
        "confidence": "INFERRED"  # EXTRACTED in tree-sitter mode
    })
```

**Acceptance Criteria:**
- Every class entry includes a `methods[]` array (may be empty for interface-only or attribute-only files).
- Output JSON includes `partial_calls[]` in `--changed-files` mode and a full `calls[]` for full-extract mode.
- Regex mode: every edge has `confidence: "INFERRED"`. Tree-sitter mode: `"EXTRACTED"`.
- Idempotency: running twice on the same file produces byte-identical output (sort before emit).
- Schema-valid: `python3 -c "import jsonschema, json; jsonschema.validate(json.load(open(out)), json.load(open(schema)))"` passes.

---

## Task 22 — graph-traversal.py — BFS, Impact, Shortest-Path, God-Nodes

**Files:**
- Create: `.claude/graph/graph-traversal.py`

**Steps:**

1. [x] Create `.claude/graph/graph-traversal.py` — pure Python 3 stdlib (no `pip` deps). Shebang `#!/usr/bin/env python3`. Make it executable (`chmod +x`).
2. [x] Top-level CLI via `argparse`:
   ```
   graph-traversal.py impact <Class[.Method]> [--hops N] [--graph PATH] [--json]
   graph-traversal.py callers <Class.Method>   [--graph PATH] [--json]
   graph-traversal.py path <NodeA> <NodeB>     [--graph PATH] [--json]
   graph-traversal.py god-nodes                [--top N] [--graph PATH] [--json]
   graph-traversal.py --finalize-calls         [--graph PATH]   # builder hook (Task 23)
   ```
   Default `--graph` is `.claude/graph/graph.json`. Default `--hops` is `3`. Default `--top` is `10`.
3. [x] **Build the in-memory graph** in a single helper:
   ```python
   def load_graph(path):
       with open(path) as f:
           g = json.load(f)
       edges = g.get("codebase", {}).get("calls", [])
       forward = defaultdict(set)   # caller -> {callee}
       reverse = defaultdict(set)   # callee -> {caller}
       for e in edges:
           forward[e["caller"]].add(e["callee"])
           reverse[e["callee"]].add(e["caller"])
       return g, forward, reverse
   ```
4. [ ] **`impact <node>`** (affected-nodes): BFS forward + reverse from `node` up to `--hops` depth. Output:
   ```json
   { "root": "X", "hops": 3, "downstream": [...], "upstream": [...], "total_affected": N }
   ```
   "downstream" = transitively callable from `node` (what `node` reaches). "upstream" = transitive callers of `node` (what reaches `node`). Both deduplicated. Return JSON when `--json` set; otherwise pretty-print a two-column table.
5. [ ] **`callers <Class.Method>`**: One-hop reverse lookup. Output JSON `[{ "caller": "...", "file": "...", "line": N, "confidence": "..." }]`. If the callee node has no incoming edges, print `No direct callers found for X.` and exit 0.
6. [ ] **`path <A> <B>`**: BFS shortest path on the `forward` graph from `A` to `B`. Output:
   ```json
   { "from": "A", "to": "B", "length": K, "path": ["A", "...", "B"] }
   ```
   If no path exists, exit 1 with `No path from A to B in the call graph.` to stderr. If `A == B`, exit 0 with `length: 0, path: [A]`.
7. [ ] **`god-nodes`**: Compute in-degree + out-degree for every node mentioned in `calls[]` (use a `Counter`); rank by `(in_degree + out_degree)` descending; emit top N as:
   ```json
   [{ "node": "...", "in": K, "out": M, "total": K+M }, ...]
   ```
   Highlight: anything with `total > 20` gets flagged with `"is_god_node": true`. Source the per-node file from `classes[].file` when the node is a class — otherwise leave `file` null.
8. [ ] **`--finalize-calls`**: read `graph.json`, sort `codebase.calls[]` by `(caller, line)`, dedupe identical edges (same caller+callee+file+line), promote tie-broken confidence (`EXTRACTED` wins over `INFERRED` when the same edge is emitted by both regex + tree-sitter passes), and atomically rewrite `graph.json`. This is the Task 23 hook point.
9. [ ] **Performance budget:** for a 1000-class project (~10k edges), every query should finish in <200 ms. Use `collections.deque` for BFS, `defaultdict(set)` for adjacency.
10. [ ] **Error handling:**
    - If `graph.json` is missing → exit 2 with `ERR_GRAPH_MISSING: run /build-knowledge-graph first.` to stderr.
    - If `codebase.calls[]` is absent or empty → for `impact`/`path`/`god-nodes`, exit 0 with `Graph has no call edges yet. Rebuild with: /build-knowledge-graph --full` to stderr.
    - If a queried node isn't in the graph → exit 0 with a clear `Node 'X' not found in graph. Did you mean: Y, Z?` (use `difflib.get_close_matches` for suggestions).

**Test Type:** NoTest — Python script under `.claude/graph/` (per the Test Type Decision Matrix). Manual validation:
- Build a fixture `graph.json` with 5 classes and 10 known edges; run each subcommand and verify the output matches the hand-derived expected result.
- Run `time python3 graph-traversal.py impact SomeClass.Foo --hops 5` on a real graph and confirm <200ms.

**Code Skeleton:**
```python
#!/usr/bin/env python3
"""Knowledge graph traversal — impact, callers, path, god-nodes."""
import argparse, json, sys
from collections import defaultdict, deque, Counter
import difflib

def load_graph(path):
    with open(path) as f:
        g = json.load(f)
    edges = g.get("codebase", {}).get("calls", [])
    forward, reverse = defaultdict(set), defaultdict(set)
    for e in edges:
        forward[e["caller"]].add(e["callee"])
        reverse[e["callee"]].add(e["caller"])
    return g, forward, reverse, edges

def bfs(adj, start, max_hops):
    seen, frontier, depth = {start}, deque([(start, 0)]), 0
    out = []
    while frontier:
        node, d = frontier.popleft()
        if d >= max_hops: continue
        for nxt in adj.get(node, ()):
            if nxt in seen: continue
            seen.add(nxt); out.append((nxt, d+1))
            frontier.append((nxt, d+1))
    return out

def cmd_impact(args, ctx):
    _, fwd, rev, _ = ctx
    down = [n for n, _ in bfs(fwd, args.node, args.hops)]
    up   = [n for n, _ in bfs(rev, args.node, args.hops)]
    print(json.dumps({"root": args.node, "hops": args.hops,
                      "downstream": sorted(down), "upstream": sorted(up),
                      "total_affected": len(set(down)|set(up))}, indent=2))

def cmd_callers(args, ctx):
    _, _, rev, edges = ctx
    hits = [e for e in edges if e["callee"] == args.node]
    print(json.dumps(hits, indent=2))

def cmd_path(args, ctx):
    _, fwd, _, _ = ctx
    if args.a == args.b:
        print(json.dumps({"from": args.a, "to": args.b, "length": 0, "path": [args.a]})); return
    prev, frontier, seen = {}, deque([args.a]), {args.a}
    while frontier:
        n = frontier.popleft()
        if n == args.b: break
        for nxt in fwd.get(n, ()):
            if nxt in seen: continue
            seen.add(nxt); prev[nxt] = n; frontier.append(nxt)
    if args.b not in prev:
        print(f"No path from {args.a} to {args.b}.", file=sys.stderr); sys.exit(1)
    path = [args.b]
    while path[-1] != args.a: path.append(prev[path[-1]])
    path.reverse()
    print(json.dumps({"from": args.a, "to": args.b, "length": len(path)-1, "path": path}, indent=2))

def cmd_god_nodes(args, ctx):
    g, fwd, rev, _ = ctx
    nodes = set(fwd.keys()) | set(rev.keys())
    ranked = sorted(
        ({"node": n, "in": len(rev[n]), "out": len(fwd[n]),
          "total": len(rev[n]) + len(fwd[n])} for n in nodes),
        key=lambda x: -x["total"]
    )[:args.top]
    for r in ranked:
        r["is_god_node"] = r["total"] > 20
    print(json.dumps(ranked, indent=2))

# argparse + dispatch + --finalize-calls ...
```

**Acceptance Criteria:**
- All four subcommands implemented and return schema-shaped JSON.
- `--hops` defaults to 3 for `impact`; `--top` defaults to 10 for `god-nodes`.
- `--finalize-calls` mode dedupes + sorts the `calls[]` array in place.
- BFS-style queries finish in <200ms on a 10k-edge graph (validated by `time` on a real run).
- Missing node → close-match suggestion via `difflib`.
- Pure stdlib — no `pip install` needed.

---

## Task 23 — graph-builder.sh Wires graph-traversal.py for Call-Graph Finalization

**Files:**
- Edit: `.claude/graph/graph-builder.sh`

**Steps:**

1. [ ] After Step 5 of v1 Task 5 ("Merge per-file extractor output with retained cache entries") and before Step 6 (event pivot), add a new step:
   ```
   5.5. Finalize call graph:
        - If extractor emitted partial_calls[] (per-file), append them to .codebase.calls[] in the merge buffer.
        - Drop any call edge whose caller's source_file is no longer in current_paths (ghost-edge purge).
        - Invoke: python3 .claude/graph/graph-traversal.py --finalize-calls --graph "$TMP_GRAPH"
          (this dedupes + sorts + promotes confidence in place).
   ```
2. [ ] In the cache-hit copy logic, when a file's hash matches and its old class entries are reused, also reuse the corresponding edges from the old `codebase.calls[]`: filter by `e.file == cached_file` and copy verbatim. This keeps the call graph consistent with the incremental cache.
3. [ ] In the ghost-purge pass (existing logic in Step 3 of v1 Task 5), extend the purge to also drop `codebase.calls[]` entries whose `file` no longer exists.
4. [ ] Update the one-line stderr summary at end of build to include edge count:
   ```
   graph: 312 classes (1,840 methods), 87 events, 12 installers, 2,103 call edges (24 cached, 8 reparsed) in 412ms
   ```
5. [ ] Skip Step 5.5 silently if `python3` is unavailable on PATH — log a warning to stderr (`graph-builder: python3 not found, skipping call-graph finalization (impact/path/god-nodes queries will be unavailable)`) and continue. The graph is still useful without the calls array.

**Test Type:** NoTest — shell script under `.claude/graph/` (per the Test Type Decision Matrix). Manual validation:
- Run `--full` build; verify `codebase.calls[]` is non-empty and sorted.
- Touch one file, re-run `--incremental --changed-files <file>`; verify only that file's edges are re-derived (the rest are reused from cache).
- Delete a file and re-run incremental; verify all its call edges are purged.

**Code Skeleton (insertion sketch):**
```bash
# After merging extractor output into $TMP_GRAPH:
if command -v python3 >/dev/null 2>&1; then
  python3 .claude/graph/graph-traversal.py --finalize-calls --graph "$TMP_GRAPH" \
    || echo "graph-builder: call-graph finalization failed (non-fatal)" >&2
else
  echo "graph-builder: python3 not found — skipping call-graph finalization" >&2
fi
# Then continue with event pivot + atomic mv to graph.json
```

**Acceptance Criteria:**
- After a `--full` build, `codebase.calls[]` exists, is sorted by `(caller, line)`, and contains no duplicate edges.
- After an `--incremental` build touching one file, edges from other files are reused without re-derivation.
- Build summary mentions edge count.
- Builder degrades gracefully (warns, doesn't fail) when `python3` is absent.

---

## Task 24 — Add 4 New Subcommands to /knowledge-graph

**Files:**
- Edit: `.claude/commands/knowledge-graph.md`

**Steps:**

1. [ ] In the **Usage** block at the top of `knowledge-graph.md`, append the four new subcommands after the existing list:
   ```
   /knowledge-graph callers <Class.Method>
   /knowledge-graph impact <ClassName> [--hops N]
   /knowledge-graph path <NodeA> <NodeB>
   /knowledge-graph god-nodes [--top N]
   ```
2. [ ] After the existing `diff` subcommand section, append four new sections — one per subcommand. Each section follows the existing format (heading, one-line description, code block with the invocation).
3. [ ] **`callers <Class.Method>`** — direct (one-hop) reverse lookup. Prefer Python (consistent CLI), with a `jq` fallback for users who don't have python3:
   ```markdown
   ### callers \<Class.Method\>
   List all call sites that invoke the given method.

   ```bash
   python3 .claude/graph/graph-traversal.py callers "<Class.Method>"
   ```

   Fallback (no python3):
   ```bash
   jq --arg name "<Class.Method>" '
     [.codebase.calls[] | select(.callee == $name)]
     | map({caller: .caller, file: .file, line: .line, confidence: .confidence})
   ' .claude/graph/graph.json
   ```
   ```
4. [ ] **`impact <ClassName>`** — multi-hop BFS via Python (jq is too slow for transitive closure):
   ```markdown
   ### impact \<ClassName\> [--hops N]
   Show downstream + upstream affected nodes within N hops (default 3).

   ```bash
   python3 .claude/graph/graph-traversal.py impact "<ClassName>" --hops "${HOPS:-3}"
   ```

   Use this before refactoring a class to estimate blast radius.
   ```
5. [ ] **`path <NodeA> <NodeB>`** — shortest path via BFS:
   ```markdown
   ### path \<NodeA\> \<NodeB\>
   Find the shortest call-graph path between two methods.

   ```bash
   python3 .claude/graph/graph-traversal.py path "<NodeA>" "<NodeB>"
   ```

   Exits 1 if no path exists.
   ```
6. [ ] **`god-nodes [--top N]`** — top-N most-connected nodes:
   ```markdown
   ### god-nodes [--top N]
   Top N nodes by (in_degree + out_degree). Default N = 10.
   Nodes with total > 20 are flagged `is_god_node: true` — candidates for refactor.

   ```bash
   python3 .claude/graph/graph-traversal.py god-nodes --top "${TOP:-10}"
   ```

   Pure-jq alternative (lower fidelity — no per-node degree breakdown):
   ```bash
   jq '[.codebase.calls[] | .caller, .callee]
       | group_by(.) | map({node: .[0], count: length})
       | sort_by(-.count) | .[0:10]' .claude/graph/graph.json
   ```
   ```
7. [ ] At the bottom of the file, add a small **"When to use which"** matrix so the user picks the right query:
   ```
   | Question | Use |
   |---|---|
   | "Who calls this method?" | `callers` |
   | "What breaks if I change this class?" | `impact` |
   | "How does X end up calling Y?" | `path` |
   | "Which classes do too much?" | `god-nodes` |
   ```
8. [ ] Update the **Staleness Check** block to also warn when `codebase.calls[]` is empty (i.e. the graph was built before v1.1.0): print `⚠ Graph has no call edges (built before v1.1.0). Rebuild with /build-knowledge-graph --full to enable callers/impact/path/god-nodes.`

**Test Type:** NoTest — markdown command file under `.claude/commands/` (per the Test Type Decision Matrix). Manual validation:
- Run each new subcommand against a real graph; verify the output matches what `graph-traversal.py` returns directly.
- Confirm the jq fallback for `callers` returns the same set of `.caller` values (modulo formatting) as the Python version.

**Code Skeleton (appended to knowledge-graph.md):**
```markdown
---

### callers <Class.Method>
List all call sites that invoke the given method.

```bash
python3 .claude/graph/graph-traversal.py callers "<Class.Method>"
```

---

### impact <ClassName> [--hops N]
Show downstream + upstream affected nodes within N hops (default 3).

```bash
python3 .claude/graph/graph-traversal.py impact "<ClassName>" --hops 3
```

---

### path <NodeA> <NodeB>
Shortest call-graph path between two methods.

```bash
python3 .claude/graph/graph-traversal.py path "<NodeA>" "<NodeB>"
```

---

### god-nodes [--top N]
Top N most-connected nodes (in_degree + out_degree).

```bash
python3 .claude/graph/graph-traversal.py god-nodes --top 10
```
```

**Acceptance Criteria:**
- All four subcommands are documented with a one-line description + invocation block + (where useful) jq fallback.
- The "When to use which" matrix appears at the bottom.
- Staleness check covers the v1.0.0 → v1.1.0 transition (warn when `calls[]` is empty).
- File still parses cleanly as markdown.

---

## What Gets Removed / Replaced — Summary

| Location | Old behavior | New behavior |
|----------|--------------|--------------|
| `/catch-up.md` Steps 1–4 (file Glob + categorize + scope/message walk) | `Glob '*.cs'`, then read each file | One `jq` per step against `graph.json` |
| `/orchestrate.md` lines 88–102 (Codebase Pre-Scan) | Three `find` shell commands | Three `jq` queries against `graph.json` |
| `/context-prime.md` Steps 1–5 | Reads three markdown files | Same + new Step 2.5 reads graph summary |
| `/architect.md` `_Framework/` survey step | `find _Framework -type f` | `jq '.codebase.assemblies[]'` |
| Per-command, ad-hoc file scanning | Repeated on every command invocation | Centralized; happens once on Write/Edit + commit |
| **v2:** "Who calls this method?" | Manual grep | `/knowledge-graph callers X.Y` |
| **v2:** "Blast radius of refactoring X?" | Manual reasoning | `/knowledge-graph impact X` |
| **v2:** "How does A reach B?" | Manual code tracing | `/knowledge-graph path A B` |
| **v2:** "Which classes are over-coupled?" | Manual review | `/knowledge-graph god-nodes` |

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
- **Phase 10 (v2) ordering:**
  - **Task 20** (schema bump) must complete first — Tasks 21 and 22 both read the new shape.
  - **Tasks 21 + 22** run in parallel (group H) — different files, no shared types.
  - **Task 23** (builder wiring) depends on both Task 21 (extractor emits `partial_calls[]`) AND Task 22 (`--finalize-calls` mode exists).
  - **Task 24** (subcommands) depends on Task 22 — every new subcommand shells out to `graph-traversal.py`.

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
| **v2:** regex-mode call extraction emits noise (BCL types, generics) | Curated `BCL_NOISE` + `CSHARP_KEYWORDS` denylist in Task 21; tree-sitter mode supersedes when available |
| **v2:** `python3` missing on the user's machine breaks impact/path/god-nodes | Task 23 logs a warning and skips finalization; Task 24 documents a jq fallback for `callers`/`god-nodes` |
| **v2:** call-graph explodes runtime on a 5k-class project | BFS budgets in Task 22 (`<200ms` on 10k edges); incremental reuse in Task 23 keeps full rebuilds rare |
| **v2:** `calls[]` deduplication merges edges with conflicting confidence | Task 22 `--finalize-calls` promotes `EXTRACTED` over `INFERRED` deterministically |
| **v2:** "ClassName.MethodName" ambiguous for overloads | Acceptable for v2 — overload disambiguation deferred (signature in `methods[].signature` is available but not part of the call-graph key) |

---

## Out of Scope (deliberately)

- Web UI / visualization of the graph (Graphify has one; we don't need it yet — `/knowledge-graph` CLI queries suffice).
- Cross-project graphs (the graph is per-project).
- ECS-specific extraction (ISystem, IJobEntity registration) — punted to a follow-up plan once a project actually uses ECS.
- Embeddings / semantic search over the graph — punted.
- Real-time MCP-driven scene watching — runtime cost too high; we refresh MCP data only on explicit `/build-knowledge-graph`.
- **v2:** Overload-aware call edges (current node key is `ClassName.MethodName`, not `ClassName.MethodName(int,string)`). Signature is captured in `methods[]` but not used as a call-key.
- **v2:** Inter-assembly call ranking, dependency-cycle detection over call edges, dead-method detection — punted to a follow-up.

---

## Definition of Done

- [x] `graph.json` exists, validates against `schema.json`, has non-empty `codebase.classes[]` on a real Unity project.
- [x] `/build-knowledge-graph --full` completes in <30s on a 200-file project.
- [x] `/build-knowledge-graph --incremental` after a one-file change completes in <2s.
- [x] `/knowledge-graph summary` prints in <500ms.
- [x] Codex validation (Task 7) reports ≥95% agreement on a 20-sample run.
- [x] `/catch-up`, `/orchestrate`, `/context-prime` all read graph data and contain no `find` / `Glob '*.cs'` references for codebase discovery.
- [x] `CLAUDE.md` and `README.md` both have a Knowledge Graph section.
- [x] `.gitignore` correctly excludes generated artifacts.
- [x] All hooks are non-blocking (exit 0, background invocation).
- [ ] **v2:** `schema.json` is at version `1.1.0` with optional `methods[]` and `calls[]` fields.
- [ ] **v2:** `codebase.calls[]` is non-empty after a `--full` build on a real Unity project; every edge has a confidence value.
- [ ] **v2:** `python3 .claude/graph/graph-traversal.py god-nodes --top 10` returns ranked output in <200ms.
- [ ] **v2:** `/knowledge-graph callers <Class.Method>` returns at least one caller for a known caller-callee pair in the project.
- [ ] **v2:** `/knowledge-graph impact <ClassName> --hops 3` returns deterministic downstream/upstream sets.
- [ ] **v2:** `/knowledge-graph path <A> <B>` returns the shortest path or exits 1 cleanly if no path exists.
- [ ] **v2:** `graph-builder.sh` skips call-graph finalization with a warning (not an error) when `python3` is absent.

### Critical Files for Implementation
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/schema.json
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/extractors/csharp-extractor.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/graph-traversal.py
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/graph-builder.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/knowledge-graph.md
