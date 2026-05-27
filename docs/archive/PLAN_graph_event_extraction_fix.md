# PLAN: Graphify Bug Fixes & Missing Features

**Date:** 2026-05-24  
**Scope:** `.claude/graph/` — graph-builder, csharp-extractor, asmdef-extractor, graph-validator, graph-watch  
**Status:** Identified in nile_hole_sphere_repo; fixes apply to template  
**Last updated:** 2026-05-24 — verify-graphify.sh session added Bugs 20–22 + test harness task

---

## Bug List

### 🔴 Bug 1 — `asmdef-extractor.sh` standalone `find` path
**File:** `.claude/graph/extractors/asmdef-extractor.sh:30`  
**Problem:** `find Assets -name '*.asmdef'` uses a hardcoded `Assets/` path relative to CWD. When the Unity project is nested (e.g. `HoleSphere/Assets/`), standalone calls find 0 files.  
**Note:** In practice the extractor is always called via `--changed-files` from `graph-builder.sh`, which already has the correct path. But standalone invocation is broken.  
**Fix:** Accept optional `--root <path>` argument; default to `Assets/`.

---

### 🔴 Bug 2 — `graph-watch.sh` watches wrong path
**File:** `.claude/graph/graph-watch.sh:56,63`  
**Problem:** Both `fswatch` and `inotifywait` invocations hardcode `Assets/`. For nested Unity projects (e.g. `HoleSphere/Assets/`) the watcher silently monitors the wrong directory and never triggers a rebuild.  
**Fix:** Add `WATCH_ROOT` variable (env-overridable `GRAPH_WATCH_ROOT`); default `Assets/`.

---

### 🔴 Bug 3 — `graph-validator.sh R3` false positive: LifetimeScope and ScriptableObject
**File:** `.claude/graph/graph-validator.sh:69–84`  
**Problem:** `CONCRETE_UNREGISTERED` rule flags `AppScope`, `GameScope` (LifetimeScope subclasses) and `LevelDefinition`, `TileDefinition` (ScriptableObject subclasses) as unregistered. Neither type should ever be registered in a VContainer installer — they are bootstrapped by Unity directly.  
**Fix:** Before the unregistered check, skip classes whose `base_types` includes `LifetimeScope` or `ScriptableObject`.

---

### 🔴 Bug 4 — `graph-validator.sh R5` false positive: 3rd-party assemblies & GUID refs
**File:** `.claude/graph/graph-validator.sh:97–108`  
**Problem:** `ASMDEF_UNRESOLVED` checks every assembly including those in `_AssetFolders/` and `Plugins/`. These packages reference other assemblies via GUID (`GUID:xxxxxxxx`) that live in `Library/PackageCache/` (UPM) or optional Unity modules — the graph extractor never scans those. Result: 36 false positive errors on every validate run.  
**Fix:**
1. Skip assemblies whose `.file` path contains `/_AssetFolders/` or `/Plugins/`
2. Skip GUID-based reference strings (`GUID:` prefix) — they always point to UPM/built-in packages

---

### 🔴 Bug 5 — `graph-validator.sh R3` `[""]` bug when no registered types
**File:** `.claude/graph/graph-validator.sh:67`  
**Problem:** `printf '%s\n' "${REGISTERED_TYPES[@]:-}"` on an empty array emits one blank line, which `jq -sc .` encodes as `[""]` instead of `[]`. If there are no registered types, ALL concretes get flagged as unregistered.  
**Fix:** Guard with `${#REGISTERED_TYPES[@]} -gt 0` before building JSON — same fix applied to `graph-builder.sh`.

---

### 🟡 Missing Feature 6 — VContainer scope extraction (always `[]`)
**File:** `.claude/graph/extractors/csharp-extractor.sh`  
**Problem:** `codebase.vcontainer.scopes` is always `[]`. The extractor never detects `LifetimeScope` subclasses or their parent-child relationships. `/knowledge-graph scope-tree` is always empty.  
**Fix:** In `process_file_regex`, detect classes extending `LifetimeScope`. Extract scope name and attempt parent detection from `[VContainerSettings(parentScope: typeof(X))]` attribute. Emit to a `scopes[]` array. In `graph-builder.sh`, replace "retain from existing" with a real extraction pass.

---

