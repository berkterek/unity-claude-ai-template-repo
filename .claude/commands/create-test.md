# /create-test — Unified Test Generator

Creates the right test for a given feature — automatically determines whether EditMode, PlayMode-ECS, or PlayMode-Scene test is appropriate, then generates the full test infrastructure.

## Usage

```
/create-test PlayerMovement
/create-test EnemyCombat "needs IEnemySpawner and IEventBus"
/create-test ScoreSystem
```

Argument: PascalCase feature or class name. Optional second argument: hint about dependencies or context.

---

## Step 1 — Parse Arguments

Extract from `$ARGUMENTS`:
- `FEATURE` — first word, PascalCase (e.g., `PlayerMovement`)
- `HINT` — remainder of the string (optional context)

If no feature name provided → stop:
```
Usage: /create-test <FeatureName> [optional hint]
Example: /create-test PlayerMovement
Example: /create-test EnemyCombat "needs IEnemySpawner and IEventBus"
```

---

## Step 2 — Preflight

### 2a — Feature Gate

Check `.claude/project-features.json` if it exists:

```bash
[ -f ".claude/project-features.json" ] && cat .claude/project-features.json || echo "{}"
```

If `testing` is `false` → stop:
```
⚠ Testing is disabled for this project (project-features.json: testing=false).
  Run /setup-project and enable Testing to use this command.
```

### 2b — Read Project Context

```bash
find . -name "*PlayModeTest*.asmdef" | head -3
find . -name "*EditModeTest*.asmdef" | head -3
find . -name "*.asmdef" -path "*/Tests/*" | head -5
```

Read one existing test file (if any) to confirm namespace and pattern in use.

### 2c — Test Type Router

Read `.claude/skills/core/test-type-router.md` and apply the decision matrix to `[FEATURE]` + `[HINT]`.

Emit the decision block:
```
Test type decision: [EditMode | PlayMode-ECS | PlayMode-Scene | NoTest]
Reason: [one sentence]
```

Route:
- `EditMode`       → Step 3-A
- `PlayMode-ECS`   → Step 3-B
- `PlayMode-Scene` → Step 3-C (MCP check first — see below)
- `NoTest`         → stop, explain why

**PlayMode-Scene only — MCP check before Step 3-C:**
Read and apply `.claude/skills/core/mcp-preflight.md`.
- State 1 (connected) → continue to 3-C normally
- State 2 (disconnected) → offer code-only mode: write C# files (Steps 3-C through 3-C-d), skip MCP scene creation (Step 4), print manual scene steps in report
- State 3 (not installed) → code-only mode; same as disconnected

### 2d — Duplicate Check

For EditMode:
- Does `_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/[Feature]Tests.cs` already exist? If yes → stop with warning.

For PlayMode-ECS:
- Does `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]SystemTests.cs` already exist? If yes → stop with warning.

For PlayMode-Scene:
- Does `Assets/_Scenes/TestScenes/[Feature]Test.unity` already exist? If yes → stop with warning.

---

## Step 3-A — EditMode Test

**When to use:** Pure C# logic, service behavior, interface contracts, event bus pub/sub. No Unity lifecycle, no MonoBehaviour, no scene loading.

### A1 — Find the Class Under Test

Search for the source class:
```bash
find . -name "[Feature].cs" -not -path "*/Tests/*" | head -5
find . -name "[Feature]Service.cs" -not -path "*/Tests/*" | head -5
```

Read the found file to understand: constructor dependencies, public methods to test, events published/subscribed.

### A2 — Write EditMode Test

File: `_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/[Feature]Tests.cs`

```csharp
using Framework.Events;
using NSubstitute;
using NUnit.Framework;
using [Namespace].Abstracts.[Module];   // adjust to actual interface location

namespace [Namespace].EditModeTest
{
    public class [Feature]Tests
    {
        // Arrange shared dependencies here if multiple tests use them
        // private IEventBus _eventBus;
        // private [Feature] _sut;

        [Test]
        public void [Method]_When[Condition]_[ExpectedBehavior]()
        {
            // Arrange
            var eventBus = Substitute.For<IEventBus>();
            // var sut = new [Feature](eventBus);

            // Act
            // sut.[Method](...);

            // Assert
            // eventBus.Received(1).Publish(Arg.Any<[SomeEvent]>());
            Assert.Fail("Not implemented — replace with real assertions");
        }
    }
}
```

