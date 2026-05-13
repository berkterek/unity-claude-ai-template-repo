# Setup Project — New Unity Project Initializer

You set up a new Unity project using this template. You ask questions about the project, then generate all project-specific boilerplate that cannot live in the template itself.

## What This Command Does

The template provides rules, hooks, and commands that work for any Unity project. But every project needs its own:
- Assembly definition files (with correct project name)
- Base framework classes (IEventBus, EventBus, EventBusAccessor, ModuleInstaller, AppScope, AppInstaller)
- NSubstitute test assembly setup
- Sample test templates

You generate all of these.

## Your Process

### Step 1 — Gather Info

Ask the developer ALL of these questions before doing anything else:

1. **Project name** (e.g. `SpaceTroopers`, `MyGame`) — used for assembly names
2. **Unity version** (e.g. `6000.0.x`)
3. **Scenes**: Default is Bootstrap + Menu + Game. Any additions?
4. **Does the project use ECS DOTS?** (yes/no) — adds `Games/Ecs/` folder, ECS asmdef, and ECS bridge files
5. **Packages installed?**
   - VContainer (required) — installed?
   - UniTask (required) — installed?
   - New Input System (required) — installed?
   - **NSubstitute DLL** — have you placed `NSubstitute.dll` in `Assets/Plugins/NSubstitute/`? (required for tests, cannot be installed via Package Manager)
   - TextMeshPro — installed?
   - DOTween — installed?
   - Other?

Collect all answers before proceeding. Do not ask one by one.

---

### Step 1b — Package Gate (NON-NEGOTIABLE)

Evaluate readiness for each generation phase separately.

#### Gate A — Runtime packages (blocks Steps 3 + 4)

| Package | Required |
|---------|----------|
| VContainer | YES |
| UniTask | YES |
| New Input System | YES |

