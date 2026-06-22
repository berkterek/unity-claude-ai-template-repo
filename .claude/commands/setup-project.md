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

### Step 0 — Detect Existing State (always runs first)

Before asking any questions, run these Bash commands to detect current project state:

```bash
# 1. Does project-features.json already exist?
[ -f ".claude/project-features.json" ] && echo "FEATURES_JSON=yes" || echo "FEATURES_JSON=no"

# 2. Detect actual feature signals in the project
[ -d "Assets/_GameFolders/Scripts/Games/Ecs" ] && echo "ECS_DIR=yes" || echo "ECS_DIR=no"
[ -d "Assets/_GameFolders/Scripts/Tests" ] && echo "TESTS_DIR=yes" || echo "TESTS_DIR=no"
grep -q "com.unity.addressables" Packages/manifest.json 2>/dev/null && echo "ADDRESSABLES_PKG=yes" || echo "ADDRESSABLES_PKG=no"

# 3. If project-features.json exists, read current declared values
[ -f ".claude/project-features.json" ] && cat .claude/project-features.json || echo "{}"
```

#### Decision Tree

**A — project-features.json does NOT exist**
→ This is a fresh setup. Proceed to Step 1 normally.
→ Pre-fill answers from detected signals as defaults (e.g. if `Ecs/` exists → suggest ECS=yes).

**B — project-features.json EXISTS and matches detected state**
→ Print: "Project already configured. Features: addressables=[x], testing=[x], ecs=[x]"
→ Ask: "Re-run setup to regenerate files, or sync settings only?"
→ If sync: run Steps 5b + 5c only (update settings.json and CLAUDE.md header), then stop.
→ If regenerate: continue from Step 1.

**C — project-features.json EXISTS but CONFLICTS with detected state**
→ Print a conflict table, for example:
```
⚠ Feature configuration conflict detected:

  Feature        | project-features.json | Detected in project
  ---------------|----------------------|--------------------
  ecs            | true                 | NO (Ecs/ folder missing)
  testing        | true                 | NO (Tests/ folder missing)
  addressables   | false                | YES (manifest.json has it)

Fix these conflicts before proceeding? (y/n)
```
→ If y: update project-features.json to match detected state, then run Steps 5b + 5c to sync settings.json and CLAUDE.md. Report what changed and stop.
→ If n: continue to Step 1 for full re-setup.

**D — project-features.json does NOT exist but partial setup is detected**
→ (e.g. Tests/ folder exists but no json)
→ Print detected state as suggested defaults:
```
Detected in project:
  - Tests/ folder: YES  → Testing default: yes
  - Ecs/ folder: NO     → ECS default: no
  - Addressables in manifest: NO → Addressables default: no

These will be used as defaults in Step 1. Override any during setup.
```
→ Proceed to Step 1 with these defaults pre-filled.

---

### Step 1 — Gather Info

Ask the developer ALL of these questions before doing anything else:

1. **Project name** (e.g. `SpaceTroopers`, `MyGame`) — used for assembly names
2. **Unity version** (e.g. `6000.0.x`)
3. **Scenes**: Default is Bootstrap + Menu + Game. Any additions?
4. **Does the project use ECS DOTS?** (yes/no) — adds `Games/Ecs/` folder, ECS asmdef, and ECS bridge files
5. **Does the project use Addressables?** (yes/no) — if no, `Resources.Load` restriction still applies but Addressables-specific rules, skills, and hooks are skipped
6. **Does the project use Testing / NSubstitute?** (yes/no) — if no, test folders, test asmdefs, test template files, and test-related hooks are all skipped
7. **Packages installed?**
   - VContainer (required) — installed?
   - UniTask (required) — installed?
   - New Input System (required) — installed?
   - **NSubstitute DLL** — only relevant if Testing=yes. Have you placed `NSubstitute.dll` in `Assets/Plugins/NSubstitute/`?
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

**If Testing=no:** Skip Gate B entirely. Do not generate test folders, test asmdefs, or test templates. Jump directly to Step 2.

**If Testing=yes and NSubstitute DLL is NOT confirmed present at `Assets/Plugins/NSubstitute/`:**
- Generate test `.asmdef` files WITHOUT `precompiledReferences` and WITHOUT `overrideReferences: true`.
- **Skip Step 5** (do not generate test template files).
- Note in checklist: "After placing NSubstitute.dll, re-run `/setup-project` or manually add `\"precompiledReferences\": [\"NSubstitute.dll\"]` and `\"overrideReferences\": true` to your test .asmdef files, then run Step 5 manually."