Generate one stub test method per public method found on the class. Name each: `MethodName_WhenCondition_ExpectedBehavior`.

### A3 → Review + Commit (Step 5 and Step 6 below)

---

## Step 3-B — PlayMode ECS Test

**When to use:** ECS System behavior — entity state changes, component transitions, job effects. Uses an isolated `World`, no scene loading.

### B1 — Find the System Under Test

```bash
find . -name "[Feature]System.cs" -not -path "*/Tests/*" | head -5
```

Read the system file to understand: query components, what it reads/writes, expected entity state transitions.

### B2 — Write PlayMode ECS Test

File: `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]SystemTests.cs`

```csharp
using NUnit.Framework;
using Unity.Entities;
using Unity.Mathematics;
using Unity.Transforms;
using UnityEngine.TestTools;
using System.Collections;

namespace [Namespace].PlayModeTest
{
    public class [Feature]SystemTests
    {
        private World _world;

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            _world = World.CreateWorld("[Feature]TestWorld");
            _world.GetOrCreateSystemManaged<[Feature]System>();
            yield return null;
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            if (_world != null && _world.IsCreated)
                _world.Dispose();
            yield return null;
        }

        [UnityTest]
        public IEnumerator [Feature]System_When[Condition]_[ExpectedBehavior]()
        {
            // Arrange
            var entity = _world.EntityManager.CreateEntity(
                typeof(/* required components */));

            // Act
            _world.Update();
            yield return null;

            // Assert
            // var result = _world.EntityManager.GetComponentData<SomeComponent>(entity);
            // Assert.AreEqual(expected, result.Value);
            Assert.Fail("Not implemented — replace with real assertions");
        }
    }
}
```

### B3 → Review + Commit (Step 5 and Step 6 below)

---

## Step 3-C — PlayMode Scene Test

**When to use:** MonoBehaviour lifecycle, VContainer injection in a real scene, prefab behavior, physics, trigger/collision. Requires actual Unity scene loading.

> **All MCP calls in this flow are made directly by the main Claude session — no subagents.**

### C1 — Additional Context

```bash
find . -path "*/Tests/[ProjectName]PlayModeTest/*.cs" | head -5   # existing test pattern
find . -name "*TestScope.cs" | head -3                             # existing TestScope pattern
```

Read one existing TestScope if found to confirm namespace.

### C2 — Write TestScope

File: `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]TestScope.cs`

> Lives in PlayModeTest assembly — excluded from production builds. Never put in `Games/` assembly.

```csharp
using VContainer;
using VContainer.Unity;

namespace [Namespace].PlayModeTest
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

### C3 — Write TestInstaller

File: `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]TestInstaller.cs`

```csharp
using UnityEngine;
using VContainer;

namespace [Namespace].PlayModeTest
{
    public sealed class [Feature]TestInstaller : MonoBehaviour
    {
        #region Fields

        // Add [SerializeField] config references here

        #endregion

        #region Public Methods

        public void Install(IContainerBuilder builder)
        {
            // Register only what this scenario needs
            // builder.RegisterInstance(_config);
            // builder.Register<[Feature]Service>(Lifetime.Singleton).As<I[Feature]Service>();
        }

        #endregion
    }
}
```

### C4 — Write PlayMode Scene Test Stub

File: `_GameFolders/Scripts/Tests/[ProjectName]PlayModeTest/[Feature]Tests.cs`

```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using VContainer;
using VContainer.Unity;

namespace [Namespace].PlayModeTest
{
    [TestFixture]
    public class [Feature]Tests
    {
        private const string ScenePath = "Assets/_Scenes/TestScenes/[Feature]Test";

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            yield return SceneManager.LoadSceneAsync(ScenePath, LoadSceneMode.Single);
            yield return null; // one frame for VContainer to initialize
        }

