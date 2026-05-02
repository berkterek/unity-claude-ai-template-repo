# Setup Project — New Unity Project Initializer

You set up a new Unity project using this template. You ask questions about the project, then generate all project-specific boilerplate that cannot live in the template itself.

## What This Command Does

The template provides rules, hooks, and commands that work for any Unity project. But every project needs its own:
- Assembly definition files (with correct project name)
- Base framework classes (IEventBus, ModuleInstaller, AppScope)
- NSubstitute test assembly setup
- Sample test templates

You generate all of these.

## Your Process

### Step 1 — Gather Info

Ask the developer:
1. **Project name** (e.g. `SpaceTroopers`, `MyGame`) — used for assembly names
2. **Unity version** (e.g. `6000.0.x`)
3. **Scenes**: Default is Bootstrap + Menu + Game. Any additions?
4. **Does the project use ECS DOTS?** (yes/no) — adds `Games/Ecs/` folder and ECS assembly refs
5. **Third-party packages installed?**
   - VContainer (required)
   - UniTask (required)
   - New Input System (required)
   - TextMeshPro
   - DOTween
   - Other?

### Step 2 — Generate Folder Structure

```
Assets/
├── _Scenes/
│   ├── Bootstrap.unity
│   ├── Menu.unity
│   └── Game.unity
├── _Framework/
│   ├── Events/             ← FrameworkEvents.asmdef
│   ├── Logging/            ← FrameworkLogging.asmdef
│   └── SaveLoadSystems/    ← FrameworkSaveLoadSystems.asmdef
└── _GameFolders/
    ├── Arts/
    ├── Prefabs/
    ├── Configs/            ← ScriptableObject assets go here
    ├── Plugins/
    │   └── NSubstitute/    ← NSubstitute.dll placed here manually
    └── Scripts/
        ├── Games/          ← [ProjectName]Games.asmdef
        │   ├── Abstracts/
        │   ├── Concretes/
        │   └── Ecs/        ← (only if ECS enabled)
        ├── Editors/        ← [ProjectName]Editor.asmdef
        └── Tests/
            ├── [ProjectName]Tests/       ← Edit Mode
            └── [ProjectName]PlayTests/   ← Play Mode
```

### Step 3 — Generate Assembly Definition Files

Generate `.asmdef` files with correct project name substituted:

- `[ProjectName]Games.asmdef` — runtime, references VContainer + UniTask + Input System
- `[ProjectName]Editor.asmdef` — editor-only
- `[ProjectName]Tests.asmdef` — Edit Mode, NSubstitute precompiledReferences
- `[ProjectName]PlayTests.asmdef` — Play Mode, NSubstitute precompiledReferences

### Step 4 — Generate Base Framework Files

**`_Framework/Events/IEventBus.cs`**
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

**`_GameFolders/Scripts/Games/Abstracts/ModuleInstaller.cs`**
```csharp
using VContainer;
using UnityEngine;

namespace Game.Abstracts
{
    public abstract class ModuleInstaller : ScriptableObject
    {
        public abstract void Install(IContainerBuilder builder);
    }
}
```

**`_GameFolders/Scripts/Games/Concretes/Infrastructure/AppScope.cs`** — Bootstrap scene scope

**`_GameFolders/Scripts/Games/Concretes/Infrastructure/AppInstaller.cs`** — Composite installer

### Step 5 — Generate Test Templates

Generate `SampleEditModeTests.cs` and `SamplePlayModeTests.cs` showing AAA pattern.

### Step 6 — Print Manual Setup Checklist

Always end with this checklist for the developer:

```
## Manual Setup Required

### NSubstitute (REQUIRED for tests)
NSubstitute cannot be installed via Package Manager.
1. Download NSubstitute.dll from https://github.com/nsubstitute/NSubstitute/releases
2. Place in Assets/_GameFolders/Plugins/NSubstitute/NSubstitute.dll
3. The .asmdef files already reference it via precompiledReferences

### VContainer
Install via Package Manager:
https://github.com/hadashiA/VContainer

### UniTask
Install via Package Manager:
https://github.com/Cysharp/UniTask

### New Input System
1. Install via Package Manager: com.unity.inputsystem
2. Edit → Project Settings → Player → Active Input Handling → Input System Package (New)
3. Create Assets/Input/[ProjectName]Controls.inputactions
4. Enable "Generate C# Class" in the .inputactions inspector

### AppScope Scene Setup
1. Open Bootstrap scene
2. Create empty GameObject "AppScope"
3. Add AppScope component
4. Create AppInstaller.asset → Assets/Configs/
5. Assign to AppScope._appInstaller
6. Set Bootstrap as Build Index 0 in Build Settings

### Input Actions
Create your .inputactions asset and enable "Generate C# Class" before writing InputView.
```
