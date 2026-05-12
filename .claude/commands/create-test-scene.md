# /create-test-scene — Play Mode Test Scene Generator

Creates a complete Play Mode test scene for a given feature: test scene, TestBootstrap prefab wiring, TestScope, TestInstaller, and a PlayMode test stub.

## Usage

```
/create-test-scene PlayerMovement
/create-test-scene EnemyCombat "needs IEnemySpawner and IEventBus"
```

Argument: PascalCase feature name. Optional second argument: hint about which services/prefabs are needed.

---

## Step 1 — Parse Arguments

Extract from `$ARGUMENTS`:
- `FEATURE` — first word, PascalCase (e.g., `PlayerMovement`)
- `HINT` — remainder of the string (optional context)

If no feature name provided → stop:
```
Usage: /create-test-scene <FeatureName> [optional hint]
Example: /create-test-scene PlayerMovement
```

---

## Step 2 — Preflight

### 2a — MCP Check (run first, before anything else)

Read and apply `.claude/skills/core/mcp-preflight.md`.

- **State 1** (connected) → continue to 2b
- **State 2** (disconnected) → stop; offer to generate C# files only (TestScope, TestInstaller, test stub) — scene creation and MCP wiring steps are skipped, manual steps are listed instead
- **State 3** (not installed) → continue in code-only mode; skip Step 3 (scene builder) entirely, print manual scene creation steps after generating C# files

### 2b — Test Type Check

Read `.claude/skills/core/test-type-router.md` and apply the decision matrix to `[FEATURE]`.

- Extract class name or path hint from `$ARGUMENTS`.
- Run the router and emit the decision block.

**If decision is NOT `PlayMode-Scene`** → stop:
```
⚠ This target does not require a Play Mode scene test.
  Decision: [EditMode | PlayMode-ECS | NoTest]
  Reason:   [one sentence]

→ Use /generate-tests instead.
```

**If decision is `PlayMode-Scene`** → continue to 2c.

### 2c — Proje Kontrolleri

1. Does `_Scenes/TestScenes/` exist? If not, it will be created by the scene builder.
2. Does `_GameFolders/Scripts/Games/TestScopes/` exist? If not, note it for the agent.
3. Does `_Scenes/TestScenes/[Feature]Test.unity` already exist? If yes → stop:
   ```
   ⚠ Test scene already exists: _Scenes/TestScenes/[Feature]Test.unity
   To recreate it, delete the scene first.
   ```
4. Find the PlayTests assembly path for the project.
5. Find existing TestScope files to understand the project namespace.

---

## Step 3 — Generate C# Scripts (inline — no subagent)

> **Why inline:** MCP tools belong to the main Claude session. Spawning a subagent loses the MCP connection — so both C# writing and scene creation happen here directly.

### 3a — Read Project Context

1. Read `.claude/CLAUDE.md` — get project name and namespace
2. Find the project's PlayTests assembly: `find . -name "*PlayTests*.asmdef"`
3. Find existing TestScopes (if any): `find . -path "*/TestScopes/*.cs" | head -5`
4. If any TestScope found, read one to confirm namespace and pattern

### 3b — Write TestScope

File: `_GameFolders/Scripts/Games/TestScopes/[Feature]TestScope.cs`

```csharp
using VContainer;
using VContainer.Unity;

namespace [Namespace].Tests
{
    public sealed class [Feature]TestScope : LifetimeScope
    {
        #region Fields

        [UnityEngine.SerializeField] private [Feature]TestInstaller _installer;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            _installer.Install(builder);
        }

        #endregion
    }
}
```

### 3c — Write TestInstaller

File: `_GameFolders/Scripts/Games/TestScopes/[Feature]TestInstaller.cs`

```csharp
using UnityEngine;
using VContainer;

namespace [Namespace].Tests
{
    public sealed class [Feature]TestInstaller : MonoBehaviour
    {
        #region Fields

        // Add [SerializeField] config references here

        #endregion

        #region Public Methods

        public void Install(IContainerBuilder builder)
        {
            // Register services needed for this test scenario
        }

        #endregion
    }
}
```

### 3d — Write PlayMode Test Stub

File: `_GameFolders/Scripts/Tests/[Project]PlayTests/[Feature]Tests.cs`