        [UnityTest]
        public IEnumerator [Feature]_When[Condition]_[ExpectedBehavior]()
        {
            // Arrange
            var scope = Object.FindFirstObjectByType<[Feature]TestScope>();
            Assert.IsNotNull(scope, "[Feature]TestScope not found in test scene");
            var service = scope.Container.Resolve<I[Feature]Service>();

            // Act
            yield return null;

            // Assert
            Assert.Fail("Not implemented — replace with real assertions");
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            yield return SceneManager.LoadSceneAsync("Assets/_Scenes/TestScenes/Empty");
        }
    }
}
```

### C5 — Wait for Compilation + Build Scene via MCP

1. Call `unity_get_project_info` or `unity_compile` — wait for compilation to finish
2. If compilation errors → stop, print errors, ask user to fix before continuing
3. If success → create scene: `unity_create_scene` at `Assets/_Scenes/TestScenes/[Feature]Test`
4. Create `TestBootstrap` GameObject in scene
5. Add `[Feature]TestScope` component to TestBootstrap
6. Add `[Feature]TestInstaller` component to TestBootstrap
7. Wire `_installer` field on TestScope to the TestInstaller component
8. Save scene
9. If `Assets/_Scenes/TestScenes/Empty.unity` missing → create minimal empty scene

---

## Step 4 — Review (all paths)

**Reviewer priority:** Codex → unity-reviewer (fallback)

### EditMode review checklist
1. Namespace matches EditModeTest assembly
2. NSubstitute used correctly — only interfaces mocked, not concrete classes
3. AAA sections present in each test method
4. Test method names follow `Method_WhenCondition_ExpectedBehavior`
5. No Unity API in EditMode tests (`UnityEngine.*` imports absent)

### PlayMode-ECS review checklist
1. Isolated `World` created in `[UnitySetUp]`, disposed in `[UnityTearDown]`
2. Never uses `World.DefaultGameObjectInjectionWorld`
3. `[UnityTest]` + `IEnumerator` on all test methods
4. Namespace matches PlayModeTest assembly

### PlayMode-Scene review checklist
1. TestScope extends `LifetimeScope` (not AppScope), sealed, correct namespace
2. TestInstaller is `MonoBehaviour` (not ScriptableObject), `Install()` signature correct
3. Test stub: `[TestFixture]` + `[UnitySetUp]` + `[UnityTearDown]` present, `ScenePath` constant correct
4. `Assert.IsNotNull` on every `FindFirstObjectByType` result
5. No AppScope dependency — TestScope is a root scope
6. No production code touched

**Output format (REQUIRED):**
```
VERDICT: APPROVED | NEEDS_FIX
ISSUES:
- [file:line] — [description] — [fix]
OR: ISSUES: none
```

**Fix loop (NEEDS_FIX only):** Spawn `unity-coder-lite` with the issues list — surgical edits only, no scene recreation. Max 2 iterations. After 2 failures → proceed with issues listed in report.

---

## Step 5 — Commit (COMMIT_GATE)

Show staged files:
```
Files to commit:
  [list generated .cs files]
  (scene .unity files excluded — add to Build Settings manually)

Commit? (go / stop)
```

Wait for `go`. On `go` → spawn **committer** with message:
- EditMode:        `test([Feature]): add EditMode unit tests`
- PlayMode-ECS:   `test([Feature]): add PlayMode ECS system tests`
- PlayMode-Scene: `test([Feature]): add PlayMode scene test, TestScope, TestInstaller`

---

## Step 6 — Report

```
## ✓ [TEST_TYPE] Test Ready: [FEATURE]

### Test type: [EditMode | PlayMode-ECS | PlayMode-Scene]
### Review: [APPROVED ✓ | ISSUES REMAIN ⚠]
[unresolved issues if any]

### Created
[list files]

### You must do manually
[EditMode]
- Run: Window → General → Test Runner → EditMode → [FEATURE]Tests

[PlayMode-ECS]
- Run: Window → General → Test Runner → PlayMode → [FEATURE]SystemTests

[PlayMode-Scene]
- Add Assets/_Scenes/TestScenes/[FEATURE]Test.unity to Build Settings
- Add Assets/_Scenes/TestScenes/Empty.unity to Build Settings (if not already)
- Open [FEATURE]Test scene → drag feature prefabs into scene
- Wire [SerializeField] config references in [FEATURE]TestInstaller
- Fill in [UnityTest] stub with real assertions
- Run: Window → General → Test Runner → PlayMode → [FEATURE]Tests
```

$ARGUMENTS
