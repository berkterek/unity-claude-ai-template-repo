# PLAN — Graph Extractor AST Fix (pub/sub + registrations) & graph.html Visualizer

> **Version:** v1 — 2026-07-14
> **Status:** Active
> **Scope:** `.claude/graph/` Python tooling only — `extractors/csharp_extractor.py`, a new `graph-viz.py`, and the `/build-knowledge-graph` wiring. No Unity C# runtime code is touched.

**Complexity: 0.55 — Medium** (two-file logic change + one new generator + regression tests; no Unity runtime, no ECS/Addressables).

## Context

Empirical testing against the real `nile_hole_sphere_repo` project (94 classes, 22 events, 898 calls) exposed a concrete extraction bug. The graph reported **0 event publishers** while the source contains **36 real `Publish` call sites**. Root cause: `csharp_extractor.py::_detect_vcontainer` flattens the class-body AST node back to raw text and runs `re.finditer(r'\w+\.(Publish|Subscribe|Unsubscribe)<([A-Za-z0-9_]+)>', text)`. That regex only matches the **generic** form `Publish<T>(…)`. Real publish code uses the **type-inferred** form `_eventBus.Publish(new SettingsClosedEvent())` — no angle brackets — so every publisher is missed. `Subscribe<T>` survives only because subscribe has no argument to infer from and is therefore always generic.

The identical root cause affects VContainer registrations: the same function only catches `builder.Register<T>(…)` and explicitly skips `builder.RegisterInstance(config)` (comment: *"type from variable name not available, skip"*). That non-generic form is the standard bootstrap pattern (`AudioModule.Install(builder, config)` → `builder.RegisterInstance(config)`), so registrations are also under-reported. The `--accuracy` validator reads 100% because build and re-validation run the **same** broken regex and agree with each other — self-consistency, not ground truth.

