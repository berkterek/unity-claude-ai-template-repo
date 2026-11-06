# PLAN — Graph as a Complete Code Map + Token-Bounded Reads
> **Version:** v1 — 2026-11-06
> **Status:** Active
> **Scope:** Template tooling only — `.claude/graph/` (Python stdlib + bash), `.claude/hooks/`, `.claude/commands/knowledge-graph.md`, `.claude/scripts/pipeline-breakdown.py`. No Unity game code; no C# is written. No Graphify dependency (ideas only). `settings.json` is not edited by Claude.

**Complexity score:** 0.78 — Complex (extractor + schema + builder + validator + query tools + hook + cross-repo measurement; changes graph semantics, forcing a full rebuild on every downstream project via EXTRACTION_VERSION).

## Approaches considered

1. **Extractor-first, measure after.** Add every field, then build tools, then measure. Cheapest to start. But there is no baseline, so "it got better" can't be proven, and we would add fields nobody's code-map asks for.
2. **Measurement-gated incremental (chosen).** Write the coverage script first and record a baseline on nile module 13. Add only the fields that the code-map's symbol kinds need, then re-measure against fixed gates. Build the nudge hook only if the gates pass, then verify cost on a real run.
3. **Query-time only.** Leave graph.json alone and make `what`/`where` re-parse source with tree-sitter on demand. This needs no schema change. But it re-reads the source the agent is trying to avoid reading, adds seconds per query, needs tree-sitter at query time, and leaves the validate rule with nothing to inspect.

## Chosen Approach

Approach 2. These decisions are fixed for the implementer:

- **D1 — What gets stored.** Store `line` + `end_line` on classes, interfaces, methods, properties and fields (fields include `event` fields). Methods gain `signature` (tree-sitter now matches regex). Constructors are not stored as members. The code-map uses the bare word "constructor" un-backticked, and adding ctors to `methods` would create `Class.Class` call keys. XML `<summary>`/`<remarks>` go to `doc: {summary, remarks}`. Tags are stripped, `<see cref="X"/>` becomes `X`, whitespace is collapsed, and each part is capped at 300 chars with a trailing `…`.
- **D2 — Registrations.** Each record gains `method`, the literal `Register*` name. It also gains `chain`, the ordered trailing-call names, e.g. `["AsSelf","AsImplementedInterfaces"]`, plus `line`. `RegisterFactory` joins `REG`. Its generic slot is the factory product, not a concrete type, so it is stored as `{type:"", factory_of:T, unresolved:true, confidence:"AMBIGUOUS"}`. The validator already exempts `unresolved`, so no false `INSTALLER_MISSING_CLASS`. `as` keeps its single-string contract.
- **D3 — Dispatch edges are not stored.** `graph_bfs_core.callers_core` already returns `matched_via: "interface_bridge"` hits through `implements_map`/`_callee_match_kind`. Stored `dispatches_to` edges would duplicate those answers in `calls[]`, inflate god-node degree (`god_nodes_core` counts edges), and go stale when an implementer changes in another file during an `--incremental` build, because edges are merged per changed file (`merge_call_edges` l.492). Graphify needs stored edges because it has no query-time resolver. This repo has one. The one useful Graphify idea, confidence by implementer count, is adopted at query time: `what` prints `dispatch: N implementer(s)` with `high` for 1, `medium` for 2-3 and `low` for 4 or more, matching `_dispatch_confidence` semantics.
- **D4 — Regex parity.** Ranges, properties, fields, signature and doc are **tree-sitter-only**. The regex fallback can't find `end_line` reliably: brace counting breaks on braces in strings, `#if` blocks, and expression bodies. It also can't attach `///` blocks to the right declaration. A half-right range is worse than none, because an agent would do a wrong ranged Read with confidence. The fallback is rare: it needs the pip bindings to be missing, which `verify-graphify.sh` already reports. **Exception: registrations get regex parity** (`method`, `chain`, `line`). The regex forms already match per method name and `line_of(pos)` exists. The validate rule is a defect detector and must not go silent in fallback mode. Query tools print `range: unavailable (regex mode)` when `end_line` is absent. The coverage script reports the mode.
- **D5 — Nile measurement protocol, read-only.** Extract nile's script roots at a pinned commit with `git -C <nile> archive <sha> … | tar -x -C $TMP/src`. Copy the template's `.claude/graph/` to `$TMP/tool/`, and run the builder from `$TMP/src` with `--output $TMP/out/graph.json --full --skip-mcp`. The builder writes its cache and `.last-build` next to `SCRIPT_DIR` and partitions next to `--output`, so every write lands in `$TMP`. nile's working tree, `.git` and graph.json are never touched (no worktree, no checkout). One script, `graph-coverage-run.sh`, does this, so the baseline and the re-measure are the same command.
- **D6 — Hook channel.** The nudge never sets `permissionDecision` ("allow" would skip permission prompts, "deny" is forbidden). It emits `hookSpecificOutput.additionalContext`. If PreToolUse does not deliver that to the model in the installed Claude Code version, the same script registers as PostToolUse instead (it is still never a deny). Task 10 step 1 decides this.

**Critique pass, with resolutions:**
- *"100% location is unreachable for rows like `RegisterComponentInHierarchy<CardManager>` and `_chapters`."* That is why fields and registration `line` are stored (D1, D2). Un-backticked descriptive words ("constructor", "fields, properties") are not symbols (Task 1 parsing rules). A row with no backticked symbol is located by its file's primary type. If the gate still misses, the report names the failing symbols. Gates are measured; they are not loosened afterwards.
- *"Behaviour ≥60% may depend on how much XML doc nile has, which the template doesn't control."* That is accepted. Behaviour also counts callers and registration facts, and the baseline shows how much each source contributes. If the gate fails, the hook phase does not ship, and the plan records why.
- *"Graph size grows on a 7.2 MB graph that every query loads."* Docs are capped (D1), and Task 9 measures the growth as a gate (≤ +35%) plus `what` wall time (< 1.5 s on nile).
- *"`chain` duplicates `as`."* `as` is the exposed-service contract, while `chain` is raw evidence. `_as_chain`'s first-wins rule means `as` cannot express `.As<IFoo>().AsImplementedInterfaces()`, so the rule needs `chain`.
- *"The nudge could fire inside the graph tooling's own tests or on graph.json reads."* It only fires on `.cs` paths under the indexed roots. graph.json reads are `block-graph-direct-read.sh`'s job, and the two never act on the same path.

## Usage Model — PUSH, not pull (decision 2026-11-06, user-approved direction; tasks below need Codex review before implementation)

