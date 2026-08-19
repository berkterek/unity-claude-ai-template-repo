# Grill Decision Record — PLAN_graph_tooling_fixes

**Date:** 2026-08-18
**Subject:** `docs/PLAN_graph_tooling_fixes.md` (v3) — the four knowledge-graph tooling defect fixes under `.claude/graph/`
**Session model:** Opus (heavy tier — grill ran directly, no delegation)

Every measurement below was run against real repositories (`unity-claude-ai-template-repo`,
`piggy-doku-repo`, plus `voxel-blast`, `terek_worm_escape_jam_repo`, `nile_hole_sphere_repo`
for prevalence counts). Nothing here is inferred where it could be measured.

---

## Resolved Decisions

### D1 — Task 7 (`ParentReference.Create<T>()` scope-parent extraction) is REMOVED from this plan and moved to a separate ADR

**Chosen:** cut Task 7; open an ADR for it instead.

**Rationale.** The plan silently overrode a recorded project decision without naming it. Stored
memory *Limitation 18* says verbatim: "Do NOT report this as a bug or try to fix it with
regex/grep on .cs files. … The fix requires an MCP extractor update (C# EditorScript querying
`AssetDatabase` + `SerializedObject`), which has not been implemented." Task 7 did exactly the
forbidden thing, on both extractors — AST on `csharp_extractor.py`, **regex** on
`csharp-extractor.sh`.

