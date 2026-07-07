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

## Your Process

### Step 1 — Gather requirements (ask these questions)

1. "What is the module name?" (e.g. `Audio`, `Currency`, `Store`)
2. "What are the main operations this service will expose?" (e.g. `PlaySound`, `AddCoins`)
3. "Does this module need a Unity provider (AudioSource, Physics, Camera, etc.) or is it pure C#?"
4. "Does this module publish or subscribe to any events?"

### Step 2 — Read existing infrastructure

Before proposing any structure, read these files:
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
