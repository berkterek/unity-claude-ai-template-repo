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
jq '.codebase.vcontainer.scopes | map({scope: .name, parent: .parent})' .claude/graph/graph.json
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
  | {event: .name, publishers: .publishers, file: .file}
' .claude/graph/graph.json
```

---

### subscribers \<EventName\>

List all classes that subscribe to the given event.

```bash
jq --arg name "<EventName>" '
  .codebase.events[]
  | select(.name == $name)
  | {event: .name, subscribers: .subscribers, file: .file}
' .claude/graph/graph.json
```

---

### registrations \<InterfaceOrClassName\>

Which installer registers the given type.

```bash
jq --arg name "<InterfaceOrClassName>" '
  .codebase.vcontainer.installers[]
  | select(.registrations[]? | .type == $name or .as == $name)
  | {installer: .name, file: .file, registrations: [.registrations[] | select(.type == $name or .as == $name)]}
' .claude/graph/graph.json
```

---

### scope-tree

Print the full VContainer scope hierarchy.

```bash
jq '
  .codebase.vcontainer.scopes
  | map({scope: .name, parent: (.parent // "(root)"), installers: .installers})
' .claude/graph/graph.json
```

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