**If Testing=yes and NSubstitute DLL IS confirmed present:**
- Generate test `.asmdef` files with full NSubstitute references.
- Run Step 5 normally.

---

### Step 1c — Write project-features.json

After collecting all answers, write `.claude/project-features.json` to the project root using Bash:

Also ask: **"Enable Unity Knowledge Graph? (y/n, default: y)** — auto-indexes codebase for `/catch-up`, `/orchestrate`, `/context-prime`. Runs incrementally in background on every Write/Edit."**

```bash
cat > .claude/project-features.json << 'EOF'
{
  "addressables": <true|false>,
  "testing": <true|false>,
  "ecs": <true|false>,
  "graph": <true|false>
}
EOF
```

Replace `<true|false>` with the actual answers. This file is read by hooks and commands to skip irrelevant checks.

### Step 5.5 — Initial Graph Build (if graph=true)

If the user enabled the Knowledge Graph:

1. Print: "Running initial graph build…"
2. Run:
   ```bash
   bash .claude/graph/graph-builder.sh --full --skip-mcp
   ```
3. Print: "Initial graph complete. Run `/build-knowledge-graph --validate-with-codex` to cross-check accuracy."
4. Add to the final manual-setup checklist:
   ```
   Knowledge Graph setup:
     1. Add PostToolUse hook to .claude/settings.json:
        {
          "hooks": {
            "PostToolUse": [{ "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "bash .claude/hooks/graph-auto-update.sh" }] }]
          }
        }
     2. Install git post-commit hook: bash .claude/hooks/install-git-hooks.sh
     3. (optional) Run watch loop: bash .claude/graph/graph-watch.sh
   ```

---

### Step 5.6 — Hybrid Graph Activation (runs immediately after Step 5.5, only when graph=true)

Activate `hybrid_graph` automatically — no user prompt. Runs five sub-steps in sequence; any failure aborts the chain and leaves `hybrid_graph=false` in `project-features.json`.

**Re-run guard (check first):**
```bash
claude mcp list | grep -q "graph-mcp" && echo "ALREADY_REGISTERED"
```
If output is `ALREADY_REGISTERED` → print "hybrid_graph already active — skipping Step 5.6." and stop.

#### 5.6a — pip Probe

```bash
python3 -m pip install mcp --quiet --exists-action i 2>&1
```

- `--exists-action i` = skip silently if already installed
- On non-zero exit: print the failure message below, set `HYBRID_FAILED=true`, skip 5.6b–5.6e.

**Failure output:**
```
[hybrid_graph] pip install mcp failed.
Manual fix: run `pip install mcp`, then re-run /setup-project.
hybrid_graph left as false.
```

#### 5.6b — MCP Registration

```bash
claude mcp add --scope project graph-mcp \
  python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
```

- `--scope project` — registration scoped to this repository only
- `$(pwd)` — absolute path; prevents working-directory ambiguity when MCP daemon starts
- On non-zero exit: print the failure message below, skip 5.6c–5.6e.

**Failure output:**
```
[hybrid_graph] MCP registration failed.
Manual fix:
  claude mcp add --scope project graph-mcp python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
Then re-run /setup-project to write hybrid_graph=true.
```

#### 5.6c — Write hybrid_graph=true to project-features.json

```bash
tmp=$(mktemp)
jq '.hybrid_graph = true' .claude/project-features.json > "$tmp" && mv "$tmp" .claude/project-features.json
```

- Uses `jq` for correct JSON handling — `sed` on JSON is fragile
- Atomic write via temp file — partial writes cannot corrupt the file
- Only runs after 5.6a and 5.6b both succeeded

#### 5.6d — Update CLAUDE.md Feature Table

```bash
sed -i '' 's/| `hybrid_graph` | \*\*DISABLED\*\*/| `hybrid_graph` | **ENABLED**/' .claude/CLAUDE.md
```

- Non-critical: on failure, print a warning and continue — does not block activation
- The CLAUDE.md template has a fixed-format table row; this sed target is stable

#### 5.6e — Confirmation

Print:
```
✓ hybrid_graph activated
  • MCP server: graph-mcp (project-scoped)
  • Call-graph queries via MCP: callers, impact, path, god-nodes
  • Unity-semantic queries unchanged: summary, violations, scope-tree, etc.

⚠  Restart Claude Code to activate MCP in the current session.
   New sessions start the server automatically.
```

---

### Step 2 — Generate Folder Structure

> **NOTE:** Claude's file system tools cannot write `.unity` scene files (`block-scene-edit.sh` blocks this). However, if MCP is connected, scenes and prefab wiring are handled automatically in Step 5d via MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`). Only fall back to manual Editor steps when MCP is unavailable.

