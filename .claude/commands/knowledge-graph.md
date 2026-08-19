# /knowledge-graph — Query the Unity Knowledge Graph

Query the Unity Knowledge Graph without rebuilding it.
All queries read `.claude/graph/graph.json` directly via `jq`.

## Usage

```
/knowledge-graph summary
/knowledge-graph implementers <InterfaceName>
/knowledge-graph publishers <EventName>
/knowledge-graph subscribers <EventName>
/knowledge-graph registrations <InterfaceOrClassName>
/knowledge-graph scope-tree
/knowledge-graph prefab <PrefabName>
/knowledge-graph violations
/knowledge-graph diff
/knowledge-graph callers <Class.Method>
/knowledge-graph impact <ClassName> [--hops N]
/knowledge-graph path <NodeA> <NodeB>
/knowledge-graph god-nodes [--top N]
```

Append `--json` to any subcommand for raw JSON output.

---

## Staleness Check (always run first)

Read `.claude/graph/.last-build`. If the file is missing or the timestamp is older than 24 hours:

```
⚠ Knowledge graph is stale (last built: <timestamp or never>).
  Rebuild with /build-knowledge-graph before querying for accurate results.
  Proceed with stale data? (y/n)
```

If `codebase.calls[]` is absent or empty (graph built before v1.1.0):

```
⚠ Graph has no call edges (built before v1.1.0).
  Rebuild with /build-knowledge-graph --full to enable callers/impact/path/god-nodes.
```

If the user says `n` → stop. If `y` → continue.

---

## Routing (hybrid mode)

When `hybrid_graph` is enabled in `project-features.json`, the four call-graph queries (`callers`, `impact`, `path`, `god-nodes`) are dispatched via `mcp__graph_mcp__*` tools per `.claude/skills/core/knowledge-graph-hybrid.md`. All other subcommands and all output formats are unchanged.

---

## Subcommands

### summary

One-screen project overview.

```bash
jq '{
  classes:    (.codebase.classes    | length),
  interfaces: (.codebase.interfaces | length),
  events:     (.codebase.events     | length),
  installers: (.codebase.vcontainer.installers | length),
  assemblies: (.codebase.assemblies | length),
  scenes:     (.codebase.scenes     | length),
  prefabs:    (.codebase.prefabs    | length),
  generated_at,
  mcp_status: .codebase.mcp_extraction.status,
  errors:     (.validation.errors   | length),
  warnings:   (.validation.warnings | length)
}' .claude/graph/graph.json
```

Also print the scope tree (top-2 levels):
```bash
jq '.codebase.vcontainer.scopes
    | map({scope: .name, parent: .parent, via: .parent_source,
           unresolved: .parent_unresolved_reason})' .claude/graph/graph.json
```

Print the top-5 most-referenced assemblies:
```bash
jq '[.codebase.assemblies[].references[]?] | group_by(.) | map({asm: .[0], count: length}) | sort_by(-.count) | .[0:5]' .claude/graph/graph.json
```

---

### implementers \<InterfaceName\>

List all classes that implement the given interface.

```bash
jq --arg name "<InterfaceName>" '
  .codebase.classes[]
  | select(.implements | index($name) != null)
  | {class: .name, file: .file, confidence: .confidence}
' .claude/graph/graph.json
```

---

### publishers \<EventName\>

List all classes that publish the given event.

```bash
jq --arg name "<EventName>" '
  .codebase.events[]
  | select(.name == $name)
  | {event: .name, publishers: .publishers,
     declared_in: (if .declaration_unresolved then "(unresolved)" else .file end),
     line: .line, namespace: .namespace}
' .claude/graph/graph.json
```

---

### subscribers \<EventName\>

List all classes that subscribe to the given event.

```bash
jq --arg name "<EventName>" '
  .codebase.events[]
  | select(.name == $name)
  | {event: .name, subscribers: .subscribers,
     declared_in: (if .declaration_unresolved then "(unresolved)" else .file end),
     line: .line, namespace: .namespace}
' .claude/graph/graph.json
```

**`file` is the DECLARATION site, and only since extraction v4.** Before that it named whichever
class published or subscribed first, so "where is this event declared?" had a confidently wrong
answer for essentially every event — an `IEvent` struct lives in `<Domain>Events.cs` and is
published from a service. If a graph predates v4 the builder promotes one run to `--full`
automatically; do not hand-correct old records.

`declaration_unresolved: true` means the event is known only from a `Publish`/`Subscribe`
reference and no `IEvent` struct declaration was extracted — `file` is then deliberately **empty**
rather than backfilled from the referencing class. Render it as `(unresolved)`, never as a path.

