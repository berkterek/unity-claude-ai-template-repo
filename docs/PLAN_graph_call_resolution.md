# PLAN — Knowledge-Graph Call-Edge Callee Resolution (RC1–RC4)

> **Version:** 1.3 — 2026-07-16
> **Status:** Active — reviewer-approved; hardened against same-name collisions, method-existence false positives, multi-implementer ambiguity, MCP staleness, and bridge-direction misuse
> **Revisions:**
> - v1.3 (2026-07-16): 3 source-verified INCREMENTAL review revisions on the v1.2 details (no structural change; tasks not renumbered). **REV5 rework** — method-existence must NOT mutate `confidence`: it persists in `graph.json` and is retained across incremental builds, so a one-way downgrade makes full vs. incremental builds disagree on the same edge (violates T1's own idempotency criterion); and two INFERRED sources — RC3 heuristic vs. method-miss — cannot be told apart in one field. It now writes a separate, stateless-per-build `method_match: true|false|null` field (T1 + T2 schema). **REV6 direction fix** — the `implements` adjacency link direction is now explicit in the `class_adjacency` skeleton: `rev_class[concrete] ∋ interface` (+ symmetric `fwd_class[interface] ∋ concrete`), the only placement that lets `impact <concrete>` reach interface-only callers. **REV-methodbridge** — method-level queries (`callers SoundManager.Play`) now also bridge to `{iface}.{method}`, restoring the interface-routed DI callers the bare-class query already saw (T5 `match_keys`). Cosmetic: plan revision labels renamed `R#` → `REV#` to avoid collision with the graphify validator rules `R1–R6` referenced in `verify-graphify.sh`; T6 step `3b` renumbered to `3a`.
> - v1.2 (2026-07-16): 6 source-verified INCREMENTAL review revisions (no structural change, tasks not renumbered), informed by comparative analysis of Graphify-Labs/graphify (same problem class). **REV1** T5: three-value `matched_via` (`exact`/`class_prefix`/`interface_bridge`) on caller hits. **REV2** T5: MCP `_graph_mtime` reload must refresh `_g`, not just adjacency. **REV3** T5: one-directional bridge (concrete→interface) documented as a decision. **REV4** T1: same-name collision tie-breaker in `resolve_call_targets` — prefer non-test file, else leave unresolved (graphify `disambiguate_ambiguous_candidates`). **REV5** T1: method-existence check (reworked in v1.3 to write `method_match`, not downgrade confidence). **REV6** T5: `impact`/`path` use `implements`-as-first-class-adjacency (graphify `affected.py`) instead of key-bridging. Critique Pass gains REV2 + REV4 hazard entries.
> - v1.1 (2026-07-16): Reviewer INCREMENTAL fixes — incremental-retention blocker (caller_file-only), dual-adjacency coverage in T5, RC3 INFERRED-confidence decision.
> **Scope:** Python knowledge-graph extractor/builder/traversal under `.claude/graph/` ONLY. No Unity C# is edited. This fixes why cross-class call edges are unusable so that `/knowledge-graph callers|impact|path` work against real projects.
> **Complexity:** 8/10 — **COMPLEX** (4 sequential root causes spanning extractor → builder post-pass → traversal → schema/validator → fixtures; RC4 re-keys the traversal graph; incremental-mode and multiple downstream consumers must not regress).

## Context

Verified against a real 213-class project (`nile_bounce_legion_repo`) graph and against the extractor source:

- 1888 call edges; `callee_file == caller_file` in **1888/1888 (100%)** — the callee file is fabricated.
- Caller side resolves to a real class node in **1860/1888 (98.5%)** — caller side is FINE and must not be touched.
- Only **~393/1888 (~21%)** callee head tokens map to a project class; the rest are Unity API (`InputActionMap`) or unresolved locals (`asset`).
- `graph-traversal.py callers SoundManager` → "No direct callers found" for a real class.

Four root causes, each confirmed in source (all line numbers re-verified by an independent reviewer against the actual files):

- **RC1** — `extractors/csharp_extractor.py:226` hardcodes `"callee_file": path` (the file being scanned). There is no global type→file index at per-file extraction time, so cross-file callees are never resolved.
- **RC2** — `_resolve_receiver_type()` (`csharp_extractor.py:118-151`) returns `None` for `invocation_expression` / lambda / element-access receivers, so `_extract_calls` line 221 falls back to `_node_text(func)` and writes the ENTIRE multi-line fluent chain + lambda body as the callee string (e.g. `"DOTween.To(() => currentScore, x => currentScore ... )"`).
- **RC3** — `_local_var_symbols()` (`csharp_extractor.py:382-402`) only infers a `var` local's type from an explicit type node or `new T()`. `var asset = InputActionAsset.FromJson(...)` leaves `asset` untyped, so `asset.FindActionMap` is unresolved.
- **RC4** — resolved field/param receivers yield the DECLARED (interface) type under DI, and `graph-traversal.py` / `graph_bfs_core.callers_core` key `reverse[callee]` on the full `Type.Method` string (`callers_core` line 107: `if e.get("callee") == node`). A `callers ConcreteClass` query therefore (a) can't match `Type.Method`-shaped callees against a bare `Class` node, and (b) never reaches callers routed through the interface.

### Confirmed consumer/backward-compat map (do NOT regress)
- `callee` string is consumed by `graph_cluster.py:74-75` and `graph_analyze.py:94-95` via `.split(".")[0]` → the `callee` value MUST stay `Type.Method`-shaped. RC2's truncation IMPROVES these (kills multi-line garbage).
- `graph-traversal.py:36-42` AND `graph-mcp-server.py:85-91` each build their OWN `forward`/`reverse` adjacency keyed on the full `callee` string. RC4 must fix BOTH — the recommended path is to centralise adjacency inside `graph_bfs_core` cores so both loaders inherit the fix (see Task 5).
- `graph.html` does NOT reference `callee`/`callee_file` — zero viz risk from new edge fields.
- Schema `callEdge` (`schema.json:305-314`) documents only `caller/callee/file/line/confidence`. `caller_file`/`callee_file` are ALREADY undocumented extras (object has no `additionalProperties:false`), so this is hygiene, not a build fix. Adding `callee_class` is additive but must be documented (Task 2).
- `graph_validate.py:74-83` references `call.get("callee_class")`/`call.get("callee_method")` over `cls.get("calls", [])` — DEAD CODE today (class dicts at 498-513 carry no `calls` key; calls live at `codebase.calls`). Task 2 repoints it to the real top-level array using the new `callee_class`.

### What is already correct (must not regress)
- PascalCase static-receiver resolution (`csharp_extractor.py:132-135`); `this`/`base`/field/param symbol resolution; caller side (98.5%); class/interface/prefab/scene inventory; injection `dependencies`; pub/sub edges.

## Goals

- [ ] **RC1 (highest impact, lowest risk):** stop fabricating `callee_file`; add a global post-processing pass in `graph-builder.py` that resolves each edge's callee to a real project type + file, mirroring `resolve_implementers()`. Set `callee_file=None` / `callee_class=None` when unresolvable. **Also fix the incremental-retention clause so real cross-file edges are not silently dropped.**
- [ ] **RC2:** stop emitting multi-line chain/lambda bodies as callee text; normalise unresolved callees to a single-line `head.Method`. (Full chain return-type threading is scoped OUT — see Task 3.)
- [ ] **RC3:** best-effort type for `var x = Type.StaticMethod(...)` locals via a PascalCase-receiver heuristic, with heuristic-derived callees marked `INFERRED`.
- [ ] **RC4:** make `callers` / `impact` / `path` resolve a `Class` or `Class.Method` node argument against `Type.Method` callee strings by prefix, and bridge interface→concrete so `callers ConcreteClass` also returns callers of its interfaces — across BOTH adjacency builders.
- [ ] Keep schema + validator consistent; add fixture-based tests in the existing stdlib style.
- [ ] Preserve incremental-mode correctness and all currently-correct data.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | T1 — RC1 cross-file callee resolution pass + stop fabricating `callee_file` + fix incremental retention | ✅ Done | — |
| 2 | T2 — Schema + validator: document fields, repoint dead `DANGLING_CALL` branch | ✅ Done | — |
| 2 | T3 — RC2 normalise fluent/lambda chained callees | ✅ Done | P3 |
| 2 | T5 — RC4 class-granularity + interface→concrete matching in traversal | ✅ Done | P3 |
| 3 | T4 — RC3 infer `var x = Type.StaticMethod()` local types | ⏳ Pending | — |
| 4 | T6 — Tests + verification (fixtures, extractor asserts, verify-graphify case) | ✅ Done | — |

**Parallelism note (honest):** T3 and T5 (group **P3**) touch disjoint files (extractor vs. traversal/bfs_core/mcp-server) and can run simultaneously. T4 shares `csharp_extractor.py` with T3 → strictly sequential after T3. T2 depends on T1's field-name decision. T6 is last. T1 is the funnel: the resolution field it introduces is what T2/T5/T6 assert on.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/extractors/csharp_extractor.py` | Modify | `_extract_calls` (154-231), `_resolve_receiver_type` (118-151), `_local_var_symbols` (382-402) |
| `.claude/graph/graph-builder.py` | Modify | add `resolve_call_targets` after `resolve_implementers` (417); wire after `merge_call_edges` (935); fix `merge_call_edges` retention (350-363) |
| `.claude/graph/graph-traversal.py` | Modify | `load_graph`/adjacency (36-42), `cmd_callers` (109-133), impact/path |
| `.claude/graph/graph_bfs_core.py` | Modify | `callers_core` (81-113), `impact_core`, `path_core`, add matcher + class adjacency |
| `.claude/graph/graph-mcp-server.py` | Modify | own adjacency build (85-91) — route through shared cores |
| `.claude/graph/schema.json` | Modify | `callEdge` (305-314) — document `caller_file`/`callee_file`/`callee_class` |
| `.claude/graph/graph_validate.py` | Modify | repoint dead `DANGLING_CALL` branch (74-83) |
| `.claude/graph/test/**` | Add/Modify | fixtures + stdlib asserts + `verify-graphify.sh` case |

## Critique Pass (Complex — required)

- **(a) Incremental regression — TWO hazards, both mitigated.**
  1. *New edges with `callee_file=None`* are safe in `merge_call_edges` (`None not in changed_set` is True → never wrongly dropped).
  2. **(reviewer blocker, now fixed in T1)** Once `callee_file` holds a real FOREIGN file, the retention clause `and c.get("callee_file") not in changed_set` (line 358) drops edge `X.foo → Y.bar` when **Y's file changed but X's did not** — and extraction only regenerates the *caller's* (X's) outgoing edges, so the edge is never rebuilt until X itself is edited. Since incremental is the default PostToolUse path, this would progressively decay the graph. **Fix (T1): retain on `caller_file` only** — an edge is regenerated iff its caller is re-extracted, so the callee-file condition can only drop edges nothing will regenerate. Plus `resolve_call_targets` re-runs over ALL merged edges every build, so surviving edges always carry a fresh `callee_file`.