### 🟡 Missing Feature 7 — `.As<Interface>()` not captured in registrations
**File:** `.claude/graph/extractors/csharp-extractor.sh:103`  
**Problem:** `extract_registrations` only captures `builder.Register<ConcreteType>()`. The `.As<IInterface>()` or `.AsImplementedInterfaces()` chain is never parsed. The `as` field is always empty string.  
**Fix:** After capturing the concrete type, look ahead for `.As<IType>()` or `.AsImplementedInterfaces()`. Populate `as` field accordingly. Use a Python pass for multi-line reliability.

---

### 🟡 Missing Feature 8 — Lifetime always hardcoded `"Singleton"`
**File:** `.claude/graph/extractors/csharp-extractor.sh:103`  
**Problem:** Every registration emits `lifetime: "Singleton"` regardless of actual `Lifetime.Transient` or `Lifetime.Scoped` usage.  
**Fix:** Detect the `Lifetime.*` argument in `Register<T>(Lifetime.X)` and populate `lifetime` field correctly.

---

### 🔴 Bug 9 — `graph-validator.sh R6` layer-violation check uses name instead of file path
**File:** `.claude/graph/graph-validator.sh:128–130`
**Problem:** R6 looks up the referenced assembly in `KNOWN_ASMDEFS` by name and then tests the **name string** for `Games/` or `GameFolders/` — but assembly names never contain path separators. The `.file` path is what holds the folder location. Result: R6 never fires even when a `_Framework/` assembly genuinely references a `Games/` assembly.
**Fix:** Build a `name → file` map from `KNOWN_ASMDEFS` at the start of R6, then resolve the referenced assembly's file path before the `grep` check.

```bash
# Build name→file map once before the R6 loop
ASMDEF_FILE_MAP=$(jq -r '.codebase.assemblies[] | "\(.name)\t\(.file)"' "$GRAPH" 2>/dev/null || true)

# Inside R6 inner loop, replace current ref_file lookup:
ref_file=$(echo "$ASMDEF_FILE_MAP" | awk -F'\t' -v r="$ref" '$1==r{print $2}')
if echo "$ref_file" | grep -qE 'Games|GameFolders'; then
  add_error "LAYER_VIOLATION" ...
fi
```

**Found by:** Codex review during Bug 3/4/5 session — 2026-05-24.

---

### 🔴 Bug 10 — `csharp-extractor.sh` default scan paths hardcoded `Assets/`
**File:** `.claude/graph/extractors/csharp-extractor.sh:40`  
**Problem:** `FIND_OPTS=( Assets/_Framework Assets/_GameFolders/Scripts )` is hardcoded. When Unity project is nested (e.g. `HoleSphere/`), a full rebuild (`--full`, no `--changed-files`) scans nothing. Only incremental runs (which pass `--changed-files` explicitly) work correctly. Bug 1 fixed `asmdef-extractor.sh` but missed this file.  
**Fix:** Accept `--root <path>` arg; auto-detect `HoleSphere/Assets` if directory exists; fall back to `Assets/`.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🔴 Bug 11 — Scope merge replaces entire list on incremental build
**File:** `.claude/graph/graph-builder.sh:271`  
**Problem:** The scope fix (Bug 6 impl) used `if NEW_SCOPES_LEN > 0 then SCOPES = NEW_SCOPES`. On an incremental build where only one file containing a scope is changed, `NEW_SCOPES` has just that one scope — discarding all scopes from unchanged files. Classes, installers, and interfaces all use retained+new merge; scopes did not.  
**Fix:** Merge retained and new scopes using `unique_by(.name)` — new extraction wins on name conflict.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🔴 Bug 12 — `RegisterInstance(obj)` non-generic form not captured
**File:** `.claude/graph/extractors/csharp-extractor.sh:101`  
**Problem:** Python regex requires `<TypeName>` generic form. `builder.RegisterInstance(_gameConfig)` (no type parameter) is silently dropped from the graph. Common pattern for ScriptableObject config instances.  
**Fix:** Add a second regex pass for non-generic `RegisterInstance(arg)` — infer type from variable name as best-effort. Mark with `"inferred": true`.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🔴 Bug 13 — `.As<T>()` only captures first interface in multi-interface chain
**File:** `.claude/graph/extractors/csharp-extractor.sh:125`  
**Problem:** `re.search(r'\.As<([A-Za-z0-9_]+)>', tail)` returns first match only. A chain like `.As<IAudioService>().As<IDisposable>()` only records `IAudioService`; `IDisposable` is silently dropped.  
**Fix:** Replace `re.search` with `re.findall`; store list when multiple matches found.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🔴 Bug 14 — `extract_scope` misses multi-line class declarations
**File:** `.claude/graph/extractors/csharp-extractor.sh:154`  
**Problem:** `grep -nE 'class ... LifetimeScope'` only matches single-line declarations. C# allows:
```csharp
public sealed class GameScope
    : LifetimeScope
```
This yields empty `scope_line` and `extract_scope` returns `null`.  
**Fix:** Rewrite in Python, joining 4 consecutive lines before pattern matching.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🔴 Bug 15 — `extract_scope` parent detection grabs any `typeof(XScope)` in file
**File:** `.claude/graph/extractors/csharp-extractor.sh:163`  
**Problem:** `grep -oE 'typeof\([A-Za-z0-9_]+Scope\)'` matches the first occurrence anywhere in the file. Any method referencing `typeof(AppScope)` for logging or reflection incorrectly sets `parent = "AppScope"` even for root scopes.  
**Fix:** Restrict to `[ParentScope(typeof(X))]` VContainer attribute only.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🟡 Bug 16 — `graph-watch.sh` default `WATCH_ROOT` wrong for nested projects
**File:** `.claude/graph/graph-watch.sh:30`  
**Problem:** `WATCH_ROOT="${GRAPH_WATCH_ROOT:-Assets}"` defaults to `Assets/`. For nested Unity projects (`HoleSphere/Assets/`), running graph-watch without the env var silently monitors the wrong directory. The previous fix added env-var support but left the hardcoded default.  
**Fix:** Auto-detect `HoleSphere/Assets` at startup.  
**Status:** ✅ Fixed — 2026-05-24

