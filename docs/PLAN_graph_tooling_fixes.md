# PLAN — Knowledge-Graph Tooling Defect Fixes (`.claude/graph/`)

## Complexity Assessment

**Score: 0.72 — Medium** (0.65 in v1 → 0.70 in v2 → 0.72 here)

| Signal | Effect |
|---|---|
| Defect 1 spans two parallel extractor implementations (`csharp_extractor.py` tree-sitter + `csharp-extractor.sh` regex fallback) that must stay behaviourally in sync | +0.20 |
| The `as` key is *not* dead: `.claude/commands/knowledge-graph.md:138-139` reads it, and `csharp-extractor.sh` currently emits it as a **list** in violation of `schema.json:177` (`"as": {"type":"string"}`). Task 2 therefore also has to normalise a value type across a live consumer, not merely add patterns | +0.05 |
| **NEW —** the tree-sitter extractor cannot read a `.As<T>()` chain at all (`_detect_member`, lines 409-417, never looks past the single invocation), so the PRIMARY extractor must gain an invocation-chain walk before any parity gate can pass | +0.02 |
| Defect 0 adds a new post-write warning path to the build orchestrator (new stderr channel usage, `--quiet` honouring, non-fatal semantics) | +0.15 |
| Defect 2 requires a genuinely new extraction capability (method-body `ParentReference.Create<T>()` detection) in both extractors + a merge-precedence decision | +0.20 |
| Defect 3 is mechanical prose/schema string replacement with an explicit do-not-touch list | +0.05 |
| No new module folder, no Unity runtime code, no VContainer registration/scene/prefab wiring, no asmdef changes | −0.10 |
| Existing harness (`verify-graphify.sh` + `lib/assert.sh`) already provides `pass`/`fail`/`known_fail`/`assert_jq`; no test infrastructure to build | −0.05 |

**Why the score moved, and by how little:** v2 already absorbed the corrected `as`-consumer premise (+0.05 over v1). This revision adds one genuinely new extraction capability to the tree-sitter side — reading the `.As<T>()` / `.AsImplementedInterfaces()` chain — because without it the parity gate the plan itself demands is unsatisfiable. It is only **+0.02** because it reuses helpers that already exist and are already correct for this shape (`_member_name_and_typearg` at line 353 returns `(method, type_arg)` for exactly the `As<T>` node form; `_walk` at line 29; `_type_name` at line 337), and because it walks *upward* through `node.parent` rather than introducing any new traversal concept. Still Medium; still one architecture, no new subsystem. Medium ⇒ two approaches proposed, one chosen and justified in `## Chosen Approach`.

---

