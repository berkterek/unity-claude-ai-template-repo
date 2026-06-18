# PLAN — Hybrid Knowledge Graph: Custom graph-mcp-server Integration

> **Version:** v3 — 2026-06-18
> **Status:** Active
> **Scope:** Knowledge graph tooling/infrastructure only. `.claude/graph/` (new MCP server), `.claude/skills/core/`, `.claude/commands/knowledge-graph.md` (reference-only), `.claude/project-features.json`, `.claude/settings.json` (manual user edit), `.claude/docs/`. No Unity C# code, no IEventBus events, no asmdefs.

> **Revision Note v1 — 2026-06-18 (superseded):** Introduced the original hybrid approach: route the four call-graph queries (`callers`, `impact`, `path`, `god-nodes`) to an external `codebase-memory-mcp` server, leave Unity-semantic queries on `graph.json`. Added the `hybrid_graph` flag, a routing skill, a `knowledge-graph-bridge.py` translation layer, and user-applied `settings.json` registration.

> **Revision Note v2 — 2026-06-18 (superseded):** Incorporated 9 grill-me review decisions on top of v1. Added an LSP-vs-tree-sitter prerequisite (Task 1 Step 0) plus a GO / SCOPE DOWN / NO GO decision gate; added a self-healing skill-load check and replaced silent degradation with an explicit stderr warning; added `knowledge-graph-bridge.py` to the File Map; made `--watch` a mandatory `mcpServers` argument; moved Task 2 into group B alongside Task 3.

> **Revision Note v3 — 2026-06-18 (BREAKING — current):** Architecture fully replaced. The external `codebase-memory-mcp` dependency is removed entirely. Instead of routing the four call-graph queries to a third-party server with unknown C# parsing fidelity, we build a **custom `graph-mcp-server.py`** that loads the already-built `graph.json` + `scenes.json` + `prefabs.json` partition files into RAM once at startup and exposes `callers` / `impact` / `path` / `god-nodes` as MCP tools backed by the exact BFS logic already proven in `graph-traversal.py`. Consequences:
> - The C#-parser LSP/tree-sitter prerequisite is **deleted** — our server consumes our own graph, so parsing fidelity equals what `graph-builder.py` already produces.
> - The **NO GO / SCOPE DOWN decision gate is deleted** — we own the server, so all 4/4 queries are guaranteed to have an MCP equivalent.
> - `knowledge-graph-bridge.py` is **removed from the plan** — the routing skill calls `mcp__graph_mcp__*` tools directly; no translation layer needed.
> - All references to `codebase-memory-mcp` are removed.
> - `--watch` is **no longer required** — Claude Code restarts MCP servers when their files change.
> - Old Tasks 1 (install/discover) and 3 (bridge) collapse into **new Task 1 (implement `graph-mcp-server.py`)**. Tasks 2, 4, 5, 6 carry forward with updated tool names.
> - MCP tool names are fixed and knowable up front: `mcp__graph_mcp__callers`, `mcp__graph_mcp__impact`, `mcp__graph_mcp__path`, `mcp__graph_mcp__god_nodes`.

## Complexity: 0.7 — Complex

Rationale: new MCP server process (stdio transport, `mcp` SDK), in-RAM re-implementation of four BFS traversals that must be byte-compatible with `graph-traversal.py`'s output, plus a routing/fallback layer across an opt-in feature flag.

## Context

The knowledge graph is at v1.3.0 and mature. Every `/knowledge-graph` subcommand currently reads `.claude/graph/graph.json` — ten Unity-semantic queries (`summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising`) via inline `jq`, and four call-graph queries (`callers`, `impact`, `path`, `god-nodes`) via `python3 .claude/graph/graph-traversal.py`, which performs BFS over `codebase.calls[]`. The v1.3.0 partition architecture stores `scenes[]` and `prefabs[]` in sibling files `scenes.json` and `prefabs.json`, referenced from `graph.json` via `{"$partition": "scenes.json"}`. There is no routing layer and no persistent MCP server today — MCP is only invoked at build time via the extractors.

This plan introduces a **custom in-process MCP server**, `graph-mcp-server.py`, as the hybrid backend for the four call-graph queries. The server loads `graph.json` + `scenes.json` + `prefabs.json` into RAM once at startup and answers each call-graph query from memory, returning only the relevant slice per query so Claude never has to read the full graph files itself. The ten Unity-semantic queries stay on `jq` / `graph-traversal.py` and are not touched.