The recorded decision is also partly outdated: its factual half ("the parent is never declared in
C# source") is false for piggy-doku, where `GameScope` builds its parent in `Awake` via
`ParentReference.Create<AppScope>()`. Its normative half (do not solve this with regex on `.cs`)
still binds the shell-fallback side. Both halves cannot stand as they are — which makes this a
decision to be taken deliberately, not a task inside a defect-fix plan.

Two further reasons: Task 7 sat alone in `parallel_group` C because it rewrote all three files
groups A and B touch, serialising the entire plan behind its riskiest, least-certain task; and the
other eight tasks are narrow, measurable, and shippable today.

**Accepted cost:** `/knowledge-graph scope-tree` keeps showing `GameScope` as a root scope. That
is a graph limitation, not an architecture defect — a PlayMode test already proves
`GameScope.Parent == AppScope` and `IsRoot == false` at runtime.

**Follow-up owed:** an ADR that (a) amends Limitation 18's factual half, (b) decides whether
code-declared parents may be read from source at all, and (c) if yes, whether the regex fallback
is permitted to participate.

---

### D2 — The disk-vs-graph reconciliation compares only files that declare a `class` or `interface`

**Chosen:** filter the disk side by declaration kind before comparing.

**Measured, not assumed.** Task 6 step 5 was marked `[BLOCKED — needs investigation]` on the
grounds that the false-positive rate "cannot be reasoned out". It was measured instead, against
piggy-doku's live graph:

| | |
|---|---|
| graph nodes carrying a source file | 63 |
| `.cs` files on disk | 72 |
| **missing (disk − graph)** | **9** |
| extra (graph − disk) | 0 |

The plan's verification gate ("a healthy build must be SILENT") would therefore have failed as
written. All nine turned out to be node kinds the graph does not model at all:

| Category | Count | Files |
|---|---|---|
| `enum`-only | 4 | `LogTag`, `CellState`, `TapAction`, `FlowState` |
| `struct`-only | 2 | `GridLayout`, `GridFramingEntry` |
| `*Events.cs` declaration sites | 3 | `GridEvents`, `LevelEvents`, `LivesEvents` |

Two structural facts fell out of this and both contradict the plan's skeleton:

1. **The graph has no `enums` and no `structs` arrays at all.** Its node kinds are `classes`,
   `interfaces`, `events`, `assemblies`, `calls`, `communities`. The plan's reconciliation unions
   `("classes","interfaces","enums","structs")` — two of those keys do not exist.
2. **`events[].source_file` points at the event's *publisher*, not its declaration site.**
   `CellStateChangedEvent` is declared in `GridEvents.cs`; the graph records `GridService.cs`.
   So `*Events.cs` files are structurally invisible as declaration sites, and reading
   `events[].source_file` into the reconciliation would mark the wrong file as covered.

**The filter was then validated on the same corpus:** 63 candidate files after filtering = 63
graph class/interface files, **0 false positives**, and none of the 9 excluded files contains the
word `class` or `interface` anywhere — so the regex is not silently dropping a declaring file on
this corpus either.

**Why this still catches the bug it exists for:** the two files that went silently missing —
`LocalSaveLoadDal.cs` and `LogDumpOnStop.cs` — both declare classes.

**Residual risk:** the regex could miss an unusual declaration (multi-line, heavily attributed) and
silently drop that file out of the comparison — a hole in the net rather than a false alarm.
Measured at zero on the current corpus; re-measure when the filter meets a new codebase.

**Rejected alternatives.** Comparing against the extractor's *processed* file set is conceptually
closer to "was a file skipped?", but it is unverified whether the builder publishes such a set
today; adopting it would add an accounting layer. Adding `enums`/`structs` as node kinds would make
the naive comparison correct *and* close a real gap (`/knowledge-graph` cannot answer "where is
`CellState` declared"), but that is an extractor capability — exactly what D1 removed Task 7 for.

---

### D3 — `AsImplementedInterfaces` stays an unresolved placeholder, and the plan's goal is narrowed to say so

**Chosen:** declare the limit explicitly; spin the real resolution out as separate work.

**Measured prevalence:** `AsImplementedInterfaces` appears 16 times in piggy-doku versus 10
explicit `.As<T>()` — it is the dominant idiom, and `bootstrap-pattern.md` mandates it
(".AsImplementedInterfaces() covers IInitializable, IDisposable, ITickable automatically"). Zero
multi-`.As<X>().As<Y>()` chains exist in either repo, so the plan's "take the first, drop the rest"
rule loses no data at any call site today.

**The problem this exposes.** The plan writes the literal string `"AsImplementedInterfaces"` into
`as` for those registrations. Its own Goals claim "the live `/knowledge-graph registrations` query
(`.as == $name`) can actually match it" — but for the dominant idiom it still cannot:
`registrations IGridService` returns nothing, because the record holds
`type='GridService'`, `as='AsImplementedInterfaces'`.

**Required plan edits:** narrow the Goal to say interface-name resolution works only for explicit
`.As<T>()` and generic `RegisterInstance<I>(…)` forms; and state in the plan text that
`as='AsImplementedInterfaces'` is a **placeholder**, so no reader mistakes it for an interface name.

**Why not resolve it properly here:** the graph already carries `implements` per class (11 of 51
classes in piggy-doku; `GridService → ['IGridService']`, `SceneService → ['ISceneService',
'IAsyncStartable', 'IDisposable']`), so build-time resolution is possible. But `as` is a single
string per `schema.json:177`, and a class implementing three interfaces does not fit in one — so
doing it right needs a new array key, a schema change, and an update to the query in
`knowledge-graph.md`. That is a capability, not a defect fix, and D1 removed Task 7 on that exact
ground an hour earlier. Taking a different capability in now would be incoherent.

**Honest consequence, recorded:** Defect 1's measured payoff is smaller than the plan implies.
Across five repos the exact forms it corrects — `RegisterInstance<I>(new C())` and
`RegisterInstance<I>(_field)` — total about **five call sites** (1 + 1 in piggy-doku, 1 each in
voxel-blast / worm-escape / nile-hole; 0 in the template). The larger real gain is elsewhere: the
`.As<T>()` chain reader gives `as` a real value at **12 call sites** where it is currently always
`''`, which is new information rather than a correction. The justification for Defect 1 is "wrong
data in the primary source of truth, plus 12 empty fields" — not a large call-site count.

---

### D4 — An extraction-semantics version is added, and the builder invalidates its own cache

**Chosen:** add an `EXTRACTION_VERSION` constant; the builder compares it against the value stored
in the existing graph and, on mismatch, promotes an `--incremental` run to `--full` once, writing
the reason to stderr.

**The gap this closes.** The plan changes the *values* of `type` and `as`, not their *shape*. So
nothing existing would signal that a graph is stale in the way that matters:

| Repo | `graph.json` tracked | builder SHA | built |
|---|---|---|---|
| template | yes | `5a23b5b` | 2026-07-06 |
| piggy-doku | yes | `20c0136` | 2026-08-18 |
| voxel-blast | no | `87fcde1` | 2026-08-14 |
| worm-escape | yes | `e732700` | 2026-08-17 |
| nile-hole | yes | `fc2c3e20` | 2026-08-13 |

`generator` (written at `graph-builder.py:815`) and `schema_version` (`1.3.0`, line 813) are both
**write-only — nothing in the pipeline reads either.** Staleness is judged purely on
`generated_at` older than 24h (`knowledge-graph.md:33`). An incremental build does not re-extract
unchanged files, so old wrong records survive indefinitely while the graph reports itself fresh,
and `/knowledge-graph` answers from them with confidence. Task 9 rebuilds piggy-doku only; three
other projects would keep wrong `type` and empty `as` forever.

**Rejected alternative:** documenting "run `--full` in every repo after this lands". That is
precisely the class of instruction that silently does not happen — and Defect 0 exists *because*
a graph silently disagreed with disk. Relying on a remembered manual step would reproduce the
failure mode the plan is fixing.

**Side benefit:** `generator` and the version fields become load-bearing for the first time.

---

### D5 — Real-corpus validation moves to immediately after Tasks 1+2, read-only, with no copying

**Chosen:** validate the changed extractor against piggy-doku's real source before reaching the
harness; Task 9 becomes propagation only, not a verification round.

**Why the old order was weak — measured.** The template has **no `Assets/` directory at all**; its
graph contains 0 classes, 0 interfaces, 0 installers, and its only 9 `.cs` files are test fixtures.
So every assertion in Tasks 1-8 runs against synthetic probes written by the same person writing
the fix, encoding the same assumptions. The originating symptom — `GridModule`'s false
`INSTALLER_MISSING_CLASS` — is reproducible only in piggy-doku, and Task 9 (the sole real-corpus
check) came *after* Tasks 1-8 were marked done.

This session demonstrated that failure mode twice: a research agent's false "nothing reads the `as`
key" claim, which was passed to the planner as verified fact; and v2's `interface_only` marker
landing on every ordinary `Register<Foo>()`, which would have disabled `INSTALLER_MISSING_CLASS`
for the common case. Both were assumption errors, and only an independent look caught either.

**Validated as executable during this grill.** The template's extractor was run read-only against
piggy-doku's module files — no copy, no commit, piggy-doku's graph untouched:

```bash
python3 $T/.claude/graph/extractors/csharp_extractor.py --changed-files <piggy-doku .cs files>
```

It works cross-repo and reproduced the defect directly, giving the plan a recorded **baseline**:

```
GridModule → [{"type": "ITapResolver", "as": "", "lifetime": ""},
              {"type": "GridService",  "as": "", "lifetime": ""}]
```

`partial_calls` in the same output also carries `builder.As` and
`builder.AsImplementedInterfaces` edges, confirming the chain information is reachable.

**Boundary:** this check does **not** enter the harness. `verify-graphify.sh` stays self-contained
on synthetic probes; the real-corpus comparison is plan-time evidence, not a CI gate that would
make the template's tests depend on another repository existing.

---

## Open Questions (deferred)

None. Every branch raised during the grill was resolved, either by a decision above or by
measurement.

---

## Risks Identified

- **The declaration regex is a hole, not an alarm (D2).** A `class`-declaring file the regex misses
  drops silently out of the comparison. Measured at zero on the current corpus. *Mitigation:*
  re-measure when the filter first runs against a new codebase; report the excluded-file count in
  the build output so the number is visible rather than implicit.
- **Defect 1's payoff is narrower than the plan's framing (D3).** ~5 call sites corrected, 12
  `as` fields populated. *Mitigation:* recorded here so the plan's value is not overstated later;
  no scope change.
- **`AsImplementedInterfaces` registrations stay unresolvable by interface name (D3).** The
  dominant idiom in this project. *Mitigation:* the Goal is narrowed and the placeholder is
  labelled in the plan text, so the gap is documented rather than discovered.
- **Three repos will carry wrong records until they rebuild (D4).** *Mitigation:* the
  `EXTRACTION_VERSION` bump forces a one-time full rebuild automatically instead of relying on a
  remembered manual step.
- **Probe `.cs` files written with the `Write` tool would trigger a background rebuild.**
  `graph-auto-update.sh` filters on `*.cs|*.asmdef|*.prefab|*.unity` (lines 27-30) and launches
  `graph-builder.py --incremental` detached, so editing `.py`/`.sh` tooling is safe — but a probe
  `.cs` created through the Write tool during Task 8 would fire it, using a half-edited extractor,
  against a tracked `graph.json`. *Mitigation:* the harness writes probes via bash heredocs into
  `.work/`; never create a probe `.cs` with the Write tool.
- **`events[].source_file` records the publisher, not the declaration site (D2).** Not a plan
  defect, but a latent trap for any future consumer that reads it as "where this event is
  declared". *Mitigation:* recorded here; no change in this plan.

---

## Required Plan Edits (before implementation)

1. Delete Task 7; renumber or leave a gap, and remove its `parallel_group` C entry. Open the ADR
   from D1.
2. Task 6: replace the `("classes","interfaces","enums","structs")` union with
   `("classes","interfaces")`, since the other two keys do not exist. Add the declaration-kind
   disk filter from D2, unmark step 5's `[BLOCKED]`, and record the measured 9→0 result as its
   justification. Do not read `events[].source_file`.
3. Narrow the Goal per D3 and label `as='AsImplementedInterfaces'` a placeholder in the plan text.
4. Add the `EXTRACTION_VERSION` task from D4 — constant, comparison, one-time promotion of
   `--incremental` to `--full`, stderr reason.
5. Move the real-corpus read-only validation from Task 9 into a checkpoint after Tasks 1+2 (D5),
   with the recorded `GridModule` baseline as its before-state. Task 9 keeps only propagation and
   re-verification.
6. Task 9: drop step 3's `[BLOCKED]`. Measured — every `.md` and `schema.json` is byte-identical
   between the two repos; only `.claude/graph/.gitignore` differs by one line, which is Task 4's
   own subject.

---

**Recommended next command:** `/update-plan docs/PLAN_graph_tooling_fixes.md` with the six edits
above, then `/adr` for the scope-parent decision from D1.