---

### 🟡 Bug 17 — R3 `ModuleInstaller` subclasses not in `base_types` skip
**File:** `.claude/graph/graph-validator.sh:83`  
**Problem:** The `base_types` skip only listed `LifetimeScope|ScriptableObject`. `ModuleInstaller` subclasses are already excluded by the `*Installer` name suffix, but the skip logic was inconsistent — a class extending `ModuleInstaller` without the suffix would fall through.  
**Fix:** Add `ModuleInstaller` to the `base_types` grep pattern.  
**Status:** ✅ Fixed — 2026-05-24

---

## Fix Priority

| # | Severity | Effort | Status |
|---|----------|--------|--------|
| 4 | 🔴 High  | Low    | ✅ Done |
| 3 | 🔴 High  | Low    | ✅ Done |
| 5 | 🔴 High  | Low    | ✅ Done |
| 9 | 🔴 Med   | Low    | ✅ Done |
| 10 | 🔴 High | Low    | ✅ Done |
| 11 | 🔴 High | Low    | ✅ Done |
| 12 | 🔴 Med  | Low    | ✅ Done |
| 13 | 🔴 Med  | Low    | ✅ Done |
| 14 | 🔴 High | Low    | ✅ Done |
| 15 | 🔴 Med  | Low    | ✅ Done |
| 2 | 🔴 Med   | Low    | ✅ Done |
| 1 | 🔴 Low   | Low    | ✅ Done |
| 7 | 🟡 Med   | Med    | ✅ Done |
| 8 | 🟡 Low   | Low    | ✅ Done |
| 6 | 🟡 High  | High   | ✅ Done |
| 16 | 🟡 Med  | Low    | ✅ Done |
| 17 | 🟡 Low  | Low    | ✅ Done |
| 18 | 🟡 Med  | Med    | 🔲 Open — MCP extractor update needed |
| 19 | 🟡 Low  | —      | 🔲 Open — game code issue, not Graphify |
| 20 | 🔴 Critical | Low | ✅ Fixed in project — 🔲 Not in template |
| 21 | 🔴 High | Low    | ✅ Fixed in project — 🔲 Not in template (test harness) |
| 22 | — | —       | ✅ Confirmed working — no fix needed |
| T20 | 🔴 High | Med  | 🔲 Open — copy test harness to template |

---

## Implementation Notes

### R3 LifetimeScope/ScriptableObject skip (Bug 3)

```bash
# In the R3 while loop, before the unregistered check:
base_types=$(echo "$row" | jq -r '.base_types[]? // empty')
echo "$base_types" | grep -qE 'LifetimeScope|ScriptableObject' && continue
```

### R5 path + GUID skip (Bug 4)