- **(b) Schema/validator drift.** New `callee_class` documented in `schema.json` and the dead `graph_validate.py` branch repointed in Task 2, landed with Task 1 so the validator never sees an undocumented field in anger.
- **(c) Performance.** `resolve_call_targets` = one dict build O(classes+interfaces) + one O(edges) pass with a single `split(".",1)` + dict lookup per edge (~1888 lookups on the sample — negligible). RC4 class adjacency is O(edges) built once per query.
- **(d) Backward-compat.** `callee_class`/`callee_file` additive; `callee` shape preserved (`Type.Method`) so `graph_cluster.py`/`graph_analyze.py` keep working; `graph.html` ignores the fields; `graph-mcp-server.py` routed through shared cores (Task 5) so it cannot silently diverge.
- **(e) MCP stale-graph hazard (REV2).** `graph-mcp-server.py` caches `_g`/`_forward`/`_reverse`/`_edges` at module level (~line 97). `class_adjacency` builds from the passed `edges` (safe), but `implements_map(g)` reads the cached `_g`. If the `_graph_mtime` reload refreshes only the adjacency indices and not `_g`, the interface bridge would run on stale `implements` after every rebuild — returning wrong callers silently. **Mitigation (T5 step 6a):** verify the reload re-reads `_g`; fix it if not.
- **(f) Same-name collision hazard (REV4).** `resolve_call_targets` keying a simple name to a single file silently mis-attributes when a production class and a same-named test fake coexist (test fakes are the norm here). First-wins (`setdefault`) could resolve a call to the test double. **Mitigation (T1 steps 2a):** prefer the single non-test candidate; if 0 or ≥2 non-test candidates, leave unresolved rather than guess. A wrong `callee_file` is worse than a null one — it fabricates a false cross-class relationship.

