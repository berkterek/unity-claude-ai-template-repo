# New Module — Static Module Generator

You generate the standard 5-file static module structure for a new service/system in this Unity project. You ask the developer for the module name, then produce all files and wire everything into `AppModules.cs` and `ConfigCatalog.cs`.

## What You Generate

For a module named `[X]` (e.g. `Audio`):

```
_GameFolders/Scripts/Games/Abstracts/[X]/
└── I[X]Service.cs                       ← Public API contract (interface)

_GameFolders/Scripts/Games/Concretes/[X]/
├── [X]Service.cs                        ← sealed pure C# service
├── [X]Configuration.cs                  ← ScriptableObject config
├── [X]Module.cs                         ← static installer class (NOT ScriptableObject)
└── [X]Events.cs                         ← IEvent structs (empty scaffold)
```

Plus two edits to existing files:
- `AppModules.cs` — add one line: `[X]Module.Install(builder, configs.[X]);`
- `ConfigCatalog.cs` — add `[SerializeField]` field, public property, and `Validate()` null check

Optional: if the module needs Unity API, also generate:
```
_GameFolders/Scripts/Games/Concretes/[X]/
└── Basic[X]Provider.cs                  ← MonoBehaviour, wraps Unity API
```

## Step 0 — Knowledge Graph Preload

Before gathering requirements, decide whether the knowledge graph can accelerate the existing-structure check for this new module — specifically, checking for existing class/interface/installer names and namespace collisions before scaffolding, so a duplicate `I[X]Service` or a namespace clash is caught before any file is written rather than after.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, skip to Step 1 (file-scan behavior, unchanged).

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
    Run /build-knowledge-graph for graph-accelerated new-module scaffolding. Falling back to file scan.
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

Keep this output as `GRAPH_CONTEXT`. When `GRAPH_CONTEXT` is empty, Step 2 behaves exactly as before — no regression.

---

## Your Process

### Step 1 — Gather requirements (ask these questions)

1. "What is the module name?" (e.g. `Audio`, `Currency`, `Store`)
2. "What are the main operations this service will expose?" (e.g. `PlaySound`, `AddCoins`)
3. "Does this module need a Unity provider (AudioSource, Physics, Camera, etc.) or is it pure C#?"
4. "Does this module publish or subscribe to any events?"

### Step 2 — Read existing infrastructure

## Knowledge Graph (class/interface/installer inventory — query this BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0 — if empty, write "No usable graph — scan source files directly."]

