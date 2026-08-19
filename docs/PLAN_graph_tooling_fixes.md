# PLAN — Knowledge-Graph Tooling Defect Fixes (`.claude/graph/`)

## Complexity Assessment

**Score: 0.57 — Medium** (0.65 in v1 → 0.70 in v2 → 0.72 in v3 → 0.57 here)

| Signal | Effect |
|---|---|
| Defect 1 spans two parallel extractor implementations (`csharp_extractor.py` tree-sitter + `csharp-extractor.sh` regex fallback) that must stay behaviourally in sync | +0.20 |
| The `as` key is *not* dead: `.claude/commands/knowledge-graph.md:138-139` reads it, and `csharp-extractor.sh` currently emits it as a **list** in violation of `schema.json:177` (`"as": {"type":"string"}`). Task 2 therefore also has to normalise a value type across a live consumer, not merely add patterns | +0.05 |
| **NEW —** the tree-sitter extractor cannot read a `.As<T>()` chain at all (`_detect_member`, lines 409-417, never looks past the single invocation), so the PRIMARY extractor must gain an invocation-chain walk before any parity gate can pass | +0.02 |
| Defect 0 adds a new post-write warning path to the build orchestrator (new stderr channel usage, `--quiet` honouring, non-fatal semantics) | +0.15 |
| ~~Defect 2 requires a genuinely new extraction capability (method-body `ParentReference.Create<T>()` detection)~~ — **REMOVED in v4 (grill D1)**; moved to its own ADR | ~~+0.20~~ 0 |
| **NEW —** `EXTRACTION_VERSION` (Task 10): one constant, one comparison against the existing graph, one-time promotion of `--incremental` to `--full`. Touches the already-in-scope `graph-builder.py`, no new subsystem | +0.05 |
| **NEW —** a real-corpus read-only validation checkpoint after Tasks 1+2 (grill D5). No new code; a recorded before/after against another repo's source | +0.00 |
| Defect 3 is mechanical prose/schema string replacement with an explicit do-not-touch list | +0.05 |
| No new module folder, no Unity runtime code, no VContainer registration/scene/prefab wiring, no asmdef changes | −0.10 |
| Existing harness (`verify-graphify.sh` + `lib/assert.sh`) already provides `pass`/`fail`/`known_fail`/`assert_jq`; no test infrastructure to build | −0.05 |

**Why the score moved in v4:** removing Task 7 (`ParentReference.Create<T>()`) takes out the single largest and least-certain signal (−0.20) and de-serialises the plan's tail; `EXTRACTION_VERSION` adds a small, well-bounded one (+0.05). Net 0.72 → 0.57. Still Medium, so the two-approaches requirement below still stands.

**Why the score moved in v3, and by how little:** v2 already absorbed the corrected `as`-consumer premise (+0.05 over v1). This revision adds one genuinely new extraction capability to the tree-sitter side — reading the `.As<T>()` / `.AsImplementedInterfaces()` chain — because without it the parity gate the plan itself demands is unsatisfiable. It is only **+0.02** because it reuses helpers that already exist and are already correct for this shape (`_member_name_and_typearg` at line 353 returns `(method, type_arg)` for exactly the `As<T>` node form; `_walk` at line 29; `_type_name` at line 337), and because it walks *upward* through `node.parent` rather than introducing any new traversal concept. Still Medium; still one architecture, no new subsystem. Medium ⇒ two approaches proposed, one chosen and justified in `## Chosen Approach`.

---