---

## Task 1 — RC1: cross-file callee resolution pass + stop fabricating `callee_file` + fix incremental retention

**Files:**
- `.claude/graph/extractors/csharp_extractor.py`
- `.claude/graph/graph-builder.py`

**Steps:**
1. [x] In `csharp_extractor.py::_extract_calls`, replace emitted `"callee_file": path` (line 226) with `"callee_file": None` and add `"callee_class": None`; keep `"caller_file": path` (correct). Keys stay present (not omitted) for stable schema + merge shape.
2. [x] In `graph-builder.py`, add `resolve_call_targets(calls, classes, interfaces)` immediately after `resolve_implementers` (after line 417). Build a `{simple_name: [(file, methods_set, is_test)]}` index over all classes then interfaces — **NOT** `setdefault` first-wins. Split each edge's `callee` on the FIRST `.`, look up the head, set `callee_class`/`callee_file` (both `None` when unresolved). Never copy `caller_file`.
2a. [x] **[REV4 — same-name tie-breaker]** When a simple name maps to >1 file (typical: a production class and a same-named test fake — test fakes are the norm here per `rules/testing.md`), prefer the single NON-test file (path not under a `Tests/`/`Test/` folder and stem not `*Test*`), mirroring graphify's `paths.py::disambiguate_ambiguous_candidates`. If exactly one non-test candidate → pick it. If zero or ≥2 non-test candidates remain → leave `callee_class`/`callee_file = None` (do NOT guess). A single candidate resolves unconditionally.
2b. [x] **[REV5 — method-existence check → `method_match` field, NOT confidence]** After head resolution, set a separate `method_match` field on the edge, computed from scratch every build: `True` if the resolved type's `methods[]` is populated AND contains the callee method name; `False` if populated AND missing it; `None` if `methods[]` is empty/absent (unknown). **Do NOT touch `confidence`.** Reason (v1.3): `confidence` persists in `graph.json` and retained edges carry it across incremental builds, so a one-way downgrade would leave an edge `INFERRED` even after its class later gains the method — while a full rebuild regenerates it `EXTRACTED` from the extractor, making full and incremental disagree on the same edge (violates this task's own idempotency acceptance criterion). Re-raising is not an option either: `confidence` also carries RC3's heuristic-`INFERRED`, and two INFERRED sources cannot be disambiguated in one field. A stateless per-build `method_match` sidesteps both problems and never collides with RC3. Caveat unchanged: `methods[]` is name-only, omits inherited/base/interface methods, and is empty for ~21% of classes (168/213 populated in the sample), so `method_match=False` is a soft signal, never a reason to drop the edge. (Scoped-down form of graphify's `(type_nid, method_key)` gate; do NOT build a separate global method index.)
3. [x] Wire it into `main` right after line 935 (`all_calls = merge_call_edges(...)`), passing `all_classes` (916) and `all_ifaces` (923). MUST run over merged `all_calls` (retained + new) so retained edges are re-resolved against the current index every build.
4. [x] **[incremental blocker fix]** In `merge_call_edges` (350-363), change the incremental retention predicate to filter on `caller_file` ONLY — remove the `and c.get("callee_file") not in changed_set` clause. An edge is regenerated iff its caller is re-extracted; keying retention on callee_file drops edges nothing will regenerate.

**Test Type:** stdlib extractor assert in `test/test_extractor_pubsub.py` + builder-level fixture (T6). Also T6 adds a two-consecutive-incremental-build test.