Always run Step 2 regardless of gate status. Create these folders (empty `.gitkeep` files where needed):

```
Assets/
├── _Scenes/                        ← create manually in Unity Editor
│   ├── Bootstrap.unity
│   ├── Menu.unity
│   └── Game.unity
├── _Framework/
│   ├── Events/                     ← FrameworkEventBus.asmdef (each subfolder = own asmdef)
│   ├── Logging/                    ← FrameworkLogging.asmdef
│   ├── SaveLoadSystems/            ← FrameworkSaveLoadSystems.asmdef
│   └── Editors/                    ← FrameworkEditor.asmdef (includePlatforms: ["Editor"])
├── Plugins/
│   └── NSubstitute/                ← place NSubstitute.dll here manually
└── _GameFolders/
    ├── Arts/
    ├── Prefabs/
    │   ├── Bootstrap/          ← AppScope.prefab, GameScope.prefab (LifetimeScope prefabs)
    │   ├── CoreObjects/        ← EventSystem.prefab, MainCamera.prefab
    │   ├── Enemies/
    │   ├── UI/
    │   ├── VFX/
    │   └── Environment/
    ├── Configs/
    ├── Input/                      ← .inputactions file goes here
    └── Scripts/
        ├── Games/                  ← [ProjectName]Games.asmdef
        │   ├── Abstracts/          ← interfaces and abstract base classes, organized by domain
        │   ├── Concretes/          ← ALL concrete classes (pure C# or MonoBehaviour), by domain
        │   │   └── Infrastructure/ ← AppScope, AppInstaller, ModuleInstaller
        │   └── Ecs/                ← only if ECS=yes
        │       ├── Authorings/
        │       ├── Components/
        │       └── Systems/
        ├── Editors/                ← [ProjectName]Editor.asmdef (Editor-only)
        └── Tests/                  ← only if Testing=yes
            ├── [ProjectName]EditModeTest/
            └── [ProjectName]PlayModeTest/
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

#### `_Framework/Editors/FrameworkEditor.asmdef`
```json
{
    "name": "FrameworkEditor",
    "rootNamespace": "Framework.Editor",
    "references": [
        "FrameworkEvents",
        "FrameworkLogging"
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
    "versionDefines": [],
    "noEngineReferences": false
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

#### `_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/[ProjectName]EditModeTest.asmdef`

**With NSubstitute (Gate B passed):**
```json
{
    "name": "[ProjectName]EditModeTest",
    "rootNamespace": "Game.EditModeTest",
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
    "name": "[ProjectName]EditModeTest",
    "rootNamespace": "Game.EditModeTest",
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

#### `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[ProjectName]PlayModeTest.asmdef`

**With NSubstitute (Gate B passed):**
```json
{
    "name": "[ProjectName]PlayModeTest",
    "rootNamespace": "Game.PlayModeTest",
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
    "name": "[ProjectName]PlayModeTest",
    "rootNamespace": "Game.PlayModeTest",
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

> `ModuleInstaller` uses `ScriptableObject` (requires `using UnityEngine`) so it lives in `Games/Concretes/Infrastructure/`, not `Games/Abstracts/`. The `check-pure-csharp.sh` hook blocks `using UnityEngine` in `Games/Abstracts/`.

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

#### `_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/SampleEditModeTests.cs`
```csharp
using Framework.Events;
using NSubstitute;
using NUnit.Framework;

namespace Game.EditModeTest
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

#### `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/SamplePlayModeTests.cs`
```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine.TestTools;

namespace Game.PlayModeTest
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

### Step 5b — Remove Disabled Feature Hooks from settings.json

Run this script exactly as-is — it reads `project-features.json` automatically and removes the correct hooks. No manual editing required.

```bash
python3 - << 'PYEOF'
import json

with open('.claude/project-features.json') as f:
    features = json.load(f)

with open('.claude/settings.json', 'r') as f:
    data = json.load(f)

# Hooks to remove per disabled feature
feature_hooks = {
    'testing': {
        '.claude/hooks/check-test-exists.sh',
        '.claude/hooks/check-test-scene-exists.sh',
    },
    'ecs': {
        '.claude/hooks/check-ecs-structural-changes.sh',
        '.claude/hooks/check-enum-byte-base.sh',
    },
    'addressables': set(),  # no addressables-specific hooks currently
}

to_remove = set()
for feature, hooks in feature_hooks.items():
    if not features.get(feature, True):
        to_remove |= hooks

if not to_remove:
    print("No hooks to remove — all features enabled.")
else:
    def filter_hooks(hook_list):
        result = []
        for item in hook_list:
            filtered = [h for h in item.get('hooks', []) if h.get('command') not in to_remove]
            if filtered:
                result.append({**item, 'hooks': filtered})
        return result

    hooks_section = data.get('hooks', {})
    for event in list(hooks_section.keys()):
        hooks_section[event] = filter_hooks(hooks_section[event])

    with open('.claude/settings.json', 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')

    print(f"Removed hooks: {sorted(to_remove)}")
PYEOF
```

---

### Step 5c — Add Project Features Header to CLAUDE.md

Prepend a `## Project Features` section to `.claude/CLAUDE.md` using Bash. This section tells Claude which rules, skills, and agents to skip for this project.

```bash
python3 - << 'PYEOF'
import json

with open('.claude/project-features.json') as f:
    features = json.load(f)

lines = ["## Project Features\n\n"]
lines.append("These features were configured during `/setup-project`. Skip rules, hooks, agents, and skills for disabled features.\n\n")
lines.append("| Feature | Status |\n")
lines.append("|---------|--------|\n")
lines.append(f"| Addressables | {'**enabled**' if features.get('addressables') else '~~disabled~~ — skip `addressables.md` rules and Addressables skills'} |\n")
lines.append(f"| Testing / NSubstitute | {'**enabled**' if features.get('testing') else '~~disabled~~ — skip `testing.md` rules, test agents, test commands'} |\n")
lines.append(f"| ECS DOTS | {'**enabled**' if features.get('ecs') else '~~disabled~~ — skip `ecs-dots.md` rules and ECS-related guidance'} |\n")
lines.append("\n---\n\n")

header = "".join(lines)

with open('.claude/CLAUDE.md', 'r') as f:
    existing = f.read()

# Only prepend if not already present
if "## Project Features" not in existing:
    with open('.claude/CLAUDE.md', 'w') as f:
        f.write(header + existing)
    print("Project Features section added to CLAUDE.md")
else:
    # Update existing section
    import re
    updated = re.sub(r'## Project Features\n.*?---\n\n', header, existing, flags=re.DOTALL)
    with open('.claude/CLAUDE.md', 'w') as f:
        f.write(updated)
    print("Project Features section updated in CLAUDE.md")
PYEOF
```

---

### Step 5d — MCP Scene & Wiring Setup

Run this step ONLY if MCP is connected (State 1 from mcp-preflight).

MCP can do what Claude's file tools cannot: create scenes, add GameObjects, attach and configure components, and wire prefab references — all through the Unity Editor directly.

#### 5d-1 — Create Scenes

```python
manage_scene(action="create", name="Bootstrap", template="empty", path="Assets/_Scenes/Bootstrap.unity")
manage_scene(action="create", name="Menu", template="empty", path="Assets/_Scenes/Menu.unity")
manage_scene(action="create", name="Game", template="3d_basic", path="Assets/_Scenes/Game.unity")
```

#### 5d-2 — Set Up Bootstrap Scene Hierarchy

Wait for compilation to finish after Step 4 scripts are generated, then:

```python
# Open Bootstrap scene
manage_scene(action="load", path="Assets/_Scenes/Bootstrap.unity")

# Create the 6 standard container GameObjects (scene-hierarchy rules)
manage_gameobject(action="create", name="[Setup]")
manage_gameobject(action="create", name="[Services]")
manage_gameobject(action="create", name="[UI]")
manage_gameobject(action="create", name="[Environment]")
manage_gameobject(action="create", name="[Characters]")
manage_gameobject(action="create", name="[VFX]")

# Create AppScope under [Setup]
manage_gameobject(action="create", name="AppScope", parent="[Setup]")

# Add AppScope component (generated in Step 4)
manage_gameobject(action="modify", target="AppScope", components_to_add=["Game.Concretes.Infrastructure.AppScope"])
```

#### 5d-3 — Create AppInstaller Asset and Wire It

```python
# Create AppInstaller ScriptableObject asset
manage_scriptable_object(
    action="create",
    path="Assets/_GameFolders/Configs",
    name="AppInstaller",
    type_name="Game.Concretes.Infrastructure.AppInstaller"
)

# Wire AppInstaller into AppScope._appInstaller field
manage_components(
    action="set_property",
    target="AppScope",
    component_type="Game.Concretes.Infrastructure.AppScope",
    property="_appInstaller",
    value="Assets/_GameFolders/Configs/AppInstaller.asset"
)

# Save AppScope as prefab — asset refs are stored on the prefab (NON-NEGOTIABLE)
manage_gameobject(
    action="save_as_prefab",
    target="AppScope",
    path="Assets/_GameFolders/Prefabs/Bootstrap/AppScope.prefab"
)
```

#### 5d-3b — Create CoreObjects Prefabs (EventSystem + MainCamera)

```python
# Create EventSystem under [Environment] and save as prefab
manage_gameobject(action="create", name="EventSystem", parent="[Environment]")
manage_components(action="add", target="EventSystem", component_type="UnityEngine.EventSystems.EventSystem")
manage_components(action="add", target="EventSystem", component_type="UnityEngine.EventSystems.StandaloneInputModule")
manage_gameobject(
    action="save_as_prefab",
    target="EventSystem",
    path="Assets/_GameFolders/Prefabs/CoreObjects/EventSystem.prefab"
)

# MainCamera is already in scene (Unity default) — reparent to [Environment] and save as prefab
manage_gameobject(action="modify", target="Main Camera", new_parent="[Environment]")
manage_gameobject(
    action="save_as_prefab",
    target="Main Camera",
    path="Assets/_GameFolders/Prefabs/CoreObjects/MainCamera.prefab"
)
```

#### 5d-4 — Configure Build Settings

```python
manage_build(action="scenes", scenes='[{"path": "Assets/_Scenes/Bootstrap.unity", "enabled": true}, {"path": "Assets/_Scenes/Menu.unity", "enabled": true}, {"path": "Assets/_Scenes/Game.unity", "enabled": true}]')
```

After this step: take a screenshot to verify the Bootstrap scene hierarchy looks correct.

```python
manage_camera(action="screenshot", capture_source="scene_view", include_image=true)
```

---

### Step 6 — Print Remaining Manual Checklist

After MCP setup (Step 5d), only these items require manual action:

```
## Manual Setup Required

### New Input System — Project Settings
After installing Input System package:
1. Edit → Project Settings → Player → Active Input Handling → Input System Package (New)
   (Unity will restart — this cannot be set via MCP)
2. Create Assets/_GameFolders/Input/[ProjectName]Controls.inputactions
3. Select the asset → enable "Generate C# Class" in Inspector → Apply

### NSubstitute (only if Testing=yes)
NSubstitute cannot be installed via Package Manager.
1. Download from https://www.nuget.org/packages/NSubstitute — click "Download package"
2. Rename .nupkg → .zip, extract, copy NSubstitute.dll from the lib/ folder
3. Place at: Assets/Plugins/NSubstitute/NSubstitute.dll
4. Re-run /setup-project to generate test templates with NSubstitute references.

### settings.json Hook Entries
Claude cannot edit settings.json (blocked by check-config-protection.sh).
Add these entries manually — see .claude/docs/setup-checklist.md for the exact JSON blocks:
- check-test-scene-exists.sh (PostToolUse, Write|Edit matcher)
- guard-reviewer-order.sh (PreToolUse, Agent matcher)
- track-codex-review.sh (PostToolUse, Agent matcher)
```

If MCP was NOT connected during Step 5d, also add these manual steps:

```
### Scenes (MCP unavailable — create manually)
In Unity Editor (File → New Scene → Save As):
- Assets/_Scenes/Bootstrap.unity (Build index 0)
- Assets/_Scenes/Menu.unity
- Assets/_Scenes/Game.unity

### Bootstrap Scene Setup (MCP unavailable)
1. Open Bootstrap.unity
2. Create 6 empty root GameObjects in this order: `[Setup]`, `[Services]`, `[UI]`, `[Environment]`, `[Characters]`, `[VFX]`
3. Under `[Setup]`: create empty GameObject named "AppScope", add AppScope component
4. Create ScriptableObject: right-click Assets/_GameFolders/Configs → Create → Game/Infrastructure/App Installer → name it AppInstaller
5. Drag AppInstaller asset onto AppScope._appInstaller field in Inspector
6. **Save AppScope as prefab**: drag AppScope from hierarchy into `Assets/_GameFolders/Prefabs/Bootstrap/` → select "Original Prefab"
7. Under `[Environment]`: create EventSystem (GameObject → UI → Event System) → drag to `Assets/_GameFolders/Prefabs/CoreObjects/EventSystem.prefab`
8. Reparent MainCamera under `[Environment]` → drag to `Assets/_GameFolders/Prefabs/CoreObjects/MainCamera.prefab`

### Build Settings (MCP unavailable)
File → Build Settings → Add Open Scenes — add all three scenes with Bootstrap at index 0.
```