If a knowledge graph inventory is provided above (non-empty), use it FIRST to check for conflicts before proposing any structure:
- Confirm no existing class/interface named `I[X]Service`, `[X]Service`, `[X]Module`, `[X]Configuration`, or `[X]Events` already exists (the graph's CLASSES/INTERFACES lists).
- Confirm the proposed `Game.Concretes.[X]` / `Game.Abstracts.[X]` namespace does not collide with an existing domain folder in the graph's class list.
- Check the INSTALLERS list for the existing module registration order, so the new `[X]Module.Install()` line is placed correctly relative to `EventBusModule` and other modules — without needing to open `AppModules.cs` directly.
- Only read source files for the specific detail (exact field list, `Validate()` body) the graph cannot provide.

If the graph inventory is empty (or absent), read these files directly before proposing any structure (unchanged fallback):
- `_GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs` — to see existing module order
- `_GameFolders/Scripts/Games/Concretes/Infrastructure/ConfigCatalog.cs` — to see existing fields

### Step 3 — Fire ARCHITECTURE_GATE

Show the proposed module structure to the user:
- Interface, Service, Configuration, static Module class, Events, Provider (if Unity API needed)
- The exact line to add in `AppModules.Install()` (after EventBusModule, before or after existing modules)
- The field + property + Validate() null check to add in `ConfigCatalog`
- Wait for explicit `go` before generating any files

After receiving `go` — write the gate-cleared file:
```bash
mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo '{"gate":"ARCHITECTURE_GATE","pipeline":"new-module","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

### Step 4 — Generate files

Generate all files in this order:

1. `I[X]Service.cs`
2. `[X]Service.cs`
3. `[X]Configuration.cs`
4. `[X]Module.cs`
5. `[X]Events.cs`
6. `Basic[X]Provider.cs` (only if Unity provider is needed)
7. Edit `AppModules.cs` — add one line
8. Edit `ConfigCatalog.cs` — add field, property, and null check in `Validate()`

### Step 5 — Cleanup and checklist

After all files written:
```bash
rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

Print the **Portability Checklist** (see below).

---

## Code Templates

### I[X]Service.cs

```csharp
// _GameFolders/Scripts/Games/Abstracts/[X]/I[X]Service.cs
namespace Game.Abstracts.[X]
{
    public interface I[X]Service
    {
        // TODO: declare public API methods here
    }
}
```

### [X]Service.cs

```csharp
// _GameFolders/Scripts/Games/Concretes/[X]/[X]Service.cs
using Game.Abstracts.[X];

namespace Game.Concretes.[X]
{
    public sealed class [X]Service : I[X]Service, IInitializable, IDisposable
    {
        #region Fields

        private readonly I[X]Provider _provider; // remove if no provider
        private readonly [X]Configuration _config;

        #endregion

        #region Constructor

        public [X]Service(I[X]Provider provider, [X]Configuration config)
        {
            _provider = provider;
            _config = config;
        }

        #endregion

        #region Lifecycle

        public void Initialize()
        {
        }

        public void Dispose()
        {
        }

        #endregion

        #region Public Methods

        // TODO: implement I[X]Service methods

        #endregion
    }
}
```

### [X]Configuration.cs

```csharp
// _GameFolders/Scripts/Games/Concretes/[X]/[X]Configuration.cs
using UnityEngine;

namespace Game.Concretes.[X]
{
    [CreateAssetMenu(menuName = "Game/[X] Configuration", fileName = "[X]Configuration")]
    public sealed class [X]Configuration : ScriptableObject
    {
        #region Fields

        // [SerializeField] private float _exampleValue = 1f;

        #endregion

        #region Properties

        // public float ExampleValue => _exampleValue;

        #endregion
    }
}
```

### [X]Module.cs (static class — NOT ScriptableObject)

```csharp
// _GameFolders/Scripts/Games/Concretes/[X]/[X]Module.cs
using UnityEngine;
using VContainer;

namespace Game.Concretes.[X]
{
    public static class [X]Module
    {
        public static void Install(IContainerBuilder builder, [X]Configuration config)
        {
            if (config == null)
            {
                Debug.LogError("[[X]Module] [X]Configuration missing.");
                return;
            }

            builder.RegisterInstance(config);
            builder.Register<[X]Service>(Lifetime.Singleton).AsImplementedInterfaces();
            // If provider is needed, register it separately:
            // builder.RegisterComponentInHierarchy<Basic[X]Provider>().AsImplementedInterfaces();
        }
    }
}
```

### [X]Events.cs

```csharp
// _GameFolders/Scripts/Games/Concretes/[X]/[X]Events.cs
using Framework.Events;

namespace Game.Concretes.[X]
{
    // Example — add module-specific events below
    // public readonly struct [X]ExampleEvent : IEvent
    // {
    //     public readonly int Value;
    //     public [X]ExampleEvent(int value) => Value = value;
    // }
}
```

### Basic[X]Provider.cs (only if Unity API needed)

```csharp
// _GameFolders/Scripts/Games/Concretes/[X]/Basic[X]Provider.cs
using Game.Abstracts.[X];
using UnityEngine;

namespace Game.Concretes.[X]
{
    public sealed class Basic[X]Provider : MonoBehaviour, I[X]Provider
    {
        #region Fields

        // [SerializeField] private AudioSource _source;

        #endregion

        #region I[X]Provider

        // TODO: implement I[X]Provider methods using Unity API

        #endregion
    }
}
```

---

## AppModules.cs edit

Add exactly one line inside `AppModules.Install()`, after `EventBusModule.Install(builder)`:

```csharp
[X]Module.Install(builder, configs.[X]);
```

`EventBusModule` must remain first — do not reorder it.

---

## ConfigCatalog.cs edits

**Add to `#region Fields`:**
```csharp
[SerializeField] private [X]Configuration _[x]; // lowercase first char
```

**Add to `#region Properties`:**
```csharp
public [X]Configuration [X] => _[x];
```

**Add null check inside `Validate()`:**
```csharp
if (_[x] == null) missing.Add(nameof(_[x]));
```

---

## Code Rules

| Rule | Detail |
|------|--------|
| `[X]Module` is a **static class** | `public static class [X]Module` — NOT ScriptableObject, NOT MonoBehaviour |
| Install signature | `public static void Install(IContainerBuilder builder, [X]Configuration config)` |
| Null guard | `if (config == null) { Debug.LogError(...); return; }` — never `throw` |
| Registration | `.AsImplementedInterfaces()` — covers `IInitializable`, `IDisposable`, `ITickable` |
| EventBusModule is always first | New module goes after it in `AppModules.Install()` |
| `AppScope.cs` never changes | Add the module line to `AppModules.cs` only |
| Service has no `using UnityEngine` | Unity API is in the Provider (if needed) |
| Events in own file | `[X]Events.cs` in `Concretes/[X]/` — never top-level `Scripts/Events/` |

---

## Portability Checklist Output

After generating, always print:

```
## Module Portability Checklist: [X]

[ ] [X]Module is a static class (not ScriptableObject, not MonoBehaviour)
[ ] Service class has no `using UnityEngine` import
[ ] No concrete cross-module dependencies (only interfaces)
[ ] Config null guard present in [X]Module.Install() — uses Debug.LogError + return, not throw
[ ] Events in their own [X]Events.cs file
[ ] Provider (if any) is in Concretes/[X]/ and is the only file with `using UnityEngine`
[ ] All public methods have a corresponding interface declaration
[ ] AppModules.cs updated — one new line after EventBusModule.Install()
[ ] ConfigCatalog.cs updated — field, property, and Validate() null check added

## One-time Editor action required

1. In Unity: right-click Assets/Configs/ (or wherever configs live) → Create → Game → [X] Configuration
2. Select the ConfigCatalog asset → drag the new [X]Configuration into the `_[x]` field
   (ConfigCatalog is the only drag-drop point — no other prefab needs this SO)
```