Two hard constraints shape the design. First, `settings.json` cannot be edited by Claude (`check-config-protection.sh` blocks it) — the `mcpServers` entry must be added manually by the user. Second, the user-facing `/knowledge-graph` interface and `graph-traversal.py` must remain unchanged — `graph-traversal.py` is the documented fallback and must stay byte-identical. Routing therefore lives in a NEW skill (`.claude/skills/core/knowledge-graph-hybrid.md`). The `hybrid_graph` feature flag (default `false`) gates everything — when off, behaviour is byte-for-byte identical to today.

Because we build the server against our own graph, there is no third-party discovery risk and therefore no GO/NO-GO gate. The work is pure implementation.

## Goals

- [ ] Implement `.claude/graph/graph-mcp-server.py` — stdio MCP server that loads `graph.json` + `scenes.json` + `prefabs.json` into RAM at startup (SCRIPT_DIR-relative) and exposes `callers`, `impact`, `path`, `god-nodes` as MCP tools with output identical to `graph-traversal.py`.
- [ ] Add `hybrid_graph: false` feature flag to `project-features.json` (opt-in, zero behaviour change when disabled).
- [ ] Document the exact user-applied `settings.json` `mcpServers` registration block for the custom server (documented, not auto-applied by Claude).
- [ ] Create `.claude/skills/core/knowledge-graph-hybrid.md` with routing table, 3-state MCP availability check, the four `mcp__graph_mcp__*` tool names, and explicit-warning fallback rules.
- [ ] Guarantee graceful fallback: if the MCP server is unavailable, call-graph queries fall back to `graph-traversal.py` and print an explicit stderr warning that results may be incomplete.
- [ ] Keep `/knowledge-graph` subcommand names, arguments, and output format identical regardless of backend.
- [ ] Update `auto-loaded-skills.md`, `knowledge-graph.md` (docs + command), `skills-index.md`, and the `CLAUDE.md` feature table.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| Core | Task 1 — Implement `graph-mcp-server.py` | ⏳ Pending | A |
| Config | Task 2 — Add `hybrid_graph` flag to project-features.json | ⏳ Pending | A |
| Config | Task 3 — Document settings.json MCP registration (user-applied) | ⏳ Pending | B (after Task 1) |
| Core | Task 4 — Create knowledge-graph-hybrid.md routing skill | ⏳ Pending | B (**blocked by Tasks 1 + 2**) |
| Docs | Task 5 — Update command reference + docs + CLAUDE.md feature table | ⏳ Pending | C (after Task 4) |
| Verify | Task 6 — End-to-end verification | ⏳ Pending | D (after all) |

> **Dependency note:** Task 1 (server implementation) and Task 2 (flag) touch different files and are independent — both run in **group A**. **Group B** is Tasks 3 + 4, both blocked on group A: Task 3 documents the exact server launch command from Task 1, and Task 4 needs both Task 1's tool names (`mcp__graph_mcp__*`) AND Task 2's flag key (`hybrid_graph`) to write the routing table. Do NOT write Task 4 with placeholder tool names — they are fixed by Task 1's server registration. Task 5 (group C) needs Task 4. Task 6 (group D) verifies the whole chain.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/graph-mcp-server.py` | **Create** | stdio MCP server. Loads `graph.json` + `scenes.json` + `prefabs.json` into RAM at startup via SCRIPT_DIR. Exposes 4 tools. BFS re-implemented inline. |
| `.claude/project-features.json` | Modify | Add `"hybrid_graph": false` key. Default OFF. |
| `.claude/settings.json` | **User-applied (manual)** | Add `mcpServers.graph-mcp` entry. Claude CANNOT edit — `check-config-protection.sh` blocks it. Document exact JSON for user to paste. |
| `.claude/skills/core/knowledge-graph-hybrid.md` | **Create** | Routing table, MCP 3-state check, `mcp__graph_mcp__*` tool map, fallback rules. |
| `.claude/commands/knowledge-graph.md` | Modify (minimal) | Add "## Routing (hybrid mode)" section only. Existing content unchanged. |
| `.claude/docs/knowledge-graph.md` | Modify | Document hybrid architecture + backend split + `settings.json` block. |
| `.claude/docs/auto-loaded-skills.md` | Modify | Add `@.claude/skills/core/knowledge-graph-hybrid.md` reference. |
| `.claude/docs/skills-index.md` | Modify | Add `knowledge-graph-hybrid` row to core skills table. |
| `.claude/CLAUDE.md` | Modify | Add `hybrid_graph` row to `## Project Features` table. |
| `.claude/graph/graph-traversal.py` | **Unchanged** | The documented fallback backend. Do NOT touch — must stay byte-identical. |
| `.claude/graph/graph-builder.py` & extractors | **Unchanged** | No changes to graph generation. |