**Code Skeleton:**
```python
# graph-builder.py — after resolve_implementers (line 417)
def _is_test_file(path):
    p = (path or "").replace("\\", "/")
    if "/Tests/" in p or "/Test/" in p:
        return True
    stem = p.rsplit("/", 1)[-1].split(".", 1)[0]
    return "Test" in stem

def resolve_call_targets(calls, classes, interfaces):
    """Resolve each call edge's callee head token to a real project type + file.
    - REV4: same simple name on multiple files → prefer the single NON-test file;
      if 0 or >=2 non-test candidates remain, leave unresolved (None) — no guess.
    - REV5: set method_match = True/False/None from the resolved type's methods[]
      (True=present, False=populated-but-absent, None=methods[] empty/unknown).
      Computed fresh every build; NEVER touches confidence (which persists and
      would desync full vs. incremental, and already carries RC3's INFERRED).
      methods[] is name-only and omits inherited/interface methods, so
      method_match=False is a soft signal, never a reason to drop the edge.
    Unresolvable heads (Unity API, unknown locals) get callee_class/callee_file=None
    and method_match=None. Runs over ALL edges every build (resolution is global)."""
    by_name = {}
    for c in list(classes) + list(interfaces):
        n = c.get("name")
        if not n:
            continue
        methods = {m.get("name") for m in (c.get("methods") or []) if m.get("name")}
        by_name.setdefault(n, []).append((c.get("file"), methods, _is_test_file(c.get("file"))))
    for e in calls:
        head, _, method = (e.get("callee") or "").partition(".")
        e["callee_class"] = None
        e["callee_file"] = None
        e["method_match"] = None
        cands = by_name.get(head)
        if not cands:
            continue
        pick = cands[0] if len(cands) == 1 else None
        if pick is None:                                   # REV4 tie-break
            non_test = [c for c in cands if not c[2]]
            pick = non_test[0] if len(non_test) == 1 else None
        if pick is None:
            continue                                       # ambiguous → leave None
        file, methods, _ = pick
        e["callee_class"] = head
        e["callee_file"] = file
        if method and methods:                             # REV5: method_match, NOT confidence
            e["method_match"] = method in methods          # True / False; stateless per build
        # methods empty/absent → method_match stays None (unknown); confidence untouched
    return calls

# main, immediately after line 935:
all_calls = merge_call_edges(existing_calls, new_partial_calls, changed_cs, args.mode)
all_calls = resolve_call_targets(all_calls, all_classes, all_ifaces)   # RC1
```
```python
# merge_call_edges — retain on caller_file ONLY (incremental blocker fix)
if mode == "incremental" and changed_cs:
    changed_set = set(changed_cs)
    retained = [c for c in (existing_calls or [])
                if c.get("caller_file") not in changed_set]   # callee_file clause removed
    return retained + list(new_partial_calls or [])
```
```python
# csharp_extractor.py::_extract_calls, replace lines 225-226:
                    "caller_file": path,     # caller side IS this file — correct
                    "callee_file": None,     # RC1: resolved in graph-builder.resolve_call_targets
                    "callee_class": None,    # RC1: filled by the builder pass
```

**Acceptance Criteria:**
- On the real project sample, `callee_file == caller_file` drops from 100% toward the ~21% of edges that genuinely call same-file classes; unresolved edges have `callee_file is None`.
- `callee_class` populated for every edge whose head is a project class/interface; `None` otherwise.
- Full and incremental builds produce identical `all_calls` resolution for unchanged files (idempotent).
- Editing ONLY a callee's file does not drop a cross-file edge whose caller was unchanged (verified in T6).
- **[REV4]** A callee whose simple name exists as both a production class and a same-named test fake resolves to the PRODUCTION file; if two non-test types share the name, the edge is left unresolved (`callee_class=None`), never guessed (verified in T6).
- **[REV5]** An edge to a resolved class with populated `methods[]` gets `method_match=True` (method present) or `method_match=False` (populated but absent); an edge to a class with empty `methods[]` gets `method_match=None`. `confidence` is never altered by this check, so full and incremental builds agree on both `confidence` and `method_match` for the same edge.
- No change to `caller`, caller-side resolution, or the `callee` string.

---

## Task 2 — Schema + validator alignment

**Files:**
- `.claude/graph/schema.json`
- `.claude/graph/graph_validate.py`

**Steps:**
1. [x] In `schema.json`, extend `callEdge.properties` (305-314) with `"caller_file"` (`{"type":"string"}`), `"callee_file"` (`{"type":["string","null"]}`), `"callee_class"` (`{"type":["string","null"]}`), and **`"method_match"` (`{"type":["boolean","null"]}`, REV5)**, each with a description. Confirm where the schema version string lives before touching it; bump patch (v1.3.0 → v1.3.1) only if a version field exists there. (No version field found in schema.json — no bump performed.)
2. [x] In `graph_validate.py` (74-83), repoint the dead `DANGLING_CALL` branch: iterate `codebase.get("calls", [])` (top-level), read `call.get("callee_class")`, derive method from `call["callee"]`. Flag ONLY when `callee_class` is non-null AND absent from `class_names`; skip `callee_class is None` (external/Unity, expected).

**Test Type:** `verify-graphify.sh` runs `graph_validate.py` — assert clean exit; `callee_class=None` edges must NOT produce `DANGLING_CALL`.

