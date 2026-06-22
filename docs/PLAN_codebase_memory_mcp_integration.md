# PLAN — Hybrid Knowledge Graph: Custom graph-mcp-server Integration

> **Version:** v4 — 2026-06-18
> **Status:** Active
> **Scope:** Knowledge graph tooling/infrastructure only. `.claude/graph/` (new MCP server, new shared BFS core, refactored `graph-traversal.py`), `.claude/skills/core/`, `.claude/commands/knowledge-graph.md` (reference-only), `.claude/project-features.json`, `.claude/settings.json` (manual user edit), `.claude/docs/`. No Unity C# code, no IEventBus events, no asmdefs.

> **Revision Note v1 — 2026-06-18 (superseded):** Introduced the original hybrid approach: route the four call-graph queries (`callers`, `impact`, `path`, `god-nodes`) to an external `codebase-memory-mcp` server, leave Unity-semantic queries on `graph.json`. Added the `hybrid_graph` flag, a routing skill, a `knowledge-graph-bridge.py` translation layer, and user-applied `settings.json` registration.

> **Revision Note v2 — 2026-06-18 (superseded):** Incorporated 9 grill-me review decisions on top of v1. Added an LSP-vs-tree-sitter prerequisite (Task 1 Step 0) plus a GO / SCOPE DOWN / NO GO decision gate; added a self-healing skill-load check and replaced silent degradation with an explicit stderr warning; added `knowledge-graph-bridge.py` to the File Map; made `--watch` a mandatory `mcpServers` argument; moved Task 2 into group B alongside Task 3.

> **Revision Note v3 — 2026-06-18 (superseded):** Architecture fully replaced. The external `codebase-memory-mcp` dependency is removed entirely. Instead of routing the four call-graph queries to a third-party server with unknown C# parsing fidelity, we build a **custom `graph-mcp-server.py`** that loads the already-built `graph.json` + `scenes.json` + `prefabs.json` partition files into RAM once at startup and exposes `callers` / `impact` / `path` / `god-nodes` as MCP tools backed by the exact BFS logic already proven in `graph-traversal.py`. Consequences: LSP/tree-sitter prerequisite deleted; NO GO / SCOPE DOWN gate deleted; `knowledge-graph-bridge.py` removed; all references to `codebase-memory-mcp` removed; `--watch` no longer required; old Tasks 1 + 3 collapse into new Task 1.

> **Revision Note v4 — 2026-06-18 (CURRENT):** Incorporated 11 grill-me design decisions from the v3 stress-test. Key structural changes:
> - **Decision 1:** Fail fast on ALL three partition files (`graph.json`, `scenes.json`, `prefabs.json`) being missing, unreadable, or malformed — not only `graph.json`.
> - **Decision 2:** Reload-on-stale replaces "load once + server restart" as the warm-path refresh strategy. `load_graph()` is called at startup AND on mtime-detected staleness. Mid-session reload failures keep last-good and emit a stderr warning without crashing.
> - **Decision 3:** Atomic rebind, lock-free. `load_graph()` builds into fresh locals then rebinds module-level names in one no-`await` burst. No `asyncio.Lock`. Code comment `# Atomic rebind — no await here` required.
> - **Decision 4 (MAJOR — new task):** Extract BFS traversal logic from `graph-traversal.py` into new `.claude/graph/graph_bfs_core.py`. Both `graph-traversal.py` (refactored internals) and `graph-mcp-server.py` import this shared pure module. "Byte-identical / do NOT touch `graph-traversal.py`" replaced throughout by "CLI surface + output identical; internals refactored to import `graph_bfs_core`."
> - **Decision 5:** 2-state model replaces 3-state. State A: tool present → call MCP. State B: tool absent → `echo "..." >&2` (Bash-emitted, not model prose) then `graph-traversal.py` fallback.
> - **Decision 6:** Warning string has exactly one canonical owner: the `echo >&2` in the routing skill's fallback Bash command. All other plan references say "the warning string emitted by the routing skill's fallback `echo >&2`."
> - **Decision 7:** Task 6 parity harness consolidates: greps the literal from the skill file at test time, forces MCP-absent, captures stderr, asserts byte-for-byte match. No hand-typed copy of the string in the test.
> - **Decision 8:** `import mcp` pip probe is lazy, once-per-session, State-B-only. Non-zero exit emits a specific `"mcp paketi kurulu değil — pip install mcp"` diagnostic before the generic warning. Zero exit: generic warning only.
> - **Decision 9:** `hybrid_graph` off/absent silently skips ALL routing including State A/B eval, the pip probe, and the stderr warning. Flag-off stderr is always empty.
> - **Decision 10:** `hops=3` and `top=10` defaults live exclusively in `graph_bfs_core` function signatures. MCP inputSchema marks fields optional with no schema-level default. Argparse `--hops`/`--top` change to `default=None`.
> - **Decision 11:** Not-found / empty-result / suggestion outcomes are returned as successful tool results matching the CLI `--json` shape. JSON-RPC errors reserved exclusively for genuine faults (parse failure, internal exception, startup partition failure).