---

## Task 1 — Implement `graph-mcp-server.py`

> Replaces v2's Task 1 (install/discover external server) + Task 3 (`knowledge-graph-bridge.py`). We own the server.

**Files:**
- `.claude/graph/graph-mcp-server.py` (**Create**)

**Steps:**
1. [ ] Install the official MCP Python SDK: `pip install mcp`. (The `mcp` PyPI package is NOT currently installed; Python 3.12.13 is available.) Document this as a prerequisite in Task 3's user instructions so the server can launch.
2. [ ] **Startup graph load (once, into RAM):** locate sibling files using `SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))`. Load `graph.json`, then resolve the `scenes` and `prefabs` `$partition` references by loading `scenes.json` and `prefabs.json` from the same dir. Reuse the partition-resolution logic that `graph-traversal.py:resolve_partition()` already implements — re-implement it inline in the server; do NOT import or subprocess `graph-traversal.py`. Build the forward/reverse adjacency sets from `codebase.calls[]` exactly as `graph-traversal.py:load_graph()` does (`forward[caller].add(callee)`, `reverse[callee].add(caller)`). Hold `g`, `forward`, `reverse`, `edges` in module-level state for the process lifetime.
   - If `graph.json` is missing at startup, the server must fail fast so the routing skill detects "MCP unavailable" and falls back. Do NOT silently serve an empty graph.
3. [ ] **Expose 4 MCP tools** over stdio transport. Tool names registered such that Claude Code surfaces them as:
   - `mcp__graph_mcp__callers` — input: `node` (Class.Method). One-hop reverse lookup. Output identical to `cmd_callers` in `graph-traversal.py`: a JSON array of `{caller, file, line, confidence}` filtered on `edge.callee == node`. Preserve the "No direct callers found" empty case and the node-not-found suggestion behaviour.
   - `mcp__graph_mcp__impact` — input: `node`, `hops` (default 3). Forward + reverse BFS. Output identical to `cmd_impact`: `{root, hops, downstream[], upstream[], total_affected}` with `downstream`/`upstream` sorted+deduped.
   - `mcp__graph_mcp__path` — input: `a`, `b`. BFS shortest path over `forward`. Output identical to `cmd_path`: `{from, to, length, path[]}`; same-node and no-path cases preserved.
   - `mcp__graph_mcp__god_nodes` — input: `top` (default 10). Output identical to `cmd_god_nodes`: prefer pre-computed `analysis.enhanced_god_nodes[]` when present (ranked by `total`, with `in`/`out`/`total`/`community_id`/`severity`), else legacy degree-only computation with `is_god_node = total > 20`.
4. [ ] **Port BFS logic inline:** copy the `bfs(adj, start, max_hops)` algorithm and the `all_nodes`/`check_node`/`suggest_node`/`require_edges` helpers from `graph-traversal.py` into the server module. The four tool handlers reuse the in-RAM `forward`/`reverse`/`edges`/`g` — no per-query file reads.
5. [ ] **Return only relevant data per query:** each tool returns just its own result object/array (the same shape `--json` mode produces in `graph-traversal.py`). The server must NOT return the whole graph.
6. [ ] **Output-format contract:** the JSON each tool returns must be structurally identical to `graph-traversal.py --json` for the corresponding subcommand. Match field names, ordering rules (sorted sets), and empty/not-found semantics exactly.
7. [ ] **No `--watch`:** the server reads the graph once at startup. Claude Code restarts MCP servers when their files change. Do not add a watcher.
8. [ ] **SCRIPT_DIR discipline:** all file access uses `os.path.dirname(os.path.abspath(__file__))`-relative paths — no hardcoded absolute paths.

**Test Type:** NoTest (infrastructure/tooling, not game code).