**Code Skeleton:**
```json
// schema.json callEdge.properties
"caller_file": { "type": "string", "description": "File containing the caller (== call-site file)." },
"callee_file": { "type": ["string", "null"], "description": "Resolved file of callee's declaring type; null when external/unresolved." },
"callee_class":{ "type": ["string", "null"], "description": "Resolved project type owning the callee method; null when unresolved." },
"method_match":{ "type": ["boolean", "null"], "description": "REV5: true if callee method is in the resolved type's methods[]; false if populated but absent; null if methods[] empty/unknown. Recomputed every build; independent of confidence." }
```
```python
# graph_validate.py — replace lines 74-83
for call in codebase.get("calls", []):
    callee_cls = call.get("callee_class")
    if callee_cls and callee_cls not in class_names:
        method = call.get("callee", "").split(".", 1)[-1]
        issues.append({
            "type": "DANGLING_CALL",
            "caller": call.get("caller", ""),
            "callee": callee_cls,
            "detail": f"{call.get('caller','')} calls {callee_cls}.{method} but {callee_cls} not in graph",
        })
```

**Acceptance Criteria:**
- A graph with the new fields validates against `schema.json`.
- `DANGLING_CALL` fires only for resolved-but-missing targets; `callee_class=None` edges never trigger it.
- Existing R1–R6 validator fixtures still pass (`verify-graphify.sh` T4).

---

## Task 3 — RC2: normalise fluent/lambda chained callees

**Files:**
- `.claude/graph/extractors/csharp_extractor.py`

**[SCOPED-DOWN — full return-type threading deferred]** Threading return types through an arbitrary fluent chain needs a method-signature index the per-file extractor lacks. OUT of scope. This task guarantees only: (1) never emit a multi-line node-text blob as `callee`, (2) normalise unresolved callees to single-line `head.Method`.

**Steps:**
1. [x] Add `_receiver_head_token(func_node, src)` → walks the receiver to its left-most `identifier`/`this`/`base` token; returns that single token or `None`.
2. [x] Add `_flatten_one_line(text)` → collapses whitespace and strips from the first `(` onward (last-resort guard so no callee contains `(...)`/lambda bodies).
3. [x] In `_resolve_receiver_type`, add an `invocation_expression`/`conditional_access_expression` branch that recurses into the inner function's receiver head; resolve via symbol table if possible, else `None` (inner return type unknown — deferred).
4. [x] In `_extract_calls`, replace line 221's fallback: `recv_type.method` when resolved; else `head.method` via `_receiver_head_token`; else bare `method`; only when `method is None` fall back to `_flatten_one_line(_node_text(func, src))`.

**Test Type:** stdlib extractor asserts (see T6).

**Code Skeleton:**
```python
def _receiver_head_token(func, src):
    n = func.child_by_field_name("expression") or func.child_by_field_name("condition")
    while n is not None:
        if n.type in ("identifier", "this", "base"):
            return _node_text(n, src).strip()
        nxt = (n.child_by_field_name("expression") or n.child_by_field_name("condition")
               or n.child_by_field_name("function"))
        if nxt is None:
            break
        n = nxt
    return None

def _flatten_one_line(text):
    return " ".join(text.split()).split("(", 1)[0]

# _extract_calls, replace line 221:
if recv_type and method:
    callee = f"{recv_type}.{method}"
elif method:
    head = _receiver_head_token(func, src)
    callee = f"{head}.{method}" if head else method
else:
    callee = _flatten_one_line(_node_text(func, src))
```

**Acceptance Criteria:**
- No `callee` contains `(`, `)`, `=>`, or `\n`.
- `.AddTo`/`.SetEase`/`.To` and lambda-subscribe callees become clean `head.Method`.
- `graph_cluster.py`/`graph_analyze.py` `.split(".")[0]` yields a real identifier for these edges.
- PascalCase static + `this`/`base`/field/param resolution unchanged (existing extractor tests pass).

---

## Task 4 — RC3: infer `var x = Type.StaticMethod()` local types

**Files:**
- `.claude/graph/extractors/csharp_extractor.py`

**Steps:**
1. [x] In `_local_var_symbols` (382-402), when `is_var` and no `object_creation_expression` initializer exists, look for an `invocation_expression` initializer whose function is a `member_access_expression` with an identifier receiver; if that receiver is PascalCase, record the local's type as that receiver type.
2. [x] **[DECISION — accept false-edge cost, downgrade confidence]** The heuristic assigns the *declaring* type, not the true return type — correct for the singleton/factory idiom (`Type.FromJson`, `Type.Create`) but wrong for `var v = Mathf.Abs(a); v.CompareTo(...)` → would emit `Mathf.CompareTo`. We accept this because: (a) full return-type inference is deferred; (b) bogus heads like `Mathf` are not project nodes, so `resolve_call_targets` sets their `callee_file=None` — no false CROSS-CLASS edge is created, only a noisier `callee` string. To let consumers distinguish, **mark call edges whose receiver type came from this heuristic with `confidence: "INFERRED"`** instead of `EXTRACTED`. Document the limitation in the function docstring.

**[NOT BLOCKING]** True cross-file return-type inference is a future enhancement requiring a method-return index; do NOT attempt here.

**Test Type:** stdlib extractor assert (see T6) — positive (`InputActionAsset.FromJson` → `asset` typed `InputActionAsset`) and negative (`var b = obj.get(); b.Use` leaves head `b`, no false project edge).

