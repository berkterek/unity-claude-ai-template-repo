# Check Portability — Module Portability Audit

You audit one or more modules to verify they are portable — can be copy-pasted to another project without modification.

## Pipeline

```
[Step 0a] Knowledge Graph Preload → GRAPH_CONTEXT (or empty on stale/empty/disabled)
    ↓
[Audit] Per-module checks (graph-first for cross-module dependency detection) → Output
```

---

## Step 0a — Knowledge Graph Preload

Before reading any module source file, decide whether the knowledge graph can accelerate this audit. This follows the graph-first spirit of `/implement`, `/create-plan`, `/fix`, `/catch-up`, and `/search`. Check #2 (No Concrete Cross-Module Dependencies) is exactly what the graph's `dependencies` field is built to answer — a class's declared dependencies and whether they cross module/domain boundaries.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, skip to the Audit (file-scan behavior, unchanged).

If it is a candidate, verify the graph is **usable** (fresh AND non-empty):

```bash
python3 -c "
import json, os, time
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
n = len(cb.get('classes', []))
lb = '.claude/graph/.last-build'
age_h = (time.time() - os.path.getmtime(lb)) / 3600 if os.path.exists(lb) else 1e9
print('classes=%d age_h=%.1f' % (n, age_h))
"
```

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, fall back to file scan. Do NOT warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to file scan:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated audit. Falling back to file scan.
  ```
- Otherwise (fresh AND non-empty) → build `GRAPH_CONTEXT` from the graph inventory:

```bash
python3 -c "
import json
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
classes = cb.get('classes', [])
interfaces = cb.get('interfaces', [])
events = cb.get('events', [])
installers = cb.get('vcontainer', {}).get('installers', [])
print('CLASSES (%d):' % len(classes))
for c in classes:
    print('  %s | mono=%s | deps=%s | pub=%s | sub=%s' % (
        c['name'], c.get('is_mono_behaviour', False),
        c.get('dependencies', []), c.get('events_published', []), c.get('events_subscribed', [])))
print('INTERFACES (%d):' % len(interfaces))
for i in interfaces: print('  %s' % i['name'])
print('EVENTS (%d):' % len(events))
for e in events: print('  %s' % e['name'])
print('INSTALLERS (%d):' % len(installers))
for inst in installers:
    regs = [r.get('type','') for r in inst.get('registrations', [])]
    print('  %s | registrations=%s' % (inst['name'], regs))
"
```

Keep this output as `GRAPH_CONTEXT` and use it during the Audit below. When `GRAPH_CONTEXT` is empty, the audit behaves exactly as before — no regression.

## Knowledge Graph (class/interface/event/installer inventory — query BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from the preload step — if empty, write "No usable graph — scan source files directly."]

Use this inventory first for check #2 (cross-module dependencies): look up the module's service class in `CLASSES`, read its `deps=` list, and flag any dependency whose owning domain differs from the module under audit and is not an interface (`I*`) name. Only fall back to reading `[ModuleName]Service.cs` constructor parameters directly when the graph inventory is empty or does not list the class. The graph's `pub=`/`sub=` lists similarly cross-check #4 (Events in Own File) without needing to open the service file first.

## What You Check

For each module folder provided (`_GameFolders/Scripts/Games/[ModuleName]/`):

### 1. No UnityEngine in Service Class
- Read `[ModuleName]Service.cs`
- Fail if `using UnityEngine` is present
- Pass if clean; note if a Provider exists in `Games/Concretes/[ModuleName]/`

### 2. No Concrete Cross-Module Dependencies
- Check constructor parameters of `[ModuleName]Service.cs`
- Fail if any parameter is a concrete class from another module (not an interface)

### 3. Config Null Guard
- Check `[ModuleName]Installer.cs`
- Fail if `Install()` has no null check on `_config` before registering

### 4. Events in Own File
- Check if `IEvent` structs are in `[ModuleName]Events.cs`
- Warn if they are embedded inside the service file

### 5. Provider Separation
- Check `_GameFolders/Scripts/Games/Concretes/[ModuleName]/`
- Warn if provider files are inside the module folder instead

### 6. Interface Coverage
- Check `I[ModuleName]Service.cs`
- Warn if `[ModuleName]Service.cs` has public methods not declared in the interface

## Output Format

```
## Portability Audit: AudioModule

✅ No UnityEngine in AudioService.cs
✅ Only interface dependencies in constructor
✅ Config null guard present in AudioInstaller.Install()
✅ Events in AudioEvents.cs
✅ Provider in Games/Concretes/Audio/ (BasicAudioProvider.cs)
⚠️  AudioService.SetVolume() is public but not declared in IAudioService

Result: PORTABLE with 1 warning
```

If any check **fails** (not just warns), the module is **NOT PORTABLE** and the output explains what to fix.