**Acceptance Criteria:**
- `python3 .claude/graph/graph-mcp-server.py` starts a stdio MCP server without error when `graph.json` exists; exits/fails fast when `graph.json` is missing.
- The server loads `graph.json` + `scenes.json` + `prefabs.json` exactly once at startup using the SCRIPT_DIR pattern — no per-query file reads.
- Four tools are exposed and surface as `mcp__graph_mcp__callers`, `mcp__graph_mcp__impact`, `mcp__graph_mcp__path`, `mcp__graph_mcp__god_nodes`.
- For each of the four queries, the tool's JSON output is structurally identical to `python3 .claude/graph/graph-traversal.py <subcommand> --json` (verified in Task 6).
- BFS is re-implemented inline — the server never subprocesses or imports `graph-traversal.py`.
- No `--watch` flag/argument. No hardcoded absolute paths.
- `graph-traversal.py` is not modified.

---

## Task 2 — Add `hybrid_graph` feature flag

**Files:**
- `.claude/project-features.json`

**Steps:**
1. [ ] Add `"hybrid_graph": false` to the JSON object (alongside `addressables`, `testing`, `ecs`, `graph`, `unity_project_folder`).
2. [ ] Keep default `false` — hybrid mode is opt-in; with it off, every query routes exactly as today.

**Test Type:** NoTest (JSON parse validation only).

**Acceptance Criteria:**
- `jq . .claude/project-features.json` parses without error.
- New key present with value `false`.
- No existing keys removed or reordered.
- With flag `false`, `/knowledge-graph callers X` produces identical output to pre-change behaviour (regression verified in Task 6).

---

## Task 3 — Document settings.json MCP server registration (user-applied)

**Files:** `.claude/settings.json` — **manual user edit only. Claude must NOT write this file** (`check-config-protection.sh` blocks it).

**Steps:**
1. [ ] Compose the exact `mcpServers` entry for the custom server:
   ```json
   "mcpServers": {
     "graph-mcp": {
       "command": "python3",
       "args": [".claude/graph/graph-mcp-server.py"]
     }
   }
   ```
   No `--watch` argument — the server reads the graph at startup and Claude Code restarts it when its files change.
2. [ ] Document the prerequisite from Task 1: the user must run `pip install mcp` in the environment whose `python3` Claude Code invokes, or the server will fail to start.
3. [ ] Present this block to the user with explicit instructions that they must paste it into `.claude/settings.json` themselves (Claude cannot edit that file).
4. [ ] Document the merge rule: if `mcpServers` already exists, add the `graph-mcp` key inside it rather than overwriting.
5. [ ] Provide a verification step: after editing, restart Claude Code — `mcp__graph_mcp__*` tools should appear in a new session.

**Test Type:** NoTest (manual verification).

**Acceptance Criteria:**
- The exact `mcpServers.graph-mcp` JSON block (command `python3`, args `[".claude/graph/graph-mcp-server.py"]`) is documented in `.claude/docs/knowledge-graph.md`.
- No `--watch` argument is present in the block.
- The `pip install mcp` prerequisite is documented.
- Instructions clearly state this is a user-only manual step.
- A post-edit verification step is included.
- The plan does NOT attempt to Edit `settings.json`.

---

## Task 4 — Create the routing skill `knowledge-graph-hybrid.md`

> **BLOCKED on Tasks 1 + 2.** Tool names (`mcp__graph_mcp__*`) come from Task 1; the flag key (`hybrid_graph`) comes from Task 2.

**Files:**
- `.claude/skills/core/knowledge-graph-hybrid.md` (**Create**)

**Steps:**
0. [ ] **Self-healing skill-load check:** before any routing decision, verify that the `knowledge-graph-hybrid` skill is loaded in the current session. If it is not loaded, load it automatically before proceeding to routing.
1. [ ] Add YAML frontmatter (`name: knowledge-graph-hybrid`, `description` covering routing + fallback) matching the style of other `core/` skills.
2. [ ] **Gate check:** read `hybrid_graph` from `project-features.json`. If `false` or absent → skip all routing; every subcommand uses today's backend exactly. This is the first routing step — the default path is unchanged.
3. [ ] **Routing table** — explicit per-subcommand backend assignment:

   | Subcommand | Hybrid-mode backend | Fallback backend (flag off / MCP unavailable) |
   |------------|---------------------|-----------------------------------------------|
   | `callers` | `mcp__graph_mcp__callers` | `python3 .claude/graph/graph-traversal.py callers` |
   | `impact` | `mcp__graph_mcp__impact` | `python3 .claude/graph/graph-traversal.py impact` |
   | `path` | `mcp__graph_mcp__path` | `python3 .claude/graph/graph-traversal.py path` |
   | `god-nodes` | `mcp__graph_mcp__god_nodes` | `python3 .claude/graph/graph-traversal.py god-nodes` |
   | `summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising` | graph.json (`jq`) — **unchanged** | graph.json (`jq`) — **unchanged** |