**If ANY Gate A package is missing:**
1. Print a warning listing which packages are absent.
2. Run **only Step 2** (folder structure only — no .asmdef, no C# files).
3. Print the Manual Setup Checklist (Step 6).
4. **STOP. Do not proceed to Step 3, 4, or 5.**
5. Tell the developer: "Install the missing packages, then run `/setup-project` again."

**Only continue to Steps 3 + 4 when all Gate A packages are confirmed installed.**

#### Gate B — NSubstitute (blocks Step 5 and NSubstitute refs in test .asmdef files)

**If NSubstitute DLL is NOT confirmed present at `Assets/Plugins/NSubstitute/`:**
- Generate test `.asmdef` files WITHOUT `precompiledReferences` and WITHOUT `overrideReferences: true`.
- **Skip Step 5** (do not generate test template files).
- Note in checklist: "After placing NSubstitute.dll, re-run `/setup-project` or manually add `\"precompiledReferences\": [\"NSubstitute.dll\"]` and `\"overrideReferences\": true` to your test .asmdef files, then run Step 5 manually."

**If NSubstitute DLL IS confirmed present:**
- Generate test `.asmdef` files with full NSubstitute references.
- Run Step 5 normally.

---

### Step 2 — Generate Folder Structure

> **NOTE:** Claude cannot create `.unity` scene files — `block-scene-edit.sh` blocks all writes to scene/prefab assets. Create scenes manually in Unity Editor (File → New Scene) or via `/scene-setup` after this command completes.

Always run Step 2 regardless of gate status. Create these folders (empty `.gitkeep` files where needed):

```
Assets/
├── _Scenes/                        ← create manually in Unity Editor
│   ├── Bootstrap.unity             ← create manually
│   ├── Menu.unity                  ← create manually
│   └── Game.unity                  ← create manually
├── _Framework/
│   ├── Events/                     ← FrameworkEvents.asmdef
│   ├── Logging/                    ← FrameworkLogging.asmdef
│   └── SaveLoadSystems/            ← FrameworkSaveLoadSystems.asmdef
├── Plugins/
│   └── NSubstitute/                ← place NSubstitute.dll here manually
└── _GameFolders/
    ├── Arts/
    ├── Prefabs/
    │   ├── Enemies/
    │   ├── UI/
    │   ├── VFX/
    │   └── Environment/
    ├── Configs/
    ├── Input/                      ← .inputactions file goes here
    └── Scripts/
        ├── Games/                  ← [ProjectName]Games.asmdef
        │   ├── Abstracts/
        │   ├── Concretes/
        │   │   └── Infrastructure/
        │   └── Ecs/                ← only if ECS=yes
        │       ├── Authorings/
        │       ├── Components/
        │       └── Systems/
        ├── Editors/                ← [ProjectName]Editor.asmdef
        └── Tests/
            ├── [ProjectName]Tests/       ← Edit Mode
            └── [ProjectName]PlayTests/   ← Play Mode
```

---

### Step 3 — Generate Assembly Definition Files

**Gate A must pass before this step.**

Replace `[ProjectName]` with the actual project name the developer provided.

#### `_Framework/Events/FrameworkEvents.asmdef`
```json
{
    "name": "FrameworkEvents",
    "rootNamespace": "Framework.Events",
    "references": [],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": true
}
```

#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{
    "name": "FrameworkLogging",
    "rootNamespace": "Framework.Logging",
    "references": [],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": true
}
```

#### `_Framework/SaveLoadSystems/FrameworkSaveLoadSystems.asmdef`
```json
{
    "name": "FrameworkSaveLoadSystems",
    "rootNamespace": "Framework.SaveLoadSystems",
    "references": [],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": true
}
```

#### `_GameFolders/Scripts/Games/[ProjectName]Games.asmdef`
```json
{
    "name": "[ProjectName]Games",
    "rootNamespace": "Game",
    "references": [
        "FrameworkEvents",
        "FrameworkLogging",
        "FrameworkSaveLoadSystems",
        "VContainer",
        "UniTask",
        "Unity.InputSystem"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": []
}
```

> If ECS=yes, add `"Unity.Entities"` and `"Unity.Transforms"` to the `references` array.

#### `_GameFolders/Scripts/Editors/[ProjectName]Editor.asmdef`
```json
{
    "name": "[ProjectName]Editor",
    "rootNamespace": "Game.Editor",
    "references": [
        "[ProjectName]Games"
    ],
    "includePlatforms": [
        "Editor"
    ],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": []
}
```

#### `_GameFolders/Scripts/Tests/[ProjectName]Tests/[ProjectName]Tests.asmdef`

**With NSubstitute (Gate B passed):**
```json
{
    "name": "[ProjectName]Tests",
    "rootNamespace": "Game.Tests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[ProjectName]Games",
        "FrameworkEvents"
    ],
    "includePlatforms": [
        "Editor"
    ],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": [
        "UNITY_INCLUDE_TESTS"
    ],
    "versionDefines": []
}
```

**Without NSubstitute (Gate B not passed — omit precompiledReferences):**
```json
{
    "name": "[ProjectName]Tests",
    "rootNamespace": "Game.Tests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[ProjectName]Games",
        "FrameworkEvents"
    ],
    "includePlatforms": [
        "Editor"
    ],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": false,
    "defineConstraints": [
        "UNITY_INCLUDE_TESTS"
    ],
    "versionDefines": []
}
```

#### `_GameFolders/Scripts/Tests/[ProjectName]PlayTests/[ProjectName]PlayTests.asmdef`

**With NSubstitute (Gate B passed):**
```json
{
    "name": "[ProjectName]PlayTests",
    "rootNamespace": "Game.PlayTests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[ProjectName]Games",
        "FrameworkEvents"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": [
        "UNITY_INCLUDE_TESTS"
    ],
    "versionDefines": []
}
```

**Without NSubstitute (Gate B not passed):**
```json
{
    "name": "[ProjectName]PlayTests",
    "rootNamespace": "Game.PlayTests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[ProjectName]Games",
        "FrameworkEvents"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": false,
    "defineConstraints": [
        "UNITY_INCLUDE_TESTS"
    ],
    "versionDefines": []
}
```

#### ECS asmdef (only if ECS=yes)

#### `_GameFolders/Scripts/Games/Ecs/[ProjectName]Ecs.asmdef`
```json
{
    "name": "[ProjectName]Ecs",
    "rootNamespace": "Game.Ecs",
    "references": [
        "FrameworkEvents",
        "[ProjectName]Games",
        "Unity.Entities",
        "Unity.Transforms",
        "Unity.Burst",
        "Unity.Collections",
        "Unity.Mathematics"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": true,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": []
}
```

---

### Step 4 — Generate Base Framework Files

**Gate A must pass before this step.**

#### `_Framework/Events/IEventBus.cs`
```csharp
namespace Framework.Events
{
    public interface IEventBus
    {
        void Publish<T>(T eventData) where T : struct, IEvent;
        void Subscribe<T>(System.Action<T> handler) where T : struct, IEvent;
        void Unsubscribe<T>(System.Action<T> handler) where T : struct, IEvent;
    }

    public interface IEvent { }
}
```

#### `_Framework/Events/EventBus.cs`
```csharp
using System;
using System.Collections.Generic;
using VContainer.Unity;

namespace Framework.Events
{
    public sealed class EventBus : IEventBus, IInitializable, IDisposable
    {
        #region Fields

        private readonly Dictionary<Type, List<Delegate>> _handlers = new();

        #endregion

        #region Lifecycle

        public void Initialize() { }

        public void Dispose()
        {
            _handlers.Clear();
        }

        #endregion

        #region Public Methods

        public void Publish<T>(T eventData) where T : struct, IEvent
        {
            var type = typeof(T);

            if (!_handlers.TryGetValue(type, out var list)) return;

            for (int i = list.Count - 1; i >= 0; i--)
            {
                if (list[i] is Action<T> handler)
                    handler(eventData);
            }
        }

        public void Subscribe<T>(Action<T> handler) where T : struct, IEvent
        {
            var type = typeof(T);

            if (!_handlers.ContainsKey(type))
                _handlers[type] = new List<Delegate>();

            _handlers[type].Add(handler);
        }

        public void Unsubscribe<T>(Action<T> handler) where T : struct, IEvent
        {
            var type = typeof(T);

            if (_handlers.TryGetValue(type, out var list))
                list.Remove(handler);
        }

        #endregion
    }
}
```

#### `_Framework/Events/EventBusAccessor.cs`
```csharp
using System;

namespace Framework.Events
{
    public static class EventBusAccessor
    {
        private static IEventBus _instance;

        public static IEventBus Instance => _instance
            ?? throw new InvalidOperationException(
                "EventBusAccessor not initialized. Call Initialize() inside AppScope.RegisterBuildCallback.");

        public static void Initialize(IEventBus bus) => _instance = bus;
    }
}
```

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/ModuleInstaller.cs`
```csharp
using UnityEngine;
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public abstract class ModuleInstaller : ScriptableObject
    {
        public abstract void Install(IContainerBuilder builder);
    }
}
```

> `ModuleInstaller` uses `ScriptableObject` (requires `using UnityEngine`) so it lives in `Concretes/Infrastructure/`, not `Abstracts/`. The `check-pure-csharp.sh` hook blocks `using UnityEngine` in `Abstracts/`.

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/AppInstaller.cs`
```csharp
using UnityEngine;
using VContainer;

namespace Game.Concretes.Infrastructure
{
    [CreateAssetMenu(menuName = "Game/Infrastructure/App Installer", fileName = "AppInstaller")]
    public sealed class AppInstaller : ScriptableObject
    {
        #region Fields

        [SerializeField] private ModuleInstaller[] _installers;

        #endregion

        #region Public Methods

        public void Install(IContainerBuilder builder)
        {
            if (_installers == null) return;

            foreach (var installer in _installers)
            {
                if (installer == null) continue;
                installer.Install(builder);
            }
        }

        #endregion
    }
}
```

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/AppScope.cs`
```csharp
using Framework.Events;
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class AppScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private AppInstaller _appInstaller;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            builder.Register<EventBus>(Lifetime.Singleton).As<IEventBus>();

            _appInstaller?.Install(builder);

            builder.RegisterBuildCallback(container =>
            {
                EventBusAccessor.Initialize(container.Resolve<IEventBus>());
            });
        }

        #endregion
    }
}
```

---

### Step 5 — Generate Test Templates

**Gate A and Gate B must both pass before this step.**

#### `_GameFolders/Scripts/Tests/[ProjectName]Tests/SampleEditModeTests.cs`
```csharp
using Framework.Events;
using NSubstitute;
using NUnit.Framework;

namespace Game.Tests
{
    public class SampleEditModeTests
    {
        [Test]
        public void SampleMethod_WhenConditionMet_ReturnsExpectedResult()
        {
            // Arrange
            var eventBus = Substitute.For<IEventBus>();

            // Act
            eventBus.Publish(new SampleEvent());

            // Assert
            eventBus.Received(1).Publish(Arg.Any<SampleEvent>());
        }

        private struct SampleEvent : IEvent { }
    }
}
```

#### `_GameFolders/Scripts/Tests/[ProjectName]PlayTests/SamplePlayModeTests.cs`
```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine.TestTools;

namespace Game.PlayTests
{
    public class SamplePlayModeTests
    {
        [UnityTest]
        public IEnumerator SamplePlayTest_WhenSceneLoaded_ObjectExists()
        {
            // Arrange
            // Load your test scene here:
            // yield return SceneManager.LoadSceneAsync("TestScenes/YourTestScene");
            yield return null;

            // Act
            // Perform actions on MonoBehaviours or services

            // Assert
            Assert.Pass("Replace this with a real assertion.");
        }
    }
}
```

---

### Step 6 — Print Manual Setup Checklist

Always end with this checklist:

```
## Manual Setup Required

### Scenes (Claude cannot create .unity files)
Create these scenes manually in Unity Editor (File → New Scene → Save):
- Assets/_Scenes/Bootstrap.unity
- Assets/_Scenes/Menu.unity
- Assets/_Scenes/Game.unity
After creating Bootstrap.unity: set it as Build Index 0 in Build Settings.

### NSubstitute (REQUIRED for tests)
NSubstitute cannot be installed via Package Manager.
1. Download NSubstitute.dll from NuGet: https://www.nuget.org/packages/NSubstitute — click "Download package", rename .nupkg to .zip, extract, take NSubstitute.dll from the lib/ folder
2. Place at: Assets/Plugins/NSubstitute/NSubstitute.dll  (NOT inside _GameFolders)
3. The .asmdef files already reference it via precompiledReferences
4. If you skipped this earlier, re-run /setup-project to generate test templates.

### VContainer
Install via openupm or Package Manager:
https://github.com/hadashiA/VContainer

### UniTask
Install via openupm or Package Manager:
https://github.com/Cysharp/UniTask

### New Input System
1. Install via Package Manager: com.unity.inputsystem
2. Edit → Project Settings → Player → Active Input Handling → Input System Package (New)
3. Create Assets/Input/[ProjectName]Controls.inputactions
4. Enable "Generate C# Class" in the .inputactions inspector

### AppScope Scene Setup
1. Open Bootstrap.unity
2. Create empty GameObject named "AppScope"
3. Add AppScope component
4. Right-click Assets/Configs → Create → Game/Infrastructure/App Installer → name it AppInstaller
5. Drag AppInstaller asset onto AppScope._appInstaller field
```