```bash
# Skip entire assembly if it lives in _AssetFolders/ or Plugins/
[[ "$asmfile" == */_AssetFolders/* || "$asmfile" == */Plugins/* || \
   "$asmfile" == */_assetfolders/* || "$asmfile" == */plugins/* ]] && continue

# Skip GUID-based references
[[ "$ref" == GUID:* ]] && continue
```

### `[""]` guard (Bug 5)

```bash
if [[ ${#REGISTERED_TYPES[@]} -gt 0 ]]; then
  REGISTERED_JSON=$(printf '%s\n' "${REGISTERED_TYPES[@]}" | jq -R . | jq -sc .)
else
  REGISTERED_JSON="[]"
fi
```

### .As<> and Lifetime capture (Features 7 & 8)

Replace the bash regex `extract_registrations` with a Python pass:

```python
import re, sys, json

text = open(sys.argv[1]).read()
results = []
for m in re.finditer(
    r'builder\.(Register(?:Instance|Component|ComponentInHierarchy)?)'
    r'<([A-Za-z0-9_]+)>'
    r'(?:\s*\(\s*Lifetime\.(\w+)\s*\))?',
    text
):
    reg = {
        "type": m.group(2),
        "as": "",
        "lifetime": m.group(3) or "Singleton",
        "scope": ""
    }
    tail = text[m.end():m.end()+300]
    as_m = re.search(r'\.As<([A-Za-z0-9_]+)>', tail)
    if as_m:
        reg["as"] = as_m.group(1)
    elif ".AsImplementedInterfaces()" in tail[:150]:
        reg["as"] = "AsImplementedInterfaces"
    results.append(reg)
print(json.dumps(results))
```

### Scope extraction (Feature 6)

```bash
extract_scope() {
  local f="$1"
  local scope_line
  scope_line=$(grep -nE 'class[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*(.*[[:space:],])?LifetimeScope' "$f" 2>/dev/null | head -1) || true
  [[ -z "$scope_line" ]] && echo "null" && return

  local scope_name
  scope_name=$(echo "$scope_line" | grep -oE 'class[[:space:]]+([A-Z][A-Za-z0-9_]*)' | awk '{print $2}')
  local parent
  parent=$(grep -oE 'typeof\(([A-Za-z0-9_]+Scope)\)' "$f" 2>/dev/null | head -1 | sed 's/typeof(//;s/)//') || parent=""

  jq -nc --arg n "$scope_name" --arg f "$f" --arg p "$parent" \
    '{name:$n, file:$f, source_file:$f, parent:($p|if .=="" then null else . end), installers:[]}'
}
```

In `graph-builder.sh`, replace retained-scopes line:
```bash
# OLD: SCOPES=$(echo "$EXISTING_GRAPH" | jq '.codebase.vcontainer.scopes // []')
# NEW: pull from fresh CS_OUTPUT
SCOPES=$(echo "$CS_OUTPUT" | jq '.vcontainer.scopes // []')
```

### graph-watch.sh WATCH_ROOT (Bug 2 + Bug 16)

```bash
if [[ -n "${GRAPH_WATCH_ROOT:-}" ]]; then
  WATCH_ROOT="$GRAPH_WATCH_ROOT"
elif [[ -d "HoleSphere/Assets" ]]; then
  WATCH_ROOT="HoleSphere/Assets"
else
  WATCH_ROOT="Assets"
fi
# Replace Assets/ with "$WATCH_ROOT"/ in fswatch and inotifywait calls
```

### asmdef-extractor.sh --root (Bug 1)

```bash
ROOT="Assets"
--root) ROOT="$2"; shift 2 ;;
# Standalone find: find "$ROOT" -name '*.asmdef' -print0
```

### csharp-extractor.sh --root + auto-detect (Bug 10)

```bash
CS_ROOT=""
--root) CS_ROOT="$2"; shift 2 ;;

if [[ -n "$CS_ROOT" ]]; then
  _prefix="$CS_ROOT"
elif [[ -d "HoleSphere/Assets" ]]; then
  _prefix="HoleSphere/Assets"
else
  _prefix="Assets"
fi
FIND_OPTS=( "${_prefix}/_Framework" "${_prefix}/_GameFolders/Scripts" )
```

### Scope merge — incremental-safe (Bug 11)

```bash
# Merge by name: new extraction wins on conflict
SCOPES=$(jq -n \
  --argjson retained "$RETAINED_SCOPES" \
  --argjson new_scopes "$NEW_SCOPES" \
  '($retained + $new_scopes) | unique_by(.name)' 2>/dev/null || echo "$NEW_SCOPES")
```

