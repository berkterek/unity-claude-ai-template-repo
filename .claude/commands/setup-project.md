# Setup Project — New Unity Project Initializer

You set up a new Unity project using this template. You ask questions about the project, then generate all project-specific boilerplate that cannot live in the template itself.

## What This Command Does

The template provides rules, hooks, and commands that work for any Unity project. But every project needs its own:
- Assembly definition files (with correct project name)
- Base framework classes (IEventBus, EventBus, EventBusAccessor, IInstaller, AppModules, ConfigCatalog, SceneModules, AppScope, GameScope)
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
| Newtonsoft Json (`com.unity.nuget.newtonsoft-json`) | YES — `LocalSaveLoadDal` will not compile without it |

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
   python3 .claude/graph/graph-builder.py --full --skip-mcp
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
claude mcp list | grep -q "graph-mcp" && \
  jq -e '.hybrid_graph == true' .claude/project-features.json > /dev/null 2>&1 && \
  echo "ALREADY_REGISTERED"
```
If output is `ALREADY_REGISTERED` → print "hybrid_graph already active — skipping Step 5.6." and stop.

#### 5.6a — pip Probe

```bash
# Check importability first — handles pipx, homebrew, venv installs without triggering PEP 668
python3 -c "import mcp" 2>/dev/null || \
  python3 -m pip install mcp --quiet --break-system-packages 2>&1