The fix is to replace the two text-regex detectors with AST-node walks (mirroring the existing `_extract_invocations`), reading `invocation_expression → member_access_expression → identifier | generic_name` and, for the non-generic case, the first `argument → object_creation_expression`. Phase 2 then adds a self-contained `graph.html` force-directed visualizer (Graphify's most valuable feature we lack); it is sequenced after the fix so it renders correct publisher data rather than the current empty set.

## Goals

- [ ] Detect event publishers/subscribers via AST, catching both `Publish<T>(…)` and `Publish(new T())`
- [ ] Detect VContainer registrations via AST, catching both `Register<T>()` and `RegisterInstance(localVar)` (with local type resolution + never-silently-drop fallback)
- [ ] Add stdlib-only regression tests that pin both patterns, wired into `verify-graphify.sh`
- [ ] Verify on `nile_hole_sphere_repo`: publishers non-empty and consistent with the 36 grep sites
- [ ] Add `graph-viz.py` → self-contained `graph.html` (no external CDN), resolving `$partition` refs
- [ ] Wire optional `graph.html` emission into `/build-knowledge-graph` and document it

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — AST pub/sub + registration detection | ⏳ Pending | — |
| 1 | Task 7 — Loud warning + validator hardening (regex-fallback + unresolved regs) | ⏳ Pending | — |
| 1 | Task 2 — Regression tests (stdlib) | ⏳ Pending | — |
| 1 | Task 3 — Harvest real snippets into repo fixtures + verify | ⏳ Pending | — |
| 2 | Task 4 — `graph-viz.py` generator | ⏳ Pending | — |
| 2 | Task 5 — Wire into `/build-knowledge-graph` + docs + gitignore | ⏳ Pending | — |
| 2 | Task 6 — Viz smoke test | ⏳ Pending | — |

> Ordering note: Task 4's code has **no** dependency on Task 1 (it only reads `graph.json`), so Tasks 1 and 4 *could* run in parallel. They are kept sequential per the chosen "fix first, then viz" ordering so Task 6 verifies the visualizer against corrected data.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/extractors/csharp_extractor.py` | Modify | Rewrite `_detect_vcontainer` as AST walk; add local symbol table helper for `RegisterInstance(var)`; tag unresolved regs `unresolved:true`/AMBIGUOUS |
| `.claude/graph/graph-builder.py` | Modify | Emit loud warning to `validation.warnings[]` + stderr when the regex-fallback `.sh` path is used (D1) |
| `.claude/graph/graph_validate.py` | Modify | Consistency mode must not flag `unresolved:true` regs as dangling (D3) |
| `.claude/graph/extractors/csharp-extractor.sh` | (unchanged) | Left as-is; its silent under-report is covered by the D1 warning, not a rewrite |
| `.claude/graph/test/test_extractor_pubsub.py` | Add | Stdlib assertions on pub/sub + registration extraction |
| `.claude/graph/test/fixtures/pubsub_realworld/` | Add | Real pub/sub + RegisterInstance snippets harvested from the example project (D2) |
| `.claude/graph/test/verify-graphify.sh` | Modify | Invoke the new python test; skip cleanly if tree-sitter unavailable |
| `.claude/graph/graph-viz.py` | Add | Reads `graph.json` (+ resolves `scenes.json`/`prefabs.json` `$partition`), emits self-contained `graph.html` |
| `.claude/commands/build-knowledge-graph.md` | Modify | Document `--viz` flag / emission step |
| `.claude/docs/knowledge-graph.md` | Modify | Document the AST detector change and `graph.html` output |
| `.gitignore` | Modify | Add `.claude/graph/graph.html` — generated artifact, NOT committed (D4) |

---

## Chosen Approach

**Extractor detection — AST walk (chosen) vs. broadened regex (rejected).**
A broadened regex (adding a `Publish\(\s*new\s+(\w+)` alternative) would patch the immediate symptom but keep the fundamental fragility: it breaks on `Publish(BuildEvent())` (factory method, no `new`), `Publish(_cachedEvent)` (variable), multi-line calls, and comments/strings containing the word. The AST walk reads the real call structure and is the same idiom already used by `_extract_invocations` — consistent, robust, and it is exactly the class of fix that regex *cannot* do in principle. Chosen: AST walk. The only case AST cannot resolve without a full type system is `RegisterInstance(localVar)` where `localVar`'s type is not on the same class — handled by a bounded local symbol table (method params + class fields) with a **record-with-empty-type fallback** so a registration is never silently dropped (the current bug).

**Visualizer — self-contained vanilla-JS canvas (chosen) vs. bundled d3/CDN (rejected).**
A strict repo principle is "everything in the repo, stdlib only, no external runtime deps." Pulling d3 from a CDN would break offline use and violate that principle; vendoring minified d3 bloats the repo. Chosen: a single self-contained `graph.html` with an inline vanilla-JS force-directed layout on `<canvas>` — no network, no build step, opens with `file://`. This matches how `graph-mcp-server.py` already loads and `$partition`-resolves the graph.

---

## Task 1 — AST-based pub/sub + registration detection

**Files:**
- `.claude/graph/extractors/csharp_extractor.py`

**Steps:**
1. [ ] Add `_type_name(node, src)` → normalize any type node to its **last segment**. `identifier`/`predefined_type` → text; `generic_name` → its `identifier` child text; `qualified_name` → recurse into `child_by_field_name("name")` (the final segment, which may itself be a `generic_name`, e.g. `Ns.Outer<Foo>` → `Outer`), falling back to the last `identifier` child only when the `name` field is absent. This mirrors the extractor's existing rule of reducing fully-qualified names to their last segment. **Do NOT use `_walk(node,"identifier")[0]` or `_find_children(node,"identifier")[-1]`** — for `Ns.Outer<Foo>` those return `Ns`.
2. [ ] Add `_member_name_and_typearg(member_access_node, src)` → `(method_name, type_arg_or_None)`:
   - name side = `child_by_field_name("name")` (fallback: last named child); if `identifier` → `(text, None)`; if `generic_name` → method = its `identifier` child text, type_arg = `_type_name(first named type node under type_argument_list, src)`. The `type_argument_list`'s payload may be `identifier`, `qualified_name`, or `generic_name` — pass the whole node to `_type_name`.
3. [ ] Add `_first_arg_new_type(inv, src)` → first `argument` under `argument_list`; if it contains an `object_creation_expression`, return `_type_name(` the OCE's first named child that is a type node — `identifier`/`qualified_name`/`generic_name`, i.e. the child before `argument_list` `, src)`; else `None`. (`new Ns.FooEvent()` → `FooEvent`.)
4. [ ] Add `_first_arg_identifier(inv, src)` → first `argument` under `argument_list`; if it is a bare `identifier` (variable reference like `config`), return its text; else `None`.
5. [ ] Add `_class_field_symbols(cls_node, src)` → `{name: type}` from `field_declaration` nodes: each has a `variable_declaration` whose **first named child is the type node** (`identifier`/`qualified_name`/… → `_type_name`) and one or more `variable_declarator` children whose `child_by_field_name("name")` is the field name. There is **no** `child_by_field_name("type")` on `field_declaration` — traverse `variable_declaration` explicitly.
6. [ ] Rewrite detection to be **per-method-scoped** (avoids parameter leakage across methods): compute class field symbols once; then for each `method_declaration` **and** `constructor_declaration` in the class, build `symbols = fields ∪ {param_name: _type_name(param.type)}` for that member's own `parameter_list`, and `_walk(member_body, "invocation_expression")`. For each invocation resolve `(method, type_arg)`:
   - **pub/sub:** if `method in {"Publish","Subscribe","Unsubscribe"}` → event = `type_arg` **else** `_first_arg_new_type(inv)`; append `{action, event}` only when an event is resolved. (Generic form has both `<T>` and `new T()`; preferring `type_arg` first prevents double-count.)
   - **registration:** if `method in {"Register","RegisterInstance","RegisterComponent","RegisterEntryPoint","RegisterComponentInHierarchy"}` → `t = type_arg`; if none and `method == "RegisterInstance"` → try `_first_arg_new_type(inv)` then `symbols.get(_first_arg_identifier(inv), "")`. Append the registration **even when `t == ""`** (never skip — the silent skip is the current bug). When `t == ""`, tag it `{"type":"", "unresolved": true, "confidence":"AMBIGUOUS"}` so downstream can surface (not silently mishandle) it — per Grill decision D3.
7. [ ] Update `extract_file` to call the per-member detector per class; delete the old `re.finditer` blocks. Remove `import re` if no longer used anywhere in the file.
8. [ ] Chained calls (`Register<T>(…).AsImplementedInterfaces()`): walking every `invocation_expression` visits the inner `Register<T>` invocation directly; confirm the outer `.AsImplementedInterfaces()` invocation resolves to method `AsImplementedInterfaces` (not in either set) and is ignored — exactly one registration results.

**Test Type:** stdlib Python unit (see Task 2) — this is tooling, not Unity C#; the Unity Test Type Matrix does not apply.

**Code Skeleton:**
```python
_TYPE_NODES = {"identifier", "qualified_name", "generic_name", "predefined_type"}

def _type_name(node, src):
    # normalize any type node to its LAST segment (Ns.Outer<Foo> -> Outer)
    if node is None: return None
    if node.type == "qualified_name":
        name = node.child_by_field_name("name")          # final segment (may be generic_name)
        if name is not None:
            return _type_name(name, src)
        idents = _find_children(node, "identifier")
        return _node_text(idents[-1], src) if idents else None
    if node.type == "generic_name":
        idents = _find_children(node, "identifier")
        return _node_text(idents[0], src) if idents else None
    return _node_text(node, src)  # identifier / predefined_type

def _member_name_and_typearg(func, src):        # func = member_access_expression
    name = func.child_by_field_name("name") or func.named_children[-1]
    if name.type == "identifier":
        return _node_text(name, src), None
    if name.type == "generic_name":
        method = _find_children(name, "identifier")[0]
        tal = next((c for c in name.children if c.type == "type_argument_list"), None)
        payload = next((c for c in tal.named_children if c.type in _TYPE_NODES), None) if tal else None
        return _node_text(method, src), _type_name(payload, src)
    return None, None

def _first_arg_node(inv, src, kind_filter):
    args = inv.child_by_field_name("arguments")            # argument_list
    if not args: return None
    arg = next((c for c in args.named_children if c.type == "argument"), None)
    if not arg: return None
    return next((c for c in arg.named_children if kind_filter(c)), None)

def _first_arg_new_type(inv, src):
    oce = _first_arg_node(inv, src, lambda c: c.type == "object_creation_expression")
    if not oce: return None
    tnode = next((c for c in oce.named_children if c.type in _TYPE_NODES), None)
    return _type_name(tnode, src)

def _first_arg_identifier(inv, src):
    idn = _first_arg_node(inv, src, lambda c: c.type == "identifier")
    return _node_text(idn, src) if idn else None

def _detect_member(member_body, src, symbols, registrations, pub_sub):
    PUBSUB = {"Publish", "Subscribe", "Unsubscribe"}
    REG = {"Register","RegisterInstance","RegisterComponent","RegisterEntryPoint","RegisterComponentInHierarchy"}
    for inv in _walk(member_body, "invocation_expression"):
        func = inv.child_by_field_name("function")
        if not func or func.type != "member_access_expression":
            continue
        method, type_arg = _member_name_and_typearg(func, src)
        if method in PUBSUB:
            ev = type_arg or _first_arg_new_type(inv, src)   # generic wins -> no double count
            if ev: pub_sub.append({"action": method, "event": ev})
        elif method in REG:
            t = type_arg
            if not t and method == "RegisterInstance":
                t = _first_arg_new_type(inv, src) or symbols.get(_first_arg_identifier(inv, src), "")
            reg = {"type": t or "", "as": "", "lifetime": ""}   # never skip
            if not t:
                reg["unresolved"] = True; reg["confidence"] = "AMBIGUOUS"   # D3
            registrations.append(reg)

def _class_field_symbols(cls_node, src):
    syms = {}
    body = cls_node.child_by_field_name("body")
    if not body: return syms
    for fd in _find_children(body, "field_declaration"):
        vd = next((c for c in fd.named_children if c.type == "variable_declaration"), None)
        if not vd: continue
        tnode = next((c for c in vd.named_children if c.type in _TYPE_NODES), None)
        tname = _type_name(tnode, src)
        for decl in _find_children(vd, "variable_declarator"):
            nm = decl.child_by_field_name("name")
            if nm and tname: syms[_node_text(nm, src)] = tname
    return syms

def _detect_vcontainer(cls_node, src):
    registrations, pub_sub = [], []
    fields = _class_field_symbols(cls_node, src)
    body = cls_node.child_by_field_name("body")
    for member in (_find_children(body, "method_declaration")
                   + _find_children(body, "constructor_declaration")) if body else []:
        symbols = dict(fields)
        plist = member.child_by_field_name("parameters")
        if plist:
            for p in _find_children(plist, "parameter"):
                pn = p.child_by_field_name("name"); pt = p.child_by_field_name("type")
                if pn and pt: symbols[_node_text(pn, src)] = _type_name(pt, src)
        mbody = member.child_by_field_name("body")
        if mbody: _detect_member(mbody, src, symbols, registrations, pub_sub)
    return registrations, pub_sub
```
> Note: `_detect_vcontainer` now takes the **class node** (not the body) so it can scope fields + per-member params. Update the `extract_file` call site accordingly.

**Acceptance Criteria:**
- Parsing `_eventBus.Publish(new SettingsClosedEvent())` yields `events_published == ["SettingsClosedEvent"]`.
- Parsing `_eventBus.Publish<GoldChangedEvent>(new GoldChangedEvent(5))` yields `["GoldChangedEvent"]` (no double-count).
- Parsing `_eventBus.Subscribe<XEvent>(OnX)` still yields `events_subscribed == ["XEvent"]`.
- `builder.RegisterInstance(config)` where an enclosing param is `AudioConfiguration config` yields `{"type":"AudioConfiguration"}`; if unresolved, `{"type":"", "unresolved":true, "confidence":"AMBIGUOUS"}` — never dropped (D3).
- `builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces()` yields exactly one registration `{"type":"AudioService"}`.
- No `re.finditer` remains in `_detect_vcontainer`.

---

## Task 2 — Regression tests (stdlib only)

**Files:**
- `.claude/graph/test/test_extractor_pubsub.py` (Add)
- `.claude/graph/test/verify-graphify.sh` (Modify)

**Steps:**
1. [ ] Write `test_extractor_pubsub.py` importing `extract_file` from `csharp_extractor.py` (via `importlib` on the hyphen-free module path) and a shared parser; assert every acceptance case from Task 1 using plain `assert` + a `__main__` runner that prints `OK`/exits non-zero on failure. No pytest — stdlib only.
2. [ ] Cover: non-generic publish, generic publish, subscribe, `RegisterInstance(var)` resolved, `RegisterInstance(var)` unresolved → `""`, chained `Register<T>().AsImplementedInterfaces()` single-count.
3. [ ] In `verify-graphify.sh`, add a step that runs `python3 test/test_extractor_pubsub.py`; if `csharp_extractor.py` exits 2 (tree-sitter unavailable) → print SKIP and do not fail the suite (mirror existing accuracy skip behavior).

**Test Type:** N/A — this task *is* the test.

**Code Skeleton:**
```python
# test_extractor_pubsub.py
import importlib.util, os
spec = importlib.util.spec_from_file_location(
    "csx", os.path.join(os.path.dirname(__file__), "..", "extractors", "csharp_extractor.py"))
csx = importlib.util.module_from_spec(spec); spec.loader.exec_module(csx)

def _facts(code):
    lang, Parser = csx._try_import()
    res = csx.extract_file(Parser(lang), "mem.cs", code.encode())
    return res["classes"][0]

def test_non_generic_publish():
    c = _facts("namespace N{class S{void M(IEventBus b){ b.Publish(new FooEvent()); }}}")
    assert c["events_published"] == ["FooEvent"], c["events_published"]
# … remaining cases …
if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"): fn()
    print("OK")
```

**Acceptance Criteria:**
- `python3 .claude/graph/test/test_extractor_pubsub.py` prints `OK` and exits 0 after Task 1.
- The same test **fails** against the pre-fix extractor (proves it pins the bug).
- `verify-graphify.sh` runs the test and SKIPs (not fails) when tree-sitter is absent.

---

## Task 3 — Harvest real-world snippets into repo fixtures + verify (D2)

**Files:**
- `.claude/graph/test/fixtures/pubsub_realworld/` (Add — committed `.cs` snippet files)

**Rationale (D2):** ground-truth verification must be **repo-internal and CI-repeatable**, not dependent on an external project's current state. The example repo (`nile_hole_sphere_repo`) is used **once** as a *source of realistic code shapes*, then those shapes are captured as committed fixtures.

**Steps:**
1. [ ] From the example project, harvest a handful of **real** call shapes into small committed `.cs` fixtures: `_eventBus.Publish(new SettingsClosedEvent())`, `_eventBus?.Publish(new GoldChangedEvent(x))` (null-conditional), a chained `builder.Register<T>(Lifetime.Singleton).AsImplementedInterfaces()`, a `builder.RegisterInstance(config)` with a resolvable enclosing param, and a `Subscribe<T>`. Strip to minimal compilable classes; do NOT copy `.meta`.
2. [ ] Extend `test_extractor_pubsub.py` (Task 2) to also run `extract_file` over each fixture file and assert the expected publishers/subscribers/registrations.
3. [ ] Record the expected facts per fixture in the test (a small table of `file → expected pub/sub/reg`).
4. [ ] (One-time, non-repeatable) Optionally sanity-check against the live example repo's 36 grep sites while harvesting — this is a manual convenience, NOT a plan acceptance gate.

**Test Type:** stdlib Python (folded into Task 2's runner).

**Acceptance Criteria:**
- Fixtures under `test/fixtures/pubsub_realworld/` are committed and self-contained (no external path references).
- `test_extractor_pubsub.py` verifies every fixture and passes after Task 1; the null-conditional `_eventBus?.Publish(new T())` case is explicitly covered.
- No step in this task depends on `nile_hole_sphere_repo` being present at run time.

---

## Task 7 — Loud warning on regex-fallback path + validator hardening (D1, D3)

**Files:**
- `.claude/graph/graph-builder.py` (Modify)
- `.claude/graph/graph_validate.py` (Modify)

**Rationale:** The fix only corrects the tree-sitter path. If tree-sitter is absent at build time, the regex-fallback `.sh` still silently under-reports pub/sub + registrations (D1). And unresolved registrations now carry `unresolved:true` (D3) which the consistency validator must not misread.

**Steps:**
1. [ ] In `graph-builder.py`, detect when the fallback `.sh` extractor was used (tree-sitter path exited 2 / unavailable). When it was, append a `validation.warnings[]` entry — e.g. `{"code":"FALLBACK_EXTRACTOR","message":"tree-sitter unavailable — pub/sub + registration data is LOW CONFIDENCE (regex fallback under-reports non-generic Publish/RegisterInstance)."}` — and echo the same to stderr so an interactive build is not silently degraded.
2. [ ] Surface this via `/knowledge-graph violations` (it already reads `validation.warnings[]`).
3. [ ] In `graph_validate.py` consistency mode, treat registrations with `unresolved:true` as **known-incomplete**, not dangling — do not emit a dangling/missing-class issue for them; optionally count them under a separate `unresolved_registrations` tally.
4. [ ] `/knowledge-graph registrations <Class>` (docs in Task 5) shows `unresolved` regs distinctly (e.g. `RegisterInstance(?) — unresolved`) rather than an empty type.

**Test Type:** stdlib Python / fixture assertion.

**Acceptance Criteria:**
- A build where tree-sitter is forced unavailable produces the `FALLBACK_EXTRACTOR` warning in both `validation.warnings[]` and stderr.
- `graph_validate.py` consistency mode does NOT report `unresolved:true` regs as dangling.
- The warning is visible through `/knowledge-graph violations`.

---

## Task 4 — `graph-viz.py` self-contained visualizer

**Files:**
- `.claude/graph/graph-viz.py` (Add)

**Steps:**
1. [ ] Load `graph.json`; resolve `$partition` refs by **mirroring `graph-mcp-server.py`'s recursive resolver** (~lines 52–77): walk any dict that is exactly `{"$partition": "<file>"}` and replace it with the parsed sibling file, resolved relative to the graph's own dir. Match the server's fail-fast behavior when a referenced partition file is missing (raise/exit with a clear message) rather than silently substituting `[]` — a silent `[]` would hide a broken graph.
2. [ ] Build nodes from `classes` (color by `is_mono_behaviour`), `interfaces`, `events`; build edges from `calls` (caller→callee), `implements` (class→interface), and pub/sub (class→event, distinct style for publish vs subscribe). If registration edges are drawn, **skip any registration with `unresolved:true`** (D3) — an empty-type reg has no valid target node.
3. [ ] Emit one self-contained `graph.html`: inline `<style>`, inline JSON as a `<script>` data island, inline vanilla-JS force-directed layout on `<canvas>` (Barnes-Hut not required; simple O(n²) repulsion + spring is fine for ≤ a few hundred nodes). Include hover-to-label, drag, and a type legend. No external URLs.
4. [ ] CLI: `python3 graph-viz.py [--graph PATH] [--out PATH]`, defaults to `.claude/graph/graph.json` → `.claude/graph/graph.html`. Exit non-zero with a clear message if `graph.json` missing.
5. [ ] Guard node count: if > ~800 nodes, still render but log a stderr note (viz gets dense) — never silently truncate.

**Test Type:** stdlib smoke test (Task 6).

**Code Skeleton:**
```python
def _resolve_partition(obj, base_dir):
    # mirror graph-mcp-server.py: any {"$partition": "<file>"} (len==1) -> parsed sibling
    if isinstance(obj, dict):
        if len(obj) == 1 and "$partition" in obj:
            part = os.path.join(base_dir, obj["$partition"])
            if not os.path.exists(part):
                raise FileNotFoundError(f"graph partition missing: {part}")
            with open(part, encoding="utf-8") as fh:
                return _resolve_partition(json.load(fh), base_dir)
        return {k: _resolve_partition(v, base_dir) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_resolve_partition(v, base_dir) for v in obj]
    return obj

def load_graph(path):
    with open(path, encoding="utf-8") as fh:
        raw = json.load(fh)
    return _resolve_partition(raw, os.path.dirname(os.path.abspath(path)))

def build_nodes_edges(g):
    cb = g["codebase"]; nodes = []; edges = []
    # classes / interfaces / events → nodes ;  calls / implements / pub-sub → edges
    return nodes, edges

def render_html(nodes, edges):
    data = json.dumps({"nodes": nodes, "edges": edges})
    return HTML_TEMPLATE.replace("/*DATA*/", data)   # single f-string template, no CDN
```

**Acceptance Criteria:**
- `python3 graph-viz.py --graph <example graph.json> --out /tmp/g.html` produces a file that opens offline with zero network requests (grep the output for `http://`/`https://`/`//cdn` → none in resource positions).
- Node count in the HTML data island equals `len(classes)+len(interfaces)+len(events)`.
- After Task 1's fix, publish edges are present (non-empty) for the example graph.

---

## Task 5 — Wire into `/build-knowledge-graph` + docs

**Files:**
- `.claude/commands/build-knowledge-graph.md` (Modify)
- `.claude/docs/knowledge-graph.md` (Modify)

**Steps:**
1. [ ] Add an optional `--viz` step to the build pipeline docs: after export, run `graph-viz.py` to emit `graph.html`. Decide default: emit only on `--viz` (keep default build fast) — document the flag.
2. [ ] In `knowledge-graph.md`, document (a) the AST-based pub/sub + registration detection replacing the regex (update the "Extractor Reliability Notes" section — the old regex caveats are now obsolete), and (b) the new `graph.html` output + how to open it.
3. [ ] Add `.claude/graph/graph.html` to `.gitignore` (D4 — generated artifact, not committed; regenerated in one command; no machine consumer, unlike the committed `graph.json`).
4. [ ] Document in `knowledge-graph.md` that `/knowledge-graph registrations <Class>` shows `unresolved:true` regs distinctly (not as empty type), and that a `FALLBACK_EXTRACTOR` warning means pub/sub data is low-confidence.

**Test Type:** N/A — docs.

**Acceptance Criteria:**
- `build-knowledge-graph.md` describes when/how `graph.html` is produced (via `--viz`).
- `knowledge-graph.md`'s reliability notes no longer claim regex-based pub/sub; they describe the AST walk and the `FALLBACK_EXTRACTOR` low-confidence warning.
- `.gitignore` contains `.claude/graph/graph.html`.

---

## Task 6 — Viz smoke test

**Files:**
- `.claude/graph/test/verify-graphify.sh` (Modify)

**Steps:**
1. [ ] Add a step: run `graph-viz.py` against a fixture/sample graph into a temp file; assert the file exists, is non-empty, contains the `<canvas>` element and the data island, and contains **no** external resource URL.
2. [ ] SKIP cleanly if no sample graph is available.

**Test Type:** N/A — this task *is* the test.

**Acceptance Criteria:**
- `verify-graphify.sh` includes a viz step that passes on a sample graph and SKIPs without one.
- The generated HTML passes the no-external-URL grep.

---

## Notes / Risks

- **`RegisterInstance(localVar)` type resolution is best-effort.** The local symbol table covers same-class fields and enclosing-method params; a variable assigned from a method return (`var x = Build(); builder.RegisterInstance(x);`) resolves to `""`. This is acceptable — the registration is still recorded (fixing the silent-drop bug); exact type is a future enhancement, not a regression.
- **Scope of the fix is `csharp_extractor.py` (tree-sitter path) only.** The regex-fallback `csharp-extractor.sh` has the same limitation but is out of scope here (its removal is the separately-agreed "make tree-sitter mandatory" decision). If tree-sitter is unavailable at build time, the fallback still under-reports — the plan does not change that; Task 3/verify assumes tree-sitter present.
- **Viz is intentionally minimal** (no communities/Leiden coloring in v1). Community coloring from `codebase.communities[]` is a fast-follow once the base renders.

---

## Grill-Me Decision Record — 2026-07-14

Four decisions resolved via `/grill-me`; all folded into the tasks above.

| # | Question | Decision | Where applied |
|---|----------|----------|---------------|
| D1 | tree-sitter absent at build → fallback `.sh` silently under-reports | **Add loud warning** (`validation.warnings[]` + stderr, `FALLBACK_EXTRACTOR`), surfaced via `/knowledge-graph violations`. Do NOT rewrite/remove `.sh` in this plan. | Task 7; File Map (`graph-builder.py`) |
| D2 | Ground-truth verification depended on external `nile_hole_sphere_repo` | **Harvest real snippets into committed repo fixtures**; external repo is a one-time shape source, not a run-time dependency. | Task 3 (reframed); File Map (`fixtures/pubsub_realworld/`) |
| D3 | Unresolved `RegisterInstance(var)` recorded as `{"type":""}` could corrupt downstream | **Tag `unresolved:true` + `confidence:"AMBIGUOUS"`**; validator must not flag as dangling; query shows it distinctly; viz skips the edge. | Task 1, Task 7, Task 4, Task 5 |
| D4 | Commit `graph.html` or gitignore? | **gitignore** — generated, one-command-regenerable, no machine consumer (unlike committed `graph.json`). | Task 5; File Map (`.gitignore`) |

Not re-litigated (already decided earlier): single plan / two phases / bug-fix-before-viz ordering; AST-walk over broadened-regex; self-contained vanilla-JS viz over CDN.