**Code Skeleton:**
```python
# _local_var_symbols, in the `if not tname and is_var:` block, after object_creation:
if not tname:
    inv = next((c for c in decl.named_children if c.type == "invocation_expression"), None)
    if inv is not None:
        fn = inv.child_by_field_name("function")
        if fn is not None and fn.type == "member_access_expression":
            recv = fn.child_by_field_name("expression")
            if recv is not None and recv.type == "identifier":
                tok = _node_text(recv, src)
                if tok and tok[0].isupper():     # PascalCase static receiver heuristic
                    tname = tok                   # NOTE: declaring type, not return type
```
> Threading the `INFERRED` confidence onto the emitted edge requires marking which symbols were heuristic-derived (e.g. a parallel `heuristic_syms` set) and setting `"confidence": "INFERRED"` in `_extract_calls` when the resolved receiver type came from one. Keep it simple; if threading proves invasive, fall back to leaving confidence `EXTRACTED` and record the limitation explicitly in the task's completion note.

**Acceptance Criteria:**
- `var a = Type.StaticMethod(...)` gives `a` the type `Type`; subsequent `a.Method()` callees become `Type.Method`.
- Non-PascalCase / instance-method initializers leave the local untyped (no false positives).
- Heuristic-derived receiver edges carry `INFERRED` (or, if threading deferred, the limitation is documented).
- No regression to explicit-type or `new T()` inference.

---

## Task 5 — RC4: class-granularity + interface→concrete matching in traversal

**Files:**
- `.claude/graph/graph_bfs_core.py`
- `.claude/graph/graph-traversal.py`
- `.claude/graph/graph-mcp-server.py`

**Design decision — bridge at QUERY time, adjacency owned by the shared cores.** Implement matching + interface→concrete bridge in `graph_bfs_core.py` (NOT build-time extra edges, which would double-count degree in analyze/cluster/god_nodes and make `callee` lie). **Adjacency ownership:** `impact`/`path` traverse `forward`/`reverse` that are built INDEPENDENTLY in both `graph-traversal.py:36-42` and `graph-mcp-server.py:85-91`. To fix both without divergence, build the class-granularity adjacency INSIDE the core functions from the `edges` param, and route `graph-mcp-server.py` through the same cores. `callers_core` already reads `edges` directly, so its matcher covers both callers paths automatically.

**Design decision — bridge is ONE-DIRECTIONAL (concrete → interface), BY DESIGN.** `match_keys("SoundManager")` expands to `{SoundManager, ISoundService}` so a concrete-class query catches interface-routed callers. A method-level query bridges the SAME direction (REV-methodbridge): `match_keys("SoundManager.Play")` expands to `{"SoundManager.Play": exact, "ISoundService.Play": interface_bridge}` so `callers SoundManager.Play` also sees DI callers targeting `ISoundService.Play` — without this (the raw v1.2 behaviour) a method query silently returned FEWER callers than the bare-class query, an asymmetry with no justification. The reverse (`callers ISoundService` expanding to every implementer's callers) is deliberately NOT done: an interface query should return callers of the interface itself, not be inflated with each implementer's direct callers. Do not add a bidirectional bridge later — it would double-count degree in `god_nodes`/`analyze`/`cluster` and conflate distinct call relationships. This asymmetry is intentional; document it in the code comment on `match_keys`.

**Known limitation — interface-bridge hits are implementer-ambiguous.** Because DI call sites target the interface (`ISoundService.Play`), a bridge match cannot know WHICH implementer actually receives the call at runtime. If `ISoundService` has two implementers (e.g. production `SoundManager` + a test `FakeSoundService` — test fakes are normal in this repo per `rules/testing.md`), `callers SoundManager` will include callers that may really be exercising the fake. This is inherent to interface-level resolution, not fixable at graph-build time. Mitigation: LABEL each caller hit with how it matched (`matched_via`) so a human/consumer can tell a direct call from an interface-bridge inference (Step 3a below).

**Steps:**
1. [x] In `graph_bfs_core.py`, add `implements_map(g)` → `{concrete_class: set(interfaces)}` from `codebase.classes[].implements`.
2. [x] Add `match_keys(node, g)` → returns a dict `{key: match_kind}`. For a method-specific arg (`Class.Method`): `{node: "exact"}` PLUS `{f"{iface}.{method}": "interface_bridge"}` for each interface of the head class (so a method query still reaches interface-routed DI callers — REV-methodbridge). For a bare-class arg (`Class`): `{head: "class_prefix"}` plus `{iface: "interface_bridge"}` for each interface of `head`. Add a comment stating the bridge is one-directional (concrete→interface) by design (see Design decision above).
3. [x] Add `_callee_match_kind(callee, keys)` → returns the matching `match_kind` with priority `exact` > `class_prefix` > `interface_bridge`, or `None`. Match on callee's head OR full string == key, or `callee.startswith(key + ".")`.
3a. [x] **[REV1 — multi-implementer disambiguation]** In `callers_core`, attach `"matched_via": <kind>` to every emitted hit — one of `"exact"` (full `Class.Method` match), `"class_prefix"` (call on the concrete class itself), `"interface_bridge"` (matched only through an implemented interface, hence implementer-ambiguous). One-line addition to the hit dict.
4. [x] Rewrite `callers_core` filter (line 107) from `e.get("callee") == node` to compute `kind = _callee_match_kind(e.get("callee",""), match_keys(node, g))` and keep the edge iff `kind is not None`, tagging the hit with `matched_via=kind`.
5. [x] **[REV6 — implements-edges-as-relations for impact/path]** Add `class_adjacency(edges, g)` → `(fwd_class, rev_class)` that (a) collapses each edge's `caller`/`callee` to head tokens, AND (b) makes `implements` a first-class BFS relation (graphify's `affected.py` model) rather than a query-time key bridge. **Direction is critical and now explicit in the skeleton:** for every `codebase.classes[].implements` entry add `rev_class[concrete].add(interface)` (+ symmetric `fwd_class[interface].add(concrete)`). The reverse link is the one that matters — `impact`/upstream walks `rev_class`, so `impact <concrete>` can only reach a caller that targets the interface if `rev_class[concrete] ∋ interface`. Putting the link on `fwd_class[concrete]` instead (the intuitive but WRONG choice) leaves upstream BFS unable to reach interface-only callers, and the bug would surface only at T6. `impact_core`/`path_core` then BFS normally over this adjacency for a bare-class arg; keep method-granularity when the arg contains `.`. (`callers_core` keeps `match_keys` — it is one-hop and needs per-edge `matched_via` labels.)
6. [x] Route `graph-mcp-server.py` (85-91) through the shared `graph_bfs_core` cores (import + call) instead of its inline adjacency, so MCP and CLI return identical sets. (Even though `hybrid_graph` is DISABLED, keep them in lockstep.)
6a. [x] **[MCP reload freshness]** The MCP server caches `_g`, `_forward`, `_reverse`, `_edges` at module level (~line 97). `class_adjacency`/`implements_map` are built from the `g`/`edges` passed in, so they are only as fresh as the cache. VERIFY the server's `_graph_mtime` reload path refreshes `_g` (the full graph dict, source of `implements`), not merely the adjacency indices — otherwise after a graph rebuild the interface bridge runs on stale `implements` data. If the reload path does not already re-read `_g`, fix it to do so.
7. [x] Confirm `all_nodes` (41-48) still lists bare class names so `check_node` accepts `SoundManager`.