Measured: agents almost never query the graph on their own (2 queries / 763 transcripts), while code-map rows that `/orchestrate` pastes into prompts are used. So graph facts reach agents by being **pushed into prompts**, not by asking agents to query:
- **P1 — code-map filled from the graph.** The planner writes only `Task(s) | Symbol | Why it matters`; a script (`graph_coverage.py fill` or a sibling) fills File, Lines, signature, doc and registrations from the graph. Planner grep discovery is what this removes.
- **P2 — `/orchestrate` pastes `what` output per task symbol** into the coder/tester/reviewer prompts next to the code-map rows (budgeted), with the `where` range for any ranged Read.
- **P3 — the nudge hook (T10) is secondary**; ship it only if P1/P2 leave measurable grep/full-read traffic.
- **Kill criterion:** if T9 gates fail, P1/P2/T10 are not built. If T11 shows no drop in planner Bash calls/spawn AND no drop in the full-file `.cs` read share (baseline on nile since 2026-10-25: ranged 152 Read + 509 `sed -n` vs full 751 Read + 633 `cat`), the feature is recorded as not useful and removed — no unused tooling is kept.
P1 and P2 are added as tasks after T9 (gated on it) in the next revision of this plan.

## Context

`.claude/graph/graph.json` answers *who calls what* (calls[] plus query-time interface bridging) and *what is registered where* (vcontainer installers/scopes). It cannot answer *where exactly is X and what does it do*. Methods carry only a start `line`. Properties and fields are absent. No XML doc is read. Registrations do not record which `Register*` method made them. So planner and reviewer agents fall back to grep+cat. A /plan-module run on nile module 13 averaged ~39 Bash discovery turns per planner spawn and made 2 graph queries in 763 tool calls.

A real defect went undetected for the same reason. `RegisterEntryPoint<T>().AsImplementedInterfaces()` registers the entry-point interfaces twice, and VContainer throws "Conflict implementation type" at scope build (seen 2026-11-06 in a downstream project). The graph stores `as="AsImplementedInterfaces"` but not the method, so the combination can't be detected.

This plan makes the graph complete enough for a module code-map, with nile `docs/modules/13-power-readout/code-map.md` as the yardstick. It also gives agents two bounded reads: `what <X>`, a 2000-token-budgeted fact sheet, and `where <X>`, which returns `file:start-end` for a ranged Read. A soft nudge hook ships only after measured coverage gates pass. Success is the final measurement on a real /plan-module run, not the field count.

## Goals
- [ ] Coverage script + fixture + **baseline** recorded before any extractor change
- [ ] Classes, interfaces, methods, properties and fields carry `line` + `end_line` (tree-sitter); methods carry `signature`; XML doc summary/remarks attached and capped
- [ ] Registrations carry `method`, `chain`, `line` in both extractor modes; `RegisterFactory` recognised
- [ ] `graph_validate.py` flags `RegisterEntryPoint` + `AsImplementedInterfaces`
- [ ] `graph-traversal.py what|where` (+ MCP tools) with a token budget
- [ ] Measured gates on nile module 13: LOCATION = 100%, BEHAVIOUR ≥ 60%, graph size ≤ +35%, `what` < 1.5 s
- [ ] Nudge hook (only if gates pass), never denies, settings entry handed to the user
- [ ] Real /plan-module run measured against the baselines (39 Bash turns/planner spawn; 2 graph queries / 763 calls)

## Status

| Phase | Task | Status | parallel_group |
|---|---|---|---|
| 0 — Baseline | T1 Coverage script + fixture + unit test | Done `0102107` | A |
| 0 — Baseline | T2 Nile runner + BASELINE recorded | Done `0102107` | B (after T1) |
| 1 — Extractor | T3 Ranges, signature, properties, fields (tree-sitter) | Done `810cc4a` | C (after T2) |
| 1 — Extractor | T4 XML doc extraction | Done `810cc4a` | D (after T3, same file) |
| 1 — Extractor | T5 Registration method/chain/line + RegisterFactory (both modes) | Done `810cc4a` | E (after T4, same file) |
| 1 — Builder | T6 Schema 1.8.0, EXTRACTION_VERSION 7, incremental survival | Done `3bda974` | F (after T5) |
| 2 — Validate | T7 ENTRYPOINT_DOUBLE_INTERFACES rule | Done `0def91c` | G1 (after T6) |
| 3 — Query | T8 `what` / `where` + MCP + /knowledge-graph doc | Done `0def91c` | G2 (after T6; parallel with T7 — disjoint files) |
| 4 — Re-measure | T9 Re-measure + gates | Done — **BEHAVIOUR gate FAIL** (55.6 < 60); other 3 gates PASS | H (after T7, T8) |
| 5 — Nudge | T10 Graph nudge hook **[gated on T9 PASS]** | **Skipped — gate failed** | I (after T9) |
| 6 — Verify | T11 Real /plan-module cost/quality run | Todo | J (after T10 or T9 if T10 skipped) |

## File Map