```

- `python3 -c "import mcp"` — succeeds silently if mcp is already installed by any method (pipx, homebrew, venv). Skips pip entirely.
- `--break-system-packages` — required on macOS Homebrew Python (PEP 668); safe for a single targeted package install.
- On non-zero exit from both commands: print the failure message below, skip 5.6b–5.6e.

**Failure output:**
```
[hybrid_graph] mcp package not available and install failed.
Manual fix: pip install mcp OR pipx install mcp, then re-run /setup-project.
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
│   ├── Installers/                 ← IInstaller.cs (pure C# interface — no asmdef, shares FrameworkEvents or root)
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
        │   │   └── Infrastructure/ ← AppScope, GameScope, AppModules, ConfigCatalog, SceneModules
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
    "references": [
        "VContainer",
        "FrameworkLogging"
    ],
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
    "noEngineReferences": false
}
```

#### `_Framework/SaveLoadSystems/FrameworkSaveLoadSystems.asmdef`
```json
{
    "name": "FrameworkSaveLoadSystems",
    "rootNamespace": "Framework.SaveLoadSystems",
    "references": [
        "FrameworkLogging"
    ],
    "includePlatforms": [],
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
using Framework.Logging;
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
                if (list[i] is not Action<T> handler) continue;

                // Per-subscriber isolation. Without it one throwing subscriber aborts the
                // whole dispatch: every remaining subscriber silently misses the event, and
                // the exception surfaces at the PUBLISHER — a class with no connection to
                // the bug. Both failures point away from the cause.
                //
                // This is also what makes DLog.Error's unconditional, unfiltered behaviour
                // load-bearing rather than a preference: nearly all game logic runs inside
                // subscribers, so this catch is where a whole class of defect is reported.
                // See _Framework/Logging/ARCHITECTURE.md -> ## Gotchas.
                //
                // catch (Exception) is correct HERE and nowhere else in this codebase: the
                // bus cannot know what a subscriber may throw, and its contract is that one
                // subscriber's failure does not become another's. It logs and continues; it
                // never swallows silently.
                try
                {
                    handler(eventData);
                }
                catch (Exception exception)
                {
                    DLog.Error(LogTag.EventBus,
                        $"Subscriber threw while handling {type.Name}; remaining subscribers still run.",
                        exception);
                }
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

#### `_Framework/Logging/LogTag.cs`
```csharp
namespace Framework.Logging
{
    public enum LogTag
    {
        General,
        EventBus,
        SaveLoad
    }
}
```

> Add one enum member per domain that logs. `DLog` filters on this tag, so a domain with no member cannot be logged.

#### `_Framework/Logging/DLog.cs`
```csharp
using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace Framework.Logging
{
    public static class DLog
    {
        #region Private Fields

        // Every declared tag starts ENABLED, derived from the enum itself rather than
        // listed here. A tag that is declared but missing from this set is silent with no
        // error and no warning — it reads as "logging is broken", not "this tag is off",
        // and it is the single most likely way to lose a log you were sure you wrote.
        //
        // A literal list was tried first and was wrong: it fixed today's three members
        // while leaving the trap fully armed for the fourth, so every new domain paid the
        // same debugging tax. Deriving from the enum removes the second place to edit, and
        // therefore removes the class of mistake rather than one instance of it.
        //
        // The objection to reflecting — "it enables a tag the author never meant to ship
        // as live" — does not survive contact: Log/Warning are [Conditional] on
        // UNITY_EDITOR/DEVELOPMENT_BUILD and are stripped from release at the call site
        // regardless, so nothing here ships. Declaring a tag you do not want is not a real
        // case; muting a noisy one during a session is, and DLog.Disable(tag) does that.
        //
        // Runs once at static init. Do not "optimise" it back into a literal list.
        private static readonly HashSet<LogTag> _enabledTags =
            new((LogTag[])Enum.GetValues(typeof(LogTag)));

        #endregion

        #region Public Methods

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Log(LogTag tag, string message)
        {
            if (!_enabledTags.Contains(tag))
            {
                return;
            }

            UnityEngine.Debug.Log($"[{tag}] {message}");
        }

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Warning(LogTag tag, string message)
        {
            if (!_enabledTags.Contains(tag))
            {
                return;
            }

            UnityEngine.Debug.LogWarning($"[{tag}] {message}");
        }

        // The two Error overloads below are deliberately NOT [Conditional] and NOT filtered
        // by _enabledTags. Log/Warning are diagnostics and may be silenced per tag; an error
        // is a defect report and must never be silenced.
        //
        // Do not "tidy up" by restoring the gate or the attributes here. The incident that
        // forced this, and the reasoning, are in _Framework/Logging/ARCHITECTURE.md ->
        // ## Gotchas — a comment is not where a load-bearing decision survives a refactor.

        public static void Error(LogTag tag, string message)
        {
            UnityEngine.Debug.LogError($"[{tag}] {message}");
        }

        /// <summary>Reports a caught exception with its full stack trace preserved.</summary>
        /// <remarks>
        /// Postcondition: writes a context line, then the exception itself via
        /// Debug.LogException so Unity emits a clickable stack trace.
        /// Side effect: never rethrows — the caller decides whether to continue.
        /// </remarks>
        public static void Error(LogTag tag, string message, Exception exception)
        {
            UnityEngine.Debug.LogError($"[{tag}] {message}");

            if (exception != null)
            {
                // exception.Message alone loses file and line; the exception object does not.
                UnityEngine.Debug.LogException(exception);
            }
        }

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Enable(LogTag tag)
        {
            _enabledTags.Add(tag);
        }

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Disable(LogTag tag)
        {
            _enabledTags.Remove(tag);
        }

        #endregion
    }
}
```

> **Runtime game code logs through `DLog`, never `UnityEngine.Debug` — see `rules/logging.md`.**
> The two `Error` overloads are deliberately not `[Conditional]` and not tag-filtered; the comment in the
> file says why and is load-bearing — do not "tidy" it away. One gap remains: `_enabledTags` starts with
> `General` only, so a newly added tag is silent for `Log`/`Warning` until something enables it
> (`docs/PLAN_framework_package_fixes.md` item 4).

#### `_Framework/SaveLoadSystems/ISaveLoadService.cs`
```csharp
namespace Framework.SaveLoadSystems
{
    public interface ISaveLoadService
    {
        void Save<T>(string key, T data);
        T Load<T>(string key);
        bool HasKey(string key);
        void Delete(string key);
    }
}
```

#### `_Framework/SaveLoadSystems/ISaveLoadDal.cs`
```csharp
namespace Framework.SaveLoadSystems
{
    public interface ISaveLoadDal
    {
        void SaveData(string key, object value);
        T LoadData<T>(string key);
        bool HasKey(string key);
        void DeleteData(string key);
    }
}
```

> `SaveData` takes `object`, so a persisted `struct` is boxed on every save. This is the first reason
> `rules/save-load.md` Card 2 requires a `[Serializable]` class.

#### `_Framework/SaveLoadSystems/LocalSaveLoadDal.cs`
```csharp
using System.IO;
using Framework.Logging;
using Newtonsoft.Json;
using UnityEngine;

namespace Framework.SaveLoadSystems
{
    public sealed class LocalSaveLoadDal : ISaveLoadDal
    {
        #region Private Methods

        private static string GetFilePath(string key)
        {
            return Path.Combine(Application.persistentDataPath, key + ".json");
        }

        #endregion

        #region ISaveLoadDal

        // Atomic: write a sibling temp file, then swap it in. A bare File.WriteAllText
        // truncates the live save BEFORE writing it, so a process killed mid-write leaves a
        // 0-byte file and the previous save is already gone. Mobile OSes kill a backgrounded
        // process without warning, so that is routine rather than exotic.
        // Rule: rules/save-load.md Card 7.
        public void SaveData(string key, object value)
        {
            string json = JsonConvert.SerializeObject(value);
            string path = GetFilePath(key);
            string temp = path + ".tmp";

            File.WriteAllText(temp, json);

            if (File.Exists(path)) File.Replace(temp, path, null);
            else                   File.Move(temp, path);
        }

        public T LoadData<T>(string key)
        {
            string path = GetFilePath(key);
            if (!File.Exists(path)) return default;

            string json = File.ReadAllText(path);
            if (string.IsNullOrEmpty(json)) return default;

            try
            {
                return JsonConvert.DeserializeObject<T>(json);
            }
            catch (JsonException exception)
            {
                // Return default so the caller falls into its HasKey/config-default branch —
                // the same path a first-run player takes. Throwing here escapes through
                // LifetimeScope.Configure() and the game does not open at all.
                // Catch JsonException specifically: an IOException (locked file, permissions)
                // is a different bug with a different fix and must not be swallowed.
                // Rule: rules/save-load.md Card 8.
                DLog.Error(LogTag.SaveLoad, $"Corrupt save for key={key}, falling back to default.", exception);
                return default;
            }
        }

        public bool HasKey(string key)
        {
            return File.Exists(GetFilePath(key));
        }

        public void DeleteData(string key)
        {
            string path = GetFilePath(key);
            if (File.Exists(path)) File.Delete(path);
        }

        #endregion
    }
}
```

> Requires `com.unity.nuget.newtonsoft-json` in `Packages/manifest.json`.
>
> This is the default backend, not the only allowed one. A `PlayerPrefsSaveLoadDal` sitting beside it is a
> legitimate `ISaveLoadDal` — required on WebGL, where `persistentDataPath` writes land in IndexedDB and are
> not flushed until an explicit sync. Swapping it is one line in `SaveLoadModule.Install`; no service and no
> consumer changes. See `rules/save-load.md` Card 1.
>
> Cards 7 and 8 are both satisfied by the body above as of 2026-09-02 — the temp-file swap and the
> `JsonException` fallback, each with its reasoning in a comment. Card 8 is backend-independent and a
> hand-written `ISaveLoadDal` must carry it too; Card 7 is not — `PlayerPrefs` has no `File.Replace`
> equivalent, so a backend that cannot offer the atomic swap says so in its own class.

#### `_Framework/SaveLoadSystems/SaveLoadService.cs`
```csharp
using Framework.Logging;

namespace Framework.SaveLoadSystems
{
    public sealed class SaveLoadService : ISaveLoadService
    {
        #region Fields

        private readonly ISaveLoadDal _dal;

        #endregion

        #region Constructor

        public SaveLoadService(ISaveLoadDal dal)
        {
            _dal = dal;
        }

        #endregion

        #region ISaveLoadService

        public void Save<T>(string key, T data)
        {
            DLog.Log(LogTag.SaveLoad, $"Save key={key}");
            _dal.SaveData(key, data);
        }

        public T Load<T>(string key)
        {
            DLog.Log(LogTag.SaveLoad, $"Load key={key}");
            return _dal.LoadData<T>(key);
        }

        public bool HasKey(string key)
        {
            return _dal.HasKey(key);
        }

        public void Delete(string key)
        {
            _dal.DeleteData(key);
        }

        #endregion
    }
}
```

> Tier 3, pure C#. Every consumer injects `ISaveLoadService` and never names this type, so swapping the
> backend is a one-line change in `SaveLoadModule.Install`.

#### `_Framework/Installers/IInstaller.cs`
```csharp
using VContainer;

namespace Framework.Installers
{
    /// <summary>
    /// Pure C# installer contract. Modules do not need to implement this —
    /// it exists for pure C# installer abstractions only.
    /// </summary>
    public interface IInstaller
    {
        void Install(IContainerBuilder builder);
    }
}
```

### ARCHITECTURE.md — one per `_Framework/` assembly

Every `_Framework/` subfolder that owns an `.asmdef` gets one. Same contract as
`Concretes/<Domain>/`: four headings in this exact order, 40-line cap, English, and **no
class-name-like symbols** — describe the shape, never the names, so a rename cannot rot the
doc. `Installers/` owns no `.asmdef`, so it gets none. There is no doc at the `_Framework/`
root; `check-architecture-doc.sh` blocks one.

These are generated with the code rather than left for later, because "later" is what
produced the defect they exist to prevent: the reason `Error` is not stripped lived only in
a source comment, and the project that inherited it carried the bug that comment describes
for months.

#### `_Framework/Events/ARCHITECTURE.md`
```markdown
# Events

## Purpose
Carries one-way notifications between modules that must not reference each other.

## Boundary
Never holds state, never orders its subscribers, and never reaches into a scene. A
notification that stays inside one prefab is not its job — that is a plain C# event on the
class that owns it.

## How to extend
Declare the payload as a readonly struct in the publishing domain's own folder, publish from
a service or handler, subscribe in the acquire step of the subscriber's lifecycle and
release in the teardown step. A shell that forwards lifecycle calls never subscribes itself.

## Gotchas
Dispatch isolates each subscriber: one that throws is logged and the rest still run. This is
the only place in the project permitted to catch every exception type, because the bus
cannot know what a subscriber may throw and one subscriber's failure must not become
another's. Without it a single bad subscriber silently starves every later one and the
error surfaces at the publisher, which has nothing to do with the cause. It is also why the
error log path is neither stripped nor filtered — see the logging assembly's own doc.

Exactly one static accessor is approved here, and it exists only because ECS systems cannot
be constructor-injected; adding a second is a design decision, not a convenience. A
subscriber that forgets its teardown keeps receiving callbacks after disposal, and the leak
surfaces as a null reference far from its cause.
```

#### `_Framework/Logging/ARCHITECTURE.md`
```markdown
# Logging

## Purpose
Gives runtime game code a log path that can be stripped from release builds and filtered per
domain.

## Boundary
Editor tooling and tests do not log through here — their output must not be silenceable by
runtime state. This assembly formats and forwards; it never decides what is worth logging.

## How to extend
A new domain adds one tag to the enum. That is the whole job — the enabled set is derived
from the enum, deliberately, so there is no second place to forget. An earlier version kept
a hand-written list beside it; a tag missing from that list compiled, ran, matched nothing
and returned, with no error and no warning, reading as broken logging rather than a
disabled tag. Do not reintroduce the list.

## Gotchas
The error path is deliberately neither compiled out nor tag-filtered, while the diagnostic
paths are both. An error is a defect report, not a diagnostic: the case that forced this was
subscriber exceptions reported under a tag nobody had enabled, so they were invisible in the
Editor and stripped from release at the same time, and all game logic runs inside those
subscribers. Do not "tidy" the attributes or the filter back on. Pass a caught exception as
the object, not as its message text — the message alone drops the file and line.
```

#### `_Framework/SaveLoadSystems/ARCHITECTURE.md`
```markdown
# SaveLoadSystems

## Purpose
Persists and restores typed data behind one contract, so callers never learn where the bytes
go.

## Boundary
This is the only place in the project that touches the filesystem, the platform preference
store, or a JSON serializer. Game code that reaches for any of those directly is bypassing
the boundary, and a hook blocks it. Deciding what a missing value should default to is the
calling domain's job, never this one's — only that domain knows its valid range.

## How to extend
A new backend is a new implementation of the access-layer interface plus one changed
registration line. The service above it and every caller stay untouched; if adding a backend
forces a change to either, the boundary is in the wrong place. Two backends that are both
live for different data categories are two independent pairs, not one keyed factory.

## Gotchas
Writes replace a temp file rather than truncating the live one, because a process killed
mid-write otherwise leaves an empty file and the previous save is already gone — routine on
mobile. Reads catch only the deserialization failure and fall back to the default; catching
everything would swallow a locked file or a permissions error, which are different bugs with
different fixes. Not every backend can offer the atomic swap, and one that cannot must say
so in its own class.
```

#### `_Framework/Editors/ARCHITECTURE.md`
```markdown
# Editors

## Purpose
Holds framework tooling that exists only inside the Unity Editor.

## Boundary
Never referenced from a runtime assembly, in either direction — this assembly is restricted
to the Editor platform, so a runtime reference to it does not fail at review, it fails at
build time, on the build machine, long after the change was made.

## How to extend
Add the tool here and keep it self-contained. Editor code that needs to read runtime types
references the runtime assembly, never the reverse. Runtime code that needs an Editor-only
branch guards it with the Editor compilation symbol in place, instead of moving the file.

## Gotchas
The platform restriction lives in this folder's assembly definition, not in any file, so it
cannot be granted or waived per file. Moving one script out of this folder silently drops it
into a shipping build, with no error anywhere until something Editor-only is called at
runtime.
```

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/EventBusModule.cs`
```csharp
using Framework.Events;
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class EventBusModule
    {
        /// <summary>
        /// Always called FIRST in AppModules.Install() — structural guarantee.
        /// Other modules may subscribe to events during Initialize(); EventBus must exist first.
        /// </summary>
        public static void Install(IContainerBuilder builder)
        {
            builder.Register<EventBus>(Lifetime.Singleton).AsImplementedInterfaces();
        }
    }
}
```

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs`
```csharp
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class AppModules
    {
        public static void Install(IContainerBuilder builder, ConfigCatalog configs)
        {
            EventBusModule.Install(builder); // FIRST — structural guarantee
            SaveLoadModule.Install(builder); // SECOND — many modules read persisted state in Initialize()

            // Add new modules here — one line per module:
            // AudioModule.Install(builder, configs.Audio);
            // PlayerModule.Install(builder, configs.Player);
        }
    }
}
```

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/SaveLoadModule.cs`
```csharp
using Framework.SaveLoadSystems;
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class SaveLoadModule
    {
        public static void Install(IContainerBuilder builder)
        {
            builder.Register<LocalSaveLoadDal>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<SaveLoadService>(Lifetime.Singleton).AsImplementedInterfaces();
        }
    }
}
```

> Swapping to a cloud backend later is one line here — register a different `ISaveLoadDal`. No service changes.
> This is `rules/architecture.md` Card 2.1 (Swappable Backend) applied to persistence.

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/Helpers/SaveKeyHelper.cs`
```csharp
namespace Game.Concretes.Infrastructure.Helpers
{
    public static class SaveKeyHelper
    {
        // One const per domain that persists. Never inline a key string at a call site.
        // public const string SCORE    = "score";
        // public const string SETTINGS = "settings";
    }
}
```

