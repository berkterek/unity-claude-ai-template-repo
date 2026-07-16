---
name: mcp-extractor
description: "EDITOR/MCP ONLY — Extracts scenes/prefabs/components via MCP into graph cache. Unity Editor must be open. Read this skill before any MCP calls."
alwaysApply: false
---

# MCP Extractor

**[EDITOR/MCP — Unity Editor must be open]**

This extractor cannot run when the Editor is closed. `/build-knowledge-graph` skips it automatically
if MCP is unavailable and sets `codebase.mcp_extraction.status: "skipped"`.

## Inputs

| Flag | Default | Description |
|------|---------|-------------|
| `--scenes <path1>,<path2>` | (all scenes) | Comma-separated scene paths to extract |
| `--prefabs <dir>` | `Assets/_GameFolders/Prefabs` | Prefab root directory |

## KNOWN MCP TOOL LIMITATIONS (read before writing any extraction code)

| Tool | Limitation |
|------|-----------|
| `manage_scene get_hierarchy` with `target` param | **Does NOT filter by parent.** Always returns root-level list regardless of `target` value. Use `execute_code` for deep hierarchy traversal. |
| `manage_components` | **No `get`/`read` action exists.** Only `add`, `remove`, `set_property`. For reading component data use `execute_code`. |
| Roslyn compiler in `execute_code` | **Not available** in most Unity projects (requires Microsoft.CodeAnalysis NuGet). Always use `compiler: "codedom"`. |
| CodeDom compiler in `execute_code` | **C# 6 only.** No local functions, no `var` in lambdas, no string interpolation with complex expressions. Use `delegate` + explicit `Action<T>` for recursion. |

## PRE-CONDITION GATE — Run Before Any Other Step

Confirm `execute_code` is available — it is the primary extraction tool for scene hierarchy and component data. If unavailable, fall back to `manage_prefabs get_hierarchy` for prefabs only (scenes will be empty).

## Process

All read-only MCP calls must be batched via `batch_execute` per the unity-mcp-patterns skill Rule 1.

---

### Step 1 — Scene extraction via execute_code (PRIMARY METHOD)

**Do NOT use `manage_scene get_hierarchy` for component extraction — its `target` filter is broken.**

Use `execute_code` with `compiler: "codedom"` and the recursive delegate pattern:

```csharp
// CodeDom-compatible recursive scene dump
// IMPORTANT: use delegate, NOT local functions (CodeDom = C# 6)
var sb = new System.Text.StringBuilder();
var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();

System.Action<UnityEngine.GameObject, int> printGO = null;
printGO = delegate(UnityEngine.GameObject go, int depth) {
    string indent = new string(' ', depth * 2);
    var comps = go.GetComponents<UnityEngine.Component>();
    var names = new System.Collections.Generic.List<string>();
    foreach (var c in comps) names.Add(c == null ? "null" : c.GetType().Name);
    sb.AppendLine(indent + go.name + "  active=" + go.activeSelf + "  comps=(" + string.Join(", ", names.ToArray()) + ")");
    foreach (UnityEngine.Transform child in go.transform)
        printGO(child.gameObject, depth + 1);
};

foreach (var root in scene.GetRootGameObjects())
    printGO(root, 0);

return sb.ToString();
```

Parse the string output to build `gameobjects[]` entries per the schema.

Each line format: `<indent><name>  active=<true|false>  comps=(<comp1>, <comp2>)`

Parse rules:
- `indent` depth (2 spaces per level) → determines parent/child nesting
- `active=false` → set `"active": false` on the entry (default `true` when missing)
- `comps=(...)` → split by `, ` → `components[]` array
- Duplicate detection: within the same parent's children list, if two entries share the same `name`, add `"duplicate": true` to both and log a warning
- `null` component string in `comps=(...)` → set `"has_missing_scripts": true` on the gameobject entry (default `false` when absent)

Schema for each `gameobject` entry:
```json
{
  "name": "TapToStartPanel",
  "active": false,
  "components": ["RectTransform", "Image", "TapToStartView"],
  "has_missing_scripts": false,
  "duplicate": false,
  "children": []
}
```

`"active": false` entries are the primary risk signal for `RegisterComponentInHierarchy<T>()` failures — always surface them in Researcher output.

---

### Step 2 — Prefab enumeration via manage_prefabs (WORKS CORRECTLY)

`manage_prefabs get_hierarchy` correctly returns component lists per prefab. Use it.

```bash
find Assets -name '*.prefab' 2>/dev/null
```

Batch `manage_prefabs get_hierarchy` calls (max 25 per batch):

```json
{"tool": "manage_prefabs", "params": {"action": "get_hierarchy", "prefab_path": "Assets/..."}}
```

**IMPORTANT — child GOs:** `manage_prefabs get_hierarchy` only returns the root item; it does not include child/grandchild GOs. To get the full hierarchy (e.g. `Player/Body`, `Tile/ItemSpawnPoints/Point1`) use `execute_code`:

```csharp
// CodeDom-compatible prefab full hierarchy dump
var sb = new System.Text.StringBuilder();
var guids = UnityEditor.AssetDatabase.FindAssets("t:Prefab", new string[]{"Assets/_GameFolders/Prefabs"});
System.Action<UnityEngine.Transform, int> walk = null;
walk = delegate(UnityEngine.Transform t, int depth) {
    string indent = new string(' ', depth * 2);
    var comps = t.GetComponents<UnityEngine.Component>();
    var names = new System.Collections.Generic.List<string>();
    foreach (var c in comps) names.Add(c == null ? "null" : c.GetType().Name);
    sb.AppendLine(indent + t.name + "|comps=" + string.Join(",", names.ToArray()));
    foreach (UnityEngine.Transform child in t)
        walk(child, depth + 1);
};
foreach (var guid in guids) {
    var path = UnityEditor.AssetDatabase.GUIDToAssetPath(guid);
    var go = UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEngine.GameObject>(path);
    if (go == null) continue;
    sb.AppendLine("PREFAB:" + path);
    walk(go.transform, 0);
}
return sb.ToString();
```