```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using VContainer;

namespace [Namespace].Tests
{
    [TestFixture]
    public class [Feature]Tests
    {
        private const string ScenePath = "TestScenes/[Feature]Test";

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            yield return SceneManager.LoadSceneAsync(ScenePath, LoadSceneMode.Single);
            yield return null;
        }

        [UnityTest]
        public IEnumerator [Feature]_WhenCondition_ExpectedBehavior()
        {
            // Arrange
            // TODO: find components, resolve services from TestScope

            // Act
            yield return null;

            // Assert
            Assert.Fail("Not implemented — replace with real assertions");
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            yield return SceneManager.LoadSceneAsync("TestScenes/Empty");
        }
    }
}
```

---

## Step 4 — Create Scene via MCP (inline — main session)

> MCP calls are made directly by the main Claude session, not a subagent.

1. Check editor state: `unity_get_project_info` — ensure Unity is ready
2. Create the scene: `unity_create_scene` with path `_Scenes/TestScenes/[Feature]Test`
3. Create a `TestBootstrap` GameObject in the scene via MCP
4. Add the `[Feature]TestScope` component to TestBootstrap via MCP
5. Add the `[Feature]TestInstaller` component to TestBootstrap via MCP
6. Wire `_installer` field on TestScope to the TestInstaller component via MCP
7. Save the scene

If `_Scenes/TestScenes/Empty.unity` does not exist — create it as a minimal empty scene via MCP.

Check if `_GameFolders/Prefabs/TestBootstrap/TestBootstrap.prefab` exists.
- If not: note in the final report that TestBootstrap is a standalone GameObject (not yet a shared prefab).
- If yes: note in the final report that the scene uses a standalone GameObject (shared prefab not linked).

---

## Step 5 — Review

**Reviewer priority:** Try **unity-reviewer** first. If unavailable → **codex:rescue**. If also unavailable → review inline with Claude.

Spawn the reviewer with this prompt:

```
Review the following generated test infrastructure files for a Unity Play Mode test scene.

## Files to Review
- TestScope:  _GameFolders/Scripts/Games/TestScopes/[FEATURE]TestScope.cs
- Installer:  _GameFolders/Scripts/Games/TestScopes/[FEATURE]TestInstaller.cs
- Test stub:  _GameFolders/Scripts/Tests/[Project]PlayTests/[FEATURE]Tests.cs

## Review Checklist

1. **TestScope** — extends LifetimeScope (not AppScope), sealed, correct namespace, #region tags present
2. **TestInstaller** — MonoBehaviour (not ScriptableObject), sealed, Install() method correct signature
3. **Test stub** — [TestFixture] + [UnitySetUp] + [UnityTearDown] present, ScenePath constant matches feature name, namespace correct
4. **Naming** — all files follow [Feature]TestScope / [Feature]TestInstaller / [Feature]Tests convention
5. **No production code touched** — these are test-only files
6. **No AppScope dependency** — TestScope must be a root scope

## Output Format (REQUIRED)

VERDICT: APPROVED | NEEDS_FIX

ISSUES:
- [file:line] — [description] — [fix]
OR: ISSUES: none
```

### Fix Loop (NEEDS_FIX only)

**Fix scope is surgical — only the specific files and lines flagged. The scene and MCP work are NOT redone.**

- Spawn **unity-coder-lite** with the ISSUES list. It edits only the flagged files.
- Re-run the reviewer on the same files. Max **2 fix iterations**.
- After 2 iterations still failing → proceed to Step 6 with issues listed in the report (do not redo scene creation).

**What never restarts:** scene creation, TestBootstrap wiring, MCP operations — those are done once and kept.

---

## Step 6 — Post-generation Report

After review passes (or max iterations reached), print:

```
## ✓ Test Scene Ready: [FEATURE]Test

### Created
- Scene:     _Scenes/TestScenes/[FEATURE]Test.unity
- TestScope: _GameFolders/Scripts/Games/TestScopes/[FEATURE]TestScope.cs
- Installer: _GameFolders/Scripts/Games/TestScopes/[FEATURE]TestInstaller.cs
- Test stub: _GameFolders/Scripts/Tests/[Project]PlayTests/[FEATURE]Tests.cs

### Review: [APPROVED ✓ | ISSUES REMAIN ⚠]
[list any unresolved issues if applicable]

### You must do manually (Claude cannot do these)
1. Add _Scenes/TestScenes/[FEATURE]Test.unity to Build Settings
2. Add _Scenes/TestScenes/Empty.unity to Build Settings (if not already)
3. Open [FEATURE]Test scene in Unity Editor
4. Drag your feature prefabs into the scene
5. Wire any [SerializeField] config references in [FEATURE]TestInstaller
6. Fill in the [UnityTest] stub with real assertions

### Run the test
Window → General → Test Runner → PlayMode → run [FEATURE]Tests
```

$ARGUMENTS