> **Version:** v4 — 2026-08-19 (revised after the grill recorded in `docs/decisions/2026-08-18-grill-plan-graph-tooling-fixes.md`, applying its six required edits: **D1** Task 7 (`ParentReference.Create<T>()` scope-parent extraction) deleted and moved to an ADR — it overrode stored *Limitation 18* without naming it, and it serialised the whole plan behind its riskiest task; **D2** Task 6's reconciliation unions only `("classes","interfaces")` — `enums`/`structs` are not graph node kinds at all — and the disk side is filtered by declaration kind, with step 5's `[BLOCKED]` cleared by measurement (9 missing → 0 false positives on piggy-doku); **D3** the Goal is narrowed and `as == "AsImplementedInterfaces"` is labelled a placeholder, not an interface name; **D4** new Task 10 adds `EXTRACTION_VERSION` with builder-side cache invalidation; **D5** real-corpus read-only validation moves into a new Checkpoint C1 right after Tasks 1+2, with a recorded baseline, and Task 9 becomes propagation only; **edit 6** Task 9 step 3's `[BLOCKED]` cleared by measurement. Version number gap at Task 7 is intentional — task IDs are not renumbered, so references in git history and the decision record stay valid.)
> **Version:** v3 — 2026-08-18 (revised after second review: `interface_only` narrowed to the `RegisterInstance`-only, concrete-unresolvable case; `.As<T>()` chain reading added to the tree-sitter extractor so the parity gate is satisfiable; Task 7's search window fixed to slice from the class-declaration line; validator block re-cited as 93-118; `schema.json:12` semver rule and the `lifetime` enum non-conformance both stated correctly. Then, after the third review: Task 8's reg.4 parity compare scoped to resolved-type records with the asymmetric `RegisterInstance(SomeStatic.Opaque())` shape pinned by a new per-extractor reg.6 instead of an unsatisfiable multiset compare; Task 2's `FIELD_TYPES` comprehension inverted to key by field name, which the Form 1c lookup requires.)
> **Status:** Active
> **Scope (v4):** `.claude/graph/extractors/csharp_extractor.py`, `.claude/graph/extractors/csharp-extractor.sh`, `.claude/graph/graph_validate.py`, `.claude/graph/graph-builder.py`, `.claude/graph/schema.json`, `.claude/graph/.gitignore`, `.claude/graph/test/verify-graphify.sh`, `.claude/commands/build-knowledge-graph.md`, `.claude/commands/setup-project.md`, `.claude/graph/extractors/mcp-extractor.md`, `.claude/graph/codex-validator.md`. **Python + bash tooling only — nothing under `Assets/` is touched.** No Unity C#, no scenes, no prefabs, no asmdefs.

---

## Context

The knowledge graph under `.claude/graph/` is declared the PRIMARY source of truth for codebase questions by `.claude/CLAUDE.md`, yet four defects currently make it emit wrong data, hide real data, or instruct agents to run a file that does not exist. The most damaging is Defect 1: in `csharp_extractor.py:409-417` (`_detect_member`) the generic type argument wins unconditionally (`t = type_arg` at line 410, `"as": ""` at line 413), so `builder.RegisterInstance<ITapResolver>(new TapResolver(...))` is recorded as `{"type": "ITapResolver"}` and the concrete `TapResolver` is discarded. That is not a cosmetic loss — `graph_validate.py` assigns the flagged name at **line 104** (`reg.get("class","") or reg.get("type","")`) and tests it against `class_names` at **line 105** (`class_names` built at line 52 from `codebase.classes` only; line 110 is the `detail` f-string, not the membership test), and emits a **false** `INSTALLER_MISSING_CLASS` for the interface (observed on `GridModule` in piggy-doku module 04), while `/knowledge-graph registrations TapResolver` returns nothing because the graph believes the interface is the registered class.

A second, quieter half of Defect 1 surfaced during review: `_detect_member` also never reads a `.As<T>()` chain. For `builder.Register<Bar>(Lifetime.Singleton).As<IBar>()` the tree-sitter extractor emits `{"type":"Bar","as":""}` while the shell fallback emits `{"type":"Bar","as":"IBar"}` (`csharp-extractor.sh:375-377`). Since `as` is the very key this plan makes load-bearing, and since the PRIMARY extractor is the one that loses the information, Task 1 closes that too (see `## Chosen Approach` decision 5).

Defect 0 is a trust problem with no reproducible root cause left: `_Framework/SaveLoadSystems/LocalSaveLoadDal.cs` and `_Framework/Editors/LogDumpOnStop.cs` existed on disk but were absent from the graph until a `--full` rebuild added them — and that `--full` run overwrote `cache/file-hashes.json`, destroying the evidence. There is currently **no reconciliation anywhere** between the files walked on disk and the files represented in the written graph, so a silent omission is undetectable until a human notices a query lying. This plan therefore does not hunt the root cause it cannot reproduce; it installs a detection net at the single write point (`graph-builder.py:1138`) so the next occurrence announces itself.

Defects 3 and 2 are respectively the cheapest and the most expensive. Defect 3 is stale prose: `graph-builder.sh` no longer exists, but **nine live locations** still tell a human or an agent to run it — verified with `grep -rn "graph-builder\.sh" .claude/`, excluding the six do-not-touch occurrences and the append-only `state/subagent-log.jsonl` history entry: `build-knowledge-graph.md:23,66,82` (×3), `setup-project.md:162` (×1), `mcp-extractor.md:249` (×1), `codex-validator.md:49,69` (×2), `schema.json:5,21` (×2) = 9. That set is exactly Task 3's file list, so Task 3 step 1's census check is satisfiable. Among them is a Step 0 preflight gate at `build-knowledge-graph.md:23` that would make an agent *stop* on a healthy repo. Defect 2 is a real capability gap: `GameScope` sets its parent in code via `ParentReference.Create<AppScope>()`, and neither extractor looks inside method bodies for that, so `/knowledge-graph scope-tree` misreports `GameScope` as a root while a PlayMode test proved `GameScope.Parent == AppScope` at runtime. **Defect 2 is NOT addressed by this plan** — grill decision D1 removed it, because a fix here would silently override the recorded project decision *Limitation 18* ("do NOT fix this with regex/grep on `.cs` files; the fix requires an MCP extractor update"), whose factual half is itself partly outdated and needs deciding deliberately rather than inside a defect-fix plan. The accepted cost is that `scope-tree` keeps showing `GameScope` as a root — a graph limitation, not an architecture defect. Follow-up owed: an ADR per D1. See `## Out of Scope`.

---

## Goals

- [ ] `RegisterInstance<IFoo>(new Foo(...))` and `RegisterInstance<IFoo>(_fooField)` record the **concrete** class, with the interface preserved in the `as` field, in *both* extractors.
- [ ] The false `INSTALLER_MISSING_CLASS` on interfaces disappears without weakening detection of genuinely missing classes — in particular, a plain `Register<UnknownClass>(Lifetime.Singleton)` must still be flagged.
- [ ] Tree-sitter and regex-fallback extractors produce the same registration shape *and the same value types* for the same input, so graph content does not depend on whether `tree_sitter` happens to be installed. This includes `.As<T>()`-chained registrations.
- [ ] `as` is always a **string**, matching `schema.json:177`, so the live `/knowledge-graph registrations` query (`.as == $name`) can actually match it.
- [ ] **Interface-name resolution works for the explicit forms only — this is the declared limit (grill D3).** `registrations <IFoo>` resolves through `as` for explicit `.As<IFoo>()` chains and for generic `RegisterInstance<IFoo>(…)`. It does **not** resolve for `.AsImplementedInterfaces()`, which is the dominant idiom in this project (16 uses vs 10 explicit `.As<T>()` in piggy-doku) and is mandated by `.claude/rules/bootstrap-pattern.md`. For those registrations `as` holds the literal string `"AsImplementedInterfaces"`, which is a **placeholder marking "the interface set was not enumerated" — it is not an interface name**, and no query will ever match a real interface through it. Resolving it properly needs the per-class `implements` data folded into a new *array* key (`as` is a single string per `schema.json:177`), i.e. a schema change plus a query change — a capability, not a defect fix, and therefore out of scope for the same reason D1 removed Task 7. Tracked as follow-up work.
- [ ] Every build compares disk contents against graph contents and warns (stderr, non-fatal, `--quiet`-aware) with an explicit "run `--full`" recommendation on mismatch.
- [ ] A change to extraction *semantics* invalidates its own stale output: `EXTRACTION_VERSION` mismatch promotes an `--incremental` run to `--full` once, automatically, in every repo (Task 10).
- [ ] Zero live references to `graph-builder.sh` remain; the six documented do-not-touch occurrences are untouched.
- [ ] The changed extractors are validated **read-only against a real codebase** (piggy-doku source) immediately after Tasks 1+2, before the synthetic harness work — Checkpoint C1.
- [ ] Every task is verified by a harness assertion or a stated manual command with expected output — no task rests on "it looks right".
- [ ] All changed files are copied to `/Users/berkterek/Desktop/Github/piggy-doku-repo` and the harness passes there too.

**Explicit non-goal (grill D1):** `ParentReference.Create<XScope>()` scope-parent extraction. Deferred to an ADR; see `## Out of Scope`.

**Recorded honest scope of Defect 1's payoff (grill D3):** the forms it *corrects* — `RegisterInstance<I>(new C())` and `RegisterInstance<I>(_field)` — total about **five call sites** across five measured repos (1+1 piggy-doku, 1 each voxel-blast / worm-escape / nile-hole, 0 template). The larger gain is the `.As<T>()` chain reader, which gives `as` a real value at **12 call sites** where it is currently always `""` — new information rather than a correction. The justification is "wrong data in the declared primary source of truth, plus 12 empty fields", not a large call-site count.

---

## Approaches Considered

**Approach A — Fix at the consumer (`graph_validate.py` only).**
Leave both extractors alone; teach the `INSTALLER_MISSING_CLASS` check (name assigned at line 104, membership tested at line 105) to accept a name that resolves to a known interface (`callee_node_names` at line 57 already unions `class_names` with interface names). Cheapest possible change, one file, no extractor parity risk.
*Rejected:* it silences the symptom and keeps the wrong data. `/knowledge-graph registrations TapResolver` still returns nothing, because the graph still believes the interface is the registered class. And an interface-accepting guard is exactly the "too loose" guard the requirements warn about — a genuinely missing `IFoo`-named class would now pass silently. Fixing a data-extraction bug in the validator is fixing the smoke alarm.

**Approach B — Fix at the source in both extractors, add a narrow validator guard, and put the interface in the existing `as` key.**
Change `_detect_member` so the concrete type wins when one is recoverable (`new Foo(...)` → `_first_arg_new_type`; bare identifier → the `symbols` field/param map), move the generic type argument into the already-present `as` key, and teach the same branch to read a trailing `.As<T>()` chain so the PRIMARY extractor stops losing that information. Mirror the same precedence in `csharp-extractor.sh` Form 1/Form 2, and normalise `as` to a string there. Then add one *narrow* validator guard: accept a recorded name only when the registration itself declares it could not resolve a concrete — never merely because the name happens to match an interface.
*Chosen.* See below.

## Chosen Approach

**Approach B.** Five decisions are made explicitly rather than left implicit:

1. **Where the interface goes: the existing `as` key — which has exactly one live reader, and that is a feature, not a hazard.** *(Corrected from v1, which wrongly claimed zero readers.)* `as` is written at `csharp_extractor.py:413` (always `""`) and at `csharp-extractor.sh:369,377,379` (interface names / `"AsImplementedInterfaces"`), and it is **read** at `.claude/commands/knowledge-graph.md:138-139`, inside the query named `registrations <InterfaceOrClassName>`:
   ```
   select(.registrations[]? | .type == $name or .as == $name)
   ```
   Semantically that is the right home: in VContainer, `Register<Foo>().As<IFoo>()` means "concrete `Foo`, exposed as `IFoo`", and `RegisterInstance<IFoo>(new Foo())` means the same thing written differently. Putting the interface in `as` normalises the two syntaxes into one record shape instead of inventing a fourth key.
   **Declared consequence — a behaviour change to a LIVE consumer.** Once Task 1 lands, `/knowledge-graph registrations ITapResolver` starts *resolving through `as`* and returns the `GridModule` registration, where today it matches on `.type` (which currently, wrongly, holds `ITapResolver`). After the fix, `registrations TapResolver` returns it via `.type` and `registrations ITapResolver` returns it via `.as`. Both names resolve to the same record; neither returns nothing. This is intentional, is an improvement, and is asserted in Task 9's verification. No consumer is *required* to change.

2. **`as` is always a string.** `schema.json:177` declares `"as": { "type": "string" }`, but `csharp-extractor.sh:369` initialises `reg["as"] = []` and line 377 assigns a **list** when more than one `.As<T>()` is chained — a pre-existing schema violation, and a value that can never satisfy `.as == $name` in the query above. Task 2 normalises it: empty → `""`, one → the string, more than one → the **first** `.As<T>()` type, with the remainder dropped. The rest are droppable because (a) the schema never permitted them, (b) every consumer that reads `as` compares it as a scalar, so a list has always been invisible data, and (c) the tree-sitter extractor emits at most one. Task 1's new chain reader (decision 5) likewise takes the first `.As<T>()` only, so the two sides agree by construction.

3. **`type` keeps meaning "the concrete thing that was registered".** That is what `graph_validate.py:104-105` and `/knowledge-graph registrations` already assume. Changing the *meaning* of `type` (e.g. to "the requested service") would be a silent breaking change to every existing consumer; changing which *value* lands there fixes them all at once.

4. **The validator guard is narrow, the `interface_only` marker is narrower still, and I argue against the loose alternative.** Adding "or the name is a known interface" to the membership test at `graph_validate.py:105` would mask genuinely missing classes: any project where an interface `IFoo` exists but its implementation was deleted or excluded from the walk would now validate clean — and Defect 0 is *precisely* a bug where real classes go missing from the graph. The two defects would cover for each other. Instead the guard keys on provenance: skip the `INSTALLER_MISSING_CLASS` check only when the registration record itself declares it could not resolve a concrete (`unresolved is True`, already handled at lines 101-103, plus the new `interface_only` marker).
   **`interface_only` is therefore set in exactly one situation:** `method == "RegisterInstance"` **and** the argument-side concrete could not be resolved **and** a generic type argument was nonetheless available. It is *never* set for `Register<Foo>()`, `RegisterEntryPoint<Foo>()`, `RegisterComponent<Foo>()`, or `RegisterComponentInHierarchy<Foo>()`, because for those the generic slot *is* the concrete and the record is making a full-strength claim. *(v2 set the marker on every non-`RegisterInstance` registration, which would have disabled `INSTALLER_MISSING_CLASS` for essentially every normal call site — the exact opposite of this decision. Task 5's acceptance criteria now pin that regression with an explicit assertion.)* A record that names a class and claims resolution must still resolve. This keeps the check honest.

5. **The tree-sitter extractor learns to read `.As<T>()` — it is the PRIMARY extractor and this is the same `as` key everything above turns on.** *(New in v3, in place of v2's unsatisfiable parity gate.)* `_detect_member` (lines 409-417) inspects one `invocation_expression` at a time and never looks at what the result is chained into, so `Register<Bar>(Lifetime.Singleton).As<IBar>()` loses `IBar` on the PRIMARY path while the fallback keeps it. v2's Task 2 verification demanded an empty `{type, as}` diff *including* that record, and Task 8 AC 2 made it a harness gate — a gate no implementation could pass. Rather than exempt chained records (the fallback option, which would leave the plan's own headline key divergent between extractors for no reason), Task 1 gains a small upward chain walk: from the `Register…` invocation, follow `node.parent` while it is a `member_access_expression` whose parent is an `invocation_expression`, and read `(method, type_arg)` off each link with the existing `_member_name_and_typearg`. `As` → take `type_arg`, first one wins; `AsImplementedInterfaces` → the literal string, matching `csharp-extractor.sh:379`. An explicit chain wins over a generic interface argument, mirroring the fallback's precedence (Task 2 step 7). Cost: one helper, no new traversal concept, +0.02 complexity.
   **`as == "AsImplementedInterfaces"` is a PLACEHOLDER, not an interface name (v4, grill D3).** Both extractors write that literal for `.AsImplementedInterfaces()` registrations. It marks "the exposed interface set was not enumerated"; it is not a type name and `/knowledge-graph registrations <IFoo>` can never match through it. This matters more than it sounds: `AsImplementedInterfaces` is the **dominant** idiom here — 16 uses vs 10 explicit `.As<T>()` in piggy-doku, and `.claude/rules/bootstrap-pattern.md` mandates it — so the registration query stays blind to the majority of registrations by interface name even after this plan lands. Resolving it properly is possible (the graph already carries per-class `implements`: 11 of 51 piggy-doku classes, e.g. `SceneService → ['ISceneService','IAsyncStartable','IDisposable']`) but a class implementing three interfaces does not fit in one string, so it needs a new **array** key, a `schema.json` change, and a change to the query in `knowledge-graph.md`. That is a capability, not a defect fix — the same ground on which D1 removed Task 7 — so it is deliberately not taken here. Stated in the Goals as the declared limit.

   **Interaction with the `As` invocation itself:** `_walk` also hands `_detect_member` the outer `.As<IBar>()` invocation. `"As"` is not in `REG` (line 391) and not in `PUBSUB`, so it is already ignored and no duplicate record appears — verified against the current control flow, and pinned by Task 1's "record count per installer is unchanged" criterion.

**Known schema non-conformance, knowingly out of scope:** `schema.json:178` constrains `lifetime` to the enum `["Singleton","Scoped","Transient"]`, but `csharp_extractor.py:413` emits `"lifetime": ""` today and Task 1's rewrite keeps doing so. **Decision: note it, do not fix it here.** Reason: making the key conditional (omit when empty) changes the emitted key set on the tree-sitter side only, which breaks the record-shape parity with `csharp-extractor.sh` that Tasks 2 and 8 exist to enforce; fixing it properly means teaching the tree-sitter path to read `Lifetime.X` from the argument list in both extractors, which is a separate capability with its own probe and its own acceptance criteria. This plan claims conformance for `as` (which it changes) and explicitly does **not** claim it for `lifetime` (which it merely carries forward unchanged). Task 1 AC states this so no reader infers otherwise.

---

## Status

| Phase | Task | Status | parallel_group |
|---|---|---|---|
| 1 | Task 1 — Concrete-type precedence + `.As<T>()` chain in `csharp_extractor.py` (`_detect_member`) | ✅ Done | A |
| 1 | Task 2 — Parity fix in `csharp-extractor.sh` (Form 1 + Form 2 + `as` normalisation) | ✅ Done | A |
| 1 | Task 3 — Stale `graph-builder.sh` reference sweep (docs + schema) | ✅ Done | A |
| 1 | Task 4 — Nested `.claude/graph/.gitignore` self-sufficiency | ✅ Done | A |
| 1.5 | **Checkpoint C1 — Real-corpus read-only validation of Tasks 1+2 against piggy-doku source** | ✅ **PASSED 2026-08-19** | — (gate) |
| 2 | Task 5 — Narrow `graph_validate.py` guard on `interface_only` | ✅ Done | B |
| 2 | Task 6 — Disk-vs-graph reconciliation warning in `graph-builder.py` | ✅ Done | B |
| 3 | ~~Task 7 — `ParentReference.Create<T>()` scope-parent extraction~~ | ❌ **REMOVED (v4, grill D1)** — moved to an ADR | — |
| 3 | Task 10 — `EXTRACTION_VERSION` constant + builder-side cache invalidation | ✅ Done | C |
| 4 | Task 8 — Harness assertions for Tasks 1/2/5/6/10 | ✅ Done | D |
| 5 | Task 9 — Propagate changed files to `piggy-doku-repo` and re-verify | ⏸ **DEFERRED 2026-08-19** — user is updating that repo separately | E |

**Task numbering:** Task 7's ID is retired, not reused, and the tasks after it keep their original numbers. Renumbering would invalidate every reference to "Task 8" / "Task 9" in this file's own history, in `docs/decisions/2026-08-18-grill-plan-graph-tooling-fixes.md`, and in git log. The new task takes the next free ID, 10.

**parallel_group reasoning** (v4: group C's occupant changed — Task 7 removed, Task 10 takes its slot)
- **A** — four distinct file sets, no shared file, no shared key. Tasks 1 and 2 both introduce the same *concept* but touch different files and neither reads the other's output.
- **Checkpoint C1** — a hard gate, not a group. It runs after Tasks 1 and 2 are written and before anything in B starts. It is read-only and spawns no edit, so it parallelises with nothing.
- **B** — sequential after A (and after C1) because Task 5's guard reads the `interface_only` key that Task 1 introduces, and Task 6's reconciliation must not be authored against a moving extractor. Tasks 5 and 6 touch different files (`graph_validate.py` vs `graph-builder.py`) and are mutually independent within B.
- **C** — Task 10 writes `graph-builder.py`, the same file as Task 6, so it **must** be sequential after B. Two tasks writing the same file are never parallel.
- **D** — Task 8 writes `verify-graphify.sh` and asserts on behaviour from Tasks 1, 2, 5, 6, 10; strictly last among edits.
- **E** — Task 9 copies files, so it depends on *every* preceding edit task.

---

## File Map

| File | Change Type | Notes |
|---|---|---|
| `.claude/graph/extractors/csharp_extractor.py` | Modify | Task 1 (`_detect_member`, lines 389-417, plus a new chain helper). *(Task 7's scope emission edit removed in v4.)* |
| `.claude/graph/extractors/csharp-extractor.sh` | Modify | Task 2 (Form 1 at 360-380, Form 2 at 382-392, dedup at 394-401). *(Task 7's `extract_scope` edit removed in v4.)* |
| `.claude/graph/graph_validate.py` | Modify | Task 5 — narrow guard at the `INSTALLER_MISSING_CLASS` block, lines **93-118** (93-94 are the section comment and counter init; name assigned at 104, membership tested at 105) |
| `.claude/graph/graph-builder.py` | Modify | Task 6 — new reconciliation after `atomic_write_json` (line 1138); **Task 10 — `EXTRACTION_VERSION` constant, comparison, one-time `--incremental`→`--full` promotion; metadata write near lines 813-815**. *(Task 7's `scope_merge` edit removed in v4.)* |
| `.claude/graph/schema.json` | Modify | Task 3 — `description` at line 5, `generator` description at line 21; **Task 10 — document `extraction_version` in `metadata`, minor `schema_version` bump per the rule at `schema.json:12`**. *(Task 7's `scopeEntry` edit removed in v4.)* |
| `.claude/graph/.gitignore` | Modify | Task 4 — add `cache/mcp-extract.json` |
| `.claude/commands/build-knowledge-graph.md` | Modify | Task 3 — lines 23, 66, 82 |
| `.claude/commands/setup-project.md` | Modify | Task 3 — line 162 |
| `.claude/graph/extractors/mcp-extractor.md` | Modify | Task 3 — line 249 |
| `.claude/graph/codex-validator.md` | Modify | Task 3 — lines 49, 69 |
| `.claude/graph/test/verify-graphify.sh` | Modify | Task 8 — new assertions ONLY; lines 261, 430, 547 must not change |

**Explicitly NOT modified** (changing these breaks tests or rewrites accurate history) — all six must stay excluded from Task 3's sweep: `.claude/graph/test/verify-graphify.sh:261`, `:430`, `:547`; `.claude/graph/test/README.md:58`; `.claude/graph/graph-builder.py:8`; `.claude/graph/graph.json.bak:4`. Also untouched: `.claude/state/subagent-log.jsonl` (append-only run history), anything under `Assets/`, and `docs/archive/**` plus `docs/PLAN_graph_*.md` (historical plans that correctly describe the era when `graph-builder.sh` existed).

---

## Task 1 — Concrete-Type Precedence and `.As<T>()` Chain in `csharp_extractor.py`

**Files:**
- `.claude/graph/extractors/csharp_extractor.py` (modify `_detect_member`, currently lines 389-417; add two module-level helpers near `_first_arg_identifier` at line 384)

**Steps:**
1. [ ] Re-read `.claude/graph/extractors/csharp_extractor.py` lines 330-425 to confirm the current shape of `_type_name` (line 337), `_member_name_and_typearg` (line 353 — returns `(method, type_arg)` and already handles the `generic_name` + `type_argument_list` form that `As<IBar>` parses to), `_first_arg_new_type` (line 376), `_first_arg_identifier` (line 384), `_detect_member` (line 389), and the `REG` set (line 391). Confirm the `symbols` map is the field/param type map populated at lines 217 and 508.
2. [ ] Confirm which callers pass `symbols` into `_detect_member` and that it is populated for installer/scope classes (it is built by `_class_field_symbols`, **line 420**) — the fix depends on it being non-empty for the `RegisterInstance<IFoo>(_field)` form.
3. [ ] Introduce a helper `_resolve_concrete(inv, src, symbols)` that returns the concrete type name argument-side, trying `_first_arg_new_type(inv, src)` first, then `symbols.get(_first_arg_identifier(inv, src), "")`. Return `""` when neither yields a name.
4. [ ] Introduce a helper `_as_chain(inv, src)` that walks the invocation chain **upward** and returns the exposed service string, or `""`. From `inv`, repeatedly: if `node.parent` is a `member_access_expression` and *its* parent is an `invocation_expression`, read `_member_name_and_typearg(node.parent, src)`; on `("As", T)` return `T` (first `.As<T>()` wins — `## Chosen Approach` decision 2, so both extractors keep one string); on `("AsImplementedInterfaces", _)` return the literal `"AsImplementedInterfaces"`, matching `csharp-extractor.sh:379`; otherwise continue from the outer invocation. Guard the loop with a hop limit (say 8) so a pathological chain cannot spin. **This is the capability the PRIMARY extractor lacks today** (`_detect_member` inspects one invocation and never looks at what it is chained into), and without it no `{type, as}` parity gate between the two extractors can pass — see `## Chosen Approach` decision 5.
5. [ ] Rewrite the `elif method in REG:` branch (lines 409-417) so precedence is: **concrete-from-argument wins over `type_arg`**, and `type_arg` is retained as the exposed service. Apply the argument-side resolution for `RegisterInstance` only — this is what fixes the second form (`RegisterInstance<IFoo>(_someField)`), where today `t = type_arg` (line 410) is truthy so the argument-side path is never reached.
6. [ ] Set `as` from `_as_chain` when the chain yielded something (an explicit `.As<T>()` is the author's stated intent and outranks an inferred interface, mirroring Task 2 step 7); otherwise from `type_arg` when a concrete was resolved from the argument and `type_arg` differs from it; otherwise `""`. Always a **string**, never a list — `## Chosen Approach` decision 2. When `type_arg == concrete` and there is no chain, leave `as` as `""` (its current value at line 413): there is no service/impl split to record.
7. [ ] When `method == "RegisterInstance"`, **no** concrete could be resolved argument-side, and `type_arg` is present, keep `type = type_arg` (best available information) and add `reg["interface_only"] = True` plus `reg["confidence"] = "INFERRED"`. This is the marker Task 5 keys on, and this is the **only** place it is ever set — see `## Chosen Approach` decision 4. Do **not** set it on the `Register` / `RegisterComponent` / `RegisterEntryPoint` / `RegisterComponentInHierarchy` paths: for those the generic slot *is* the concrete, the record makes a full-strength claim, and marking it would switch off `INSTALLER_MISSING_CLASS` for nearly every registration in every project. Do **not** set `unresolved` here either: `unresolved`/`AMBIGUOUS` already means "nothing at all was recoverable" (lines 414-416) and must keep that meaning.
8. [ ] Leave the existing `unresolved` / `AMBIGUOUS` path (lines 414-416) intact for the case where neither `type_arg` nor an argument-side concrete exists.
9. [ ] Do not change the behaviour of the non-`RegisterInstance` methods except to route them through the same record construction and the same `_as_chain` call — for those, `Register<Foo>()` already names the concrete in the generic slot and argument-side resolution must not override it. Gate the argument-side attempt and the `interface_only` marker on `method == "RegisterInstance"` only.
10. [ ] Confirm the outer `.As<T>()` invocation that `_walk` also visits produces no extra record: `"As"` and `"AsImplementedInterfaces"` are in neither `REG` (line 391) nor `PUBSUB` (line 390), so the loop already skips them. Pin it with the record-count criterion below.
11. [ ] Verify the `never skip` invariant at the `registrations.append(reg)` line (417) still holds: every `REG` invocation appends exactly one record.
12. [ ] Keep `"lifetime": ""` exactly as line 413 emits it today. This does **not** satisfy the `schema.json:178` enum; that non-conformance is pre-existing and knowingly out of scope, with the reason stated at the end of `## Chosen Approach`.

**Verification:** **(a) harness assertion** — added in Task 8, plus this **(b) manual command** for immediate feedback during implementation. Create a scratch C# file (in the harness `.work/` sandbox, not in `Assets/`) containing:
```csharp
public class ProbeModule { void Configure(IContainerBuilder builder) {
    builder.RegisterInstance<ITapResolver>(new TapResolver(1));
    builder.RegisterInstance<IFoo>(_fooField);
    builder.Register<Bar>(Lifetime.Singleton).As<IBar>();
} private Foo _fooField; }
```
then run:
```bash
python3 .claude/graph/extractors/csharp_extractor.py --changed-files <probe.cs> | jq '.vcontainer.installers[0].registrations'
```
Expected: exactly three records — `{"type":"TapResolver","as":"ITapResolver",...}`, `{"type":"Foo","as":"IFoo",...}`, `{"type":"Bar","as":"IBar",...}`. Note the third: `as` is `"IBar"`, **not** `""` — that is step 4's new chain reader, and it is what makes Task 2's parity diff empty. Every `as` is a JSON **string**. No record has `type` equal to an `I`-prefixed name. Exactly three records, not four (the `.As<IBar>()` invocation must not add one). If `tree_sitter` is unavailable the script exits 2 — install it or run the Task 2 probe instead; note which happened.

**Code Skeleton:**
```python
def _resolve_concrete(inv, src, symbols):
    """Argument-side concrete type for RegisterInstance: `new Foo(..)` then field/param symbol."""
    return _first_arg_new_type(inv, src) or symbols.get(_first_arg_identifier(inv, src), "") or ""


def _as_chain(inv, src, hops=8):
    """Exposed service from a trailing chain: `.As<IBar>()` / `.AsImplementedInterfaces()`.
    Walks UP through parents because `_detect_member` only ever sees one invocation at a
    time; the chained call is a member_access_expression on this invocation's own result.
    First `.As<T>()` wins -> always a single STRING (Chosen Approach decision 2)."""
    node = inv
    for _ in range(hops):
        ma = node.parent
        if ma is None or ma.type != "member_access_expression":
            return ""
        outer = ma.parent
        if outer is None or outer.type != "invocation_expression":
            return ""
        m, ta = _member_name_and_typearg(ma, src)
        if m == "As" and ta:
            return ta
        if m == "AsImplementedInterfaces":
            return "AsImplementedInterfaces"      # matches csharp-extractor.sh:379
        node = outer
    return ""

# inside _detect_member, replacing lines 409-417:
elif method in REG:
    chained = _as_chain(inv, src)
    if method == "RegisterInstance":
        concrete = _resolve_concrete(inv, src, symbols)
        if concrete:
            reg = {"type": concrete,
                   "as": chained or (type_arg if type_arg and type_arg != concrete else ""),
                   "lifetime": ""}                    # lifetime enum: see Chosen Approach
        elif type_arg:
            # ONLY place interface_only is ever set: RegisterInstance<IFoo>(opaqueExpr).
            reg = {"type": type_arg, "as": chained, "lifetime": "",
                   "interface_only": True, "confidence": "INFERRED"}
        else:
            reg = {"type": "", "as": chained, "lifetime": "",
                   "unresolved": True, "confidence": "AMBIGUOUS"}
    elif type_arg:
        # Register/RegisterComponent/RegisterEntryPoint/RegisterComponentInHierarchy:
        # the generic slot IS the concrete. Full-strength claim -> NO interface_only,
        # so INSTALLER_MISSING_CLASS keeps biting on Register<UnknownClass>(...).
        reg = {"type": type_arg, "as": chained, "lifetime": ""}
    else:
        reg = {"type": "", "as": chained, "lifetime": "",
               "unresolved": True, "confidence": "AMBIGUOUS"}
    registrations.append(reg)   # never skip
```

**Acceptance Criteria:**
- `RegisterInstance<ITapResolver>(new TapResolver(...))` → `type == "TapResolver"`, `as == "ITapResolver"`.
- `RegisterInstance<IFoo>(_fooField)` where `_fooField` is declared `Foo` → `type == "Foo"`, `as == "IFoo"`.
- `Register<Bar>(Lifetime.Singleton)` → `type == "Bar"`, `as == ""`, unchanged from today.
- `Register<Bar>(Lifetime.Singleton).As<IBar>()` → `type == "Bar"`, **`as == "IBar"`** (new capability; today the tree-sitter path emits `""` here, which is why the Task 2 parity diff cannot be empty without this).
- `Register<Baz>(...).As<IBaz>().As<IQux>()` → `as == "IBaz"` (a single string; first chain link wins).
- `Register<Foo>(...).AsImplementedInterfaces()` → `as == "AsImplementedInterfaces"`, matching the fallback's literal.
- `RegisterInstance(unresolvableExpr)` with no generic → still `unresolved: true`, `confidence: "AMBIGUOUS"`.
- `interface_only` appears **only** on `RegisterInstance` records whose argument-side concrete was unresolvable. No `Register<T>` / `RegisterEntryPoint<T>` / `RegisterComponent<T>` / `RegisterComponentInHierarchy<T>` record ever carries it.
- Every emitted `as` is a string (schema-conformant per `schema.json:177`).
- `lifetime` is still `""`, still not enum-conformant per `schema.json:178`; declared out of scope, not an oversight.
- Record count per installer is unchanged for every input: one record per `REG` invocation, and a `.As<T>()` link adds none.
- No record produced by this branch has an empty `type` unless `unresolved` is also set.

---

## Task 2 — Parity Fix in `csharp-extractor.sh` (Regex Fallback)

**Files:**
- `.claude/graph/extractors/csharp-extractor.sh` (modify the registration Python heredoc: Form 1 at lines 360-380, Form 2 at lines 382-392, dedup at lines 394-401)

**Steps:**
1. [ ] Re-read `.claude/graph/extractors/csharp-extractor.sh` lines 350-405 in full. Confirm: Form 1's regex captures the generic arg as `m.group(2)` and writes it to `reg["type"]`; `reg["as"]` is initialised to `[]` at **line 369** and assigned a **list-or-string** at **line 377** (`as_matches if len(as_matches) > 1 else as_matches[0]`), with `"AsImplementedInterfaces"` at **line 379**; Form 2 (382-392) *guesses* the type by stripping `_` and upper-casing the first character (`type_name = arg.lstrip('_')`, with `"inferred": True`); dedup runs at 394-401.
2. [ ] Confirm this extractor is selected only when tree-sitter is unavailable: `.claude/graph/graph-builder.py:243-261` tries `csharp_extractor.py` first and falls back on exit code 2, warning `FALLBACK_EXTRACTOR` at lines 1080-1087. Note in the implementation comment that this path is already flagged LOW CONFIDENCE, which bounds how much *fidelity* is required — but the **record shape and value types** must match Task 1 exactly, because both feed the same `graph.json`, the same `schema.json`, and the same consumers.
3. [ ] **Normalise `as` to a string throughout this heredoc** (`## Chosen Approach` decision 2). Change line 369's initialiser from `[]` to `""`, and line 377 from the list-or-string assignment to `as_matches[0]`. Add a comment recording the rule and why the remaining `.As<T>()` types are droppable: `schema.json:177` declares `"as": {"type":"string"}` so a list was always non-conformant; `.claude/commands/knowledge-graph.md:139` compares `as` as a scalar (`.as == $name`), so list values have never matched anything; and Task 1's `_as_chain` takes the first link only, so first-wins is the agreed rule on both sides. Dropping them loses no information any consumer could ever see.
4. [ ] Add a generic-`RegisterInstance`-with-`new` pattern: `builder.RegisterInstance<IFoo>(new Foo(...))`. Today Form 1 matches this and records `IFoo`; the new pattern must extract `Foo` from the `new` expression and put `IFoo` in `as`. Order matters — this pattern must be tried **before** Form 1 consumes the same text, or Form 1's match must be skipped when the argument list starts with `new`.
5. [ ] Add a generic-`RegisterInstance`-with-identifier pattern: `builder.RegisterInstance<IFoo>(_fooField)`. Resolve `_fooField` against a field-type map scraped from the same file with a declaration regex (e.g. `(?:private|protected|public|internal|readonly|\s)+([A-Za-z0-9_<>]+)\s+(_?[a-zA-Z][A-Za-z0-9_]*)\s*[;=]`). On a hit, `type` = declared type, `as` = `IFoo`. On a miss, fall back to `type = IFoo` with `interface_only: True` — **do not** reuse Form 2's name-guessing heuristic here, because the generic argument is strictly better information than a de-underscored identifier. This is the fallback's counterpart to Task 1 step 7, and it is likewise the **only** place this extractor sets `interface_only`.
6. [ ] Leave Form 2 (non-generic `RegisterInstance(someVar)`, lines 382-392) behaviour intact apart from also consulting the new field-type map before falling back to the name guess; keep `"inferred": True` on the guessed path so its low confidence stays visible. Do not add `interface_only` here — there is no interface in play.
7. [ ] Preserve the **precedence** of an explicit `.As<T>()` chain over a generic interface argument, which is now the rule on both sides (Task 1 step 6 implements the same order). **[BLOCKED — needs investigation]** if a single registration has both a generic interface arg *and* an explicit `.As<T>()` chain (`RegisterInstance<IFoo>(new Foo()).As<IBar>()`), which one belongs in `as` is a genuine product question and no such call site exists in either repo to arbitrate it. Keep the explicit chain winning (current behaviour, and now Task 1's behaviour too) and add a `# TODO(parity)` comment naming this case. Note this is only a question of *which string*, not of string-vs-list — step 3 settles the type unconditionally. **Implementation note (v4):** the chain-wins rule is now actually implemented on the fallback for Form 1b/1c too, via a single shared `_chain_as(pos)` helper that Form 1, 1b and 1c all call. Final review caught that the rule was *documented* in a comment here but never executed on the 1b/1c paths, so `RegisterInstance<IFoo>(new Foo()).As<IBar>()` gave `as="IFoo"` on the fallback and `as="IBar"` on tree-sitter — a live parity break at the exact shape this step is about. The `[BLOCKED]` above still stands: it is about whether chain-wins is the *right* rule, not about whether the two extractors agree. They now do. **This `[BLOCKED]` is deliberately kept in v4** (a reviewer flagged it; the grill's six required edits do not include it, and the grill's own "Open Questions" section is about grill branches, not about this): the *behaviour* is settled — explicit chain wins on both sides — and what stays open is only which string a shape that exists at **zero call sites in either repo** should carry. There is nothing to arbitrate it with, so the marker records honest uncertainty rather than gating anything. It does not block implementation of this step.
8. [ ] Re-check the dedup block ("Deduplicate by type (first occurrence wins)", lines 394-401). With `type` now holding concretes, two different interfaces backed by the same concrete would collapse into one record. Dedup on the `(type, as)` pair rather than `type` alone, so `RegisterInstance<IReader>(_store)` and `RegisterInstance<IWriter>(_store)` both survive. Because `as` is now always a string (step 3), the key needs no `json.dumps` wrapper. Note that Task 1's tree-sitter path has no dedup at all, so this change also reduces (does not create) divergence.
9. [ ] **Bound the `.As<T>()` tail scan at the statement terminator `;`, not at a fixed character
   count.** Found during v4 implementation (while Task 8 built its probe) and confirmed by direct
   reproduction: Form 1 scanned a fixed 400-char window forward from its own match, so a chainless
   `Register<Bar>(...)` immediately followed by a chained `Register<Baz>(...).As<IBaz>()` read
   `IBaz` out of the **next statement** and emitted `{"type":"Bar","as":"IBaz"}` — wrong data in the
   key this plan makes load-bearing, and a parity break (tree-sitter correctly emits `""`). Cut the
   tail at the first `;` before running the `.As<T>()` / `.AsImplementedInterfaces()` searches, and
   drop the now-redundant `[:300]` / `[:200]` sub-slices. Task 8's probe deliberately orders the
   chainless registration BEFORE the chained one so this stays pinned; reverting the fix turns
   reg.4 red with exactly the signature above (demonstrated, not assumed).
10. [ ] Keep the emitted key set identical to Task 1's: `type`, `as`, `lifetime`, plus optional `scope`, `inferred`, `interface_only`, `unresolved`, `confidence`.

**Verification:** **(b) manual command.** Run the fallback extractor directly against the same probe file used in Task 1 (which includes an `.As<IBar>()` chain):
```bash
bash .claude/graph/extractors/csharp-extractor.sh --changed-files <probe.cs> | jq '.vcontainer.installers[0].registrations'
```
Expected: `type` values `TapResolver`, `Foo`, `Bar` (order may differ), every `as` a JSON string, and **no** `type` beginning with a capital-`I`-plus-capital pattern. Then diff the two extractors' `{type, as}` sets to prove parity:
```bash
diff <(python3 .claude/graph/extractors/csharp_extractor.py --changed-files <probe.cs> | jq -S '[.vcontainer.installers[].registrations[] | {type, as}] | sort') \
     <(bash .claude/graph/extractors/csharp-extractor.sh --changed-files <probe.cs> | jq -S '[.vcontainer.installers[].registrations[] | {type, as}] | sort')
```
Expected: empty diff, **including** the `.As<IBar>()` record (`{"type":"Bar","as":"IBar"}` from both). This is satisfiable only because Task 1 step 4 added the chain reader to the tree-sitter side; before that change the tree-sitter half of this diff is `{"type":"Bar","as":""}` and the diff cannot be empty. Task 8 promotes this into a harness assertion with a probe that exercises the chain.

**Code Skeleton:**
```python
# inside the registration heredoc, before Form 1:
# The regex yields (type, name) pairs; the lookup at Form 1c is by NAME, so the
# comprehension inverts them. dict(re.findall(...)) would key by type and make
# every FIELD_TYPES.get(ident) miss.
FIELD_TYPES = {name: typ for typ, name in re.findall(
    r'(?:private|protected|public|internal|readonly|static|\s)+'
    r'([A-Za-z0-9_<>\.]+)\s+(_?[a-zA-Z][A-Za-z0-9_]*)\s*[;=]', text)}
# -> {"_fooField": "Foo", ...}

# Form 1b: RegisterInstance<IFoo>(new Foo(...))
for m in re.finditer(r'builder\.RegisterInstance<([A-Za-z0-9_]+)>\s*\(\s*new\s+([A-Za-z0-9_]+)', text):
    results.append({"type": m.group(2), "as": m.group(1),
                    "lifetime": "Singleton", "scope": ""})

# Form 1c: RegisterInstance<IFoo>(_fooField)
for m in re.finditer(r'builder\.RegisterInstance<([A-Za-z0-9_]+)>\s*\(\s*(_?[a-zA-Z][A-Za-z0-9_]*)\s*\)', text):
    iface, ident = m.group(1), m.group(2)
    concrete = FIELD_TYPES.get(ident, "")
    if concrete:
        results.append({"type": concrete, "as": iface, "lifetime": "Singleton", "scope": ""})
    else:
        # mirrors Task 1 step 7: the ONLY interface_only site in this extractor
        results.append({"type": iface, "as": "", "lifetime": "Singleton",
                        "scope": "", "interface_only": True, "confidence": "INFERRED"})

# Form 1 (existing generic, lines 360-380) — `as` is now always a STRING:
#   line 369:  "as": ""                      (was [])
#   line 377:  reg["as"] = as_matches[0]     (was as_matches if len>1 else as_matches[0])
# Rationale: schema.json:177 types `as` as string; knowledge-graph.md:139 compares it
# as a scalar, so a list has never matched any consumer. Task 1's _as_chain also takes
# the first link, so first-wins is the agreed rule on both sides.
# Skip Form 1 when the arg list opens with `new` or a bare identifier already consumed
# above; guard by tracking matched spans.

# dedup (lines 394-401): key on (type, as) not type alone — both are strings now
seen = set()
for r in results:
    k = (r["type"], r.get("as", ""))
    if k not in seen: seen.add(k); deduped.append(r)
```

**Acceptance Criteria:**
- Both extractors emit the same `{type, as}` multiset for the probe file **over records where that extractor resolved a type** (`select(.type != "")`), **including records that carry an `.As<T>()` chain** (empty diff). Satisfiable because Task 1 step 4 teaches the tree-sitter side to read the chain. The one shape only one side can represent — non-generic `RegisterInstance` whose argument contains a call, e.g. `RegisterInstance(SomeStatic.Opaque())`, which `csharp-extractor.sh:384`'s regex cannot match — is deliberately NOT given a new fallback pattern here; it is asserted per-extractor by Task 8's reg.6 instead. See Task 8's reg.4 comment for why an unfiltered compare is unsatisfiable by construction rather than by an unfinished fix.
- Every emitted `as` is a JSON string; no code path can emit a list. (`jq '[.vcontainer.installers[].registrations[].as] | map(type) | unique == ["string"]'` → `true`.)
- No emitted `type` is an interface name when a concrete was recoverable from the argument.
- `interface_only` appears only on the Form 1c miss path; no `Register<T>` record carries it.
- `.AsImplementedInterfaces()` handling is unchanged (still the literal string `"AsImplementedInterfaces"`, which Task 1 now emits identically), and single-`.As<T>()` output is unchanged; only the multi-`.As<T>()` case changes, from a list to its first element, per `## Chosen Approach` decision 2.
- Dedup no longer collapses two interfaces sharing one concrete.
- Script still exits 0 and prints valid JSON when the file has no registrations (the `print("[]")` guard at the top of the heredoc still fires).

---

## Checkpoint C1 — Real-Corpus Read-Only Validation (gate, immediately after Tasks 1 + 2)

**New in v4 (grill D5). This is a gate, not an edit task — it writes nothing.**

**Why it exists, measured.** The template repo has **no `Assets/` directory at all**: its graph contains 0 classes, 0 interfaces, 0 installers, and its only 9 `.cs` files are test fixtures. So every assertion in Tasks 1-8 runs against synthetic probes written by the same person writing the fix, encoding the same assumptions. The originating symptom — `GridModule`'s false `INSTALLER_MISSING_CLASS` — is reproducible **only** in piggy-doku, and in v3 the sole real-corpus check (Task 9) came *after* Tasks 1-8 were already marked done. That ordering failed twice during the grill session itself: a research agent's false "nothing reads the `as` key" claim was passed to the planner as verified fact, and v2's `interface_only` marker landed on every ordinary `Register<Foo>()`, which would have disabled `INSTALLER_MISSING_CLASS` for the common case. Both were assumption errors; only an independent look caught either.

**Boundary — this does NOT enter the harness.** `verify-graphify.sh` stays self-contained on synthetic probes. This is plan-time evidence, not a CI gate; making the template's tests depend on another repository existing is explicitly rejected.

**Steps:**
1. [ ] Run the template's *changed* tree-sitter extractor read-only against piggy-doku's real module files. No copy, no commit, piggy-doku's `graph.json` untouched (this exact invocation was validated as executable during the grill):
   **`--changed-files` is COMMA-separated, not space-separated** (`csharp_extractor.py:717`,
   split at line 724). Passing a shell glob or space-joined list does **not** error — it silently
   yields an empty file list and an empty `installers` array, which reads exactly like "no
   registrations found". This bit during the v4 C1 run; build the list with `paste -sd,`:
   ```bash
   T=/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
   P=/Users/berkterek/Desktop/Github/piggy-doku-repo
   M=$(find "$P/PiggyDoku/Assets/_GameFolders/Scripts/Games/Concretes" -name '*Module.cs' | paste -sd, -)
   python3 "$T/.claude/graph/extractors/csharp_extractor.py" --changed-files "$M" \
     | jq -c '.vcontainer.installers[] | {name, registrations}'
   ```
2. [ ] Compare against the **recorded baseline** — the pre-fix output captured during the grill against the *unmodified* extractor:
   ```
   GridModule → [{"type": "ITapResolver", "as": "", "lifetime": ""},
                 {"type": "GridService",  "as": "", "lifetime": ""}]
   ```
3. [ ] Run the changed fallback extractor over the same files and diff `{type, as}` against the tree-sitter output, exactly as in Task 2's verification — but on real source rather than a probe.
4. [ ] Do **not** modify anything in `$P`. Do **not** run `graph-builder.py` inside `$P` at this checkpoint — that is Task 9's job, and running it here would rewrite a tracked `graph.json` with a half-finished plan's output.
5. [ ] Record the before/after in the checkpoint's completion note.

**Acceptance Criteria (gate — B does not start until all pass):**
- `GridModule`'s first record moves from `{"type":"ITapResolver","as":""}` to `{"type":"TapResolver","as":"ITapResolver"}`; the recorded baseline above is the before-state.
- `GridService`'s **`type` is unchanged** (`GridService`) and it carries **no `interface_only`** — the generic slot is the concrete and Task 1 must not touch it. **Corrected during the v4 C1 run:** an earlier draft of this criterion said the whole record was unchanged. That was wrong — `GridModule.cs:30` is `builder.Register<GridService>(Lifetime.Singleton).AsImplementedInterfaces()`, so Task 1's chain reader correctly moves `as` from `""` to the placeholder `"AsImplementedInterfaces"`. The criterion was written from the recorded baseline without checking the call shape; C1 caught it, which is the entire reason D5 moved this checkpoint ahead of group B.
- No record on real source has `type` matching `^I[A-Z]` where a concrete was recoverable.
- Every `as` on real source is a JSON string.
- No registration on real source that came from a plain `Register<T>()` carries `interface_only` — this is the v2 regression, checked against real code rather than a probe.
- `$P` has zero modified files afterwards (`git -C "$P" status --porcelain` is empty).

**If any criterion fails, Tasks 1/2 are not done** — fix them and re-run this checkpoint before starting group B.

---

## Task 3 — Stale `graph-builder.sh` Reference Sweep

**Nine live locations, matching the census in `## Context`:**
- `.claude/commands/build-knowledge-graph.md` (lines 23, 66, 82) — 3
- `.claude/commands/setup-project.md` (line 162) — 1
- `.claude/graph/extractors/mcp-extractor.md` (line 249) — 1
- `.claude/graph/codex-validator.md` (lines 49, 69) — 2
- `.claude/graph/schema.json` (lines 5, 21) — 2

**Steps:**
1. [ ] Re-run the census before editing and confirm it yields exactly these nine live hits plus the six do-not-touch occurrences plus the two `.claude/state/subagent-log.jsonl` history lines (append-only, not a reference to run anything):
   `grep -rn "graph-builder\.sh" .claude/ docs/`
2. [ ] `build-knowledge-graph.md:23` — change the Step 0 preflight from `Check \`.claude/graph/graph-builder.sh\` exists.` to reference `graph-builder.py`. This is the highest-priority line in the task: as written, the gate fails on a healthy repo and the following block tells the agent "Stop here."
3. [ ] `build-knowledge-graph.md:66` — replace `bash .claude/graph/graph-builder.sh [--full|--incremental] [--skip-mcp] [--quiet]` with `python3 .claude/graph/graph-builder.py [--full|--incremental] [--skip-mcp] [--quiet]`. Note the interpreter changes from `bash` to `python3`, not just the filename.
4. [ ] `build-knowledge-graph.md:82` — `python3 .claude/graph/graph-builder.py --incremental`.
5. [ ] `setup-project.md:162` — `python3 .claude/graph/graph-builder.py --full --skip-mcp` (preserve the existing `--skip-mcp` flag; the current line has it).
6. [ ] `mcp-extractor.md:249` — `python3 .claude/graph/graph-builder.py --incremental`.
7. [ ] `codex-validator.md:49` and `:69` — update the recommendation text to `python3 .claude/graph/graph-builder.py --full`.
8. [ ] `schema.json:5` — in `description`, change "Generated by graph-builder.sh" to "Generated by graph-builder.py". Do not touch the rest of the description string (the v1.3.0 partition note).
9. [ ] `schema.json:21` — change the `generator` property's `description` from `"graph-builder.sh@<git-sha>"` to `"graph-builder.py@<git-sha>"`. **Checked and safe:** `graph-builder.py:815` already emits `"generator": f"graph-builder.py@{git_sha}"`, and a grep for `generator` across `.claude/graph/*.py` and `.claude/graph/test/*.sh` found only that write site plus an unrelated docstring in `graph-viz.py:2` — nothing validates or pattern-matches the generator string, so the schema description is currently *wrong about its own output* and this edit corrects the drift rather than causing it. Stale `graph.json`/`graph.json.bak` artifacts that still literally read `graph-builder.sh@<sha>` are regenerated on the next build and are not validated against this description (it is a `description`, not a `pattern`).
10. [ ] Confirm the do-not-touch list is untouched by re-running the census and diffing against the expected residual set: `verify-graphify.sh:261,430,547`, `test/README.md:58`, `graph-builder.py:8`, `graph.json.bak:4`, `state/subagent-log.jsonl:49-50`, plus all `docs/archive/**` and historical `docs/PLAN_graph_*.md` hits.

**Verification:** **(b) manual command.**
```bash
grep -rn "graph-builder\.sh" .claude/ | grep -v -e 'test/verify-graphify\.sh' -e 'test/README\.md' -e 'graph-builder\.py:8' -e 'graph\.json\.bak' -e 'state/subagent-log\.jsonl'
```
Expected output: **empty** (nine lines removed, six do-not-touch plus the log excluded by the filter). Then confirm the schema still parses and the harness still passes:
```bash
jq empty .claude/graph/schema.json && bash .claude/graph/test/verify-graphify.sh
```
Expected: `jq` silent (exit 0); harness exit 0 with unchanged pass/fail counts (this task changes no code paths the harness exercises).

**Code Skeleton:** Pure textual substitution; no logic. Canonical replacement form, from the three live invocation sites `.claude/hooks/install-git-hooks.sh:33-34`, `.claude/hooks/graph-auto-update.sh:101`, `.claude/graph/graph-watch.sh:9`:
```
bash   .claude/graph/graph-builder.sh  <flags>
  ->
python3 .claude/graph/graph-builder.py <flags>
```

**Acceptance Criteria:**
- The filtered grep above returns no lines.
- All nine planned locations changed; the census count before the edit was nine live hits.
- The six documented do-not-touch occurrences are byte-identical to `HEAD` (`git diff` shows no hunks in `verify-graphify.sh`, `test/README.md`, `graph-builder.py`, `graph.json.bak` from this task).
- `.claude/graph/schema.json` is still valid JSON and `bash .claude/graph/test/verify-graphify.sh` exits 0.
- No `docs/archive/**` or historical `docs/PLAN_*.md` file is modified.

---

## Task 4 — Nested `.claude/graph/.gitignore` Self-Sufficiency

**Files:**
- `.claude/graph/.gitignore` (currently two entries: `.last-build`, `cache/file-hashes.json`)

**Included, and why it is worth a task:** nothing leaks today — the template's root `.gitignore:37` (`.claude/graph/cache/*`) already covers `cache/mcp-extract.json`, and in piggy-doku `git check-ignore -v` resolves it to `.claude/graph/.gitignore:4`. The value is *portability*, which is this template's whole purpose: `.claude/graph/` is copied into projects wholesale, and a nested ignore file that depends on a root-level rule silently stops working the moment someone copies the directory into a repo whose root `.gitignore` lacks line 37. One line buys drift-free parity with piggy-doku and removes a hidden coupling. Low priority, near-zero risk.

**Steps:**
1. [ ] Re-read `.claude/graph/.gitignore` and confirm it still has exactly the two entries.
2. [ ] Confirm the root rule that currently covers the gap: `grep -n 'graph/cache' .gitignore` → expect `.gitignore:37: .claude/graph/cache/*`.
3. [ ] Append `cache/mcp-extract.json` under the existing "Build artifacts" comment, matching piggy-doku's line 4 exactly so the two repos stay byte-identical.
4. [ ] Do **not** remove or alter root `.gitignore:37` — belt and braces is correct here; the nested file is a portability fallback, not a replacement.
5. [ ] Confirm `docs/.idea` needs nothing: it is already covered by `.gitignore:119` (`**/.idea/`). No task.

**Verification:** **(b) manual command.**
```bash
git check-ignore -v .claude/graph/cache/mcp-extract.json
git status --porcelain .claude/graph/cache/
```
Expected: `check-ignore` reports `.claude/graph/.gitignore:<n>:cache/mcp-extract.json` (the nested file now wins as the more specific match, matching piggy-doku's behaviour); `git status` lists nothing under `cache/`. Also confirm `git config core.excludesfile` is still unset, so the result does not depend on the developer's machine.

**Code Skeleton:**
```gitignore
# Build artifacts — regenerated on every graph build, no history value
.last-build
cache/file-hashes.json
cache/mcp-extract.json
```

**Acceptance Criteria:**
- `git check-ignore -v .claude/graph/cache/mcp-extract.json` attributes the match to `.claude/graph/.gitignore`.
- `.claude/graph/.gitignore` is byte-identical to piggy-doku's copy.
- Root `.gitignore` is unmodified.
- No previously-tracked file becomes ignored (`git ls-files .claude/graph/cache/` is empty before and after).

---

## Task 5 — Narrow `graph_validate.py` Guard on `interface_only`

**Sequential after Task 1** — reads the `interface_only` key Task 1 introduces.

**Files:**
- `.claude/graph/graph_validate.py` (the `INSTALLER_MISSING_CLASS` block, lines **93-118** inside `run_consistency`; 93 is the `# Installer references non-existent class` comment and 94 initialises `unresolved_registrations`)

**Steps:**
1. [ ] Re-read `.claude/graph/graph_validate.py` lines 40-120. Confirm: `class_names` is built at line 52 from `codebase.classes` only; `callee_node_names` at line 57 is `class_names | {i["name"] for i in interfaces}` and is used **only** for the `DANGLING_CALL` check; the block opens at **line 93** with its section comment; the `unresolved is True` skip spans **lines 101-103** with an `unresolved_registrations` counter; the flagged name `reg.get("class","") or reg.get("type","")` is assigned at **line 104** and tested with `not in class_names` at **line 105**; **line 110 is the `detail` f-string**, not the membership test; the aggregated stderr note is lines 113-118.
2. [ ] Add an `interface_only` skip immediately after the existing `unresolved` skip (i.e. between lines 103 and 104), with its own counter, following the established pattern exactly (accumulate a count, `continue`, print one aggregated stderr line at the end — see lines 113-118).
3. [ ] Word the aggregated stderr line to say what it means and what it is not: `RegisterInstance` registrations where only a generic interface argument was recoverable are known-incomplete, not dangling. Keep it on `sys.stderr` and keep it out of the returned `issues` list so it does not affect exit status.
4. [ ] Do **not** widen the membership test at **line 105** to `class_names | interface_names`. Argued in `## Chosen Approach` decision 4: a loose guard makes any missing implementation of an existing interface validate clean, which is exactly the class of silent omission Defect 0 is about. The two defects would mask each other. Provenance-based skipping (the record itself admits it could not resolve a concrete) keeps a record that *claims* resolution fully accountable.
5. [ ] Confirm the blast radius of the new `continue` is as narrow as Task 1 makes it. Task 1 step 7 sets `interface_only` **only** on `RegisterInstance` records whose argument-side concrete was unresolvable; every `Register<T>` / `RegisterEntryPoint<T>` / `RegisterComponent<T>` / `RegisterComponentInHierarchy<T>` record reaches line 105 exactly as it does today. Verify this against the extractor output before declaring the task done — a build in which most registrations carry `interface_only` means Task 1 regressed and this guard has switched the check off wholesale rather than narrowing it. Sanity command: `jq '[.codebase.vcontainer.installers[].registrations[] | select(.interface_only == true)] | length' .claude/graph/graph.json` — expect a small number, not the total registration count.
6. [ ] Confirm the guard is a no-op on graphs built before Task 1: old records have no `interface_only` key, so `reg.get("interface_only") is not True` and the existing behaviour is preserved for stale graphs.

**Verification:** **(a) harness assertion**, added in Task 8, plus **(b) manual** during implementation:
```bash
python3 .claude/graph/graph_validate.py --graph .claude/graph/graph.json 2>&1 | grep -i "INSTALLER_MISSING_CLASS\|interface"
```
Expected on a repo rebuilt after Tasks 1-2: no `INSTALLER_MISSING_CLASS` naming an interface (no `I`-prefixed class name in the output), and at most one aggregated stderr note about interface-only registrations. Then confirm the check still bites, in **two** independent ways, by hand-editing a *copy* of `graph.json`:
- add `{"type":"DefinitelyNotAClass"}` with no `interface_only` → `INSTALLER_MISSING_CLASS` must still fire;
- add a plain `Register<UnknownClass>(Lifetime.Singleton)`-shaped record `{"type":"UnknownClass","as":"","lifetime":""}` → `INSTALLER_MISSING_CLASS` must still fire. This second case is the regression the over-broad `interface_only` of the previous draft would have introduced, so it is checked explicitly rather than assumed.

**Code Skeleton:**
```python
unresolved_registrations = 0      # line 94
interface_only_registrations = 0
for installer in vcontainer.get("installers", []):
    for reg in installer.get("registrations", []):
        if reg.get("unresolved") is True:        # existing, lines 101-103
            unresolved_registrations += 1
            continue
        # NEW: RegisterInstance<IFoo>(opaqueExpr) — only a generic interface arg was
        # recoverable. Known-incomplete, not dangling. Set by Task 1 on that ONE shape;
        # a plain Register<Foo>() never carries it, so it still gets checked below.
        # Deliberately NOT "name is a known interface" — that would mask a genuinely
        # deleted implementation, which is exactly Defect 0's failure mode.
        if reg.get("interface_only") is True:
            interface_only_registrations += 1
            continue
        cls_name = reg.get("class", "") or reg.get("type", "")   # line 104, unchanged
        if cls_name and cls_name not in class_names:             # line 105, unchanged
            issues.append({...})   # unchanged; detail f-string at line 110 untouched
...
if interface_only_registrations:
    print(f"graph_validate: {interface_only_registrations} interface-only registration(s) "
          f"(RegisterInstance<IFoo> with an unresolvable argument) — known-incomplete, "
          f"not dangling", file=sys.stderr)
```

**Acceptance Criteria:**
- A registration carrying `interface_only: true` produces no `INSTALLER_MISSING_CLASS` issue.
- **A plain `Register<UnknownClass>(Lifetime.Singleton)` record (no `interface_only`, no `unresolved`) still produces `INSTALLER_MISSING_CLASS`.** This is the pinned regression: if it does not fire, Task 1 set `interface_only` too broadly and the check has been switched off for ordinary registrations.
- A registration naming an unknown class **without** `interface_only`/`unresolved` still produces `INSTALLER_MISSING_CLASS`.
- A registration naming a known **interface** without `interface_only` still produces `INSTALLER_MISSING_CLASS` (the guard did not become name-based).
- On a freshly rebuilt graph, the count of `interface_only: true` registrations is a small minority of all registrations, not all of them.
- The membership test at line 105 is byte-identical to `HEAD`.
- The stderr note is informational only; `run_consistency`'s returned `issues` list and the script's exit code are unaffected by it.
- Running against a pre-Task-1 `graph.json` yields byte-identical output to before this task.

---

## Task 6 — Disk-vs-Graph Reconciliation Warning in `graph-builder.py`

**Sequential after Task 1/2** (group B), and after Checkpoint C1. Touches `graph-builder.py`, which Task 10 also touches — so Task 10 must follow this.

**Files:**
- `.claude/graph/graph-builder.py` (new reconciliation immediately after `atomic_write_json(graph, output_path)` at line 1138)

**Steps:**
1. [ ] Re-read `.claude/graph/graph-builder.py`: `log(msg, quiet=False)` at lines 59-62 (the single stderr channel); `select_changed(all_files, cache, mode)` at lines 210-230 (note it appends to `current_paths` even for files that fail `os.path.isfile`, and counts them as `scanned`); the `current_paths` construction at **line 1015** (`[f for f in full_cs if f] + [f for f in full_asmdef if f]` — deliberately from the **full** directory walk, so a `--changed-files` run does not treat the rest of the project as deleted); the `FALLBACK_EXTRACTOR` warning pattern at lines 1080-1087 (both a `fallback_warnings` dict entry *and* a `print(... file=sys.stderr)`); the collapse guard at **lines 1124-1132** (`return 1`, fatal — the pattern this task must **not** copy); the partition-file write just above; `atomic_write_json(graph, output_path)` at line 1138.
2. [ ] **Comparison unit: the path SET, not the count.** Justify in a comment: a count-only check is defeated by the exact failure that motivated this task — one file dropped while another is added nets to zero delta and reports healthy. Sets also let the warning name the missing files, which is what makes it actionable ("`LocalSaveLoadDal.cs`, `LogDumpOnStop.cs` missing") rather than a bare "counts differ".
3. [ ] **Path convention — RESOLVED, not open.** This repo already settled it: `docs/plans/graph-incremental-purge-fix.md:5` records that the hook passes *absolute* `--changed-files` paths while the full walk and extractors emit *relative* ones, that the mixed formats caused silent duplicate/decay, and that the fix (commit `57c9340`) normalises everything to **repo-root-relative** form via `os.path.relpath(os.path.realpath(f), os.path.realpath("."))` — with `realpath` specifically to defeat macOS `/var → /private/var` aliasing. Its closing lesson is binding here: *any* future path set-lookup in the graph pipeline must normalise to repo-root-relative form first. Implement exactly one shared helper and route **both** sides of the comparison through it:
   ```python
   def norm(p):
       """Repo-root-relative, realpath-resolved. See docs/plans/graph-incremental-purge-fix.md:5
       (commit 57c9340): mixed absolute/relative paths silently decayed the graph; realpath
       defeats macOS /var -> /private/var aliasing."""
       return os.path.relpath(os.path.realpath(p), os.path.realpath("."))
   ```
   Reuse the existing normalisation helper if `57c9340` already introduced a named one rather than adding a second; grep for `relpath` before writing.
4. [ ] Build `graph_cs_paths` as the distinct set of `norm(source_file)` (falling back to `file`) over **exactly two** node kinds: `("classes", "interfaces")`. **Corrected in v4 (grill D2):** v3 unioned `("classes","interfaces","enums","structs")`, but **the graph has no `enums` and no `structs` arrays at all** — its node kinds are `classes`, `interfaces`, `events`, `assemblies`, `calls`, `communities`, so two of the four keys always yielded an empty list and read as if coverage existed. Do **not** add `events` either: `events[].source_file` points at the event's **publisher**, not its declaration site (`CellStateChangedEvent` is declared in `GridEvents.cs`; the graph records `GridService.cs`), so folding it in would mark the *wrong* file as covered. Build `disk_cs_paths` per step 5.
5. [ ] **Filter the disk side by declaration kind before comparing** — `[BLOCKED]` cleared in v4 by measurement, not by reasoning. Include a disk `.cs` file only if it declares a `class` or an `interface`; anything else is a node kind the graph does not model, and comparing it produces a permanent false alarm.

   **The measurement (piggy-doku, live graph):**

   | | |
   |---|---|
   | graph nodes carrying a source file | 63 |
   | `.cs` files on disk | 72 |
   | **missing (disk − graph), unfiltered** | **9** |
   | extra (graph − disk) | 0 |

   All nine are node kinds the graph does not model: 4 `enum`-only (`LogTag`, `CellState`, `TapAction`, `FlowState`), 2 `struct`-only (`GridLayout`, `GridFramingEntry`), 3 `*Events.cs` declaration sites (`GridEvents`, `LevelEvents`, `LivesEvents` — invisible for the `source_file` reason in step 4). So v3's own verification gate ("a healthy build must be SILENT") **would have failed as written**.

   **The filter was then validated on the same corpus:** 63 candidate files after filtering = 63 graph class/interface files, **0 false positives**, and none of the 9 excluded files contains the word `class` or `interface` anywhere — so on this corpus the regex is not silently dropping a declaring file either. **It still catches the bug it exists for:** `LocalSaveLoadDal.cs` and `LogDumpOnStop.cs`, the two files that went silently missing, both declare classes.

   **Second failure direction, found in v4 end-to-end verification — the regex can ALSO
   over-match.** A file whose only mention of `class` sits in a **comment** (`// class GhostThing
   — see below`) or in a string literal passed the declaration test, landed on the disk side,
   matched no graph node, and raised `GRAPH_DISK_MISMATCH` **on a healthy build** — the exact false
   alarm this task's gate forbids. Reproduced in a scratch project, then fixed by stripping
   comments and string/char literals before the test (`_strip_comments_and_strings`, same
   precedent as `check-no-monobehaviour-in-services.sh`). Re-measured afterwards on piggy-doku:
   72 disk / 63 graph / 63 kept / 9 excluded / missing 0 / extra 0 — **identical**, so the original
   D2 measurement was structurally sound and merely lucky about comments. Verified the net did not
   blunt: a genuinely missing `class` is still reported.

   **Residual risk, recorded not hand-waved:** the regex is a *hole*, not a false alarm — an unusual declaration (multi-line, heavily attributed) would silently drop that file out of the comparison. Measured at zero on the current corpus. *Mitigation:* print the excluded-file count in the build output so the number is visible rather than implicit, and re-measure the first time this filter meets a new codebase.

   **Rejected alternatives:** comparing against the extractor's *processed* file set is conceptually closer to "was a file skipped?", but it is unverified whether the builder publishes such a set today and adopting it adds an accounting layer. Adding `enums`/`structs` as real node kinds would make the naive comparison correct *and* close a genuine gap (`/knowledge-graph` cannot answer "where is `CellState` declared") — but that is an extractor capability, which is exactly what D1 removed Task 7 for.
6. [ ] Compute `missing = disk_cs_paths - graph_cs_paths`. Warn only when non-empty, on stderr, through `log(..., quiet)` so `--quiet` suppresses it, listing up to N (say 10) paths plus a `(+K more)` tail, and ending with the explicit recommendation to run a full rebuild: `python3 .claude/graph/graph-builder.py --full`.
7. [ ] Also compute `extra = graph_cs_paths - disk_cs_paths` and fold it into the same warning as a separate line. That is the ghost-node direction; the existing purge logic should already keep it empty, so a non-empty `extra` is independently interesting.
8. [ ] **Non-fatal, unconditionally.** Do not `return 1` (that is the collapse guard's pattern at 1124-1132, deliberately not copied), do not `sys.exit`, do not skip the cache update or the post-write modules. The requirement is explicit and the reasoning holds: a false alarm that blocks every build is worse than the silent omission it replaces. Wrap the whole reconciliation in `try/except Exception` and `log` the failure — a bug in the detector must never break the builder.
9. [ ] Place the block **after** `atomic_write_json` (line 1138) so it reconciles against what was actually written, and after the partition-file write immediately above it. Prefer reusing the in-memory `graph` dict over reading back from disk (cheaper, and the atomic write is all-or-nothing so they cannot disagree); note that partitioned `scenes`/`prefabs` live in sibling files — irrelevant here since only `.cs` class nodes are compared.
10. [ ] Mirror the `FALLBACK_EXTRACTOR` precedent (1080-1087) and append a structured entry (e.g. `{"code": "GRAPH_DISK_MISMATCH", "message": ...}`) to the same warnings collection if it is still in scope at the write point; if the graph dict is already sealed by line 1138, emit stderr only and note in a comment why the structured entry was omitted.

**Verification:** **(a) harness assertion** (Task 8) plus **(b) manual**, which is the more convincing evidence here:
```bash
# 1. Healthy baseline — must be SILENT
python3 .claude/graph/graph-builder.py --full --skip-mcp 2>&1 | grep -i "GRAPH_DISK_MISMATCH"
# expected: no output
# 2. Induced omission — must WARN and must still exit 0
#    (in the harness .work/ sandbox: build full, then hand-remove one class entry
#     from the graph copy and re-run the reconciliation against it)
```
Expected: step 1 emits **no `GRAPH_DISK_MISMATCH`** (this is the false-positive gate; the separate `reconciliation: N .cs file(s) excluded` line is expected and is not a mismatch warning — on piggy-doku N is 9); step 2 prints a warning naming the removed file, recommends `--full`, and the process exit code is still `0`. Run step 1 in **piggy-doku** as well as the template — the template has no `Assets/` and therefore proves nothing here.

**Code Skeleton:**
```python
def norm(p):
    """Repo-root-relative, realpath-resolved — the convention fixed in 57c9340.
    See docs/plans/graph-incremental-purge-fix.md:5."""
    return os.path.relpath(os.path.realpath(p), os.path.realpath("."))

# v4 (grill D2): the disk side is filtered by declaration kind. Measured on piggy-doku —
# unfiltered gave 9 permanent false positives (4 enum-only, 2 struct-only, 3 *Events.cs),
# filtered gives 63 == 63, zero false positives. This regex is a HOLE, not an alarm: a
# declaring file it misses drops out of the comparison silently, so the excluded count is
# logged (below) rather than left implicit.
_DECL_RE = re.compile(r'\b(?:class|interface)\s+[A-Za-z_]', re.M)

def _declares_node(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return bool(_DECL_RE.search(fh.read()))
    except OSError:
        return False   # unreadable -> not comparable; counted as excluded

def reconcile_graph_with_disk(graph, disk_cs, quiet, limit=10):
    """Non-fatal net for silent omissions. Path SET comparison, not counts:
    a count check passes when one file drops and another is added.
    BOTH sides go through norm() — mixed path formats were the 57c9340 bug."""
    try:
        cb = graph.get("codebase", {})
        # ONLY these two kinds exist in the graph. `enums`/`structs` are not node kinds at
        # all, and events[].source_file is the PUBLISHER, not the declaration site — folding
        # it in would mark the wrong file as covered. See Task 6 step 4.
        graph_paths = {
            norm(n.get("source_file") or n.get("file"))
            for kind in ("classes", "interfaces")
            for n in cb.get(kind, []) or []
            if (n.get("source_file") or n.get("file"))
        }
        candidates = [p for p in disk_cs if p]
        disk_paths = {norm(p) for p in candidates if _declares_node(p)}
        excluded = len(candidates) - len(disk_paths)
        if excluded:
            log(f"reconciliation: {excluded} .cs file(s) excluded — declare no class/interface "
                f"(enum-only, struct-only, event declaration sites)", quiet)
        missing = sorted(disk_paths - graph_paths)
        extra   = sorted(graph_paths - disk_paths)
        if not missing and not extra:
            return
        if missing:
            head = ", ".join(missing[:limit])
            tail = f" (+{len(missing) - limit} more)" if len(missing) > limit else ""
            log(f"WARNING: GRAPH_DISK_MISMATCH — {len(missing)} .cs file(s) on disk are "
                f"absent from the graph: {head}{tail}. "
                f"Run 'python3 .claude/graph/graph-builder.py --full' to rebuild.", quiet)
        if extra:
            log(f"WARNING: GRAPH_DISK_MISMATCH — {len(extra)} graph node(s) reference "
                f"files not on disk: {', '.join(extra[:limit])}", quiet)
    except Exception as e:
        log(f"reconciliation check failed (non-fatal): {e}", quiet)

# call site, right after line 1138:
atomic_write_json(graph, output_path)
reconcile_graph_with_disk(graph, full_cs, quiet)
```

**Acceptance Criteria:**
- No `GRAPH_DISK_MISMATCH` on a healthy `--full` build in **both** repos (zero false positives — this is the gate, not a nice-to-have). Measured expectation on piggy-doku: 63 filtered disk files vs 63 graph class/interface files, missing = 0, extra = 0.
- The graph side unions exactly `("classes","interfaces")`; no code path reads `enums`, `structs`, or `events[].source_file`.
- The disk side is filtered by the class/interface declaration regex, and the count of excluded files is **logged**, not silent (piggy-doku: 9).
- Warns and names the offending paths when a `.cs` file on disk has no graph node.
- Both sides of the comparison are normalised through the single `norm()` helper; no raw path string is compared.
- Exit code, `graph.json` bytes, hash-cache update, and post-write module execution are all identical to before this task in every case.
- `--quiet` suppresses the warning (routed through `log`, not a bare `print`).
- An exception inside the reconciliation is caught and logged; the build still succeeds.
- The comparison is a set operation; no code path compares only lengths.

---

## Task 7 — REMOVED in v4 (grill D1) — moved to an ADR

**Was:** `ParentReference.Create<T>()` scope-parent extraction across both extractors plus a
`scope_merge` precedence decision. The full v3 text is recoverable from git history
(`docs/PLAN_graph_tooling_fixes.md` at v3) and its rationale is preserved in
`docs/decisions/2026-08-18-grill-plan-graph-tooling-fixes.md` D1.

**Why it was removed — three reasons, in order of weight:**

1. **It silently overrode a recorded project decision without naming it.** Stored memory
   *Limitation 18* says verbatim: "Do NOT report this as a bug or try to fix it with regex/grep
   on .cs files. … The fix requires an MCP extractor update (C# EditorScript querying
   `AssetDatabase` + `SerializedObject`), which has not been implemented." Task 7 did exactly the
   forbidden thing on both extractors — AST on `csharp_extractor.py`, and **regex** on
   `csharp-extractor.sh`. A defect-fix plan is not the place to reverse a standing decision.
2. **That recorded decision is itself partly outdated, which makes this a decision, not a task.**
   Limitation 18's factual half ("the parent is never declared in C# source") is **false** for
   piggy-doku, where `GameScope` builds its parent in `Awake` via `ParentReference.Create<AppScope>()`.
   Its normative half (do not solve this with regex on `.cs`) still binds the shell-fallback side.
   Both halves cannot stand as written — that needs deciding deliberately.
3. **It serialised the entire plan behind its riskiest, least-certain task.** Task 7 alone occupied
   `parallel_group` C because it rewrote all three files that groups A and B touch. The other eight
   tasks are narrow, measurable, and shippable today.

**Accepted cost, recorded:** `/knowledge-graph scope-tree` keeps showing `GameScope` as a root
scope. That is a graph limitation, not an architecture defect — a PlayMode test already proves
`GameScope.Parent == AppScope` and `IsRoot == false` at runtime.

**Follow-up owed — an ADR, and it is NOT YET WRITTEN.** Open it with `/adr` (the decision record's
own "Recommended next command", to be run after this plan update). It must decide (a) whether
Limitation 18's factual half is amended, (b) whether code-declared parents may be read from source
at all, and (c) if yes, whether the regex fallback is permitted to participate. **This plan does
not block on the ADR** — Tasks 1-6 and 8-10 are independent of it — but the ADR is a tracked debt,
not an optional nicety: until it exists, the reason `scope-tree` is wrong lives only in a grill
transcript and this stub.

---

## Task 10 — `EXTRACTION_VERSION` and Builder-Side Cache Invalidation

**New in v4 (grill D4). Sequential after group B** — writes `graph-builder.py`, the same file as
Task 6.

**Files:**
- `.claude/graph/graph-builder.py` (new module-level constant; a comparison in the mode-selection
  path; the metadata write near lines 813-815 where `schema_version` and `generator` are emitted)
- `.claude/graph/schema.json` (document `metadata.extraction_version`; minor `schema_version` bump
  per the rule at `schema.json:12`)

**The gap this closes, measured.** This plan changes the *values* of `type` and `as`, not their
*shape* — so nothing existing signals that a graph is stale in the way that matters. `generator`
(written at `graph-builder.py:815`) and `schema_version` (`1.3.0`, line 813) are both
**write-only: nothing in the pipeline reads either.** Staleness is judged purely on `generated_at`
being older than 24h (`knowledge-graph.md:33`). An `--incremental` build does not re-extract
unchanged files, so old wrong records survive indefinitely while the graph reports itself fresh,
and `/knowledge-graph` answers from them with confidence.

| Repo | `graph.json` tracked | builder SHA | built |
|---|---|---|---|
| template | yes | `5a23b5b` | 2026-07-06 |
| piggy-doku | yes | `20c0136` | 2026-08-18 |
| voxel-blast | no | `87fcde1` | 2026-08-14 |
| worm-escape | yes | `e732700` | 2026-08-17 |
| nile-hole | yes | `fc2c3e20` | 2026-08-13 |

Task 9 rebuilds piggy-doku only. Without this task, **three other projects keep wrong `type` and
empty `as` forever.**

**Rejected alternative:** documenting "run `--full` in every repo after this lands". That is
precisely the class of instruction that silently does not happen — and Defect 0 exists *because* a
graph silently disagreed with disk. Relying on a remembered manual step would reproduce the exact
failure mode this plan is fixing.

**Side benefit:** `generator` and the version fields become load-bearing for the first time.

**Steps:**
1. [ ] Re-read `graph-builder.py`: the argparse block at lines 42-50 (`--full` / `--incremental`
   mutually exclusive, `set_defaults(mode="incremental")` at line 46); `select_changed` at 210-230
   and its `if mode == "full" or cur != cache.get(f, "")` test at line 226; the metadata write at
   813-815; `log(msg, quiet=False)` at 59-62.
2. [ ] Add a module-level constant near the top, with a comment stating the rule that governs it:
   `EXTRACTION_VERSION = 2` — **bump this whenever extraction SEMANTICS change**, i.e. whenever the
   same input file would now produce a different record. Renaming a variable does not count;
   changing which value lands in `type` or `as` does. v4's Tasks 1 and 2 are exactly such a change,
   which is why the constant lands at 2 rather than 1.
3. [ ] Before mode selection, read the existing `graph.json`'s `metadata.extraction_version`
   (absent → treat as `0`). If it differs from `EXTRACTION_VERSION` **and** `mode == "incremental"`,
   promote to `"full"` **once** and write the reason to stderr through `log(...)`, naming both
   versions. Wrap the read in `try/except` — a missing, unreadable, or malformed `graph.json` must
   promote to `full` (the safe direction), never crash the builder.
4. [ ] Emit `"extraction_version": EXTRACTION_VERSION` alongside `schema_version` and `generator`
   (near line 813-815), so the *next* run can compare against it. **Corrected during v4
   implementation:** this task's prose and grill D4 both said "`metadata.extraction_version`", but
   **`graph.json` has no `metadata` wrapper** — `schema_version`, `generator`, `generated_at`,
   `stats`, `validation` are all *top-level* keys (verified: `jq 'has("metadata")'` → `false`).
   The field is therefore top-level too, matching the existing shape, and every verification
   command below reads `.extraction_version`, **not** `.metadata.extraction_version`. The promotion in
   step 3 is therefore self-clearing: the run that promotes also writes the new value, and the run
   after it is incremental again.
5. [ ] Do **not** couple this to `schema_version`. They answer different questions:
   `schema_version` = "does the *shape* differ", `extraction_version` = "does the *meaning of the
   values* differ". This plan changes the second without changing the first, which is precisely why
   `schema_version` alone could not have caught it.
6. [ ] Do not make a mismatch fatal and do not skip any post-write module — the promotion is the
   entire remedy.
7. [ ] Document `metadata.extraction_version` in `schema.json` and bump the **minor**
   `schema_version` per the rule at `schema.json:12` ("Increment minor on additive changes"), since
   an optional property is added.

**Verification:** **(a) harness assertion** (Task 8) plus **(b) manual**:
```bash
# 1. Fresh full build writes the new field
python3 .claude/graph/graph-builder.py --full --skip-mcp
jq '.metadata.extraction_version' .claude/graph/graph.json      # -> 2

# 2. An incremental run on a matching version stays incremental (no promotion line)
python3 .claude/graph/graph-builder.py --incremental 2>&1 | grep -i "extraction_version"
# expected: no output

# 3. Simulate a stale graph: force the stored version backwards, then run --incremental
jq '.metadata.extraction_version = 1' .claude/graph/graph.json > /tmp/g && mv /tmp/g .claude/graph/graph.json
python3 .claude/graph/graph-builder.py --incremental 2>&1 | grep -i "extraction_version"
# expected: a stderr line naming 1 -> 2 and stating the run was promoted to --full
jq '.metadata.extraction_version' .claude/graph/graph.json      # -> 2 again (self-clearing)

# 4. Missing metadata must promote, not crash
jq 'del(.metadata.extraction_version)' .claude/graph/graph.json > /tmp/g && mv /tmp/g .claude/graph/graph.json
python3 .claude/graph/graph-builder.py --incremental 2>&1 | grep -i "extraction_version"   # promotes
```

**Code Skeleton:**
```python
# module level, near the other constants
# Bump ONLY when extraction SEMANTICS change — i.e. when the same input file would now
# produce a different record. v4 Tasks 1+2 change which value lands in `type`/`as`, so: 2.
# This is deliberately NOT schema_version: the SHAPE is unchanged, the MEANING is not.
EXTRACTION_VERSION = 2

def _stored_extraction_version(output_path):
    try:
        with open(output_path, "r", encoding="utf-8") as fh:
            return int(json.load(fh).get("metadata", {}).get("extraction_version", 0))
    except Exception:
        return 0        # missing/unreadable/malformed -> promote (the safe direction)

# in main(), immediately after argparse resolves `mode`:
if mode == "incremental":
    stored = _stored_extraction_version(output_path)
    if stored != EXTRACTION_VERSION:
        log(f"extraction_version mismatch (graph={stored}, builder={EXTRACTION_VERSION}) — "
            f"promoting this --incremental run to --full once so stale records are re-extracted",
            quiet)
        mode = "full"

# in the metadata dict (near lines 813-815), alongside schema_version/generator:
"extraction_version": EXTRACTION_VERSION,
```

**Acceptance Criteria:**
- A `--full` build writes `metadata.extraction_version == EXTRACTION_VERSION`.
- An `--incremental` run against a graph whose stored version matches is **not** promoted and logs
  nothing.
- An `--incremental` run against a graph with a differing, absent, or malformed
  `extraction_version` is promoted to `--full` exactly once, logs the reason to stderr naming both
  versions, and the resulting graph carries the new value (self-clearing — the next run is
  incremental again).
- A missing or corrupt `graph.json` promotes to `--full` and does not raise.
- The promotion writes to stderr via `log(...)`, so `--quiet` suppresses it.
- Exit code and `graph.json` shape are otherwise unchanged; nothing is skipped on mismatch.
- `schema.json` documents `metadata.extraction_version`, is still valid JSON, and its
  `schema_version` **minor** is bumped per the rule at `schema.json:12`.
- `EXTRACTION_VERSION` is read from the existing graph by the builder — i.e. unlike `generator` and
  `schema_version`, it is not write-only.

---

## Task 8 — Harness Assertions

**Sequential last among edits** — writes `verify-graphify.sh` and asserts behaviour from Tasks 1, 2, 5, 6, 10. *(v4: the Task 7 scope-parent assertions are removed with Task 7 itself; a Task 10 `EXTRACTION_VERSION` assertion takes their place.)*

**Files:**
- `.claude/graph/test/verify-graphify.sh` (new assertions only)

**Steps:**
1. [ ] Re-read `.claude/graph/test/verify-graphify.sh`: the header conventions (lines 1-80 — `SCRIPT_DIR`, `REPO_ROOT`, `UNITY_CONCRETES`, `UNITY_HAS_CS`, `sha_of`, `section`, `jq_count`, `check_prerequisites`), the sourced helpers `pass`/`fail`/`known_fail`/`assert_eq`/`assert_jq` from `.claude/graph/test/lib/assert.sh` (lines 5-29), the `.work/` sandbox convention used by the collapse-guard tests near the end of the file, and the `# Main pipeline` block at the very bottom that calls each `run_*` function in order.
2. [ ] Add a new `run_registration_semantics_tests()` function. Write a probe `.cs` into `$SCRIPT_DIR/.work/` covering **five** registration forms — interface + `new`, interface + field, plain generic, plain generic **with an `.As<T>()` chain**, and unresolvable — run **both** extractors against it, and assert with `assert_jq`: no `type` is the interface when a concrete exists; `as` carries the interface; **every `as` is a JSON string** (`map(type) | unique == ["string"]`); the `{type, as}` multisets from the two extractors are identical (the parity gate from Task 2). The `.As<T>()` chain is mandatory in the probe — and note that the parity assertion over that record is satisfiable **only** because Task 1 step 4 added `_as_chain` to the tree-sitter extractor; before that change the tree-sitter side emits `as: ""` there and this assertion is unpassable by construction. If Task 1's chain reader was not implemented, this assertion must be reported as a `fail`, not softened.
3. [ ] Add `run_validator_interface_tests()`: construct a minimal graph fixture with (i) an `interface_only: true` registration naming an interface, (ii) a plain registration naming a genuinely absent class, and (iii) a plain `Register<T>`-shaped record `{"type":"UnknownClass","as":"","lifetime":""}` with **no** `interface_only`. Assert `graph_validate.py` emits **no** `INSTALLER_MISSING_CLASS` for (i) and **does** emit one for both (ii) and (iii). Case (iii) is the guard-not-too-loose assertion and is the most important test in this task: it fails loudly if `interface_only` is ever set on ordinary `Register<T>` registrations, which would silently disable the check project-wide.
4. [ ] Add `run_reconciliation_tests()`: (i) on a healthy `--full --skip-mcp` build into `.work/`, assert stderr contains no `GRAPH_DISK_MISMATCH`; (ii) drop a class node from a copy of the graph, re-run the check, assert the warning fires **and** exit code is `0`. Gate (i) on `UNITY_HAS_CS=1` and `known_fail` on template/empty repos, matching how the existing builder tests degrade (the template repo has no `Assets/` C# to reconcile).
5. [ ] Add `run_extraction_version_tests()` (replaces v3's `run_scope_parent_tests`, which died with Task 7): in the `.work/` sandbox, build a graph, then (i) assert `metadata.extraction_version` equals the builder's `EXTRACTION_VERSION`; (ii) rewrite the stored value to `EXTRACTION_VERSION - 1`, re-run `--incremental`, and assert stderr names the promotion **and** the resulting graph carries the new value again (self-clearing); (iii) delete the key entirely and assert the run promotes rather than raising. Gate on `UNITY_HAS_CS` the same way the other builder tests do.
6. [ ] Register all four functions in the `# Main pipeline` block at the bottom, appended after `run_viz_smoke_tests` and before `emit_report`.
7. [ ] Use `known_fail` (not `fail`) for anything that cannot run in the given environment — tree-sitter absent, no Unity C# present — so the harness stays green on the bare template repo while still reporting the gap. Follow the existing precedent of `UNITY_HAS_CS` gating. Do **not** use `known_fail` to paper over a missing implementation (see step 2).
8. [ ] Clean up `.work/` probe files the way the existing tests do (`rm -rf` of the sandbox dir), and never write probes outside `$SCRIPT_DIR/.work/`.
9. [ ] **Update the pinned `schema_version` assertion at `verify-graphify.sh:577`** — discovered
   during v4 implementation, and it is currently making the tree RED. That line asserts the literal
   `[[ "$sv" == "1.3.0" ]]`, so Task 10 step 7's *required* minor bump to `1.4.0` turns it into a
   `FAIL` (harness went 31/0 → 30/1). This is a real seam the plan did not anticipate: any task that
   bumps `schema_version` must land a matching harness update, and Task 8 is the task that owns this
   file. Fix by asserting the current version rather than re-pinning a literal that will rot again —
   read the expected value from `schema.json` (or assert `>= 1.4.0`), so the next additive bump does
   not re-break it. Record the before/after harness counts.
10. [ ] Do not modify lines 261, 430, or 547 — the two assertion message strings and the comment that mention `graph-builder.sh` are historical and are excluded from Task 3's sweep by design.

**Verification:** **(a) harness assertion** — this task *is* the harness work; it is verified by running it:
```bash
bash .claude/graph/test/verify-graphify.sh
bash .claude/graph/test/verify-graphify.sh --json | jq '{pass, fail, known_fail}'
```
Expected: exit 0, `fail == 0`, and the pass count increased by the number of new assertions relative to the pre-task baseline (record both numbers). Additionally confirm the new tests actually bite by temporarily reverting Task 1 in a scratch checkout and observing the registration-semantics assertions turn red — a test that passes against the unfixed code is worthless. Do the same for two specific assertions: the `as`-is-a-string assertion against unmodified `csharp-extractor.sh` (which emits a list for a multi-`.As<T>()` chain) must fail before Task 2 and pass after; and the validator case (iii) against an over-broad `interface_only` (set it on a `Register<T>` record by hand) must fail.

**Code Skeleton:**
```bash
run_registration_semantics_tests() {
  section "Registration semantics (Defect 1)"
  local work="$SCRIPT_DIR/.work/reg"; mkdir -p "$work"
  cat > "$work/ProbeModule.cs" <<'CS'
public class ProbeModule {
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
  py=$(python3 "$GRAPH_DIR/extractors/csharp_extractor.py" --changed-files "$work/ProbeModule.cs" 2>/dev/null)
  if [[ -z "$py" ]]; then known_fail "reg.1: tree-sitter unavailable — python extractor skipped"; else
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
  sh=$(bash "$GRAPH_DIR/extractors/csharp-extractor.sh" --changed-files "$work/ProbeModule.cs" 2>/dev/null)
  # reg.2: same interface-as-concrete assertion on the fallback
  # reg.3: `as` is always a string in BOTH outputs:
  #        jq -e '[.vcontainer.installers[].registrations[].as] | map(type) | unique == ["string"]'
  # reg.4: parity — sorted {type,as} multisets must be equal, INCLUDING the .As<T>() records,
  #        but scoped to records where a type was actually RESOLVED on that side:
  #          jq '[.vcontainer.installers[].registrations[]
  #               | select(.type != "") | {type, as}] | sort'
  #        run on both outputs and diffed; the diff must be empty.
  #        WHY the select() is not a weakening: `builder.RegisterInstance(SomeStatic.Opaque())`
  #        is representable by only ONE side. Tree-sitter emits {"type":"", …, unresolved:true}
  #        (Task 1 step 7 — "never skip"), while the fallback's Form 2 regex
  #        `builder\.RegisterInstance\(([A-Za-z0-9_\.]+)\)` (csharp-extractor.sh:384) cannot match
  #        an argument containing `()` and emits nothing at all. An unfiltered multiset compare is
  #        therefore unsatisfiable by construction, not by a missing fix. Task 2 deliberately does
  #        NOT add a pattern for this shape: that path is already LOW CONFIDENCE, and inventing a
  #        record for an argument nobody can resolve buys no fidelity. The asymmetry is pinned by
  #        reg.6 instead of being hidden by it.
  # reg.5: no Register<T> record carries interface_only (guards Task 5's blast radius):
  #        jq -e '[.vcontainer.installers[].registrations[]
  #                | select(.type=="Bar" or .type=="Baz") | .interface_only] | unique == [null]'
  # reg.6: the unresolvable form is asserted per-extractor, never as parity —
  #        tree-sitter MUST emit exactly one unresolved record:
  #          jq -e '[.vcontainer.installers[].registrations[]
  #                  | select(.unresolved == true)] | length == 1'
  #        the fallback MUST emit no record whose type is "" (it emits nothing for this shape):
  #          jq -e '[.vcontainer.installers[].registrations[]
  #                  | select(.type == "")] | length == 0'
  #        If either side's behaviour on this shape ever changes, reg.6 fails and the divergence
  #        is re-decided deliberately — which is the outcome reg.4's select() must not swallow.
  rm -rf "$work"
}
# ... run_validator_interface_tests, run_reconciliation_tests, run_extraction_version_tests ...
# appended to the Main pipeline block
```

**Acceptance Criteria:**
- `bash .claude/graph/test/verify-graphify.sh` exits 0 with `fail == 0` on the template repo.
- The registration probe contains at least one `.As<T>()` chain, and the parity assertion covers that record. That assertion presupposes Task 1's `_as_chain`; it is not weakened or exempted.
- The parity assertion (reg.4) compares only records where that extractor resolved a type (`select(.type != "")`). The one shape only one side can represent — non-generic `RegisterInstance` with an unresolvable argument — is asserted per-extractor by reg.6, so the asymmetry is pinned rather than exempted. reg.4 without the `select()` is unsatisfiable by construction (`csharp-extractor.sh:384` cannot match an argument containing `()`), and reg.6 must fail if either side's behaviour on that shape changes.
- An assertion exists that fails if either extractor emits a non-string `as`.
- An assertion exists that fails if a `Register<T>`-shaped record carries `interface_only`, and a validator assertion exists that fails if `INSTALLER_MISSING_CLASS` stops firing for a plain `Register<UnknownClass>` record.
- Each of Tasks 1, 2, 5, 6, 10 has at least one dedicated assertion that fails when that task's change is reverted (demonstrated, not assumed). No assertion references scope-parent extraction — that capability is not in this plan.
- Lines 261, 430, 547 and `test/README.md:58` are unmodified.
- Environment-dependent tests use `known_fail`, never `fail`; missing implementations use `fail`, never `known_fail`.
- No probe file is written outside `$SCRIPT_DIR/.work/`, and the sandbox is removed on completion.

---

## Task 9 — Propagate Changed Files to `piggy-doku-repo` and Re-Verify

**Sequential last — depends on Tasks 1 through 8 and Task 10.**

> **⏸ DEFERRED 2026-08-19 by the user** — piggy-doku is being updated separately in another
> session, so propagating into it now risks a collision. Everything this task depends on is done
> and green in the template. **The pre-copy diff gate (step 1) was already run read-only on
> 2026-08-19 and came back fully clean:** all four core tooling files *plus* the four `.md` files,
> `schema.json` and `verify-graphify.sh` are byte-identical between the two repos at our `HEAD`, so
> a later copy destroys nothing — re-run it anyway when the task resumes, since the premise decays.
> **Task 10 removes the urgency:** whenever these files do land in piggy-doku, its next build sees
> the `extraction_version` mismatch and promotes itself to `--full` once, automatically. No
> remembered manual step is owed.

**v4 scope change (grill D5): this task is PROPAGATION, not the plan's verification round.** In v3
it was the only real-corpus check in the whole plan and it ran *after* Tasks 1-8 were already
marked done — so every earlier assertion rested on synthetic probes written against the same
assumptions as the fix. Checkpoint C1 now owns the "does this work on real code" question and runs
before group B. What remains here is: propagate the files, rebuild, and confirm the originating
symptom is gone in situ. The re-verification below is a **confirmation** of an already-validated
change, not its first contact with reality.

**Files:** all files modified by Tasks 1-6, 8 and 10, copied from `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo` to `/Users/berkterek/Desktop/Github/piggy-doku-repo`.

**Steps:**
1. [ ] Before copying, re-establish the premise that made copying safe: all four core tooling files were verified byte-identical between the two repos today. Re-verify **immediately before** the copy, because the premise decays:
   ```bash
   for f in .claude/graph/extractors/csharp_extractor.py \
            .claude/graph/extractors/csharp-extractor.sh \
            .claude/graph/graph_validate.py \
            .claude/graph/graph-builder.py; do
     diff -q "$T/$f" "$P/$f" || echo "DIVERGED: $f"
   done
   ```
   using `T`/`P` for the two repo roots. Any `DIVERGED` line stops the task — resolve by hand-porting that file's hunks, never by blind overwrite.
2. [ ] Enumerate the exact copy set from `git diff --name-only` in the template repo rather than from this plan's File Map, so a file touched during implementation but not planned is not forgotten.
3. [ ] Treat the doc/command files (`.claude/commands/*.md`, `.claude/graph/*.md`) with the same diff-first check. **`[BLOCKED]` cleared in v4 (grill, required edit 6) — measured, not assumed:** every `.md` in the copy set **and** `schema.json` are byte-identical between the two repos; the only file that differs is `.claude/graph/.gitignore`, by exactly one line, which is Task 4's own subject (and step 4 below already skips it). So no hand-porting is expected. Still run the diff immediately before copying rather than trusting this measurement — it was taken on 2026-08-18 and decays like any other; a `DIVERGED` line stops the task exactly as in step 1.
4. [ ] `.claude/graph/.gitignore` (Task 4) needs **no** copy — the point of that task was to match piggy-doku's existing content. Diff to confirm they are now identical and skip.
5. [ ] Copy the verified-identical files. Do not copy `.claude/graph/graph.json`, `graph.json.bak`, `cache/*`, or `.last-build` — those are per-project generated artifacts.
6. [ ] In piggy-doku, run a full rebuild so the new extractor logic regenerates the graph: `python3 .claude/graph/graph-builder.py --full --skip-mcp`. A full build is required, not incremental, because the registration records for unchanged files must be re-extracted under the new logic. **With Task 10 in place this is now belt-and-braces rather than the only safeguard** — an `--incremental` run here would detect the `EXTRACTION_VERSION` mismatch and promote itself to `--full` anyway. Run `--full` explicitly regardless, and additionally verify the promotion path works *in this repo* by checking `jq '.metadata.extraction_version'` before and after. **The three repos this task does not touch (voxel-blast, worm-escape, nile-hole) are covered by Task 10, not by this task** — they self-heal on their next build.
7. [ ] Re-run validation and the harness in piggy-doku; confirm the specific originating symptom is gone, confirm **both** halves of the live `as`-consumer behaviour change declared in `## Chosen Approach` decision 1, and spot-check that `INSTALLER_MISSING_CLASS` is still capable of firing (the `interface_only` count from Task 5 step 5 must be a small minority of all registrations).
8. [ ] Record in the completion note: the diff-check result from step 1, the piggy-doku harness pass/fail counts, the before/after `GridModule` validation output, the `interface_only` share of all registrations, and the before/after output of both `registrations` queries from step 7.

**Verification:** **(b) manual commands**, run in `/Users/berkterek/Desktop/Github/piggy-doku-repo`:
```bash
python3 .claude/graph/graph-builder.py --full --skip-mcp
python3 .claude/graph/graph_validate.py --graph .claude/graph/graph.json 2>&1 | grep INSTALLER_MISSING_CLASS

# the interface_only blast radius must stay small (Task 5 step 5)
jq '{interface_only: [.codebase.vcontainer.installers[].registrations[] | select(.interface_only == true)] | length,
     total: [.codebase.vcontainer.installers[].registrations[]] | length}' .claude/graph/graph.json

# the live `as` consumer — knowledge-graph.md:138-139 — must resolve BOTH names
jq --arg name "TapResolver" '
  .codebase.vcontainer.installers[]
  | select(.registrations[]? | .type == $name or .as == $name)
  | {installer: .name, registrations: [.registrations[] | select(.type == $name or .as == $name)]}
' .claude/graph/graph.json
jq --arg name "ITapResolver" '
  .codebase.vcontainer.installers[]
  | select(.registrations[]? | .type == $name or .as == $name)
  | {installer: .name, registrations: [.registrations[] | select(.type == $name or .as == $name)]}
' .claude/graph/graph.json

bash .claude/graph/test/verify-graphify.sh
```
Expected: build exits 0 with no `GRAPH_DISK_MISMATCH` warning; the validator `grep` produces **no** line naming `ITapResolver` or any other interface on `GridModule` (the originating false positive, module 04); `interface_only` is a small fraction of `total`, not equal to it; **both** `jq` queries return the same single `GridModule` registration — `TapResolver` matching via `.type` (today it returns nothing) and `ITapResolver` matching via `.as` (today it matches via `.type`, which is the wrong-data path being fixed); harness exits 0 with `fail == 0`.

**Code Skeleton:** No code. Copy procedure only:
```bash
T=/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
P=/Users/berkterek/Desktop/Github/piggy-doku-repo
# 1. diff-gate every file in the copy set (abort on divergence)
# 2. cp -p "$T/<file>" "$P/<file>" for each verified-identical file
# 3. full rebuild + validate + harness in $P
```

**Acceptance Criteria:**
- The pre-copy diff gate ran and is recorded; no file was overwritten while diverged.
- No generated artifact (`graph.json`, `graph.json.bak`, `cache/*`, `.last-build`) was copied.
- Full rebuild in piggy-doku exits 0 with no `GRAPH_DISK_MISMATCH`.
- No `INSTALLER_MISSING_CLASS` names an interface; the `GridModule` / module-04 false positive is gone.
- `INSTALLER_MISSING_CLASS` is still live: the `interface_only` registration count is a small minority of the total, so the check was narrowed rather than disabled.
- `/knowledge-graph registrations TapResolver` returns the registration (via `.type`).
- `/knowledge-graph registrations ITapResolver` also returns the same registration (via `.as`) — the declared, benign behaviour change to the live consumer at `.claude/commands/knowledge-graph.md:138-139`.
- `bash .claude/graph/test/verify-graphify.sh` exits 0 with `fail == 0` in piggy-doku.
- The two repos' four core tooling files are byte-identical again after the copy.

---

## Out of Scope

### Removed from this plan in v4 (grill) — real gaps, deliberately deferred

- **`ParentReference.Create<T>()` scope-parent extraction (was Task 7, grill D1).** Deferred to an
  ADR because a fix here would silently reverse the recorded *Limitation 18*, whose factual half is
  itself now partly false. **Cost accepted:** `/knowledge-graph scope-tree` keeps listing
  `GameScope` as a root. **Owed:** an ADR deciding (a) whether Limitation 18's factual half is
  amended, (b) whether code-declared parents may be read from source, (c) if so, whether the regex
  fallback may participate. Full reasoning in the `## Task 7 — REMOVED` stub above.
- **Resolving `.AsImplementedInterfaces()` to real interface names (grill D3).** The dominant idiom
  in this project stays unresolvable by interface name; `as` holds a placeholder string. Needs a new
  array key + `schema.json` change + query change — a capability, not a defect fix. The graph
  already carries the per-class `implements` data this would build on. Declared in the Goals so the
  gap is documented rather than discovered.
- **Adding `enums`/`structs` as graph node kinds (grill D2).** Would make Task 6's naive comparison
  correct *and* close a real query gap (`/knowledge-graph` cannot answer "where is `CellState`
  declared"). Same reason as above: extractor capability, not defect fix.

### Verified already correct — no task

- `.claude/graph/cache/mcp-extract.json` in piggy-doku is already ignored (`git check-ignore -v` → `.claude/graph/.gitignore:4:cache/mcp-extract.json`).
- `docs/.idea` in piggy-doku is already ignored (`.gitignore:119:**/.idea/`).
- Neither is untracked-and-leaking, and `core.excludesfile` is unset, so this does not depend on the developer's machine.
- **`lifetime` enum conformance.** `schema.json:178` restricts `lifetime` to `["Singleton","Scoped","Transient"]`, but the tree-sitter extractor emits `""` (`csharp_extractor.py:413`) and Task 1 carries that forward unchanged. Knowingly out of scope: fixing it means reading `Lifetime.X` from the argument list in **both** extractors to keep the record shape identical, which is a separate capability with its own probe. This plan claims conformance only for `as`.
- Root cause of Defect 0 — unreproducible; `cache/file-hashes.json` was overwritten by the `--full` run that destroyed the evidence. Task 6 installs detection, not a diagnosis. If `GRAPH_DISK_MISMATCH` fires in the wild, capture `cache/file-hashes.json` **before** rebuilding and open a follow-up with that snapshot attached.
- `metadata.generator` values in existing `graph.json` / `graph.json.bak` that literally read `graph-builder.sh@<sha>` — regenerated on the next build; nothing validates the string (only write site is `graph-builder.py:815`, which already emits `graph-builder.py@<sha>`).
- `.claude/state/subagent-log.jsonl:49-50` — append-only run history mentioning `graph-builder.sh`; not an instruction to run anything and not part of the census.
- Historical plan documents under `docs/archive/**` and `docs/PLAN_graph_*.md` that mention `graph-builder.sh` — accurate records of the era in which that file existed. `docs/plans/graph-incremental-purge-fix.md` is likewise unmodified, but Task 6 step 3 depends on its line 5 as the binding path-normalisation convention.

### Critical Files for Implementation
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/extractors/csharp_extractor.py
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/extractors/csharp-extractor.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/graph-builder.py
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/graph_validate.py
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/graph/test/verify-graphify.sh