### Non-generic RegisterInstance + multi .As<T> + multi-line scope (Bugs 12, 13, 14, 15)

Full Python implementation for `extract_registrations` and `extract_scope` — see `csharp-extractor.sh` in nile_hole_sphere_repo commit `76009ad`.

Key points:
- `extract_registrations`: two regex passes — generic `<T>` form + non-generic `(arg)` form
- `.As<T>` chain: `re.findall` instead of `re.search` — stores list when multiple matches
- `extract_scope`: join 4 lines before matching — handles multi-line class declarations
- parent detection: only `[ParentScope(typeof(X))]` attribute — avoids false positives from unrelated `typeof()` calls

---

---

### 🟡 Limitation 18 — Scope parent relationship not detectable from code
**File:** `.claude/graph/extractors/csharp-extractor.sh`, `graph-builder.sh`  
**Problem:** VContainer's scope parent relationship is set via the `LifetimeScope.Parent` Inspector field on a prefab — it is NOT declared in C# code. There is no code attribute or constructor argument to parse. As a result, `GameScope.parent` is always `null` even when it is a child of `AppScope` in practice.  
**Example:** `GameScope.cs` contains only `public sealed class GameScope : LifetimeScope { }` — no parent reference in code. The parent is the `AppScope` prefab instance, wired in the Unity Inspector.  
**Impact:** `/knowledge-graph scope-tree` shows a flat list instead of a hierarchy. The graph cannot verify that `GameScope` is correctly parented under `AppScope`.  
**Fix approach:** MCP extraction pass — after C# extraction, query the Unity Editor for each prefab that has a `LifetimeScope` component and read its `parentReference` serialized field:

```csharp
// In MCP extractor C# code:
var scopes = new List<object>();
var guids = AssetDatabase.FindAssets("t:Prefab");
foreach (var guid in guids) {
    var path = AssetDatabase.GUIDToAssetPath(guid);
    var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
    var ls = go?.GetComponent<LifetimeScope>();
    if (ls == null) continue;
    var so = new SerializedObject(ls);
    var parentProp = so.FindProperty("parentReference");
    var parentName = parentProp?.objectReferenceValue != null
        ? parentProp.objectReferenceValue.name : null;
    scopes.Add(new { name = go.name, path, parent = parentName });
}
```

Then in `graph-builder.sh`, merge MCP scope parent data into the C#-extracted scopes by name match.  
**Status:** 🟡 Open — requires MCP extractor update  
**Found by:** Post-fix validation review — 2026-05-24

---

### 🟡 Limitation 19 — EVENT_DANGLING warnings are not false positives
**File:** Graph validation output  
**Problem:** Four events are correctly flagged as dangling:
- `LevelReadyEvent` — subscriber exists (`ScreenManager`), no publisher in codebase
- `GameStateChangedEvent` — publisher exists (`GameStateService`), no subscriber
- `LevelResetRequestedEvent` — 3 subscribers exist (`BlackholeView` et al.), no publisher
- `LevelReadyToResetEvent` — publisher exists (`LevelService`), no subscriber

These are **real architecture gaps** in the project, not false positives. Graphify is correctly identifying unfinished event wiring.  
**Impact:** Not a Graphify bug — these need to be fixed in game code or explicitly acknowledged.  
**Fix approach:** For each dangling event, either implement the missing publisher/subscriber, or if intentional (e.g. event reserved for future use), document in a `// TODO:` comment so future developers understand the intent.  
**Status:** 🟡 Open — game code issue, not a Graphify issue  
**Found by:** Full rebuild + validate run — 2026-05-24

---

---