> `Helpers/` sits **under** the `Infrastructure/` domain, never as a first-level folder under `Concretes/`
> (`rules/architecture.md` → Domain Folder Convention). One key per domain, never one shared root object —
> `rules/save-load.md` Cards 4 and 5.

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/ConfigCatalog.cs`
```csharp
using System.Collections.Generic;
using UnityEngine;

namespace Game.Concretes.Infrastructure
{
    [CreateAssetMenu(menuName = "Game/Config Catalog", fileName = "ConfigCatalog")]
    public sealed class ConfigCatalog : ScriptableObject
    {
        // Add [SerializeField] config fields here as modules are added:
        // [SerializeField] private AudioConfiguration _audio;
        // public AudioConfiguration Audio => _audio;

        public bool Validate(out List<string> missing)
        {
            missing = new List<string>();
            // Add null checks here as config fields are added:
            // if (_audio == null) missing.Add(nameof(_audio));
            return missing.Count == 0;
        }
    }
}
```

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/SceneModules.cs`
```csharp
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class SceneModules
    {
        public static void InstallGame(IContainerBuilder builder)
        {
            // Leave empty until a scene-local pure C# service is needed.
            // Scene-lifetime services go here — they resolve AppScope services via parent scope.
            // Example: LevelTimerModule.Install(builder);
        }

        public static void InstallMenu(IContainerBuilder builder)
        {
            // Leave empty until a menu-scene service is needed.
        }
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

        [SerializeField] private ConfigCatalog _configCatalog;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            if (_configCatalog == null)
            {
                Debug.LogError("[AppScope] ConfigCatalog reference is missing.");
                return;
            }

            if (!_configCatalog.Validate(out var missing))
            {
                Debug.LogError($"[AppScope] ConfigCatalog missing fields: {string.Join(", ", missing)} — installation stopped.");
                return;
            }

            AppModules.Install(builder, _configCatalog);

            builder.RegisterBuildCallback(container =>
            {
                EventBusAccessor.Initialize(container.Resolve<IEventBus>());
            });
        }

        #endregion
    }
}
```