---

## Complexity: 0.8 — Complex

Rationale: new shared BFS core module + refactored `graph-traversal.py` + new MCP server, all of which must stay in parity; reload-on-stale with atomic rebind; 2-state routing skill with Bash-emitted warnings and a lazy pip probe; consolidated parity harness that greps its assertion target from the skill file at test time.

---

## Context

The knowledge graph is at v1.3.0 and mature. Every `/knowledge-graph` subcommand currently reads `.claude/graph/graph.json` — eleven Unity-semantic queries (`summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising`) via inline `jq`, and four call-graph queries (`callers`, `impact`, `path`, `god-nodes`) via `python3 .claude/graph/graph-traversal.py`, which performs BFS over `codebase.calls[]`. The v1.3.0 partition architecture stores `scenes[]` and `prefabs[]` in sibling files `scenes.json` and `prefabs.json`, referenced from `graph.json` via `{"$partition": "scenes.json"}`. There is no routing layer and no persistent MCP server today — MCP is only invoked at build time via the extractors.

This plan introduces a **custom in-process MCP server**, `graph-mcp-server.py`, as the hybrid backend for the four call-graph queries. The server loads `graph.json` + `scenes.json` + `prefabs.json` into RAM at startup and checks for staleness on each handler call, reloading all three partitions if `graph.json`'s mtime has advanced. It answers each call-graph query from memory via a shared `graph_bfs_core.py` module, returning only the relevant slice per query. The eleven Unity-semantic queries stay on `jq` / `graph-traversal.py` and are not touched.

Two hard constraints shape the design. First, `settings.json` cannot be edited by Claude (`check-config-protection.sh` blocks it) — the `mcpServers` entry must be added manually by the user. Second, the user-facing `/knowledge-graph` interface, subcommand names, arguments, and output format must remain unchanged — `graph-traversal.py`'s CLI surface and output stay identical to today, though its internals are refactored to import `graph_bfs_core`. Routing lives in a NEW skill (`.claude/skills/core/knowledge-graph-hybrid.md`). The `hybrid_graph` feature flag (default `false`) gates everything — when off, behaviour is byte-for-byte identical to today with zero stderr noise and zero probe cost.

Because we build the server against our own graph, there is no third-party discovery risk and therefore no GO/NO-GO gate.

---

## Goals

- [ ] Extract BFS traversal logic into `.claude/graph/graph_bfs_core.py` — a pure shared module (no file I/O, no CLI, no stdout) consumed by both `graph-traversal.py` and `graph-mcp-server.py`.
- [ ] Refactor `.claude/graph/graph-traversal.py` to import `graph_bfs_core`; CLI surface and output must be identical to pre-refactoring.
- [ ] Implement `.claude/graph/graph-mcp-server.py` — stdio MCP server that loads `graph.json` + `scenes.json` + `prefabs.json` into RAM at startup, checks mtime on each handler call and reloads all three partitions when stale, and exposes `callers`, `impact`, `path`, `god-nodes` as MCP tools via `graph_bfs_core`.
- [ ] Add `hybrid_graph: false` feature flag to `project-features.json` (opt-in, zero behaviour change when disabled).
- [ ] Document the exact user-applied `settings.json` `mcpServers` registration block for the custom server (documented, not auto-applied by Claude).
- [ ] Create `.claude/skills/core/knowledge-graph-hybrid.md` with routing table, 2-state MCP availability check, the four `mcp__graph_mcp__*` tool names, Bash-emitted warning, lazy pip probe, and explicit fallback rules.
- [ ] Guarantee graceful fallback: if the MCP server is unavailable and `hybrid_graph` is on, call-graph queries fall back to `graph-traversal.py` and the routing skill emits the warning string via `echo >&2`; if `hybrid_graph` is off, there is no warning and no probe at all.
- [ ] Keep `/knowledge-graph` subcommand names, arguments, and output format identical regardless of backend.
- [ ] Update `auto-loaded-skills.md`, `knowledge-graph.md` (docs + command), `skills-index.md`, and the `CLAUDE.md` feature table.

---

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| Core | Task 0 — Extract `graph_bfs_core.py` (new) | ⏳ Pending | A |
| Config | Task 2 — Add `hybrid_graph` flag to project-features.json | ⏳ Pending | A |
| Core | Task 1 — Implement `graph-mcp-server.py` | ⏳ Pending | B (after Task 0) |
| Config | Task 3 — Document settings.json MCP registration (user-applied) | ⏳ Pending | C (after Task 1) |
| Core | Task 4 — Create knowledge-graph-hybrid.md routing skill | ⏳ Pending | C (blocked by Tasks 1 + 2) |
| Docs | Task 5 — Update command reference + docs + CLAUDE.md feature table | ⏳ Pending | D (after Task 4) |
| Verify | Task 6 — End-to-end verification | ⏳ Pending | E (after all) |