4. [ ] **3-state MCP availability check:**
   - **State 1 (connected):** the `mcp__graph_mcp__*` tools are present → use them. No normalization needed — server emits `graph-traversal.py` output shape natively.
   - **State 2 (registered, not connected) / State 3 (not registered):** fall back to `python3 .claude/graph/graph-traversal.py <subcommand>` AND print an **explicit warning to stderr**: `"MCP bağlı değil — sonuçlar eksik olabilir"`. Never block the query — there is always a working fallback — but the user must be told results may be incomplete.
5. [ ] **Tool I/O note:** document each tool's input args — `callers`→`node`; `impact`→`node`,`hops`; `path`→`a`,`b`; `god-nodes`→`top` — so the dispatcher passes the same arguments the user gave `/knowledge-graph`.
6. [ ] Document that `graph-traversal.py` is intentionally unchanged and is the single source of fallback truth, and that the ten Unity-semantic queries never route through MCP in any mode.

**Test Type:** NoTest (skill-content review + manual dispatch walk-through in Task 6).

**Acceptance Criteria:**
- Frontmatter parses; skill is reachable from `auto-loaded-skills.md` (wired in Task 5).
- Routing table covers ALL 14 current subcommands with no gaps (4 call-graph + 10 Unity-semantic).
- The four hybrid-mode tool names are exactly `mcp__graph_mcp__callers`, `mcp__graph_mcp__impact`, `mcp__graph_mcp__path`, `mcp__graph_mcp__god_nodes` — no placeholders.
- Fallback path (`graph-traversal.py`) is reachable for all 4 call-graph queries when MCP is absent, and emits the stderr warning `"MCP bağlı değil — sonuçlar eksik olabilir"`.
- Flag-off path is documented as identical to current behaviour.
- No instruction to modify `graph-traversal.py` or `settings.json`. No reference to a bridge script or to `codebase-memory-mcp`.

---

## Task 5 — Update command reference, docs, and CLAUDE.md feature table

**Files:**
- `.claude/commands/knowledge-graph.md`
- `.claude/docs/knowledge-graph.md`
- `.claude/docs/auto-loaded-skills.md`
- `.claude/docs/skills-index.md`
- `.claude/CLAUDE.md`

**Steps:**
1. [ ] `commands/knowledge-graph.md`: add a short `## Routing (hybrid mode)` section after the staleness-check section — when `hybrid_graph` is enabled, `callers` / `impact` / `path` / `god-nodes` are dispatched via `mcp__graph_mcp__*` per `.claude/skills/core/knowledge-graph-hybrid.md`; all other subcommands and all output formats are unchanged. Do NOT alter any existing subcommand spec, `jq` snippet, or python invocation.
2. [ ] `docs/knowledge-graph.md`: add a "Hybrid architecture" subsection describing the two-backend split (4 call-graph queries → `graph-mcp-server.py`; 10 Unity-semantic → `jq`), the role of the `hybrid_graph` flag, and the exact user-applied `settings.json` `mcpServers.graph-mcp` block from Task 3 (including the `pip install mcp` prerequisite and "no `--watch`" note).
3. [ ] `docs/auto-loaded-skills.md`: add `@.claude/skills/core/knowledge-graph-hybrid.md` reference so it loads automatically every session (same pattern as the other `core/` `@`-references).
4. [ ] `docs/skills-index.md`: add a core-skills row — `knowledge-graph-hybrid` → "Routes the 4 call-graph queries to the in-process `graph-mcp-server.py` with `graph-traversal.py` fallback; Unity-semantic queries stay on graph.json."
5. [ ] `CLAUDE.md`: add a `hybrid_graph` row to the `## Project Features` table with its disabled-effect: "Skip `graph-mcp-server.py` routing; all call-graph queries use `graph-traversal.py`, all Unity-semantic queries use graph.json/`jq` (current behaviour)."

**Test Type:** NoTest (doc review).

**Acceptance Criteria:**
- A single new section added to `commands/knowledge-graph.md`; zero changes to existing subcommand definitions or the usage block.
- All docs reference the new skill, the `graph-mcp-server.py` server, and the `hybrid_graph` flag consistently — no leftover `codebase-memory-mcp` or `knowledge-graph-bridge.py` references anywhere.
- The backend split (which queries go where) is described identically across all docs and the skill.
- `auto-loaded-skills.md` contains the `@` reference so the skill loads without manual invocation.
- The `settings.json` block documented in `docs/knowledge-graph.md` matches Task 3 exactly (command `python3`, args `[".claude/graph/graph-mcp-server.py"]`, no `--watch`).