An event with **empty `publishers` and `subscribers`** is now visible rather than absent: it is
declared and never used. That is a real finding — R2 `EVENT_DANGLING` only catches "publisher but
no subscriber", so this stricter case has no violation rule and shows up only here.

---

### registrations \<InterfaceOrClassName\>

Which installer registers the given type.

```bash
jq --arg name "<InterfaceOrClassName>" '
  def hit: .type == $name or .as == $name or ((.as_resolved // []) | index($name) != null);
  [ (.codebase.vcontainer.installers[]? | {holder: .name, kind: "installer", file, registrations}),
    (.codebase.vcontainer.scopes[]?     | {holder: .name, kind: "scope",     file, registrations}) ]
  | map(select((.registrations // [])[]? | hit))
  | map({holder, kind, file,
         registrations: [(.registrations // [])[] | select(hit)
                         | {type, as, as_resolved, as_resolution, as_resolution_reason, lifetime}]})
' .claude/graph/graph.json
```

**Searching by interface name works for `.AsImplementedInterfaces()` too — since extraction v5.**
That call names no type, so `as` holds the literal string `"AsImplementedInterfaces"`; before v5 a
lookup by interface returned nothing for every service registered the way
`rules/bootstrap-pattern.md` mandates. The builder now expands the placeholder into `as_resolved`
using the concrete type's own **and inherited** `implements`, and the query above matches it.

`as` is deliberately left as the placeholder rather than rewritten: an explicit `.As<IEventBus>()`
is a statement of intent, a wildcard that happens to cover `IEventBus` is a side effect. Report
which one you found — they are not the same fact.

**Check `as_resolution` before treating `as_resolved` as complete.** `full` means a concrete type
was named and its whole base chain was walkable. `partial` comes with a reason:

| `as_resolution_reason` | Means |
|---|---|
| `type-unresolved` | The registration named no concrete type (e.g. `RegisterComponent(_field)` with an opaque argument). Nothing to look up; `as_resolved` is empty. |
| `class-not-in-graph` | The concrete type is not in `classes[]` — third-party or generated, or a genuine extraction miss. Worth checking which. |
| `base-not-in-graph` | The base chain left the graph partway up, so interfaces declared on an unseen ancestor are missing from the list. What is listed is real; what is absent is unknown. |

**Expect `IDisposable`, `IInitializable` and `ITickable` to match almost every service.** That is
correct, not noise to filter: `.AsImplementedInterfaces()` genuinely registers them —
`bootstrap-pattern.md` says so explicitly. Do **not** add a filter that hides VContainer lifecycle
interfaces from this query; the registration exists, and a query that omits it would be lying.

Prefer `/knowledge-graph implementers <IFoo>` when the question is "who implements this?" rather
than "who registers it?" — the two answers differ whenever a type is implemented but never wired.

---

### scope-tree

Print the full VContainer scope hierarchy.

```bash
jq '
  .codebase.vcontainer.scopes
  | map({scope: .name,
         parent: (.parent // ("(unresolved: " + (.parent_unresolved_reason // "unknown") + ")")),
         via: .parent_source,
         installers: .installers})
' .claude/graph/graph.json
```

**Never render a null parent as `(root)`.** `.parent // "(root)"` is what this line used to do,
and it turned "the extractor could not resolve a parent" into the printed assertion "this scope
is a root scope" — the one thing the reader must not conclude. A scope reported as root when it
is really a child of `AppScope` looks exactly like the failure `GameScope.Configure()` guards
against (a second container, a second `IEventBus`, publishers and subscribers on different buses,
every test still green). Print the reason instead:

| Printed | Means |
|---|---|
| `parent: "AppScope", via: "code"` | resolved from `ParentReference.Create<AppScope>()` in `Awake()` |
| `parent: "AppScope", via: "inspector"` | resolved from the prefab's serialized `parentReference.TypeName` |
| `(unresolved: mcp-extraction-absent)` | the Inspector route was never read — Unity was not connected for this build. Re-run with the Editor open before drawing any conclusion. |
| `(unresolved: no-parent-declared)` | both routes were read and neither named a parent. Consistent with a genuine root scope (`AppScope`) **and** with a parent assigned indirectly (via a helper, or `Create<>` through a variable). Confirm in the scope's `Awake()` before reporting a missing parent as a defect. |

---

### prefab \<PrefabName\>

Show components, variant status, base prefab, and domain for a given prefab.