| File | Change Type | Notes |
|---|---|---|
| .claude/graph/graph_coverage.py | Create | Code-map × graph coverage report (LOCATION / BEHAVIOUR / mode), gate flags |
| .claude/graph/graph-coverage-run.sh | Create | Read-only nile runner: git archive → temp → temp tooling copy → build → coverage |
| .claude/graph/test/fixtures/coverage/13-power-readout.code-map.md | Create | Verbatim copy of the nile code-map |
| .claude/graph/test/fixtures/coverage/mini.code-map.md, mini.graph.json | Create | Synthetic unit fixture for the coverage script (hand-written test input, not a generated graph) |
| .claude/graph/test/fixtures/coverage/baseline-13.json, after-13.json | Create | Recorded measurement outputs |
| .claude/graph/test/test_graph_coverage.py | Create | Stdlib test |
| .claude/graph/extractors/csharp_extractor.py | Modify | Member ranges, signature, properties, fields, doc, registration method/chain/line, RegisterFactory |
| .claude/graph/extractors/csharp-extractor.sh | Modify | Regex registration parity only (method/chain/line, RegisterFactory) |
| .claude/graph/test/fixtures/members_docs/*.cs + EXPECTED.md | Create | Extractor fixtures (C# test input files, not game code) |
| .claude/graph/test/test_extractor_members_docs.py | Create | Stdlib test |
| .claude/graph/test/test_registration_method.py | Create | Stdlib test, both extractor modes |
| .claude/graph/graph-builder.py | Modify | EXTRACTION_VERSION 7, schema_version 1.8.0, comment block |
| .claude/graph/schema.json | Modify | methodEntry/classEntry/interfaceEntry/registrationEntry new fields; propertyEntry, fieldEntry, docEntry defs |
| .claude/graph/graph_validate.py | Modify | New consistency issue type |
| .claude/graph/test/test_validate_entrypoint_rule.py | Create | Stdlib test |
| .claude/graph/graph_bfs_core.py | Modify | `resolve_symbol`, `where_core`, `what_core`, `budget_truncate` |
| .claude/graph/graph-traversal.py | Modify | `what`, `where` subcommands |
| .claude/graph/graph-mcp-server.py | Modify | `what`, `where` tools (thin wrappers) |
| .claude/graph/test/test_what_where.py | Create | Stdlib test |
| .claude/graph/test/verify-graphify.sh | Modify | Register new tests |
| .claude/commands/knowledge-graph.md | Modify | Document `what`/`where` as the first-choice lookup |
| .claude/hooks/graph-nudge.sh | Create (gated) | Soft reminder, chmod +x |
| .claude/hooks/pre-compact.sh | Modify (gated) | Reset nudge counters |
| .claude/hooks/tests/test-graph-nudge.sh | Create (gated) | Bash test, in the existing hook test dir |
| .claude/scripts/pipeline-breakdown.py | Modify | `--tools` mode: Bash turns/spawn per agent type, graph queries per transcript |

---

## Task 1 — Coverage script, fixture, unit test

**Files:** .claude/graph/graph_coverage.py, .claude/graph/test/fixtures/coverage/13-power-readout.code-map.md, .claude/graph/test/fixtures/coverage/mini.code-map.md, .claude/graph/test/fixtures/coverage/mini.graph.json, .claude/graph/test/test_graph_coverage.py

**Steps:**
1. [ ] Copy `/Users/berkterek/Desktop/Github/nile_bounce_legion_repo/docs/modules/13-power-readout/code-map.md` verbatim to `fixtures/coverage/13-power-readout.code-map.md`, and add a first line `<!-- source: nile_bounce_legion_repo@12bb3911 -->`.
2. [ ] Parse the code-map:
   - Read `Base \`S\` = \`…\`` lines into an alias map.
   - Table rows are the lines after the `|---|` separator. Columns are Task(s) | File | Symbol | Lines | Why.
   - Expand the `S/` prefix in File.
   - In-scope rows: File ends in `.cs`. Others count as `out_of_scope` grouped by extension.
3. [ ] Normalise symbols from the backticked tokens in the Symbol cell:
   - Drop `(…)` argument lists.
   - Treat `Register\w*<T>` as a **registration** symbol `(method, T)`.
   - Split `Owner.Member` into qualifier + member.
   - `A → B` yields both A and B.
   - Skip tokens followed by `(new)` (expected-absent).
   - Un-backticked words are descriptive and never symbols.
   - A row with zero symbols resolves to the primary type of its file (the type whose name equals the file stem, else the first type).
4. [ ] Resolve each symbol, restricted to records whose `file` equals the row's File:
   - Type: class/interface/struct, then members (methods, properties, fields) of types in that file, then registrations in installers/scopes of that file (match on method + T against `type`/`factory_of`/`as`).
   - If the owner qualifier names a type in another file, follow it.
5. [ ] Compute LOCATION and the diagnostics:
   - LOCATION(symbol) = resolved AND `line` and `end_line` are ints (registrations: `line` only, since a call has no range worth reading).
   - Row LOCATION = all of the row's symbols located.
   - Also report `location_start_only` and `hint_overlap` (resolved range intersects the Lines hint). Both are diagnostic only.
6. [ ] Compute BEHAVIOUR:
   - BEHAVIOUR(symbol) = `doc.summary` non-empty, OR ≥1 caller via `graph_bfs_core.callers_core` (any `matched_via`), OR a registration fact (type appears in a registration's `type`/`as`/`as_resolved`/`factory_of`, or the symbol is itself a registration with `method`).
   - Row BEHAVIOUR = all located symbols have ≥1 fact.
   - Also report which source supplied each fact (doc/callers/registration).
7. [ ] Report the mode: `tree-sitter` if every class has `confidence == "EXTRACTED"` and `validation.warnings` has no fallback warning, else `regex`.
8. [ ] CLI flags: `--code-map`, `--graph`, `--json`, `--gate-location PCT`, `--gate-behaviour PCT`. Exit 1 if any gate is missed, 2 on input error.
9. [ ] Write `mini.code-map.md` (6 rows: type, method, property, field, registration, out-of-scope `.uxml`) and a hand-written `mini.graph.json` that resolves exactly 4/5 for location and 3/5 for behaviour. Write `test_graph_coverage.py` in the `check()`/`_failures` style, with a header docstring that states what it pins.

**Test Type:** stdlib test script

**Code Skeleton:**
```python
# graph_coverage.py — stdlib only
ROW_RE = re.compile(r"^\|(.+)\|\s*$")
TICK_RE = re.compile(r"`([^`]+)`")
REG_RE = re.compile(r"^(Register\w*)<([A-Za-z0-9_.]+)>")

def parse_code_map(text) -> tuple[dict, list[dict]]:     # (aliases, rows[{tasks,file,symbols,hint,in_scope,ext}])
def normalise_symbol(tok) -> dict | None:              # {kind:'reg'|'name', owner, member, method, targ}
def index_graph(g) -> dict:                            # file -> {types, members, registrations}
def resolve(sym, row_file, idx) -> dict | None:        # {file,line,end_line,kind,record}
def behaviour_facts(sym, rec, g, bfs_ctx) -> list[str] # ['doc','callers','registration']
def detect_mode(g) -> str
def measure(code_map_path, graph_path) -> dict         # {mode, rows_total, in_scope, out_of_scope:{ext:n},
                                                       #  location_pct, behaviour_pct, location_start_only_pct,
                                                       #  per_row:[...], failing_symbols:[...]}
def main(argv) -> int
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_graph_coverage.py` prints `ALL PASSED` and exits 0.
- `python3 .claude/graph/graph_coverage.py --code-map .claude/graph/test/fixtures/coverage/13-power-readout.code-map.md --graph .claude/graph/test/fixtures/coverage/mini.graph.json --json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["rows_total"],d["in_scope"])'` prints `34 27` (measured 2026-11-06 on the nile working-tree code-map; `code-map.md` is untracked there, not part of `12bb3911`).
- `--gate-location 100` against mini.graph.json exits 1. `--gate-location 50` exits 0.

---

## Task 2 — Read-only nile runner + BASELINE

**Files:** .claude/graph/graph-coverage-run.sh, .claude/graph/test/fixtures/coverage/baseline-13.json, docs/PLAN_graph_complete_map.md (this plan file — created at /create-plan save; Baseline table below)

**Steps:**
1. [ ] Write `graph-coverage-run.sh <target-repo> <sha> <code-map> [out.json]`, with `set -euo pipefail`:
   - `TMP=$(mktemp -d)`, with an `EXIT` trap that removes it unless `KEEP_TMP=1`; then `mkdir -p "$TMP/src" "$TMP/out" "$TMP/tool"` before any extract or build.
   - Read `unity_project_folder` from `git -C "$repo" show "$sha:.claude/project-features.json"`.
   - Build the root list first: for each candidate (`$uf/Assets/_Framework`, `$uf/Assets/_GameFolders/Scripts`, `.claude/project-features.json`) keep it only if `git -C "$repo" cat-file -e "$sha:<root>"` succeeds (so `git archive` never sees an absent path); zero kept code roots → exit 2 with a message. Then `git -C "$repo" archive "$sha" -- "${roots[@]}" | tar -x -C "$TMP/src"`. Asmdefs outside those roots are not needed for coverage. Every write (src, tool copy, cache, `.last-build`, partitions, out) stays under `$TMP`.
   - `git -C "$TMP/src" init -q` so `get_repo_root` resolves inside `$TMP`.
   - `cp -R <template>/.claude/graph "$TMP/tool"`, then delete `"$TMP/tool"/{graph.json,scenes.json,prefabs.json,cache,.last-build}` in the copy.
   - `(cd "$TMP/src" && python3 "$TMP/tool/graph-builder.py" --full --skip-mcp --quiet --output "$TMP/out/graph.json")`.
   - Run `graph_coverage.py --json` and write the result to stdout or out.json. Add `graph_bytes`, `template_sha` (`git rev-parse --short HEAD`), `target_sha` and `mode`.
2. [ ] Guard: refuse to run when `realpath` of the output path is inside `<target-repo>`.
3. [ ] Run the baseline **before any Phase 1 change** and commit the JSON:
   `bash .claude/graph/graph-coverage-run.sh /Users/berkterek/Desktop/Github/nile_bounce_legion_repo 12bb3911 .claude/graph/test/fixtures/coverage/13-power-readout.code-map.md .claude/graph/test/fixtures/coverage/baseline-13.json`
4. [ ] Copy the numbers into the Baseline table below. Expect LOCATION 0% under the range definition (no `end_line` exists yet). Record `location_start_only` as well.
5. [ ] Prove read-only: before and after the run, `git -C <nile> status --porcelain | wc -l`, `shasum <nile>/.claude/graph/graph.json` and `stat -f %m <nile>/.claude/graph/graph.json` are identical.

| Metric | Baseline (T2) | After (T9) | Gate |
|---|---|---|---|
| mode | tree-sitter | tree-sitter | tree-sitter — PASS |
| in-scope rows | 27 | 27 | — |
| LOCATION % | 0.0 | 100.0 | = 100 — PASS |
| location_start_only % | 63.0 | 100.0 | — |
| BEHAVIOUR % | 0.0 (resolved-only diagnostic: 37.0; sources doc 0 / callers 18 / registration 0) | 55.6 (sources doc 4 / callers 18 / registration 4) | ≥ 60 — **FAIL** |
| graph_bytes | 6987023 (±~700 B run to run) | 8142772 (×1.17) | ≤ baseline × 1.35 — PASS |
| `what` wall time (s) | n/a | 0.05 (`what CardManager`, 3 runs) | < 1.5 — PASS |

Baseline recorded 2026-11-06, template `4aed387`, nile `12bb3911`. 15 symbols unresolved (properties, fields, `Register*<T>` rows — no record kind exists yet), 28 resolved without a range. BEHAVIOUR stays 0 by construction while nothing is ranged, so `behaviour_resolved_pct` and `fact_sources` are reported as diagnostics; the gate stays on `behaviour_pct`.

**T9 result (2026-11-06, nile `12bb3911`):** LOCATION 100.0, BEHAVIOUR 55.6, size ×1.17, `what` 0.05 s. BEHAVIOUR misses 60 by 2 rows of 27; the gate is not changed. 17 symbols have no behaviour fact:
- **Property/field/event reads are not call edges** (9): `Damage`, `HitsPerShot`, `OnStatsChanged`, `ICardService.CardsOnGame`, `CardManager.CardsOnGame`, `Chapters`, `ChapterText`, `StageText`, `BossReward`, `LOBBY_UXML_PATH`. `calls[]` records invocations only; nothing records reads or `+=` subscriptions.
- **Engine/test-runner callbacks** (5): `OnEnable` ×2, `OnDisable`, `SetUp`, `TearDown`. No code caller exists by design; only a doc could supply a fact, and nile has none there.
- **Namespace-qualified static calls lose their type** (2, a pre-existing extractor defect): `SceneModules` calls `Game.Concretes.Lobby.LobbyModule.InstallMenu(builder)`, which is stored as callee `Game.InstallMenu` (external), so `LobbyModule.InstallMenu` and `PowerModule.Install` show no callers. Fixing this alone would put BEHAVIOUR at 63.0 (17/27), above the gate.
Per the kill criterion, T10, P1 and P2 are not built on this result. T11 needs a nile sync and a user-run `/plan-module`, so it is outside this run.

**Test Type:** NoTest (the runner is exercised by its own output plus the read-only proof in step 5)

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# graph-coverage-run.sh — measure graph coverage of a code-map against ANOTHER repo, read-only.
set -euo pipefail
repo=$1 sha=$2 map=$3 out=${4:-/dev/stdout}
TPL=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); [[ ${KEEP_TMP:-0} == 1 ]] || trap 'rm -rf "$TMP"' EXIT
case "$(realpath "$(dirname "$out")")" in "$(realpath "$repo")"*) echo "refusing: output inside target" >&2; exit 2;; esac
# archive → src ; cp tooling → tool ; build ; measure ; jq-merge metadata
```

**Acceptance Criteria:**
- `baseline-13.json` exists and holds `mode`, `location_pct`, `behaviour_pct` and `graph_bytes`, and the Baseline column is filled in.
- The step-5 before/after values are identical: `git -C /Users/berkterek/Desktop/Github/nile_bounce_legion_repo status --porcelain | wc -l`, then `shasum /Users/berkterek/Desktop/Github/nile_bounce_legion_repo/.claude/graph/graph.json`.
- `git -C /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo status --porcelain .claude/graph/graph.json .claude/graph/cache` prints nothing (the template's own graph/cache are untouched).

---

## Task 3 — Ranges, signature, properties, fields (tree-sitter)

**Files:** .claude/graph/extractors/csharp_extractor.py, .claude/graph/test/fixtures/members_docs/Members.cs, .claude/graph/test/fixtures/members_docs/EXPECTED.md, .claude/graph/test/test_extractor_members_docs.py

**Steps:**
1. [ ] Generalise `_own_method_nodes` (l.130) into `_own_member_nodes(node, kinds, results)` with the same descent rules (through preproc, not into nested types or bodies). Keep `_own_method_nodes` as a wrapper so existing callers are unchanged.
2. [ ] `_extract_methods` (l.148): add `end_line = end_point[0]+1`. Add `signature`: the source slice from the first modifier or the type up to the body/`=>`/`;`, flattened via `_flatten_one_line` (l.245), with attribute lists excluded.
3. [ ] Add `_extract_properties(body, src)` for `property_declaration`. Emit `{name, type, line, end_line, accessibility, is_static, accessors:[get|set|init], is_expression_bodied}`.
4. [ ] Add `_extract_fields(body, src)` for `field_declaration` and `event_field_declaration`. Emit one entry per declarator: `{name, type, line, end_line, accessibility, is_static, is_const, is_readonly, is_event}`. Leave `field_types` as it is (its consumers are unchanged).
5. [ ] In `extract_file`, add `end_line`, `properties` and `fields` to class records (l.~770-790). Add `end_line` and `properties` to interface records (l.~826-842).
6. [ ] Fixture `Members.cs`: a class with an expression-bodied property, an auto-property, a `#if UNITY_EDITOR`-wrapped method, a nested class (whose members must NOT leak into the outer class), multi-declarator fields, an `event Action` field, a const, and an interface with a property. EXPECTED.md lists the exact line/end_line per member.
7. [ ] Test (the extractor-half of `test_extractor_members_docs.py`): import the extractor through `importlib` the way `test_extractor_pubsub.py` does, skip with exit 0 and a `SKIP` line if tree-sitter is unavailable, and assert every EXPECTED.md range.

**Test Type:** stdlib test script

**Code Skeleton:**
```python
_MEMBER_KINDS_METHOD = {"method_declaration"}
_MEMBER_KINDS_PROP = {"property_declaration"}
_MEMBER_KINDS_FIELD = {"field_declaration", "event_field_declaration"}

def _own_member_nodes(node, kinds, results): ...
def _range(n): return n.start_point[0] + 1, n.end_point[0] + 1
def _signature(decl, src):
    stop = decl.child_by_field_name("body") or _first_child(decl, ("arrow_expression_clause", ";"))
    start = next((c for c in decl.children if c.type != "attribute_list"), decl)
    return _flatten_one_line(src[start.start_byte:(stop.start_byte if stop else decl.end_byte)].decode())
def _extract_properties(body, src) -> list[dict]: ...
def _extract_fields(body, src) -> list[dict]:     # one dict per variable_declarator
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_extractor_members_docs.py` prints `ALL PASSED` (or `SKIP: tree-sitter unavailable` with exit 0 only when the bindings are missing).
- `python3 .claude/graph/extractors/csharp_extractor.py --changed-files .claude/graph/test/fixtures/members_docs/Members.cs | python3 -c 'import json,sys;c=json.load(sys.stdin)["classes"][0];print(all("end_line" in m for m in c["methods"]), len(c["properties"])>0, any(f["is_event"] for f in c["fields"]))'` prints `True True True`.
- `python3 .claude/graph/test/test_call_kind_and_field_resolution.py` and `python3 .claude/graph/test/test_extractor_pubsub.py` still pass, so existing extraction did not regress.

---

## Task 4 — XML doc extraction

**Files:** .claude/graph/extractors/csharp_extractor.py, .claude/graph/test/fixtures/members_docs/Docs.cs, .claude/graph/test/fixtures/members_docs/EXPECTED.md, .claude/graph/test/test_extractor_members_docs.py

**Steps:**
1. [ ] Write `_doc_for(decl, src)`. Walk `prev_sibling` while the node is a `comment` whose text starts with `///` and the line gap to the next node is ≤ 1. Concatenate the comments, strip the `///` prefixes, and parse them as a snippet wrapped in `<doc>…</doc>` with `xml.etree.ElementTree`. If parsing fails, fall back to a regex tag strip.
2. [ ] Normalise: `<see cref="X"/>` and `<paramref name="x"/>` become `X`/`x`, remaining tags are dropped, whitespace is collapsed, and each part is capped at `DOC_CAP = 300` with `…` appended. Emit `doc: {summary, remarks}` only when at least one part is non-empty. Never emit an empty object.
3. [ ] Attach `doc` to class, interface, method, property and field records (Task 3's builders call `_doc_for`).
4. [ ] Fixture `Docs.cs`: a multi-line summary, `<see cref>`, a summary + remarks pair, a 600-char summary (to test the cap), a `//` (non-doc) comment that must be ignored, a doc block separated by a blank line (must not attach), and an attribute between the doc and the method (must attach, since the attribute belongs to the declaration node).

**Test Type:** stdlib test script

**Code Skeleton:**
```python
DOC_CAP = 300
def _doc_for(decl, src) -> dict | None:
    lines, node, last = [], decl.prev_sibling, decl.start_point[0]
    while node is not None and node.type == "comment":
        t = _node_text(node, src)
        if not t.startswith("///") or last - node.end_point[0] > 1: break
        lines.insert(0, t[3:]); last = node.start_point[0]; node = node.prev_sibling
    return _parse_doc("\n".join(lines)) if lines else None
def _parse_doc(xml_text) -> dict | None:   # ET first, regex fallback; cap; drop empties
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_extractor_members_docs.py` prints `ALL PASSED`, including the cap case (`len(summary) <= 301` and it ends with `…`) and both negative cases (no `doc` key).
- `python3 .claude/graph/extractors/csharp_extractor.py --changed-files .claude/graph/test/fixtures/members_docs/Docs.cs | grep -c '"summary"'` equals the count stated in EXPECTED.md.

---

## Task 5 — Registration `method` / `chain` / `line` + RegisterFactory (both modes)

**Files:** .claude/graph/extractors/csharp_extractor.py, .claude/graph/extractors/csharp-extractor.sh, .claude/graph/test/fixtures/members_docs/Registrations.cs, .claude/graph/test/test_registration_method.py

**Steps:**
1. [ ] Add `RegisterFactory` to `REG` (l.520). Add a branch to emit `{type:"", factory_of:type_arg, as:chained, lifetime:"", unresolved:True, confidence:"AMBIGUOUS"}`.
2. [ ] Write `_chain_calls(inv, src, hops=8)`, which walks up exactly like `_as_chain` (l.496) but collects every trailing member name (`As<IFoo>` rendered with its type arg, `AsSelf`, `AsImplementedInterfaces`, `WithParameter`, …). Leave `_as_chain` unchanged.
3. [ ] At the single `registrations.append(reg)` (l.586), set `reg["method"] = method`, `reg["chain"] = _chain_calls(...)` and `reg["line"] = inv.start_point[0]+1`. Every branch passes through it, so nothing is missed.
4. [ ] Regex parity in `csharp-extractor.sh`: each registration Form already knows its method name. Add `"method"`, `"line": line_of(m.start())` and a `chain` built by a `_chain_list(pos)` sibling of `_chain_as` (l.~369). Add a RegisterFactory form with the same record shape.
5. [ ] Fixture `Registrations.cs`: `RegisterEntryPoint<A>(Lifetime.Singleton).AsImplementedInterfaces()`, `RegisterEntryPoint<B>(Lifetime.Singleton).AsSelf()`, `Register<C>(Lifetime.Singleton).As<IFoo>().AsImplementedInterfaces()`, `RegisterFactory<IThing>(r => () => new Thing())`, `RegisterComponentInHierarchy<D>()`.
6. [ ] Test: run the tree-sitter extractor and the regex path (`bash csharp-extractor.sh` with python forced to fail, e.g. `PATH` shadowing python3 with a stub that exits 2, mirroring how `verify-graphify.sh` sandboxes). Assert both modes yield identical `(method, type|factory_of, chain, line)` tuples.

**Test Type:** stdlib test script

**Code Skeleton:**
```python
def _chain_calls(inv, src, hops=8) -> list[str]:
    out, node = [], inv
    for _ in range(hops):
        ma = node.parent
        if ma is None or ma.type != "member_access_expression": break
        outer = ma.parent
        if outer is None or outer.type != "invocation_expression": break
        m, ta = _member_name_and_typearg(ma, src)
        out.append(f"{m}<{ta}>" if ta else m); node = outer
    return out
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_registration_method.py` prints `ALL PASSED` with both `tree-sitter` and `regex` sections reported. A `SKIP` is allowed only for tree-sitter, never for regex.
- `python3 .claude/graph/test/test_as_implemented_resolution.py` and `python3 .claude/graph/test/test_event_defs_and_installer_detection.py` still pass.

---

## Task 6 — Schema 1.8.0, EXTRACTION_VERSION 7, incremental survival

**Files:** .claude/graph/schema.json, .claude/graph/graph-builder.py, .claude/graph/test/test_extractor_members_docs.py, .claude/graph/test/verify-graphify.sh

**Steps:**
1. [ ] schema.json:
   - Add `end_line` and `doc` (→ `#/definitions/docEntry`) to `methodEntry` (l.627; `signature` already declared).
   - Add `end_line`, `doc`, `properties[]` (→ `propertyEntry`) and `fields[]` (→ `fieldEntry`) to `classEntry` (l.156).
   - Add `end_line`, `doc` and `properties[]` to `interfaceEntry` (l.232).
   - Add `method` (enum of the six names), `chain` (string[]), `line` (int) and `factory_of` (string) to `registrationEntry` (l.856).
   - Add new defs `propertyEntry`, `fieldEntry` and `docEntry` (`summary`, `remarks`, maxLength 301).
   - None of these go in `required`, so older graphs still validate.
2. [ ] graph-builder.py: `EXTRACTION_VERSION = 7` (l.96) and `"schema_version": "1.8.0"` (l.1132). Extend the comment block (l.86-95): 7 adds fields, so schema_version moves as well, following the 3/4/5 precedent.
3. [ ] Confirm the new keys flow through the merge path. `retain_entries` (l.436) keeps whole records, `merge_arrays` (l.484) concatenates, and `resolve_as_implemented` (l.659-682) mutates in place without rebuilding dicts. No code change is expected; the test proves it.
4. [ ] Add a builder test to `test_extractor_members_docs.py` (sandbox pattern from verify-graphify.sh):
   - Run a `--full` build over the fixtures dir in a temp repo, then an `--incremental --changed-files <other file>` build.
   - Assert that the untouched file's class still carries `end_line`, `properties`, `doc` and registration `method`.
   - Assert that a graph stamped `extraction_version: 6` is promoted to `--full` (the stderr has "promoting").
5. [ ] Register `test_graph_coverage.py`, `test_extractor_members_docs.py` and `test_registration_method.py` in `verify-graphify.sh`, next to the existing python test invocations. (T7 and T8 run in parallel, so neither edits `verify-graphify.sh`; T9 step 0 registers their tests.)

**Test Type:** stdlib test script

**Code Skeleton:**
```json
"docEntry": {"type":"object","properties":{"summary":{"type":"string","maxLength":301},"remarks":{"type":"string","maxLength":301}}},
"propertyEntry": {"type":"object","required":["name","line"],"properties":{"name":{},"type":{},"line":{},"end_line":{},"accessibility":{},"is_static":{},"accessors":{},"is_expression_bodied":{},"doc":{"$ref":"#/definitions/docEntry"}}}
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_extractor_members_docs.py` prints `ALL PASSED`, including the incremental-survival and promotion checks.
- `bash .claude/graph/test/verify-graphify.sh` exits 0, and its T-section for extraction_version reads `7` from graph-builder.py (the harness derives it from the source; l.681-690).
- `python3 -c 'import json;json.load(open(".claude/graph/schema.json"))'` exits 0.

---

## Task 7 — `ENTRYPOINT_DOUBLE_INTERFACES` validate rule

**Files:** .claude/graph/graph_validate.py, .claude/graph/test/test_validate_entrypoint_rule.py

**Steps:**
1. [ ] In `run_consistency` (l.44), after the installer loop, iterate installers + scopes. For each registration with `method == "RegisterEntryPoint"` and `"AsImplementedInterfaces" in (reg.get("chain") or [])`, append `{type:"ENTRYPOINT_DOUBLE_INTERFACES", holder, registered:type, line, detail}`. The detail reads: `"<holder> line <n>: RegisterEntryPoint<T>().AsImplementedInterfaces() — RegisterEntryPoint already registers implemented interfaces; VContainer throws 'Conflict implementation type' at scope build. Drop .AsImplementedInterfaces()."`
2. [ ] Records with no `method` (older graphs) are skipped silently. Count them in a `registrations_without_method` stat so a stale graph shows up as stale rather than clean.
3. [ ] Test (mirror `test_validate_interface_nodes.py`): three synthetic graph dicts. (a) Entry point + AIF in chain is flagged once. (b) Entry point + AsSelf is not flagged. (c) `Register<C>().As<IFoo>().AsImplementedInterfaces()` is not flagged (different method).

**Test Type:** stdlib test script

**Code Skeleton:**
```python
for holder in list(vcontainer.get("installers", [])) + list(vcontainer.get("scopes", [])):
    for reg in holder.get("registrations", []) or []:
        if "method" not in reg: no_method += 1; continue
        if reg["method"] == "RegisterEntryPoint" and "AsImplementedInterfaces" in (reg.get("chain") or []):
            issues.append({...})
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_validate_entrypoint_rule.py` prints `ALL PASSED`.
- After a fixture build including `Registrations.cs`, `python3 .claude/graph/graph_validate.py --graph <work>/graph.json` prints a line containing `[ENTRYPOINT_DOUBLE_INTERFACES]`, exactly once.

---

## Task 8 — `what` / `where` queries + MCP + /knowledge-graph doc

**Files:** .claude/graph/graph_bfs_core.py, .claude/graph/graph-traversal.py, .claude/graph/graph-mcp-server.py, .claude/commands/knowledge-graph.md, .claude/graph/test/test_what_where.py

**Steps:**
1. [ ] Add `resolve_symbol(name, g)` to `graph_bfs_core.py`. It accepts `Type`, `Type.Member`, a bare `Member` (returns all matches, ambiguous if >1) and `Register*<T>`. It returns candidates `{kind, owner, name, file, line, end_line, signature, doc, record}`. Exact matches come first; otherwise use the `suggest_node` (l.73) difflib suggestions.
2. [ ] `where_core(name, g)` returns per candidate: `file:line-end_line` plus the suggested Read arguments `offset=line limit=end_line-line+1`. If `end_line` is missing, say `range unavailable (regex mode)`.
3. [ ] `what_core(name, g, forward, reverse, edges, budget_tokens=2000)` builds ordered sections:
   - header: kind, owner, location, range, signature. Never truncated.
   - doc summary, then remarks.
   - registrations where the type appears: holder, method, chain, `as`/`as_resolved`, line.
   - for interfaces: implementers with the D3 dispatch confidence label.
   - callers via `callers_core`: `caller (file:line) [matched_via]`.
   - members list for types: name + range, one per line.
4. [ ] `budget_truncate(sections, budget_tokens)` estimates tokens as `ceil(len(text)/2.5)`. It appends sections in order. When the next section would overflow, it fits as many lines of that list as possible and adds `… +N more (raise --budget)`, then stops. Lower sections are dropped, never the header.
5. [ ] graph-traversal.py: add subcommands `what <symbol> [--budget N] [--json]` and `where <symbol> [--json]` to `build_parser` (l.279) and the `dispatch` dict (l.~339).
6. [ ] graph-mcp-server.py: add tools `what` and `where` as thin wrappers next to `callers` (l.134-214). This is cheap because the core is shared. If the tool-list layout needs more than ~40 lines, skip it and note that in the Status table.
7. [ ] knowledge-graph.md: add a "Look up a symbol (first choice)" section at the top with `python3 .claude/graph/graph-traversal.py what <X>` and `where <X>`, and state the budget default and the ranged-Read pattern. Do not suggest reading graph.json.
8. [ ] Test: build a fixture graph from the `members_docs` fixtures. Assert that `where Members.SomeMethod` returns the EXPECTED.md range, that `what` output is ≤ 2000×2.5 chars with the default budget, that `--budget 50` keeps the header and prints `… +`, and that an ambiguous bare member lists all candidates.

**Test Type:** stdlib test script

**Code Skeleton:**
```python
CHARS_PER_TOKEN = 2.5
def est_tokens(s): return math.ceil(len(s) / CHARS_PER_TOKEN)
def resolve_symbol(name, g) -> list[dict]: ...
def where_core(name, g) -> dict: ...                    # {"ok":True,"hits":[{"file","line","end_line","read":{"offset","limit"}}]}
def what_core(name, g, forward, reverse, edges, budget_tokens=2000) -> dict:  # {"ok","text","truncated","sections"}
def budget_truncate(sections: list[tuple[str, list[str]]], budget_tokens: int) -> tuple[str, bool]: ...
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_what_where.py` prints `ALL PASSED`.
- `python3 .claude/graph/graph-traversal.py --graph <fixture-graph> where Members.SomeMethod` prints `…/Members.cs:<line>-<end_line>` and a `Read offset=<line> limit=<n>` line.
- `python3 .claude/graph/graph-traversal.py --graph <fixture-graph> what Members --budget 50 | wc -c` is ≤ 125 plus the header length, and the output contains `+`.
- Existing subcommands are unchanged: `python3 .claude/graph/test/test_traversal_resolution.py` passes.

---

## Task 9 — Re-measure + gates

**Files:** .claude/graph/test/fixtures/coverage/after-13.json, .claude/graph/test/verify-graphify.sh, docs/PLAN_graph_complete_map.md (After column)

**Steps:**
0. [ ] Register `test_validate_entrypoint_rule.py` (T7) and `test_what_where.py` (T8) in `verify-graphify.sh`; `bash .claude/graph/test/verify-graphify.sh` exits 0.
1. [ ] `bash .claude/graph/graph-coverage-run.sh /Users/berkterek/Desktop/Github/nile_bounce_legion_repo 12bb3911 .claude/graph/test/fixtures/coverage/13-power-readout.code-map.md .claude/graph/test/fixtures/coverage/after-13.json`
2. [ ] Apply the gates with `python3 .claude/graph/graph_coverage.py … --gate-location 100 --gate-behaviour 60`. To get there, add a `--gate-location/--gate-behaviour` pass-through to the runner, or re-run with `KEEP_TMP=1` and point at `$TMP/out/graph.json`.
3. [ ] Size gate: `after.graph_bytes ≤ 1.35 × baseline.graph_bytes`. Timing gate: `KEEP_TMP=1` run, then `time python3 "$TMP/tool/graph-traversal.py" --graph "$TMP/out/graph.json" what CardManager` must be < 1.5 s real.
4. [ ] Read-only proof: repeat Task 2 step 5.
5. [ ] Fill in the After column. If any gate fails, list `failing_symbols` and their missing fact source in the Status table, mark T10 **Skipped — gate failed**, and go straight to T11.

**Test Type:** NoTest (measurement task)

**Code Skeleton:** n/a (runs Task 1/2 artifacts)

**Acceptance Criteria:**
- `python3 -c 'import json;b=json.load(open(".claude/graph/test/fixtures/coverage/baseline-13.json"));a=json.load(open(".claude/graph/test/fixtures/coverage/after-13.json"));print(a["mode"],a["location_pct"],a["behaviour_pct"],round(a["graph_bytes"]/b["graph_bytes"],2))'` prints `tree-sitter 100.0 <≥60> <≤1.35>`. Any other result is recorded as a gate FAIL; the gates are not changed.

---

## Task 10 — Graph nudge hook **[gated on T9 PASS]** **[BLOCKED — needs investigation: output channel, step 1]**

**Files:** .claude/hooks/graph-nudge.sh, .claude/hooks/pre-compact.sh, .claude/hooks/tests/test-graph-nudge.sh

**Steps:**
1. [ ] Investigate: confirm in the installed Claude Code version's hook docs (`claude --version`, then the hooks reference) that PreToolUse `hookSpecificOutput.additionalContext` reaches the model without a `permissionDecision`. Test it with a throwaway hook and a Read. If not, register the same script as **PostToolUse**, which definitely supports `additionalContext`. Record the outcome here before writing step 2 onward.
2. [ ] `graph-nudge.sh`:
   - Starts with `trap 'exit 0' ERR`, and the whole body runs under `timeout 2`-style self-bounding (a background watchdog `( sleep 2; kill $$ ) &`). It always exits 0 and never prints `permissionDecision`.
   - Reads input JSON with `jq`.
   - If graph is disabled (`project-features.json .graph != true`), it exits 0.
3. [ ] Classify the tool call:
   - **Graph query:** `tool_name` matches `mcp__graph_mcp__*`, or a Bash `command` contains `graph-traversal.py`, `knowledge-graph` or `graph.json`. Touch `$UNITY_HOOK_STATE_DIR/graph-query.stamp` and exit.
   - **Source read:** a Read `file_path`, a Grep `path`/`glob`, or a Bash `command` matching `(cat|sed -n|head|tail|grep|rg)\b.*\.cs\b`. The `.cs` path must be under `<unity_project_folder>/Assets/_Framework` or `<unity_project_folder>/Assets/_GameFolders/Scripts` (same roots as `scan_files`).
4. [ ] Nudge only when the stamp is missing or older than 1800 s and the per-session counter `graph-nudge-<session_id>.count` is below 5. Increment the counter and emit:
   `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"graph: try `python3 .claude/graph/graph-traversal.py what <Symbol>` / `where <Symbol>` (ranged Read) before reading whole C# files."}}`
5. [ ] Interaction with `block-graph-direct-read.sh`: the two are disjoint. That hook acts only on graph.json/scenes.json/prefabs.json under `.claude/graph`, and this one only on `.cs` paths. Both can sit on the Read matcher as separate entries. The nudge text never suggests reading graph.json, which that hook would block when `hybrid_graph` is true.
6. [ ] `pre-compact.sh`: add `rm -f "$UNITY_HOOK_STATE_DIR"/graph-nudge-*.count 2>/dev/null || true` (reset on compact).
7. [ ] `chmod +x .claude/hooks/graph-nudge.sh`.
8. [ ] Bash test with `UNITY_HOOK_STATE_DIR=$(mktemp -d)` and piped JSON fixtures:
   - a Read of an indexed `.cs` nudges, and the 6th call does not;
   - a graph-traversal Bash call sets the stamp, after which a Read is silent;
   - a non-indexed path is silent;
   - malformed JSON exits 0 silently;
   - output never contains `deny` or `permissionDecision`.
9. [ ] Hand the user the exact settings.json entry (Claude must not edit settings.json). For PreToolUse, add it as a new object in the `hooks.PreToolUse` array:
   ```json
   {
     "matcher": "Read|Grep|Bash|mcp__graph_mcp__.*",
     "hooks": [
       { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/graph-nudge.sh", "timeout": 2 }
     ]
   }
   ```
   If step 1 chose PostToolUse, the same object goes under `hooks.PostToolUse`.

**Test Type:** NoTest under the Unity matrix. The hook has its own bash test script (step 8), which counts as a stdlib test script.

**Code Skeleton:**
```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh" 2>/dev/null || exit 0
trap 'exit 0' ERR; ( sleep 2; kill -TERM $$ 2>/dev/null ) & WD=$!; trap 'kill $WD 2>/dev/null; exit 0' EXIT
INPUT=$(cat); TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT"); SID=$(jq -r '.session_id // "nosession"' <<<"$INPUT")
STAMP="$UNITY_HOOK_STATE_DIR/graph-query.stamp"; COUNT="$UNITY_HOOK_STATE_DIR/graph-nudge-$SID.count"
is_graph_query && { touch "$STAMP"; exit 0; }
target=$(source_path_of "$TOOL" "$INPUT") || exit 0
is_indexed_cs "$target" || exit 0
fresh_stamp "$STAMP" 1800 && exit 0
n=$(cat "$COUNT" 2>/dev/null || echo 0); [ "$n" -ge 5 ] && exit 0; echo $((n+1)) > "$COUNT"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"…"}}'
```

**Acceptance Criteria:**
- `test -x .claude/hooks/graph-nudge.sh && echo ok` prints `ok`.
- The hook test exits 0 with all cases passing.
- `echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | .claude/hooks/graph-nudge.sh; echo "exit=$?"` ends with `exit=0`.
- `grep -c 'permissionDecision\|deny' .claude/hooks/graph-nudge.sh` prints `0`.
- The step-1 investigation result is recorded in this task. The settings entry has been given to the user in the completion message.

---

## Task 11 — Real /plan-module cost/quality run

**Files:** .claude/scripts/pipeline-breakdown.py, docs/PLAN_graph_complete_map.md (Results table)

**Steps:**
1. [ ] Add a `--tools` mode to `pipeline-breakdown.py`. Per agent type, it reports Bash `tool_use` count per spawn (from subagent `.jsonl`). Per run (main + subagents), it reports graph queries and total tool calls. A graph query is a Bash command containing `graph-traversal.py`/`knowledge-graph`/`graph.json`, or a `mcp__graph_mcp__*` tool_use. The existing positional args (`<project-dir> [since]`) are unchanged.
2. [ ] Calibrate: `python3 -I .claude/scripts/pipeline-breakdown.py ~/.claude/projects/-Users-berkterek-Desktop-Github-nile-bounce-legion-repo --tools` over pre-change runs must reproduce the baselines within ±10%: planner Bash ≈ 39/spawn on module 13, and ≈ 2 graph queries / 763 calls. If it doesn't, write down the counting difference before comparing anything.
3. [ ] Sync the template tooling into nile. This is a user-approved step: it writes to nile, so ask first. Then rebuild nile's graph there with the nile copy (`python3 .claude/graph/graph-builder.py --full`), and have the user add the T10 settings entry in nile if T10 shipped.
4. [ ] The user runs one `/plan-module 13` (or the next unplanned module) in nile.
5. [ ] Measure: `python3 -I .claude/scripts/pipeline-breakdown.py ~/.claude/projects/-Users-berkterek-Desktop-Github-nile-bounce-legion-repo 2026-11-07 --tools` (since = day of the run). Also run the default mode (cost units) with the same since date.
6. [ ] Fill in the Results table. Report the cost delta per `/plan-module` run against the script's recorded baseline (avg 3.7M units, opus planner 49%).

| Metric | Baseline | After |
|---|---|---|
| planner Bash calls / spawn | ~39 | |
| graph queries / tool calls (run) | 2 / 763 | |
| /plan-module avg units | 3.7M | |
| planner share | 49% | |

**Test Type:** NoTest (measurement task)

**Code Skeleton:**
```python
GRAPH_Q = re.compile(r"graph-traversal\.py|knowledge-graph|graph\.json")
def tool_mix(jsonl_path) -> tuple[int, int, int]:   # (bash_calls, graph_queries, total_tool_calls)
    for o in lines: for c in assistant content: if c["type"]=="tool_use": total+=1;
        if c["name"]=="Bash": bash+=1; graph += bool(GRAPH_Q.search(c["input"].get("command","")))
        elif c["name"].startswith("mcp__graph_mcp__"): graph+=1
```

**Acceptance Criteria:**
- Calibration (step 2) prints planner Bash/spawn within 35–43 and graph queries ≤ 3 per ~763 calls on pre-2026-11-07 runs.
- The Results table is filled in from the step-5 command output. The result counts as an improvement only if planner Bash/spawn falls and graph queries/run rises. Otherwise it is recorded as no improvement, with the transcript evidence.

---

### Critical Files for Implementation
- .claude/graph/extractors/csharp_extractor.py
- .claude/graph/graph-builder.py
- .claude/graph/schema.json
- .claude/graph/graph_bfs_core.py
- .claude/graph/graph-traversal.py

Other relevant files:
- .claude/graph/extractors/csharp-extractor.sh
- .claude/graph/graph_validate.py
- .claude/hooks/block-graph-direct-read.sh
- .claude/hooks/_lib.sh
- .claude/hooks/pre-compact.sh
- .claude/scripts/pipeline-breakdown.py
- /Users/berkterek/Desktop/Github/nile_bounce_legion_repo/docs/modules/13-power-readout/code-map.md