> **Dependency note:** Task 0 (extract `graph_bfs_core.py`) and Task 2 (flag) touch different files and are independent — both run in **group A**. Task 1 (server implementation) is in **group B**, blocked on Task 0 because it imports `graph_bfs_core`. **Group C** is Tasks 3 + 4: Task 3 documents the exact server launch command from Task 1, and Task 4 needs Task 1's tool names AND Task 2's flag key. Task 5 (group D) needs Task 4. Task 6 (group E) verifies the whole chain. Do NOT write Task 4 with placeholder tool names — they are fixed by Task 1's server registration.

---

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/graph_bfs_core.py` | **Create** | Pure shared BFS module. Takes loaded graph state as arguments; returns result objects. No file I/O, no CLI parsing, no stdout. Owns `hops=3` and `top=10` signature defaults. |
| `.claude/graph/graph-traversal.py` | **Modify** | Internals refactored to import `graph_bfs_core`. CLI surface + output identical to pre-refactoring. Argparse `--hops`/`--top` change to `default=None`. |
| `.claude/graph/graph-mcp-server.py` | **Create** | stdio MCP server. Loads `graph.json` + `scenes.json` + `prefabs.json` into RAM at startup via SCRIPT_DIR. Stale-checks `graph.json` mtime on each handler call; reloads all 3 partitions when stale. Atomic rebind, lock-free. Imports `graph_bfs_core`. Exposes 4 tools. |
| `.claude/project-features.json` | Modify | Add `"hybrid_graph": false` key. Default OFF. |
| `.claude/settings.json` | **User-applied (manual)** | Add `mcpServers.graph-mcp` entry. Claude CANNOT edit — `check-config-protection.sh` blocks it. Document exact JSON for user to paste. |
| `.claude/skills/core/knowledge-graph-hybrid.md` | **Create** | Routing table, 2-state MCP check, `mcp__graph_mcp__*` tool map, Bash-emitted warning (canonical single owner), lazy pip probe, fallback rules. |
| `.claude/commands/knowledge-graph.md` | Modify (minimal) | Add "## Routing (hybrid mode)" section only. Existing content unchanged. |
| `.claude/docs/knowledge-graph.md` | Modify | Document hybrid architecture + backend split + `settings.json` block. |
| `.claude/docs/auto-loaded-skills.md` | Modify | Add `@.claude/skills/core/knowledge-graph-hybrid.md` reference. |
| `.claude/docs/skills-index.md` | Modify | Add `knowledge-graph-hybrid` row to core skills table. |
| `.claude/CLAUDE.md` | Modify | Add `hybrid_graph` row to `## Project Features` table. |
| `.claude/graph/graph-builder.py` & extractors | **Unchanged** | No changes to graph generation. |

---

## Task 0 — Extract `graph_bfs_core.py` (shared BFS module)

> **New task added by v4 Decision 4.** Must complete before Task 1 (server implementation) because `graph-mcp-server.py` imports this module.

**Files:**
- `.claude/graph/graph_bfs_core.py` (**Create**)
- `.claude/graph/graph-traversal.py` (**Modify** — internals only; CLI surface + output unchanged)

**Steps:**
1. [ ] **Create `.claude/graph/graph_bfs_core.py` as a pure module.** The module takes loaded graph state (`g`, `forward`, `reverse`, `edges`) as function arguments and returns result objects. It performs NO file I/O, NO CLI argument parsing, and NO stdout or stderr printing. It has no `if __name__ == "__main__"` block.
2. [ ] **Move the following into `graph_bfs_core.py`:**
   - `bfs(adj, start, max_hops)` — BFS traversal algorithm.
   - `all_nodes(g, forward, reverse)` — full node set helper.
   - `check_node(node, all_node_set)` — node presence check.
   - `suggest_node(node, all_node_set)` — difflib-based suggestion.
   - `require_edges(edges)` — edge set guard.
   - Query core for `callers`: logic that computes the result object given loaded graph state and a `node` argument.
   - Query core for `impact`: logic that computes `{root, hops, downstream[], upstream[], total_affected}` given `node` and `hops: int = 3`.
   - Query core for `path`: logic that computes `{from, to, length, path[]}` given `a` and `b`.
   - Query core for `god-nodes`: logic that computes the ranked list given `top: int = 10`, preferring `analysis.enhanced_god_nodes[]` when present.