Parse: each `PREFAB:` line starts a new prefab; indented lines are the GO tree.

For each root item in the result:
- `componentTypes[]` → `components[]` in the schema
- `isNestedRoot: true` on root item → `isVariant: true`
- If any component name in the `comps=` list is `null`, set `"has_missing_scripts": true` on that prefab's root entry.

Classify `domain` from path:
- `**/UI/**` → `UI`
- `**/VFX/**` → `VFX`
- `**/Enemies/**` → `Enemies`
- `**/Characters/**` → `Characters`
- `**/Environment/**` → `Environment`
- `**/Audio/**` → `Audio`
- `**/Bootstrap/**` or `**/Services/**` → `Bootstrap`
- `**/CoreObjects/**` → `CoreObjects`
- Otherwise → `ThirdParty`

---

### Step 2b — Scope parent extraction

For each prefab whose component list includes a `LifetimeScope` subclass, use `execute_code` to read the `parentReference` field:

```csharp
// CodeDom-compatible
// NOTE: parentReference is a VContainer.Unity.ParentReference STRUCT — != null won't compile.
// Use .TypeName field (string) instead; empty string means no parent.
var results = new System.Collections.Generic.List<string>();
var prefabs = UnityEditor.AssetDatabase.FindAssets("t:Prefab", new string[]{"Assets/_GameFolders/Prefabs"});
foreach (var guid in prefabs) {
    var path = UnityEditor.AssetDatabase.GUIDToAssetPath(guid);
    var go = UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEngine.GameObject>(path);
    if (go == null) continue;
    var scope = go.GetComponent<VContainer.Unity.LifetimeScope>();
    if (scope == null) continue;
    var parentTypeName = scope.parentReference.TypeName;
    var shortParent = string.IsNullOrEmpty(parentTypeName) ? "null"
        : parentTypeName.Contains(".") ? parentTypeName.Substring(parentTypeName.LastIndexOf('.') + 1)
        : parentTypeName;
    results.Add(go.name + "|" + scope.GetType().Name + "|" + shortParent);
}
return string.Join("\n", results.ToArray());
```

Parse each line as `prefab_name | scope_class | parent_class`.

---

### Step 2c — Inspector field values via SerializedObject (OPTIONAL)

`manage_components get` does not exist. Use `execute_code` + `UnityEditor.SerializedObject` +
`SerializedProperty` iterator instead. Verified working in live Editor session.

```csharp
// CodeDom-compatible inspector field reader
// Reads primitive/enum/string serialized fields from all prefab components
var sb = new System.Text.StringBuilder();
var guids = UnityEditor.AssetDatabase.FindAssets("t:Prefab", new string[]{"Assets/_GameFolders/Prefabs"});
foreach (var guid in guids) {
    var path = UnityEditor.AssetDatabase.GUIDToAssetPath(guid);
    var go = UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEngine.GameObject>(path);
    if (go == null) continue;
    var comps = go.GetComponentsInChildren<UnityEngine.Component>();
    foreach (var comp in comps) {
        if (comp == null) continue;
        var so = new UnityEditor.SerializedObject(comp);
        var prop = so.GetIterator();
        bool entered = prop.NextVisible(true);
        while (entered) {
            string val = null;
            if (prop.propertyType == UnityEditor.SerializedPropertyType.Float)
                val = prop.floatValue.ToString("F2");
            else if (prop.propertyType == UnityEditor.SerializedPropertyType.Integer)
                val = prop.intValue.ToString();
            else if (prop.propertyType == UnityEditor.SerializedPropertyType.Boolean)
                val = prop.boolValue.ToString();
            else if (prop.propertyType == UnityEditor.SerializedPropertyType.String)
                val = prop.stringValue;
            else if (prop.propertyType == UnityEditor.SerializedPropertyType.Enum)
                val = prop.enumNames[prop.enumValueIndex];
            if (val != null)
                sb.AppendLine(go.name + "|" + comp.GetType().Name + "|" + prop.name + "=" + val);
            entered = prop.NextVisible(false);
        }
    }
}
return sb.ToString();
```

Parse each line as `prefab_name | component_name | field=value`. Skip this step for speed — it adds
meaningful data (e.g. `PlayerView._moveSpeed=5.0`, `ButtonView._label="Play"`)
but takes longer and can produce noisy output for large prefab sets.

---

### Step 3 — Write output

Write the result to `.claude/graph/cache/mcp-extract.json`:

```json
{
  "scenes": [ /* sceneEntry[] per schema */ ],
  "prefabs": [ /* prefabEntry[] */ ],
  "scope_parents": [
    { "scope_name": "GameScope", "parent_name": "AppScope" }
  ],
  "extracted_at": "<ISO8601 UTC>"
}
```

After writing, re-run:
```bash
bash .claude/graph/graph-builder.sh --incremental
```

---

## Failure Modes

If Unity Editor is not connected or `execute_code` is unavailable:

1. Exit 0 (never crash — the rest of the build still proceeds).
2. Write empty output to `.claude/graph/cache/mcp-extract.json`:
   ```json
   { "scenes": [], "prefabs": [], "extracted_at": null }
   ```
3. The builder sets `codebase.mcp_extraction.status: "skipped"`.

## Confidence

All MCP-extracted entries use `confidence: "EXTRACTED"` (live Editor data is authoritative).