### 🔴 Bug 20 — `extract_base_list()` matches `grep -n` line-number prefix colon
**File:** `.claude/graph/extractors/csharp-extractor.sh:77`  
**Problem:** `process_file_regex` calls `grep -n` to find class declarations, producing lines like `"45:  public sealed class X : IFoo"`. `extract_base_list()` then runs `grep -oE ':[[:space:]]*...'` on that full string — the regex matches the `"45:"` line-number colon first, capturing `"public sealed class X IFoo"` as the base list instead of just `"IFoo"`. Result: `base_types[]` contains the full class declaration string; `implements[]` is always empty because no base type starts with `^I[A-Z]` after being polluted.  
**Root cause:** `grep -n` output was never stripped of its `N:` prefix before being passed to `extract_base_list`.  
**Impact:** Critical — `class.implements[]` is always `[]` for every class. `/knowledge-graph implementers` returns no results. Architecture violation checks that depend on interface implementation are blind.  
**Fix:** Strip the line-number prefix first, then match specifically the class-declaration colon:
```bash
extract_base_list() {
  local line="$1"
  local decl
  decl=$(echo "$line" | sed 's/^[0-9]*://')
  echo "$decl" | grep -oE 'class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*[A-Za-z0-9_<>, ]+' \
    | sed -E 's/class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*//' \
    | tr -d '\n' || echo ""
}
```
**Verified fix:** After fix, 21 classes have non-empty `implements[]`, 0 classes have polluted `base_types[]`.  
**Status:** ✅ Fixed in nile_hole_sphere_repo — commit `4965e91` — 2026-05-24  
**Template status:** 🔲 Not yet applied  

---

### 🔴 Bug 21 — `sandbox.sh` uses `declare -A` — incompatible with macOS bash 3.2
**File:** `.claude/graph/test/lib/sandbox.sh:18`  
**Problem:** `declare -A _EXISTED_BEFORE` (associative arrays) requires bash 4.0+. macOS ships bash 3.2 as the system shell. Running the test harness on macOS produces:  
```
sandbox.sh: line 18: declare: -A: invalid option
```  
The sandbox fails to track which files existed before the test run, causing corrupt cleanup.  
**Fix:** Replace associative array with a marker-file pattern — for each protected path that exists, write a zero-byte marker file into a temp directory. Marker filename = path with `/` replaced by `__`:
```bash
SANDBOX_EXISTED_DIR="$(mktemp -d -t graphify-existed-XXXXXX)"
_existed_marker() { echo "$SANDBOX_EXISTED_DIR/$(echo "$1" | sed 's|/|__|g')"; }
```
**Status:** ✅ Fixed in nile_hole_sphere_repo — commit `bb6c594` — 2026-05-24  
**Template status:** 🔲 Not yet applied (test harness not yet in template)  

---

### 🟡 Clarification 22 — BUG#2 MCP merge was a stale cache, not a code bug
**File:** `.claude/graph/graph-builder.sh:143`  
**Problem reported:** `graph.json.codebase.prefabs` always `[]` despite `mcp-extract.json` containing 27 prefabs.  
**Investigation:** The MCP merge code (`jq -r '.prefabs // []'` + `--argjson prefabs`) was confirmed correct. The actual cause was that `mcp-extract.json` was older than 60 minutes at the time of investigation, so `MCP_AGE -lt 60` evaluated false and `MCP_PREFABS` stayed as `"[]"`. When cache was fresh (< 60 min), 27 prefabs merged correctly.  
**No code fix needed.** The freshness threshold (60 min) is appropriate. The T8 test in `verify-graphify.sh` was incorrectly using `--skip-mcp` for its WORK_GRAPH, causing a false KNOWN_FAIL — that was fixed by building a separate `graph-mcp.json` with MCP enabled for the BUG#2 check.  
**Status:** ✅ Confirmed working — no fix required — 2026-05-24  

---

## Task T20 — Apply Test Harness to Template

Add the full `verify-graphify.sh` test harness to the template so every project generated from it has regression coverage from day one.

**Source:** `.claude/graph/test/` in nile_hole_sphere_repo (commits `912538f`, `bb6c594`)

**Files to copy:**
| Source | Template destination |
|--------|---------------------|
| `.claude/graph/test/verify-graphify.sh` | `.claude/graph/test/verify-graphify.sh` |
| `.claude/graph/test/lib/sandbox.sh` | `.claude/graph/test/lib/sandbox.sh` |
| `.claude/graph/test/lib/assert.sh` | `.claude/graph/test/lib/assert.sh` |
| `.claude/graph/test/fixtures/r1_singleton/graph.json` | same |
| `.claude/graph/test/fixtures/r2_dangling_event/graph.json` | same |
| `.claude/graph/test/fixtures/r3_unregistered_concrete/graph.json` | same |
| `.claude/graph/test/fixtures/r4_misplaced_interface/graph.json` | same |
| `.claude/graph/test/fixtures/r5_unknown_asmdef_ref/graph.json` | same |
| `.claude/graph/test/fixtures/r6_layer_violation/graph.json` | same |
| `.claude/graph/test/fixtures/mcp-extract.fresh.json` | same |
| `.claude/graph/test/.work/.gitignore` | same |
| `.claude/graph/test/README.md` | same |