**Test Type:** `verify-graphify.sh` full-build case + stdlib `test/test_traversal_resolution.py` on in-memory graph dicts (see T6).

**Code Skeleton:**
```python
# graph_bfs_core.py
def implements_map(g):
    m = defaultdict(set)
    for cls in g.get("codebase", {}).get("classes", []):
        n = cls.get("name")
        for iface in cls.get("implements", []) or []:
            if n:
                m[n].add(iface)
    return m

def match_keys(node, g):
    # One-directional BY DESIGN: concrete -> its interfaces only.
    # Do NOT bridge interface -> implementers (would inflate degree, conflate callers).
    im = implements_map(g)
    if "." in node:                                # method-specific query
        head, _, method = node.partition(".")
        keys = {node: "exact"}
        for iface in im.get(head, set()):          # REV-methodbridge: reach ISvc.Method DI callers
            keys.setdefault(f"{iface}.{method}", "interface_bridge")
        return keys
    keys = {node: "class_prefix"}                  # bare-class query
    for iface in im.get(node, set()):
        keys.setdefault(iface, "interface_bridge")
    return keys

_KIND_PRIORITY = {"exact": 0, "class_prefix": 1, "interface_bridge": 2}

def _callee_match_kind(callee, keys):
    head = callee.split(".", 1)[0]
    best = None
    for t, kind in keys.items():
        if callee == t or head == t or callee.startswith(t + "."):
            if best is None or _KIND_PRIORITY[kind] < _KIND_PRIORITY[best]:
                best = kind
    return best

# callers_core: replace the exact-match filter
targets = match_keys(node, g)
hits = []
for e in edges:
    kind = _callee_match_kind(e.get("callee", ""), targets)
    if kind is not None:
        hit = mk_hit(e)
        hit["matched_via"] = kind          # "exact" | "class_prefix" | "interface_bridge"
        hits.append(hit)

# impact_core / path_core adjacency — implements is a first-class relation (REV6).
# DIRECTION IS LOAD-BEARING: the two implements lines below must go on rev_class
# (concrete -> interface) or impact(<concrete>) never reaches interface-only callers.
def class_adjacency(edges, g):
    fwd_class, rev_class = defaultdict(set), defaultdict(set)
    for e in edges:
        ch = (e.get("caller") or "").split(".", 1)[0]
        eh = (e.get("callee") or "").split(".", 1)[0]
        if ch and eh:
            fwd_class[ch].add(eh)          # caller -> callee
            rev_class[eh].add(ch)          # callee -> caller (upstream / impact walk)
    for concrete, ifaces in implements_map(g).items():
        for iface in ifaces:
            rev_class[concrete].add(iface)  # REV6: upstream(impact) steps concrete -> interface
            fwd_class[iface].add(concrete)  # symmetric; forward/path from interface -> impl
    return fwd_class, rev_class
```

**Acceptance Criteria:**
- `callers SoundManager` returns real callers on the sample project (previously 0), including those calling `ISoundService.<method>`.
- **[REV1]** Each caller hit carries `matched_via` ∈ {`exact`, `class_prefix`, `interface_bridge`}: a call to `SoundManager.<m>` from a bare-class query is `class_prefix`, one to `ISoundService.Play` is `interface_bridge`, and a `callers SoundManager.Play` hit on `SoundManager.Play` is `exact`.
- When an interface has ≥2 implementers, `callers <concrete>` still returns interface-bridge hits, all labeled `interface_bridge` (implementer-ambiguous by nature — documented, not a bug).
- `callers ISoundService` returns callers of the interface only; it is NOT expanded to each implementer's direct callers (one-directional bridge).
- **[REV-methodbridge]** `callers SoundManager.Play` matches `Play` sites (`matched_via="exact"`) AND `ISoundService.Play` DI callers (`matched_via="interface_bridge"`), but no other methods — a method query is no longer poorer than the bare-class query.
- **[REV6]** `impact`/`path` on a bare class name traverse a `class_adjacency` graph in which `implements` is a first-class relation wired `rev_class[concrete] ∋ interface`; `impact <concrete>` reaches callers that only touch its interface (verified in T6).
- `graph-traversal.py` and `graph-mcp-server.py` return identical caller sets for the same node, and the MCP result stays correct across a graph rebuild (reload refreshes `_g`).
- Existing exact-match `callers X.Method` queries return the same hits as before.