> **Version:** v3 — 2026-08-18 (revised after second review: `interface_only` narrowed to the `RegisterInstance`-only, concrete-unresolvable case; `.As<T>()` chain reading added to the tree-sitter extractor so the parity gate is satisfiable; Task 7's search window fixed to slice from the class-declaration line; validator block re-cited as 93-118; `schema.json:12` semver rule and the `lifetime` enum non-conformance both stated correctly. Then, after the third review: Task 8's reg.4 parity compare scoped to resolved-type records with the asymmetric `RegisterInstance(SomeStatic.Opaque())` shape pinned by a new per-extractor reg.6 instead of an unsatisfiable multiset compare; Task 2's `FIELD_TYPES` comprehension inverted to key by field name, which the Form 1c lookup requires.)
> **Status:** Active
> **Scope:** `.claude/graph/extractors/csharp_extractor.py`, `.claude/graph/extractors/csharp-extractor.sh`, `.claude/graph/graph_validate.py`, `.claude/graph/graph-builder.py`, `.claude/graph/schema.json`, `.claude/graph/.gitignore`, `.claude/graph/test/verify-graphify.sh`, `.claude/commands/build-knowledge-graph.md`, `.claude/commands/setup-project.md`, `.claude/graph/extractors/mcp-extractor.md`, `.claude/graph/codex-validator.md`. **Python + bash tooling only — nothing under `Assets/` is touched.** No Unity C#, no scenes, no prefabs, no asmdefs.

---

## Context

The knowledge graph under `.claude/graph/` is declared the PRIMARY source of truth for codebase questions by `.claude/CLAUDE.md`, yet four defects currently make it emit wrong data, hide real data, or instruct agents to run a file that does not exist. The most damaging is Defect 1: in `csharp_extractor.py:409-417` (`_detect_member`) the generic type argument wins unconditionally (`t = type_arg` at line 410, `"as": ""` at line 413), so `builder.RegisterInstance<ITapResolver>(new TapResolver(...))` is recorded as `{"type": "ITapResolver"}` and the concrete `TapResolver` is discarded. That is not a cosmetic loss — `graph_validate.py` assigns the flagged name at **line 104** (`reg.get("class","") or reg.get("type","")`) and tests it against `class_names` at **line 105** (`class_names` built at line 52 from `codebase.classes` only; line 110 is the `detail` f-string, not the membership test), and emits a **false** `INSTALLER_MISSING_CLASS` for the interface (observed on `GridModule` in piggy-doku module 04), while `/knowledge-graph registrations TapResolver` returns nothing because the graph believes the interface is the registered class.

A second, quieter half of Defect 1 surfaced during review: `_detect_member` also never reads a `.As<T>()` chain. For `builder.Register<Bar>(Lifetime.Singleton).As<IBar>()` the tree-sitter extractor emits `{"type":"Bar","as":""}` while the shell fallback emits `{"type":"Bar","as":"IBar"}` (`csharp-extractor.sh:375-377`). Since `as` is the very key this plan makes load-bearing, and since the PRIMARY extractor is the one that loses the information, Task 1 closes that too (see `## Chosen Approach` decision 5).

Defect 0 is a trust problem with no reproducible root cause left: `_Framework/SaveLoadSystems/LocalSaveLoadDal.cs` and `_Framework/Editors/LogDumpOnStop.cs` existed on disk but were absent from the graph until a `--full` rebuild added them — and that `--full` run overwrote `cache/file-hashes.json`, destroying the evidence. There is currently **no reconciliation anywhere** between the files walked on disk and the files represented in the written graph, so a silent omission is undetectable until a human notices a query lying. This plan therefore does not hunt the root cause it cannot reproduce; it installs a detection net at the single write point (`graph-builder.py:1138`) so the next occurrence announces itself.

Defects 3 and 2 are respectively the cheapest and the most expensive. Defect 3 is stale prose: `graph-builder.sh` no longer exists, but **nine live locations** still tell a human or an agent to run it — verified with `grep -rn "graph-builder\.sh" .claude/`, excluding the six do-not-touch occurrences and the append-only `state/subagent-log.jsonl` history entry: `build-knowledge-graph.md:23,66,82` (×3), `setup-project.md:162` (×1), `mcp-extractor.md:249` (×1), `codex-validator.md:49,69` (×2), `schema.json:5,21` (×2) = 9. That set is exactly Task 3's file list, so Task 3 step 1's census check is satisfiable. Among them is a Step 0 preflight gate at `build-knowledge-graph.md:23` that would make an agent *stop* on a healthy repo. Defect 2 is a real capability gap: `GameScope` sets its parent in code via `ParentReference.Create<AppScope>()`, and neither extractor looks inside method bodies for that, so `/knowledge-graph scope-tree` misreports `GameScope` as a root while a PlayMode test proved `GameScope.Parent == AppScope` at runtime. That is a graph limitation, not an architecture defect, and it is materially larger than the other three.

---

## Goals

- [ ] `RegisterInstance<IFoo>(new Foo(...))` and `RegisterInstance<IFoo>(_fooField)` record the **concrete** class, with the interface preserved in the `as` field, in *both* extractors.
- [ ] The false `INSTALLER_MISSING_CLASS` on interfaces disappears without weakening detection of genuinely missing classes — in particular, a plain `Register<UnknownClass>(Lifetime.Singleton)` must still be flagged.
- [ ] Tree-sitter and regex-fallback extractors produce the same registration shape *and the same value types* for the same input, so graph content does not depend on whether `tree_sitter` happens to be installed. This includes `.As<T>()`-chained registrations.
- [ ] `as` is always a **string**, matching `schema.json:177`, so the live `/knowledge-graph registrations` query (`.as == $name`) can actually match it.
- [ ] Every build compares disk contents against graph contents and warns (stderr, non-fatal, `--quiet`-aware) with an explicit "run `--full`" recommendation on mismatch.
- [ ] Zero live references to `graph-builder.sh` remain; the six documented do-not-touch occurrences are untouched.
- [ ] `ParentReference.Create<XScope>()` in a scope's method body populates `scopeEntry.parent`, with MCP data still authoritative on conflict.
- [ ] Every task is verified by a harness assertion or a stated manual command with expected output — no task rests on "it looks right".
- [ ] All changed files are copied to `/Users/berkterek/Desktop/Github/piggy-doku-repo` and the harness passes there too.

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
   **Interaction with the `As` invocation itself:** `_walk` also hands `_detect_member` the outer `.As<IBar>()` invocation. `"As"` is not in `REG` (line 391) and not in `PUBSUB`, so it is already ignored and no duplicate record appears — verified against the current control flow, and pinned by Task 1's "record count per installer is unchanged" criterion.

**Known schema non-conformance, knowingly out of scope:** `schema.json:178` constrains `lifetime` to the enum `["Singleton","Scoped","Transient"]`, but `csharp_extractor.py:413` emits `"lifetime": ""` today and Task 1's rewrite keeps doing so. **Decision: note it, do not fix it here.** Reason: making the key conditional (omit when empty) changes the emitted key set on the tree-sitter side only, which breaks the record-shape parity with `csharp-extractor.sh` that Tasks 2 and 8 exist to enforce; fixing it properly means teaching the tree-sitter path to read `Lifetime.X` from the argument list in both extractors, which is a separate capability with its own probe and its own acceptance criteria. This plan claims conformance for `as` (which it changes) and explicitly does **not** claim it for `lifetime` (which it merely carries forward unchanged). Task 1 AC states this so no reader infers otherwise.

---

## Status

| Phase | Task | Status | parallel_group |
|---|---|---|---|
| 1 | Task 1 — Concrete-type precedence + `.As<T>()` chain in `csharp_extractor.py` (`_detect_member`) | ⏳ Pending | A |
| 1 | Task 2 — Parity fix in `csharp-extractor.sh` (Form 1 + Form 2 + `as` normalisation) | ⏳ Pending | A |
| 1 | Task 3 — Stale `graph-builder.sh` reference sweep (docs + schema) | ⏳ Pending | A |
| 1 | Task 4 — Nested `.claude/graph/.gitignore` self-sufficiency | ⏳ Pending | A |
| 2 | Task 5 — Narrow `graph_validate.py` guard on `interface_only` | ⏳ Pending | B |
| 2 | Task 6 — Disk-vs-graph reconciliation warning in `graph-builder.py` | ⏳ Pending | B |
| 3 | Task 7 — `ParentReference.Create<T>()` scope-parent extraction (both extractors + merge precedence) | ⏳ Pending | C |
| 4 | Task 8 — Harness assertions for Tasks 1/2/5/6/7 | ⏳ Pending | D |
| 5 | Task 9 — Copy changed files to `piggy-doku-repo` and re-verify | ⏳ Pending | E |

**parallel_group reasoning** (structure unchanged by this revision — no task's file set moved; the `.As<T>()` chain reader added to Task 1 lands in `csharp_extractor.py`, which Task 1 already owned)
- **A** — four distinct file sets, no shared file, no shared key. Tasks 1 and 2 both introduce the same *concept* but touch different files and neither reads the other's output.
- **B** — sequential after A because Task 5's guard reads the `interface_only` key that Task 1 introduces, and Task 6's reconciliation must not be authored against a moving extractor. Tasks 5 and 6 touch different files (`graph_validate.py` vs `graph-builder.py`) and are mutually independent within B.
- **C** — Task 7 writes `csharp_extractor.py` and `csharp-extractor.sh` (same files as Tasks 1 and 2) and `graph-builder.py` (same file as Task 6), so it **must** be sequential after both A and B. Two tasks writing the same file are never parallel.
- **D** — Task 8 writes `verify-graphify.sh` and asserts on behaviour from Tasks 1, 2, 5, 6, 7; strictly last among edits.
- **E** — Task 9 copies files, so it depends on *every* preceding edit task.

---

## File Map

| File | Change Type | Notes |
|---|---|---|
| `.claude/graph/extractors/csharp_extractor.py` | Modify | Task 1 (`_detect_member`, lines 389-417, plus a new chain helper); Task 7 (scope emission near 580-583) |
| `.claude/graph/extractors/csharp-extractor.sh` | Modify | Task 2 (Form 1 at 360-380, Form 2 at 382-392, dedup at 394-401); Task 7 (`extract_scope`, 413-456) |
| `.claude/graph/graph_validate.py` | Modify | Task 5 — narrow guard at the `INSTALLER_MISSING_CLASS` block, lines **93-118** (93-94 are the section comment and counter init; name assigned at 104, membership tested at 105) |
| `.claude/graph/graph-builder.py` | Modify | Task 6 — new reconciliation after `atomic_write_json` (line 1138); Task 7 — `scope_merge` precedence (559-579) |
| `.claude/graph/schema.json` | Modify | Task 3 — `description` at line 5, `generator` description at line 21; Task 7 — document `parent` provenance on `scopeEntry` (185-193) |
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
7. [ ] Preserve the **precedence** of an explicit `.As<T>()` chain over a generic interface argument, which is now the rule on both sides (Task 1 step 6 implements the same order). **[BLOCKED — needs investigation]** if a single registration has both a generic interface arg *and* an explicit `.As<T>()` chain (`RegisterInstance<IFoo>(new Foo()).As<IBar>()`), which one belongs in `as` is a genuine product question and no such call site exists in either repo to arbitrate it. Keep the explicit chain winning (current behaviour, and now Task 1's behaviour too) and add a `# TODO(parity)` comment naming this case. Note this is only a question of *which string*, not of string-vs-list — step 3 settles the type unconditionally.
8. [ ] Re-check the dedup block ("Deduplicate by type (first occurrence wins)", lines 394-401). With `type` now holding concretes, two different interfaces backed by the same concrete would collapse into one record. Dedup on the `(type, as)` pair rather than `type` alone, so `RegisterInstance<IReader>(_store)` and `RegisterInstance<IWriter>(_store)` both survive. Because `as` is now always a string (step 3), the key needs no `json.dumps` wrapper. Note that Task 1's tree-sitter path has no dedup at all, so this change also reduces (does not create) divergence.
9. [ ] Keep the emitted key set identical to Task 1's: `type`, `as`, `lifetime`, plus optional `scope`, `inferred`, `interface_only`, `unresolved`, `confidence`.

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

**Sequential after Task 1/2** (group B). Touches `graph-builder.py`, which Task 7 also touches — so Task 7 must follow this.

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
4. [ ] Build `graph_cs_paths` as the distinct set of `norm(source_file)` (falling back to `file`) across the written graph's `codebase.classes`, plus interfaces/enums/structs if they carry file fields — the goal is "which .cs files does the graph represent", so union every node kind that names a source file. Build `disk_cs_paths` as `{norm(p) for p in full_cs if p}`.
5. [ ] Exclude from `disk_cs_paths` any path that legitimately contributes no node: files that exist but declare nothing the graph models. **[BLOCKED — needs investigation]** the false-positive rate here is genuinely empirical and cannot be reasoned out (e.g. a `.cs` containing only a namespace-level `delegate`, an attribute, or only `partial` continuations already attributed to another file). Measure it first: run the comparison on a healthy full build in both repos and read the resulting missing-set. If it is non-empty on a known-good graph, the warning must either subtract those categories or be gated behind a threshold — decide *after* measuring, not before.
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
Expected: step 1 silent (this is the false-positive gate — if it warns on a healthy repo, step 5's [BLOCKED] item is unresolved and the task is not done); step 2 prints a warning naming the removed file, recommends `--full`, and the process exit code is still `0`.

**Code Skeleton:**
```python
def norm(p):
    """Repo-root-relative, realpath-resolved — the convention fixed in 57c9340.
    See docs/plans/graph-incremental-purge-fix.md:5."""
    return os.path.relpath(os.path.realpath(p), os.path.realpath("."))

def reconcile_graph_with_disk(graph, disk_cs, quiet, limit=10):
    """Non-fatal net for silent omissions. Path SET comparison, not counts:
    a count check passes when one file drops and another is added.
    BOTH sides go through norm() — mixed path formats were the 57c9340 bug."""
    try:
        cb = graph.get("codebase", {})
        graph_paths = {
            norm(n.get("source_file") or n.get("file"))
            for kind in ("classes", "interfaces", "enums", "structs")
            for n in cb.get(kind, []) or []
            if (n.get("source_file") or n.get("file"))
        }
        disk_paths = {norm(p) for p in disk_cs if p}
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
- Silent on a healthy `--full` build in **both** repos (zero false positives — this is the gate, not a nice-to-have).
- Warns and names the offending paths when a `.cs` file on disk has no graph node.
- Both sides of the comparison are normalised through the single `norm()` helper; no raw path string is compared.
- Exit code, `graph.json` bytes, hash-cache update, and post-write module execution are all identical to before this task in every case.
- `--quiet` suppresses the warning (routed through `log`, not a bare `print`).
- An exception inside the reconciliation is caught and logged; the build still succeeds.
- The comparison is a set operation; no code path compares only lengths.

---

## Task 7 — `ParentReference.Create<T>()` Scope-Parent Extraction

**Sequential after Tasks 1, 2, and 6** — writes `csharp_extractor.py`, `csharp-extractor.sh`, and `graph-builder.py`, all of which earlier tasks modify. This is the largest task in the plan and is deliberately scoped narrowly.

**Files:**
- `.claude/graph/extractors/csharp_extractor.py` (scope entry emission, lines ~578-583)
- `.claude/graph/extractors/csharp-extractor.sh` (`extract_scope`, lines 413-456)
- `.claude/graph/graph-builder.py` (`scope_merge`, lines 559-579)
- `.claude/graph/schema.json` (`scopeEntry`, lines 185-193 — documentation only)

**Steps:**
1. [ ] Re-read all four sites. Confirm: `csharp_extractor.py:581` builds `entry = {"name": name, "file": path, "source_file": path, "registrations": registrations}` with **no** `parent` key and appends it to `scopes` when `"LifetimeScope" in base_types`; `csharp-extractor.sh:442` matches only `\[ParentScope\s*\(\s*typeof\s*\(\s*([A-Za-z0-9_]+Scope)\s*\)` and line 450 emits `"parent": parent` (which is `None` → JSON `null` when absent); `graph-builder.py:559-579` `scope_merge` overlays `mcp_scope_parents` (`{scope_name, parent_name}` pairs from `mcp-extractor.md:240-242`, sourced from Unity's serialized `scope.parentReference.TypeName` at `mcp-extractor.md:172`) onto merged scopes, unconditionally overwriting `s["parent"]`; `schema.json:185-193` already declares `"parent": {"type": "string"}`.
2. [ ] **Precedence decision, stated up front:** MCP (serialized `parentReference` read from the live Editor) > `[ParentScope(typeof(X))]` attribute > `ParentReference.Create<X>()` in code. MCP reflects actual runtime state and is the ground truth the PlayMode test agreed with; the code form is a static approximation that cannot see a parent assigned by a different code path or overridden in the Inspector. `scope_merge`'s existing unconditional overwrite already implements "MCP wins" — the new code-derived value must therefore be written *before* that overlay (i.e. by the extractor into `entry["parent"]`) so the overlay naturally supersedes it. No change to the overwrite itself.
3. [ ] In `csharp_extractor.py`, add a helper `_scope_parent(cls_node, src)` that walks the class body for an invocation whose function resolves to `ParentReference.Create` and returns its generic type argument. Reuse the existing machinery: `_walk(body, "invocation_expression")` (line 29), `_member_name_and_typearg(func, src)` (line 353, already used at line 404 and returns `(method, type_arg)`), and `_TYPE_NODES`/`_type_name` (line 337) for the type name. Only run it when `is_scope` is true (line 580) — no cost on ordinary classes.
4. [ ] Handle the realistic call shapes: `parentReference = ParentReference.Create<AppScope>();` (assignment in `Awake`), `ParentReference.Create<AppScope>()` as a plain expression statement, and the fully-qualified `VContainer.Unity.ParentReference.Create<AppScope>()`. Match on the *method name* `Create` plus a receiver whose text ends in `ParentReference` rather than on an exact receiver string, so the qualified form is not missed.
5. [ ] Set `entry["parent"] = parent` on the scope entry only when a name was found; when nothing is found, **omit the key** rather than writing `""` — the schema types `parent` as a string, and an empty string is indistinguishable from "genuinely rootless", which is exactly the ambiguity that made `GameScope` look like a root.
6. [ ] Add a provenance marker on the entry (`parent_source: "code" | "attribute" | "mcp"`) so `/knowledge-graph scope-tree` and `codex-validator` can tell a statically-inferred parent from an Editor-verified one. Set `"mcp"` in `scope_merge` when the overlay fires. **Schema question RESOLVED — no rejection risk:** `schema.json` declares `"additionalProperties": false` at only two places, lines 70 and 88; `scopeEntry` (185-193) declares none, so an extra key is accepted as-is. The one remaining check is the consumer half: read the `/knowledge-graph scope-tree` query before adding the key and confirm it projects named fields (`{name, parent, ...}`) rather than echoing whole objects into a fixed shape; if it projects, the marker is invisible to it and safe. Only drop the marker if that query would actually break.
7. [ ] In `csharp-extractor.sh`'s `extract_scope` heredoc, add a second regex tried **after** the existing `[ParentScope(...)]` match at line 442 and only when that produced nothing: `ParentReference\s*\.\s*Create\s*<\s*([A-Za-z0-9_\.]+)\s*>`. Take the last dot-separated segment as the short name (matching `mcp-extractor.md:172-175`, which shortens `Namespace.AppScope` to `AppScope`). Preserve the attribute form's precedence so the two extractors agree.
8. [ ] Note the fallback extractor's structural limit in a comment: `extract_scope` finds only the **first** `LifetimeScope` class per file (it `break`s at the first match) and scans the whole file text for the parent, so a file containing two scopes will mis-attribute. That pre-exists this task and is out of scope — but a `ParentReference.Create` scan over whole-file text makes the mis-attribution *more* likely to produce a wrong value rather than a null. Restrict the new regex's search window to the text from the matched class declaration onward, and record the residual risk. **Slice by line index, not by `m.start()`:** the loop at lines 429-430 matches `m` against `chunk = " ".join(lines[i:i+4])`, so `m.start()` is an offset into that throwaway 4-line join and has no meaning in `text` — using it would pick an arbitrary window. Record `class_line = i` when the class declaration matches and search `"\n".join(lines[class_line:])`.
9. [ ] In `graph-builder.py`'s `scope_merge`, add a **key-level merge** that preserves a known `parent` over a missing one, rather than letting `by_name[name] = s` (lines 565-568) replace the whole retained dict. **RESOLVED — this is not speculative.** `new_scopes` is read at line 1052 from `cs_output`, i.e. from the extraction over the changed-file set, so on an incremental run it contains only scopes whose files were re-extracted — and each such file is re-extracted in full, so the *code*-derived parent cannot be lost. The real loss case is provenance-crossed: a retained entry whose `parent` came from the **MCP overlay** is replaced by a freshly extracted entry that has no `parent`, on any run where MCP data is absent (`--skip-mcp`, or Unity not running). Today that silently drops a known parent. Fix it by carrying `parent`/`parent_source` forward from the retained entry when the new entry lacks them; the MCP overlay at lines 571-578 still runs afterwards and still wins when present.
10. [ ] Update `schema.json:185-193` `scopeEntry` — add a `description` to `parent` recording the three sources and their precedence, and add `parent_source` (step 6 resolves in favour of it unless the `scope-tree` query objects). Additive and optional; bump the **minor** `schema_version` per the schema's own rule, which is the `description` at **`schema.json:12`** ("Semver. Increment minor on additive changes, major on breaking changes." — line 10 is the `"type": "string"` line, not the rule), since a new documented property is added.

**Verification:** **(a) harness assertion** (Task 8) plus **(b) manual**:
```bash
# probe: a scope file setting its parent in code
# public class GameScope : LifetimeScope {
#     protected override void Awake() { parentReference = ParentReference.Create<AppScope>(); base.Awake(); } }
python3 .claude/graph/extractors/csharp_extractor.py --changed-files <GameScope.cs> \
  | jq '.vcontainer.scopes[] | {name, parent}'
bash .claude/graph/extractors/csharp-extractor.sh --changed-files <GameScope.cs> \
  | jq '.vcontainer.scopes[] | {name, parent}'
```
Expected from both: `{"name":"GameScope","parent":"AppScope"}`. Then, after a real build, `/knowledge-graph scope-tree` must show `GameScope` nested under `AppScope` rather than as a second root — record the before/after output in the task's completion note, since that user-visible symptom is the actual acceptance signal.

**Code Skeleton:**
```python
# csharp_extractor.py
def _scope_parent(cls_node, src):
    """`parentReference = ParentReference.Create<AppScope>()` inside the scope body.
    Returns the short type name, or None. Matches on method name + receiver suffix so
    the fully-qualified VContainer.Unity.ParentReference form is not missed."""
    body = cls_node.child_by_field_name("body")
    if not body:
        return None
    for inv in _walk(body, "invocation_expression"):
        func = inv.child_by_field_name("function")
        if not func or func.type != "member_access_expression":
            continue
        method, type_arg = _member_name_and_typearg(func, src)
        if method != "Create" or not type_arg:
            continue
        recv = _node_text(func.child_by_field_name("expression"), src) or ""
        if recv.split(".")[-1] == "ParentReference":
            return type_arg.split(".")[-1]
    return None

# at the scope-emission site (~line 580):
if is_scope:
    parent = _scope_parent(cls_node, src)
    if parent:
        entry["parent"] = parent
        entry["parent_source"] = "code"     # scopeEntry has no additionalProperties:false
    scopes.append(entry)
```
```python
# csharp-extractor.sh heredoc — record the class line in the existing loop (429-430):
for i, line in enumerate(lines):
    chunk = " ".join(lines[i:i+4])
    m = re.search(r'class\s+([A-Z][A-Za-z0-9_]*)\s*[:<][^{]*LifetimeScope', chunk)
    if m:
        scope_name = m.group(1)
        class_line = i          # NOTE: m.start() is an offset into `chunk`, NOT `text`
        break

# after the [ParentScope(...)] attempt (line 442):
if not parent:
    tail = "\n".join(lines[class_line:])     # from the class decl onward, not whole file
    cm = re.search(r'ParentReference\s*\.\s*Create\s*<\s*([A-Za-z0-9_\.]+)\s*>', tail)
    if cm:
        parent = cm.group(1).split(".")[-1]
```
```python
# graph-builder.py scope_merge (559-579): key-level merge so a re-extracted entry
# cannot drop an MCP-derived parent on a --skip-mcp run; MCP overlay still wins.
for s in new_scopes or []:
    name = s.get("name")
    if not name:
        continue
    prev = by_name.get(name)
    if prev and not s.get("parent") and prev.get("parent"):
        s["parent"] = prev["parent"]
        s["parent_source"] = prev.get("parent_source", "retained")
    by_name[name] = s
...
# MCP overlay unchanged (it must still win); only annotate provenance when it fires:
for s in scopes:
    if s.get("name") in parent_map:
        s["parent"] = parent_map[s["name"]]
        s["parent_source"] = "mcp"
```

**Acceptance Criteria:**
- Both extractors report `parent: "AppScope"` for a `GameScope` that sets its parent via `ParentReference.Create<AppScope>()`.
- The fallback's `ParentReference.Create` search window starts at the matched class-declaration **line**, derived from the loop index, not from `m.start()` (which indexes the 4-line `chunk`, not `text`).
- The `[ParentScope(typeof(X))]` attribute form still wins over the code form when both are present.
- MCP `scope_parents` data still overrides both (`scope_merge` overlay unchanged).
- An incremental `--skip-mcp` rebuild does not drop a previously MCP-derived `parent` (key-level merge, step 9).
- A scope with no discoverable parent has **no** `parent` key (not `""`), and is still reported as a root.
- `/knowledge-graph scope-tree` no longer lists `GameScope` as a root.
- `schema.json` remains valid, the `schema_version` **minor** is bumped for the new `parent_source` property per the rule at `schema.json:12`, and `bash .claude/graph/test/verify-graphify.sh` exits 0.

---

## Task 8 — Harness Assertions

**Sequential last among edits** — writes `verify-graphify.sh` and asserts behaviour from Tasks 1, 2, 5, 6, 7.

**Files:**
- `.claude/graph/test/verify-graphify.sh` (new assertions only)

**Steps:**
1. [ ] Re-read `.claude/graph/test/verify-graphify.sh`: the header conventions (lines 1-80 — `SCRIPT_DIR`, `REPO_ROOT`, `UNITY_CONCRETES`, `UNITY_HAS_CS`, `sha_of`, `section`, `jq_count`, `check_prerequisites`), the sourced helpers `pass`/`fail`/`known_fail`/`assert_eq`/`assert_jq` from `.claude/graph/test/lib/assert.sh` (lines 5-29), the `.work/` sandbox convention used by the collapse-guard tests near the end of the file, and the `# Main pipeline` block at the very bottom that calls each `run_*` function in order.
2. [ ] Add a new `run_registration_semantics_tests()` function. Write a probe `.cs` into `$SCRIPT_DIR/.work/` covering **five** registration forms — interface + `new`, interface + field, plain generic, plain generic **with an `.As<T>()` chain**, and unresolvable — run **both** extractors against it, and assert with `assert_jq`: no `type` is the interface when a concrete exists; `as` carries the interface; **every `as` is a JSON string** (`map(type) | unique == ["string"]`); the `{type, as}` multisets from the two extractors are identical (the parity gate from Task 2). The `.As<T>()` chain is mandatory in the probe — and note that the parity assertion over that record is satisfiable **only** because Task 1 step 4 added `_as_chain` to the tree-sitter extractor; before that change the tree-sitter side emits `as: ""` there and this assertion is unpassable by construction. If Task 1's chain reader was not implemented, this assertion must be reported as a `fail`, not softened.
3. [ ] Add `run_validator_interface_tests()`: construct a minimal graph fixture with (i) an `interface_only: true` registration naming an interface, (ii) a plain registration naming a genuinely absent class, and (iii) a plain `Register<T>`-shaped record `{"type":"UnknownClass","as":"","lifetime":""}` with **no** `interface_only`. Assert `graph_validate.py` emits **no** `INSTALLER_MISSING_CLASS` for (i) and **does** emit one for both (ii) and (iii). Case (iii) is the guard-not-too-loose assertion and is the most important test in this task: it fails loudly if `interface_only` is ever set on ordinary `Register<T>` registrations, which would silently disable the check project-wide.
4. [ ] Add `run_reconciliation_tests()`: (i) on a healthy `--full --skip-mcp` build into `.work/`, assert stderr contains no `GRAPH_DISK_MISMATCH`; (ii) drop a class node from a copy of the graph, re-run the check, assert the warning fires **and** exit code is `0`. Gate (i) on `UNITY_HAS_CS=1` and `known_fail` on template/empty repos, matching how the existing builder tests degrade (the template repo has no `Assets/` C# to reconcile).
5. [ ] Add `run_scope_parent_tests()`: probe `GameScope.cs` with `ParentReference.Create<AppScope>()`; assert both extractors yield `parent == "AppScope"`; assert a parentless scope emits no `parent` key; assert the `[ParentScope(...)]` attribute form still takes precedence when both are present.
6. [ ] Register all four functions in the `# Main pipeline` block at the bottom, appended after `run_viz_smoke_tests` and before `emit_report`.
7. [ ] Use `known_fail` (not `fail`) for anything that cannot run in the given environment — tree-sitter absent, no Unity C# present — so the harness stays green on the bare template repo while still reporting the gap. Follow the existing precedent of `UNITY_HAS_CS` gating. Do **not** use `known_fail` to paper over a missing implementation (see step 2).
8. [ ] Clean up `.work/` probe files the way the existing tests do (`rm -rf` of the sandbox dir), and never write probes outside `$SCRIPT_DIR/.work/`.
9. [ ] Do not modify lines 261, 430, or 547 — the two assertion message strings and the comment that mention `graph-builder.sh` are historical and are excluded from Task 3's sweep by design.

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
# ... run_validator_interface_tests, run_reconciliation_tests, run_scope_parent_tests ...
# appended to the Main pipeline block
```

**Acceptance Criteria:**
- `bash .claude/graph/test/verify-graphify.sh` exits 0 with `fail == 0` on the template repo.
- The registration probe contains at least one `.As<T>()` chain, and the parity assertion covers that record. That assertion presupposes Task 1's `_as_chain`; it is not weakened or exempted.
- The parity assertion (reg.4) compares only records where that extractor resolved a type (`select(.type != "")`). The one shape only one side can represent — non-generic `RegisterInstance` with an unresolvable argument — is asserted per-extractor by reg.6, so the asymmetry is pinned rather than exempted. reg.4 without the `select()` is unsatisfiable by construction (`csharp-extractor.sh:384` cannot match an argument containing `()`), and reg.6 must fail if either side's behaviour on that shape changes.
- An assertion exists that fails if either extractor emits a non-string `as`.
- An assertion exists that fails if a `Register<T>`-shaped record carries `interface_only`, and a validator assertion exists that fails if `INSTALLER_MISSING_CLASS` stops firing for a plain `Register<UnknownClass>` record.
- Each of Tasks 1, 2, 5, 6, 7 has at least one dedicated assertion that fails when that task's change is reverted (demonstrated, not assumed).
- Lines 261, 430, 547 and `test/README.md:58` are unmodified.
- Environment-dependent tests use `known_fail`, never `fail`; missing implementations use `fail`, never `known_fail`.
- No probe file is written outside `$SCRIPT_DIR/.work/`, and the sandbox is removed on completion.

---

## Task 9 — Copy Changed Files to `piggy-doku-repo` and Re-Verify

**Sequential last — depends on Tasks 1 through 8.**

**Files:** all files modified by Tasks 1-8, copied from `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo` to `/Users/berkterek/Desktop/Github/piggy-doku-repo`.

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
3. [ ] Treat the doc/command files (`.claude/commands/*.md`, `.claude/graph/*.md`) with the same diff-first check — piggy-doku may carry project-specific edits to `setup-project.md` that a blind copy would destroy. **[BLOCKED — needs investigation]** the byte-identical verification covered only the four tooling files; the markdown and `schema.json` state in piggy-doku is unverified. Diff each before copying and hand-port where they differ.
4. [ ] `.claude/graph/.gitignore` (Task 4) needs **no** copy — the point of that task was to match piggy-doku's existing content. Diff to confirm they are now identical and skip.
5. [ ] Copy the verified-identical files. Do not copy `.claude/graph/graph.json`, `graph.json.bak`, `cache/*`, or `.last-build` — those are per-project generated artifacts.
6. [ ] In piggy-doku, run a full rebuild so the new extractor logic regenerates the graph: `python3 .claude/graph/graph-builder.py --full --skip-mcp`. A full build is required, not incremental, because the registration and scope records for unchanged files must be re-extracted under the new logic.
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

## Out of Scope (verified already correct — no task)

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