---

## Task 6 — End-to-end verification

**Files:** none (verification only).

**Steps:**
1. [ ] **Flag OFF (regression):** with `hybrid_graph: false`, run `callers`, `impact`, `path`, `god-nodes`, and one Unity-semantic query. Confirm output is identical to pre-change behaviour.
2. [ ] **Flag ON, MCP connected:** with the server registered and `pip install mcp` done, run the 4 call-graph queries. Confirm they are dispatched through `mcp__graph_mcp__*` and that each tool's output is structurally identical to `python3 .claude/graph/graph-traversal.py <subcommand> --json`.
3. [ ] **Flag ON, MCP unavailable** (simulate by not registering the server, or by uninstalling `mcp` so the server fails to start): confirm the 4 queries fall back to `graph-traversal.py`, still return results, and print the explicit stderr warning `"MCP bağlı değil — sonuçlar eksik olabilir"`.
4. [ ] **Unity-semantic queries** (`summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising`) stay on `jq` / graph.json in all three modes above.
5. [ ] Confirm `graph-traversal.py`, `graph-builder.py`, the extractors, and `settings.json` were never modified by Claude.

**Test Type:** NoTest (manual end-to-end / verification-before-completion).

**Acceptance Criteria:**
- Flag-off output matches baseline exactly (no regression).
- Flag-on connected path dispatches through `mcp__graph_mcp__*` tools and output format matches `graph-traversal.py --json` per subcommand.
- Flag-on unavailable path falls back to `graph-traversal.py` without error, with the explicit stderr warning `"MCP bağlı değil — sonuçlar eksik olabilir"` printed.
- Unity-semantic queries unaffected in every mode.
- `/knowledge-graph` interface (subcommand names, args, output columns) unchanged throughout.
- `graph-traversal.py` byte-identical to its pre-change version; `settings.json` unmodified by Claude.

---

## Implementation Notes

- **Sequencing:** Group A = Task 1 (server) + Task 2 (flag), independent. Group B = Task 3 (settings doc) + Task 4 (routing skill), both blocked on group A. Group C = Task 5 (docs), blocked on Task 4. Group D = Task 6 (verification), blocked on everything.
- **We own the server:** there is no third-party discovery, no LSP/tree-sitter question, and no GO/NO-GO gate. The server consumes the same `graph.json` the rest of the toolchain already produces. All 4/4 call-graph queries have a guaranteed MCP equivalent.
- **BFS parity is the hard part:** `graph-mcp-server.py` re-implements the exact algorithms in `graph-traversal.py` (`bfs`, `cmd_impact`, `cmd_callers`, `cmd_path`, `cmd_god_nodes`) inline. It must NOT subprocess or import `graph-traversal.py`. The output JSON must match `--json` mode field-for-field, including the `enhanced_god_nodes` preference, the `is_god_node = total > 20` legacy rule, sorted/deduped `downstream`/`upstream`, and the not-found/empty-result semantics.
- **No silent degradation:** when MCP is unavailable, the fallback to `graph-traversal.py` must always emit the stderr warning `"MCP bağlı değil — sonuçlar eksik olabilir"`. The query still succeeds, but the user must know results may be incomplete.
- **No `--watch`:** the server loads the graph once at startup. Claude Code restarts MCP servers when their files change; `graph-builder.py` runs on demand. Staleness of `graph.json` is handled by the existing `graph-auto-update.sh` hook + `/build-knowledge-graph`; the in-RAM copy refreshes on the next server restart.
- **SCRIPT_DIR pattern:** `graph-mcp-server.py` uses `os.path.dirname(os.path.abspath(__file__))` to locate `graph.json`, `scenes.json`, and `prefabs.json` — same discipline as `graph-traversal.py` line 11. No hardcoded absolute paths.
- **settings.json reminder:** Claude cannot edit this file under any circumstances. `check-config-protection.sh` blocks it. The `mcpServers.graph-mcp` entry and the `pip install mcp` prerequisite are documented for the user to apply manually.
- **No changes to graph generation:** `graph-builder.py` and all extractors are untouched. `graph-traversal.py` is untouched and remains the fallback.
