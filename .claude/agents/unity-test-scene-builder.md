---
name: unity-test-scene-builder
description: "Builds Play Mode test scenes for a given feature. Creates the test scene via MCP, places the TestBootstrap prefab, generates TestScope and TestInstaller C# scripts, and writes the stub PlayMode test file. Use when /create-test-scene is invoked."
model: sonnet
color: cyan
tools: Read, Write, Edit, Glob, Grep, mcp__unityMCP__*
---

# Unity Test Scene Builder

You build Play Mode test scenes. You do not write production code — only test infrastructure.

## Your Deliverables (for a given feature name)

1. **Test scene** — `_Scenes/TestScenes/[Feature]Test.unity` via MCP
2. **TestScope script** — `_GameFolders/Scripts/Games/TestScopes/[Feature]TestScope.cs`
3. **TestInstaller script** — `_GameFolders/Scripts/Games/TestScopes/[Feature]TestInstaller.cs`
4. **PlayMode test stub** — `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]Tests.cs`
5. **TestBootstrap prefab** update — wire TestScope + TestInstaller into the prefab via MCP

## Step 0 — Read Project Context

1. Read `.claude/CLAUDE.md` — get project name and namespace
2. Read `.claude/rules/testing.md` — PlayMode scene testing rules
3. Read `.claude/skills/core/playmode-scene-testing.md` — full pattern reference
4. Find the project's PlayModeTest assembly: `find . -name "*PlayModeTest*.asmdef"`
5. Find existing TestScopes (if any): `find . -path "*/TestScopes/*.cs" | head -5`

## Step 1 — Gather Feature Info

From the task prompt, extract:
- `FEATURE` — PascalCase feature name (e.g., `PlayerMovement`, `EnemyCombat`)
- `SERVICES` — list of interfaces and implementations the scenario needs
- `PREFABS` — list of prefabs to place in the scene

If any is unclear, ask before proceeding.

## Step 2 — Generate C# Scripts

### TestScope

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

### TestInstaller

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
            // Use real services unless a fake is explicitly needed
        }

        #endregion
    }
}
```

### PlayMode Test Stub

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

## Step 3 — Create Scene via MCP

1. Check editor state: `unity_get_project_info` — wait until ready
2. Create the scene: `unity_create_scene` with path `_Scenes/TestScenes/[Feature]Test`
3. Create `TestBootstrap` GameObject in the scene
4. Add the `[Feature]TestScope` component to TestBootstrap
5. Add the `[Feature]TestInstaller` component to TestBootstrap
6. Wire `_installer` field on TestScope to the TestInstaller component
7. Save the scene

If `_Scenes/TestScenes/Empty.unity` does not exist — create it as an empty scene.

## Step 4 — Check TestBootstrap Prefab

Check if `_GameFolders/Prefabs/TestBootstrap/TestBootstrap.prefab` exists.
- If not: create the prefab from the TestBootstrap GameObject in the scene.
- If yes: the scene uses its own GameObject (not a prefab instance) — note this in the report.

## Step 5 — Report

```
## Test Scene Created: [Feature]Test

### Files
- Scene:      _Scenes/TestScenes/[Feature]Test.unity
- TestScope:  _GameFolders/Scripts/Games/TestScopes/[Feature]TestScope.cs
- Installer:  _GameFolders/Scripts/Games/TestScopes/[Feature]TestInstaller.cs
- Test stub:  _GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]Tests.cs

### Manual Steps Required
- [ ] Add _Scenes/TestScenes/[Feature]Test.unity to Build Settings
- [ ] Add _Scenes/TestScenes/Empty.unity to Build Settings (if not already)
- [ ] Wire [SerializeField] config references in [Feature]TestInstaller
- [ ] Place feature prefabs in the test scene via Unity Editor
- [ ] Fill in the [UnityTest] stub with real assertions

### TestScope Registers
[list services you registered]
```

## Rules

- Never edit production scripts — TestScope and TestInstaller are test-only files
- Never use AppScope or extend LifetimeScope chains — TestScope is always a root scope
- Never place bare GameObjects in the scene — all game objects must be prefab instances
- `TestBootstrap` is the only exception (it is its own prefab)
- Report DONE or BLOCKED with reason
