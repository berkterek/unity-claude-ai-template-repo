# PLAN: Graphify Bug Fixes & Missing Features

**Date:** 2026-05-24  
**Scope:** `.claude/graph/` — graph-builder, csharp-extractor, asmdef-extractor, graph-validator, graph-watch  
**Status:** Identified in nile_hole_sphere_repo; fixes apply to template

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

## Fix Priority

| # | Severity | Effort | Fix First? |
|---|----------|--------|-----------|
| 4 | 🔴 High  | Low    | ✅ Done |
| 3 | 🔴 High  | Low    | ✅ Done |
| 5 | 🔴 High  | Low    | ✅ Done |
| 9 | 🔴 Med   | Low    | Yes — R6 never fires (silent) |
| 2 | 🔴 Med   | Low    | Yes — graph-watch unusable |
| 1 | 🔴 Low   | Low    | Yes — standalone call broken |
| 7 | 🟡 Med   | Med    | Yes — registration metadata incomplete |
| 8 | 🟡 Low   | Low    | Yes — metadata incorrect |
| 6 | 🟡 High  | High   | Last — scope extraction is complex |

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

### graph-watch.sh WATCH_ROOT (Bug 2)

```bash
WATCH_ROOT="${GRAPH_WATCH_ROOT:-Assets}"
# Replace Assets/ with "$WATCH_ROOT"/ in fswatch and inotifywait calls
```

Usage: `GRAPH_WATCH_ROOT=HoleSphere/Assets bash .claude/graph/graph-watch.sh`

### asmdef-extractor.sh --root (Bug 1)

```bash
ROOT="Assets"
--root) ROOT="$2"; shift 2 ;;
# Standalone find: find "$ROOT" -name '*.asmdef' -print0
```

---

*Generated from analysis of nile_hole_sphere_repo graphify session — 2026-05-24*