> `AppScope.cs` **never changes** to add a new module. Add one line to `AppModules.Install()` instead.

#### `_GameFolders/Scripts/Games/Concretes/Infrastructure/GameScope.cs`
```csharp
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class GameScope : LifetimeScope
    {
        // Add [SerializeField] fields for scene MonoBehaviours that need injection:
        // [SerializeField] private PlayerController _playerController;

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            // Register scene MonoBehaviours with builder.RegisterComponent(...):
            // if (_playerController == null) { Debug.LogError("[GameScope] PlayerController is missing."); return; }
            // builder.RegisterComponent(_playerController);

            SceneModules.InstallGame(builder);
        }

        #endregion
    }
}
```

> `GameScope` only calls `builder.RegisterComponent(...)` for scene MonoBehaviours and delegates pure C# services to `SceneModules`. Inline `builder.Register<T>()` in `GameScope` is forbidden.

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

#### 5d-3 — Create ConfigCatalog Asset and Wire It

```python
# Create ConfigCatalog ScriptableObject asset
manage_scriptable_object(
    action="create",
    path="Assets/_GameFolders/Configs",
    name="ConfigCatalog",
    type_name="Game.Concretes.Infrastructure.ConfigCatalog"
)

# Wire ConfigCatalog into AppScope._configCatalog field
manage_components(
    action="set_property",
    target="AppScope",
    component_type="Game.Concretes.Infrastructure.AppScope",
    property="_configCatalog",
    value="Assets/_GameFolders/Configs/ConfigCatalog.asset"
)

# Save AppScope as prefab — asset refs are stored on the prefab (NON-NEGOTIABLE)
manage_gameobject(
    action="save_as_prefab",
    target="AppScope",
    path="Assets/_GameFolders/Prefabs/Bootstrap/AppScope.prefab"
)

# Create GameScope under [Setup] and save as prefab (fields populated per-scene at runtime)
manage_gameobject(action="create", name="GameScope", parent="[Setup]")
manage_gameobject(action="modify", target="GameScope", components_to_add=["Game.Concretes.Infrastructure.GameScope"])
manage_gameobject(
    action="save_as_prefab",
    target="GameScope",
    path="Assets/_GameFolders/Prefabs/Bootstrap/GameScope.prefab"
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
4. Create ScriptableObject: right-click Assets/_GameFolders/Configs → Create → Game/Config Catalog → name it ConfigCatalog
5. Drag ConfigCatalog asset onto AppScope._configCatalog field in Inspector
6. **Save AppScope as prefab**: drag AppScope from hierarchy into `Assets/_GameFolders/Prefabs/Bootstrap/` → select "Original Prefab"
7. Under `[Setup]`: create empty GameObject named "GameScope", add GameScope component → drag to `Assets/_GameFolders/Prefabs/Bootstrap/GameScope.prefab` (leave SerializeField fields empty — filled per-scene)
8. Under `[Environment]`: create EventSystem (GameObject → UI → Event System) → drag to `Assets/_GameFolders/Prefabs/CoreObjects/EventSystem.prefab`
9. Reparent MainCamera under `[Environment]` → drag to `Assets/_GameFolders/Prefabs/CoreObjects/MainCamera.prefab`

### Build Settings (MCP unavailable)
File → Build Settings → Add Open Scenes — add all three scenes with Bootstrap at index 0.
```
