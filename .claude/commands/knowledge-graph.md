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