```bash
jq --arg name "<PrefabName>" '
  .codebase.prefabs[]
  | select(.name == $name)
  | {name: .name, path: .path, domain: .domain, isVariant: .isVariant,
     basePrefab: .basePrefab, components: .components, confidence: .confidence}
' .claude/graph/graph.json
```

---

### violations

Print all architecture errors and warnings.

```bash
jq '
  {
    errors:   [.validation.errors[]   | {rule: .rule_id, file: .file, message: .message}],
    warnings: [.validation.warnings[] | {rule: .rule_id, file: .file, message: .message}]
  }
' .claude/graph/graph.json
```

If `.validation.errors` is empty and `.validation.warnings` is empty, print:
```
No violations found. Run /build-knowledge-graph --validate to check architecture invariants.
```

---

### diff

Compare current `graph.json` with `graph.json.bak`.

```bash
diff \
  <(jq -S '.codebase.classes | map(.name) | sort' .claude/graph/graph.json.bak 2>/dev/null || echo '[]') \
  <(jq -S '.codebase.classes | map(.name) | sort' .claude/graph/graph.json)
```

Show added/removed classes, events, and installers.

---

### callers \<Class.Method\>

List all call sites that directly invoke the given method.

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

---

### impact \<ClassName\> [--hops N]

Show downstream + upstream affected nodes within N hops (default 3).
Use this before refactoring a class to estimate blast radius.

```bash
python3 .claude/graph/graph-traversal.py impact "<ClassName>" --hops 3
```

---

### path \<NodeA\> \<NodeB\>

Find the shortest call-graph path between two methods or classes.
Exits 1 if no path exists.

```bash
python3 .claude/graph/graph-traversal.py path "<NodeA>" "<NodeB>"
```

---

### god-nodes [--top N]

Top N nodes by (in_degree + out_degree). Default N = 10.
Nodes with total > 20 are flagged `is_god_node: true` — candidates for refactor.

```bash
python3 .claude/graph/graph-traversal.py god-nodes --top 10
```

Pure-jq alternative (lower fidelity — no per-node degree breakdown):
```bash
jq '[.codebase.calls[] | .caller, .callee]
    | group_by(.) | map({node: .[0], count: length})
    | sort_by(-.count) | .[0:10]' .claude/graph/graph.json
```

### communities [--scope \<ScopeName\>]

List all detected community groups (class clusters identified by `graph_cluster.py`).
Each community shows its top 5 members; full member list available via jq.

**Requires:** `codebase.communities[]` — absent on graphs built without call edges or before a v1.2.0 build.

```bash
# All communities
jq '(.codebase.communities // []) | map({id, label, size, scope, algorithm, members: .members[0:5]})' .claude/graph/graph.json
```

```bash
# Filter by VContainer scope
jq '(.codebase.communities // []) | map(select(.scope == "<ScopeName>"))
    | map({id, label, size, members})' .claude/graph/graph.json
```

Empty-state message: if `codebase.communities` is missing or `[]`, communities have not yet been computed — run `/build-knowledge-graph` to trigger `graph_cluster.py`.

---

### surprising [--severity warning|info] [--limit N]

List cross-boundary call edges that indicate architectural drift.
Default: warnings first, limit 20. Reasons: `CROSS_SCOPE` (warning), `CROSS_ASSEMBLY` (info), `CROSS_COMMUNITY` (info).

**Requires:** `analysis.surprising_connections[]` — computed by `graph_analyze.py` after clustering.

```bash
# All surprising connections (warnings first, limit 20)
jq '(.analysis.surprising_connections // [])
    | sort_by(.severity != "warning") | .[0:20]' .claude/graph/graph.json
```

```bash
# Filter by severity
jq '(.analysis.surprising_connections // [])
    | map(select(.severity == "warning"))' .claude/graph/graph.json
```

Empty-state message: if `analysis` is missing or `surprising_connections` is `[]`, either no cross-boundary edges exist (healthy codebase) or `graph_analyze.py` has not run yet — rebuild with `/build-knowledge-graph`.

---

## When to use which

| Question | Use |
|---|---|
| "Who calls this method?" | `callers` |
| "What breaks if I change this class?" | `impact` |
| "How does X end up calling Y?" | `path` |
| "Which classes do too much?" | `god-nodes` |
| "Who implements this interface?" | `implementers` |
| "Which installer registers this type?" | `registrations` |
| "Who publishes/subscribes to this event?" | `publishers` / `subscribers` |
| "Which classes form a module?" | `communities` |
| "Architecture drifting where?" | `surprising` |