---

## Task 6 — Tests + verification

**Files:**
- `.claude/graph/test/test_extractor_pubsub.py`
- `.claude/graph/test/test_traversal_resolution.py` (new)
- `.claude/graph/test/fixtures/call_resolution/` (new, + `EXPECTED.md`)
- `.claude/graph/test/verify-graphify.sh`

**Convention note (IMPORTANT):** `test_extractor_pubsub.py` is **stdlib-only** — own `_run()` harness, run via `python3 test/test_extractor_pubsub.py`, SKIPs cleanly when tree-sitter is unavailable. Do NOT introduce pytest (contradicts the earlier brief; the real convention wins).

**Steps:**
1. [x] Add extractor asserts from T1/T3/T4 into `test/test_extractor_pubsub.py` (reuse existing `_facts`/`_extract` helpers): callee_file/callee_class None from extractor; fluent-chain single-line callee; lambda-subscribe callee; `Type.FromJson` factory local.
2. [x] Create `test/fixtures/call_resolution/` with 2–3 minimal self-contained `.cs` files: a cross-class caller/callee pair (RC1), a DOTween-style fluent+lambda chain (RC2), a `Type.FromJson(...)` factory local (RC3), an interface-routed DI call + concrete implementer (RC4). Add `EXPECTED.md` in the exact style of `test/fixtures/pubsub_realworld/EXPECTED.md`.
3. [x] Create `test/test_traversal_resolution.py` (stdlib `_run()` harness copied from `test_extractor_pubsub.py`) asserting RC4 `callers_core`/`impact_core`/`path_core` on in-memory graph dicts — no file I/O, no build. Include:
   - interface→concrete bridge: `callers_core("SoundManager")` finds a caller of `ISoundService.Play`, hit tagged `matched_via == "interface_bridge"`;
   - class_prefix match: a caller of `SoundManager.Play` from a bare-class query is tagged `matched_via == "class_prefix"`;
   - exact match: `callers_core("SoundManager.Play")` matches only `Play`, tagged `matched_via == "exact"`;
   - **method-query bridge (REV-methodbridge):** `callers_core("SoundManager.Play")` ALSO returns a caller of `ISoundService.Play`, tagged `matched_via == "interface_bridge"` (method query is not poorer than the bare-class query);
   - **multi-implementer (REV1):** a graph where `ISoundService` is implemented by BOTH `SoundManager` and `FakeSoundService` → `callers_core("SoundManager")` returns the `ISoundService.Play` caller as `interface_bridge` (asserting the known ambiguity is surfaced, not hidden);
   - **one-directional (REV3):** `callers_core("ISoundService")` is NOT expanded to `SoundManager`'s direct callers;
   - **REV6 impact (direction guard):** `impact_core("SoundManager")` reaches a class that only calls `ISoundService.Play` — this passes ONLY if `class_adjacency` wired `rev_class[concrete] ∋ interface`; a `fwd_class`-only wiring fails this assert.
3a. [x] **[REV5 method_match]** Add a builder-level assert (in the incremental fixture test or a small unit): a resolved edge whose callee method is present in the resolved class's populated `methods[]` gets `method_match == True`; one whose method is absent (but `methods[]` populated) gets `method_match == False`; an edge to a class with EMPTY `methods[]` gets `method_match is None`. Assert `confidence` is UNCHANGED by this check, and that a full rebuild and an incremental rebuild produce the same `method_match` for the same edge.
4. [x] Add a **builder-level incremental fixture test** (RC1 blocker guard): run two consecutive incremental builds where only the CALLEE's file is edited, assert the cross-file caller→callee edge survives the second build.
4a. [x] **[REV4 same-name tie-breaker]** Add a fixture: a production `Foo.cs` and a same-named class in a `Tests/` folder both declaring `Foo`; assert a call to `Foo.Bar` resolves `callee_file` to the PRODUCTION `Foo.cs`, not the test one; and a second fixture with two NON-test `Foo`s asserts `callee_class` is left `None` (no guess).
5. [x] Add a `verify-graphify.sh` T6-section sub-case: full build → `graph-traversal.py callers <concrete class>` returns ≥1; and `graph_validate.py` clean-exit assert. Follow the existing `pass`/`fail`/`known_fail`/`[SKIP] … template mode` idiom, guard on the repo having C# (`UNITY_HAS_CS`).
6. [x] Run full `test/test_extractor_pubsub.py` + `test/verify-graphify.sh` to confirm no regression in pub/sub, registrations, implementers, R1–R6, incremental sections.

**Test Type:** this task IS the test task — both harnesses green.

**Acceptance Criteria:**
- New fixtures + `EXPECTED.md` under `test/fixtures/call_resolution/`, matching the `pubsub_realworld` style.
- `python3 test/test_extractor_pubsub.py` and `python3 test/test_traversal_resolution.py` print `OK` (or `SKIP` when tree-sitter absent).
- Two-build incremental test proves cross-file edges survive callee-only edits.
- `test/verify-graphify.sh` passes including new callers/validator cases and all pre-existing sections.
- No pytest dependency introduced.