**Steps:**
1. [ ] Copy all files listed above from nile_hole_sphere_repo to template
2. [ ] Apply Bug 20 fix (`extract_base_list`) to template's `csharp-extractor.sh`
3. [ ] Apply Bug 21 fix (`declare -A` → marker-file) to `sandbox.sh`
4. [ ] Run `bash .claude/graph/test/verify-graphify.sh` on a template project — target: 35 PASS, 0 FAIL
5. [ ] Add `.claude/graph/.gitignore` (gitignore `.last-build` and `cache/file-hashes.json`)
6. [ ] Commit to template repo

**Acceptance criteria:**
- `bash .claude/graph/test/verify-graphify.sh` exits 0 with 35 PASS on a fresh template project
- `class.implements[]` populated for all classes with inheritance
- Sandbox cleanup works on macOS bash 3.2 without errors

---

### 🟡 CLAUDE.md Update Required — graph.json as primary source of truth
**Files:** `.claude/CLAUDE.md` (template repo)  
**Problem:** The template CLAUDE.md still describes graph as secondary/optional:
- Optional Features table: `"retain their original file-scan paths unchanged"` — misleading; implies graph has no effect on behavior when enabled
- Session Start: only says "read its summary" — does not instruct Claude to *prefer* graph over folder scan
- NON-NEGOTIABLE Pre-Implementation Scan: lists only file-scan steps, no mention of reading graph.json when available
- Project Features table: no `graph` row at all

**Fix:** Three updates to `.claude/CLAUDE.md`:

1. **Optional Features table** — change `graph` row description:
```
| **Unity Knowledge Graph** | Built-in (`.claude/graph/`) | `graph` | Skip extractors and hooks. `/catch-up`, `/orchestrate`, `/context-prime`, `/architect` fall back to direct file-scan. |
```

2. **Session Start** — replace single bullet with explicit priority rule + query cheatsheet:
```markdown
- If `.claude/graph/graph.json` exists: run `/knowledge-graph summary` — this is the primary source of truth for classes, interfaces, events, installers, scopes, and prefabs. Do NOT manually scan source folders if the graph is available and fresh (< 24h).

**Graph query cheatsheet (use before touching any existing system):**
- "What interfaces exist?" → `/knowledge-graph implementers IAudioService`
- "Who publishes/subscribes to an event?" → `/knowledge-graph publishers RunStartedEvent`
- "What does an installer register?" → `/knowledge-graph registrations AudioService`
- "VContainer scope hierarchy?" → `/knowledge-graph scope-tree`
- "Any architecture violations?" → `/knowledge-graph violations`
- "What components does a prefab have?" → `/knowledge-graph prefab BlackholeSphere`
```

3. **NON-NEGOTIABLE Pre-Implementation Scan** — add graph-first path:
```markdown
**If `graph` feature is ENABLED and graph.json is fresh (< 24h):** query graph.json directly — do NOT re-scan source folders.
  jq '.codebase.interfaces[] | {name, file}' .claude/graph/graph.json
  jq '.codebase.classes[] | select(.file | contains("Concretes")) | {name, file, implements}' .claude/graph/graph.json
  jq '.validation | {errors: (.errors|length), warnings: (.warnings|length)}' .claude/graph/graph.json

**If graph is disabled or stale (> 24h):** fall back to direct file-scan (original steps 1–3).
```

4. **Project Features table** — add missing `graph` row:
```
| `graph` | **DISABLED** | graph.json is the primary source of truth. `/orchestrate` pre-scan reads graph instead of scanning folders. `/catch-up`, `/context-prime`, `/architect` query graph first; fall back to file-scan only if graph is stale (> 24h) or disabled. |
```

**Status:** 🔲 Open — apply to template repo `.claude/CLAUDE.md`  
**Found by:** Comparing nile_hole_sphere_repo (updated) vs template repo (stale) — 2026-05-24

---

*Generated from analysis of nile_hole_sphere_repo graphify session — 2026-05-24*  
*Updated with Codex review findings (Bugs 10–17) — 2026-05-24*  
*Updated with post-fix validation findings (Limitations 18–19) — 2026-05-24*  
*Updated with CLAUDE.md sync requirement — 2026-05-24*