3. [ ] **Default values owned exclusively by `graph_bfs_core` signatures:** `hops=3` in the `impact` core and `top=10` in the `god-nodes` core. Both functions treat an explicit `None` argument as "use the signature default." These literals appear nowhere else (not in argparse, not in the MCP inputSchema).
4. [ ] **Refactor `graph-traversal.py`:** add `import graph_bfs_core` (same directory, resolved via `sys.path` insert using SCRIPT_DIR). Replace the inline definitions of the functions listed in Step 2 with calls into `graph_bfs_core`. Change argparse `--hops default=3` to `default=None`; change `--top default=10` to `default=None`. The CLI's subcommand names, flags, `--json` output format, exit codes, not-found/suggestion semantics, and all stdout/stderr output must be byte-for-byte identical to the pre-refactoring version for the same inputs.
5. [ ] **Verify `graph-traversal.py` CLI surface unchanged:** after refactoring, run at least one query per subcommand (`callers`, `impact`, `path`, `god-nodes`) with a known node and confirm output matches the pre-refactoring baseline. This is the regression contract: CLI surface + output identical; only internals change.

**Test Type:** NoTest (Python utility module, not Unity C#).

**Acceptance Criteria:**
- `graph_bfs_core.py` exists in `.claude/graph/`, is importable (`python3 -c "import sys; sys.path.insert(0, '.claude/graph'); import graph_bfs_core"`), and contains no file I/O, no `argparse`, no `print` / `sys.stdout` calls, no `sys.exit`.
- All four query core functions are present in `graph_bfs_core`. The `impact` core signature has `hops=3`; the `god-nodes` core has `top=10`. Both accept `None` as equivalent to the default.
- `graph-traversal.py` imports `graph_bfs_core` and delegates traversal logic to it. No inline duplicate definitions of the moved functions remain.
- Argparse `--hops` and `--top` in `graph-traversal.py` are `default=None`.
- Running `python3 .claude/graph/graph-traversal.py callers X --json`, `impact X --json`, `path A B --json`, `god-nodes --json` (with and without `--hops` / `--top`) produces output structurally identical to the pre-refactoring baseline.
- The literal `3` and `10` for these defaults do not appear in `graph-traversal.py`'s argparse setup or in any MCP inputSchema definition.

---

## Task 1 — Implement `graph-mcp-server.py`

> Replaces v2's Task 1 (install/discover external server) + Task 3 (`knowledge-graph-bridge.py`). We own the server. **Blocked on Task 0** — the server imports `graph_bfs_core`.

**Files:**
- `.claude/graph/graph-mcp-server.py` (**Create**)

**Steps:**
1. [ ] Install the official MCP Python SDK: `pip install mcp`. (The `mcp` PyPI package is NOT currently installed; Python 3.12.13 is available.) Document this as a prerequisite in Task 3's user instructions so the server can launch.
2. [ ] **Startup graph load — `load_graph()` function:** factor all partition-load and adjacency-build logic into a single reusable `load_graph()` function callable both at startup and on stale-detect. The function must:
   - Locate `graph.json`, `scenes.json`, and `prefabs.json` using `SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))`.
   - **Fail fast if ANY of the three partition files is missing, unreadable, or contains malformed JSON.** Do NOT silently serve a partial or empty graph. Raise / exit with a non-zero code so the MCP stdio handshake never completes and the routing skill's availability check correctly detects State B (tool absent).
   - Resolve the `$partition` references in `graph.json` by loading `scenes.json` and `prefabs.json` from the same directory (replicating the logic of `graph-traversal.py:resolve_partition()`).
   - Build the forward/reverse adjacency sets from `codebase.calls[]` exactly as `graph-traversal.py:load_graph()` does.
   - Return the four fresh objects: `(g, forward, reverse, edges)`.
   - Record the `graph.json` mtime (`os.path.getmtime`) after each successful load, storing it in a module-level variable.
3. [ ] **Expose 4 MCP tools** over stdio transport. Tool names registered such that Claude Code surfaces them as:
   - `mcp__graph_mcp__callers` — input: `node` (Class.Method). One-hop reverse lookup. Output identical to `cmd_callers` in `graph-traversal.py`.
   - `mcp__graph_mcp__impact` — input: `node`; `hops` optional integer, **no schema-level default** (core supplies `3`). Output identical to `cmd_impact`.
   - `mcp__graph_mcp__path` — input: `a`, `b`. BFS shortest path. Output identical to `cmd_path`.
   - `mcp__graph_mcp__god_nodes` — input: `top` optional integer, **no schema-level default** (core supplies `10`). Output identical to `cmd_god_nodes`.
4. [ ] **Stale-check + reload on each handler call:** at the top of every tool handler, before calling into `graph_bfs_core`, check `os.path.getmtime(graph_json_path)` against the stored startup mtime. If the file is newer:
   - Call `load_graph()` to rebuild all three partitions into fresh locals.
   - **Atomic rebind — no `await` here:** rebind the four module-level names (`g`, `forward`, `reverse`, `edges`) to the fresh objects and update the stored mtime in a single synchronous block containing no `await` statements. Add the code comment `# Atomic rebind — no await here` at this exact point.
   - **Mid-session reload failure:** if the mid-session `load_graph()` call raises (missing/broken partition at runtime): do NOT crash the server and do NOT serve a partial graph. Keep the last successfully loaded module-level graph, answer the query from it, and emit a stderr warning that the reload was skipped due to a broken partition.
   - No `asyncio.Lock` anywhere in the module.
5. [ ] **Call `graph_bfs_core` for all traversal logic:** import `graph_bfs_core` (same `.claude/graph/` directory, resolved via `sys.path.insert` using SCRIPT_DIR). The four tool handlers call the corresponding query core functions from `graph_bfs_core` with the in-RAM `g`/`forward`/`reverse`/`edges`. The server never reimplements BFS inline. It does NOT import or subprocess `graph-traversal.py` itself — only the shared core.
6. [ ] **Return only relevant data per query:** each tool returns just its own result object/array (the same shape `--json` mode produces in `graph-traversal.py`). The server must NOT return the whole graph.
7. [ ] **Not-found / empty-result contract:** handler outcomes that are valid query answers — node-not-found (with difflib suggestion), "No direct callers found," "No path found in the call graph," and any other empty-set result — MUST be returned as **successful tool results** whose payload matches the CLI `--json` shape. They must NOT be raised as JSON-RPC errors. JSON-RPC errors are reserved exclusively for genuine faults: malformed/missing partition files at startup (Decision 1 fail-fast), internal exceptions in the traversal core, unparseable arguments. This mirrors `graph-traversal.py`'s exit-0 contract for not-found cases.
8. [ ] **No `--watch`:** the server reads the graph at startup and rechecks mtime on each handler call. Claude Code restarts MCP servers when their files change. Do not add a file watcher.
9. [ ] **SCRIPT_DIR discipline:** all file access uses `os.path.dirname(os.path.abspath(__file__))`-relative paths — no hardcoded absolute paths.

**Test Type:** NoTest (infrastructure/tooling, not game code).

**Acceptance Criteria:**
- `python3 .claude/graph/graph-mcp-server.py` starts a stdio MCP server without error when all three partition files (`graph.json`, `scenes.json`, `prefabs.json`) exist and are valid JSON; exits/fails fast (non-zero, no successful handshake) when ANY of the three is missing, unreadable, or malformed.
- The server calls `load_graph()` at startup. Each handler checks `graph.json` mtime before answering; if newer, calls `load_graph()` and atomically rebinds module-level names with the code comment `# Atomic rebind — no await here`. A mid-session reload failure keeps last-good, answers from it, and emits a stderr warning without crashing.
- No `asyncio.Lock` anywhere in the module.
- Four tools are exposed and surface as `mcp__graph_mcp__callers`, `mcp__graph_mcp__impact`, `mcp__graph_mcp__path`, `mcp__graph_mcp__god_nodes`.
- `hops` and `top` are declared optional in the MCP inputSchema with **no schema-level default value**.
- For each of the four queries, the tool's JSON output is structurally identical to `python3 .claude/graph/graph-traversal.py <subcommand> --json` (verified in Task 6).
- Handler not-found/empty/suggestion outcomes are returned as successful tool results matching the CLI `--json` shape; no JSON-RPC protocol errors for valid but empty/not-found results.
- All traversal logic is delegated to `graph_bfs_core` — the server never reimplements BFS inline and never imports or subprocesses `graph-traversal.py`.
- No `--watch` flag/argument. No hardcoded absolute paths.
- The `graph-traversal.py` CLI surface + output is identical to pre-change; internals may import `graph_bfs_core` (Task 0).

---

## Task 2 — Add `hybrid_graph` feature flag

**Files:**
- `.claude/project-features.json`

**Steps:**
1. [ ] Add `"hybrid_graph": false` to the JSON object (alongside `addressables`, `testing`, `ecs`, `graph`, `unity_project_folder`).
2. [ ] Keep default `false` — hybrid mode is opt-in; with it off, every query routes exactly as today, with no stderr output and no pip probe.

**Test Type:** NoTest (JSON parse validation only).

**Acceptance Criteria:**
- `jq . .claude/project-features.json` parses without error.
- New key present with value `false`.
- No existing keys removed or reordered.
- With flag `false`, `/knowledge-graph callers X` produces identical output to pre-change behaviour and emits nothing to stderr (regression verified in Task 6).

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
   No `--watch` argument — the server reads the graph at startup and rechecks mtime on each handler call.
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
2. [ ] **Gate check:** read `hybrid_graph` from `project-features.json`. If `false` or absent → **skip all routing entirely**: every subcommand uses today's backend exactly, the State A/B evaluation is NOT performed, the stderr warning is NOT emitted, and the `import mcp` pip probe is NOT run. This is the first and only routing step on the default path — no MCP state is consulted and no new stderr noise is produced. The off-path is completely silent.
3. [ ] **Routing table** — explicit per-subcommand backend assignment:

   | Subcommand | Hybrid-mode backend | Fallback backend (flag off / MCP absent) |
   |------------|---------------------|------------------------------------------|
   | `callers` | `mcp__graph_mcp__callers` | `python3 .claude/graph/graph-traversal.py callers` |
   | `impact` | `mcp__graph_mcp__impact` | `python3 .claude/graph/graph-traversal.py impact` |
   | `path` | `mcp__graph_mcp__path` | `python3 .claude/graph/graph-traversal.py path` |
   | `god-nodes` | `mcp__graph_mcp__god_nodes` | `python3 .claude/graph/graph-traversal.py god-nodes` |
   | `summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising` | graph.json (`jq`) — **unchanged** | graph.json (`jq`) — **unchanged** |

4. [ ] **2-state MCP availability model** (only reached when `hybrid_graph` is `true`):
   - **State A — tool present:** the `mcp__graph_mcp__*` tools are present in the session → call the MCP tool directly. No warning emitted. No pip probe run.
   - **State B — tool absent:** the `mcp__graph_mcp__*` tools are NOT present in the session → execute the following fallback sequence:
     1. **Lazy once-per-session `import mcp` pip probe:** on the first State B hit this session, run `python3 -c "import mcp" 2>/dev/null` and cache the result for the rest of the session. Never run this probe in State A, and never run it eagerly at session start.
        - Non-zero (mcp not installed): emit the specific diagnostic to stderr **before** the generic warning:
          `echo "graph-mcp-server gerektiren 'mcp' paketi kurulu değil — pip install mcp" >&2`
        - Zero (mcp installed but tool still absent): no specific diagnostic; emit only the generic warning below.
     2. **Bash-emitted generic warning:** as part of the same fallback Bash invocation, emit the warning string via `echo "MCP bağlı değil — sonuçlar eksik olabilir" >&2`. This `echo >&2` command is the **single canonical owner** of that warning string. It must appear verbatim in the skill's documented fallback Bash command. The warning is NOT narrated as model prose — it is a side effect of the Bash fallback invocation, executed deterministically on every State B hit.
     3. **Fallback execution:** run `python3 .claude/graph/graph-traversal.py <subcommand> [args]` as the query backend.
5. [ ] **Tool I/O note:** document each tool's input args — `callers`→`node`; `impact`→`node`, `hops` (optional, no schema default); `path`→`a`, `b`; `god-nodes`→`top` (optional, no schema default) — so the dispatcher passes the same arguments the user gave `/knowledge-graph`. When `hops` or `top` is omitted by the user, pass nothing (or `None`) to the tool; `graph_bfs_core` supplies the default.
6. [ ] Document that `graph-traversal.py`'s CLI surface and output are intentionally preserved (internals refactored to import `graph_bfs_core` in Task 0) and that it is the single source of fallback truth. Document that the eleven Unity-semantic queries never route through MCP in any mode.

**Test Type:** NoTest (skill-content review + manual dispatch walk-through in Task 6).

**Acceptance Criteria:**
- Frontmatter parses; skill is reachable from `auto-loaded-skills.md` (wired in Task 5).
- Routing table covers ALL 15 current subcommands with no gaps (4 call-graph + 11 Unity-semantic).
- The four hybrid-mode tool names are exactly `mcp__graph_mcp__callers`, `mcp__graph_mcp__impact`, `mcp__graph_mcp__path`, `mcp__graph_mcp__god_nodes` — no placeholders.
- When `hybrid_graph` is off or absent: stderr is empty, no pip probe is run, no MCP state is consulted — the off-path is completely silent and behaviorally identical to the pre-change baseline.
- State B fallback path: `echo "MCP bağlı değil — sonuçlar eksik olabilir" >&2` appears verbatim in the skill's documented fallback Bash command (this is the single canonical owner of that string). The warning is Bash-emitted, not model prose.
- State B pip probe: when mcp is uninstalled, the specific `"graph-mcp-server gerektiren 'mcp' paketi kurulu değil — pip install mcp"` diagnostic is emitted to stderr ahead of the generic warning. When mcp is installed but the tool is absent, only the generic warning appears.
- Pip probe is documented as lazy (first State B this session only), cached, never run in State A or on flag-off paths.
- Flag-off path is documented as identical to current behaviour with zero stderr output.
- No instruction to modify `settings.json`. No reference to a bridge script or to `codebase-memory-mcp`. No 3-state model.

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
2. [ ] `docs/knowledge-graph.md`: add a "Hybrid architecture" subsection describing the two-backend split (4 call-graph queries → `graph-mcp-server.py` via `graph_bfs_core`; 11 Unity-semantic → `jq`), the role of the `hybrid_graph` flag, and the exact user-applied `settings.json` `mcpServers.graph-mcp` block from Task 3 (including the `pip install mcp` prerequisite and "no `--watch`" note).
3. [ ] `docs/auto-loaded-skills.md`: add `@.claude/skills/core/knowledge-graph-hybrid.md` reference so it loads automatically every session (same pattern as the other `core/` `@`-references).
4. [ ] `docs/skills-index.md`: add a core-skills row — `knowledge-graph-hybrid` → "Routes the 4 call-graph queries to the in-process `graph-mcp-server.py` (backed by `graph_bfs_core.py`) with `graph-traversal.py` fallback and Bash-emitted stderr warning; Unity-semantic queries stay on graph.json."
5. [ ] `CLAUDE.md`: add a `hybrid_graph` row to the `## Project Features` table with its disabled-effect: "Skip `graph-mcp-server.py` routing; all call-graph queries use `graph-traversal.py`, all Unity-semantic queries use graph.json/`jq` (current behaviour). No stderr output, no pip probe."

**Test Type:** NoTest (doc review).

**Acceptance Criteria:**
- A single new section added to `commands/knowledge-graph.md`; zero changes to existing subcommand definitions or the usage block.
- All docs reference the new skill, the `graph-mcp-server.py` server, `graph_bfs_core.py`, and the `hybrid_graph` flag consistently — no leftover `codebase-memory-mcp` or `knowledge-graph-bridge.py` references anywhere.
- The backend split (which queries go where) is described identically across all docs and the skill.
- `auto-loaded-skills.md` contains the `@` reference so the skill loads without manual invocation.
- The `settings.json` block documented in `docs/knowledge-graph.md` matches Task 3 exactly (command `python3`, args `[".claude/graph/graph-mcp-server.py"]`, no `--watch`).

---

## Task 6 — End-to-end verification

**Files:** none (verification only).

**Steps:**
1. [ ] **Flag OFF (regression):** with `hybrid_graph: false`, run `callers`, `impact`, `path`, `god-nodes`, and one Unity-semantic query. Confirm output is identical to pre-change behaviour. Assert that **stderr is empty** for all four call-graph queries — no warning, no diagnostic, no probe noise — even when the `mcp` package is uninstalled and the server is unregistered. This is the complete silence guarantee for the off-path.
2. [ ] **Flag ON, MCP connected (State A):** with the server registered and `pip install mcp` done, run the 4 call-graph queries. Confirm they are dispatched through `mcp__graph_mcp__*` and that each tool's output is structurally identical to `python3 .claude/graph/graph-traversal.py <subcommand> --json`. No warning emitted to stderr in State A.
3. [ ] **Parity harness — consolidated (State B + structural parity + negative cases):** for each of the four call-graph queries, execute the following two-armed harness:
   - **MCP-present arm (State A structural parity):** run the query through `mcp__graph_mcp__*` and through `python3 .claude/graph/graph-traversal.py <subcommand> --json`. Assert the two outputs are structurally identical, field-for-field.
     - **Omit-defaults sub-case:** run `impact` without `--hops` on the CLI and without `hops` in the MCP call; run `god-nodes` without `--top` on both sides. Assert both produce identical output (both resolve to `graph_bfs_core`'s `hops=3` / `top=10` signature defaults).
     - **Negative-case sub-arm:** run an unknown node (guaranteed absent from the graph) through both backends. Assert (1) the suggestion/empty-result structure is identical between `graph-traversal.py <subcommand> --json` and the `mcp__graph_mcp__*` tool; and (2) the MCP call returns a **successful tool result**, not a JSON-RPC protocol error. This mechanically enforces the Decision 11 exit-0 / result-not-error contract.
   - **MCP-absent arm (State B stderr assertion):** force MCP-absent (unregister the server or uninstall `mcp` so the tool is not present). Then:
     a. Grep the canonical warning literal from `.claude/skills/core/knowledge-graph-hybrid.md` — specifically, extract the exact byte sequence from the `echo "..." >&2` command in the skill's documented fallback Bash.
     b. Invoke the fallback path (State B trigger).
     c. **pip probe sub-cases (mcp installed, tool absent — the mcp-present-but-unregistered case):** capture stderr and assert it contains **only** the grepped generic-warning literal (byte-for-byte match on the warning portion). Do NOT hardcode the warning string in the test; the skill file is the source of truth. If the skill's literal ever changes, the harness picks up the new bytes automatically.
     d. **pip probe sub-cases (mcp uninstalled):** force `mcp` uninstalled. Capture stderr. Assert it contains the specific diagnostic `"graph-mcp-server gerektiren 'mcp' paketi kurulu değil — pip install mcp"` **followed by** the grepped generic-warning literal — in that order. The generic-warning portion must still byte-for-byte match the grepped literal; the specific diagnostic is asserted as a prefix.
4. [ ] **Unity-semantic queries** (`summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising`) stay on `jq` / graph.json in all modes above.
5. [ ] Confirm `graph-builder.py`, the extractors, and `settings.json` were never modified by Claude. Confirm `graph-traversal.py`'s CLI surface + output is identical to pre-change; its internals may import `graph_bfs_core` (Task 0 change is expected and correct).

**Test Type:** NoTest (manual end-to-end / verification-before-completion).

**Acceptance Criteria:**
- Flag-off output matches baseline exactly (no regression). Flag-off stderr is **empty** for all four call-graph queries regardless of `mcp` installation status or server registration status.
- Flag-on State A: connected path dispatches through `mcp__graph_mcp__*` tools; output format matches `graph-traversal.py --json` per subcommand; no stderr output.
- Omit-defaults parity confirmed: omitting `hops`/`top` on both CLI and MCP produces identical output via shared `graph_bfs_core` defaults.
- Negative-case sub-arm confirmed: unknown-node query returns identical suggestion/empty structure from both backends; MCP returns a successful tool result (not a JSON-RPC protocol error).
- State B stderr assertion: the parity harness greps the canonical generic-warning literal from `knowledge-graph-hybrid.md` at test time; mcp-present-but-unregistered case asserts stderr = grepped literal byte-for-byte; mcp-uninstalled case asserts specific diagnostic precedes the grepped literal — no independently typed copy of the warning string exists in the test steps.
- pip probe sub-cases verified: mcp uninstalled → specific diagnostic before generic warning; mcp present-but-unregistered → generic warning only.
- Unity-semantic queries unaffected in every mode.
- `/knowledge-graph` interface (subcommand names, args, output columns) unchanged throughout.
- `graph-traversal.py` CLI surface + output identical to pre-change version; `settings.json` unmodified by Claude.

---

## Implementation Notes

- **Sequencing:** Group A = Task 0 (BFS core extraction) + Task 2 (flag), independent. Group B = Task 1 (server), blocked on Task 0. Group C = Task 3 (settings doc) + Task 4 (routing skill), both blocked on group B. Group D = Task 5 (docs), blocked on Task 4. Group E = Task 6 (verification), blocked on everything.
- **We own the server:** there is no third-party discovery, no LSP/tree-sitter question, and no GO/NO-GO gate. The server consumes the same `graph.json` the rest of the toolchain already produces. All 4/4 call-graph queries have a guaranteed MCP equivalent.
- **Single source of BFS truth:** `graph_bfs_core.py` is the one place where `bfs`, the query cores, and the `hops=3`/`top=10` defaults live. Both `graph-traversal.py` (internals refactored) and `graph-mcp-server.py` import this module. The parity test is the regression tripwire: even with a shared core, Task 6 still runs both surfaces side by side and asserts structural equality, catching any future divergence introduced by a surface-specific filter or post-process.
- **Stale graph handling:** `graph-mcp-server.py` records `graph.json` mtime at startup. Each handler checks mtime before answering; if newer, `load_graph()` is called and all three partitions are reloaded. The atomic rebind (fresh locals → module-level rebind in one no-`await` burst, with comment `# Atomic rebind — no await here`) is safe because the `mcp` stdio server serializes tool calls on one asyncio event loop. On mid-session reload failure, the handler keeps the last-good graph, answers from it, and emits a stderr warning without crashing. Startup still fails fast per Decision 1.
- **No `asyncio.Lock`:** single-threaded asyncio event loop + no-`await` rebind block = no preemption risk. A lock would add only a stall point and failure mode with zero safety benefit.
- **Fail fast on all three partition files:** if ANY of `graph.json`, `scenes.json`, or `prefabs.json` is missing, unreadable, or malformed JSON at startup, the server exits with a non-zero code before completing the stdio handshake. This makes State B the correct routing outcome, triggering the fallback with the warning string emitted by the routing skill's fallback `echo >&2`.
- **Warning string ownership:** the warning string has exactly one canonical owner — the `echo "..." >&2` command in the routing skill's documented fallback Bash invocation (`.claude/skills/core/knowledge-graph-hybrid.md`). All other references in this plan — including this note — point at "the warning string emitted by the routing skill's fallback `echo >&2`" without restating the literal. The Task 6 parity harness greps the literal from the skill file at test time — there is no second hand-typed copy in the test.
- **2-state routing, flag-gated:** the `hybrid_graph` gate (Task 4 Step 2) is the outermost check. When off, all MCP machinery — State A/B eval, the stderr warning, and the lazy pip probe — is skipped entirely. The off-path is completely silent. Only when `hybrid_graph` is `true` does State A/B evaluation occur.
- **Not-found is success:** handler outcomes for valid-but-empty queries (not-found, no callers, no path, suggestion) are returned as successful MCP tool results matching the CLI `--json` shape. JSON-RPC errors are reserved for genuine faults only. This mirrors `graph-traversal.py`'s exit-0 contract.
- **SCRIPT_DIR pattern:** `graph-mcp-server.py` uses `os.path.dirname(os.path.abspath(__file__))` to locate all three partition files and to insert the local path for `import graph_bfs_core`. Same discipline as `graph-traversal.py` line 11. No hardcoded absolute paths.
- **settings.json reminder:** Claude cannot edit this file under any circumstances. `check-config-protection.sh` blocks it. The `mcpServers.graph-mcp` entry and the `pip install mcp` prerequisite are documented for the user to apply manually.
- **No changes to graph generation:** `graph-builder.py` and all extractors are untouched.
