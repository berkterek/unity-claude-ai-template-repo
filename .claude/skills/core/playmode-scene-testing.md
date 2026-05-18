---
name: playmode-scene-testing
description: Play Mode scene testing pattern — TestBootstrap prefab, TestScope (VContainer), scene setup, and UnityTest patterns for real MonoBehaviour and prefab integration tests
model-tier: normal
---

# Play Mode Scene Testing

## Philosophy

Edit Mode tests verify *logic*. Scene tests verify *wiring* — that prefabs initialize correctly, VContainer resolves dependencies, and MonoBehaviours behave correctly in a live scene.

**Scene test = real scene + real prefabs + isolated TestScope**

---

## Folder Conventions

```
_Scenes/TestScenes/           ← all test scenes here
    [Feature]Test.unity       ← one scene per scenario

_GameFolders/Prefabs/
    TestBootstrap/
        TestBootstrap.prefab  ← reusable bootstrap shell

_GameFolders/Scripts/
    Games/
        TestScopes/           ← TestScope + TestInstaller per scenario
            [Feature]TestScope.cs
            [Feature]TestInstaller.cs
    Tests/
        [ProjectName]PlayModeTest/
            [Feature]Tests.cs
```

---

## TestBootstrap Prefab

One per scene. First in hierarchy. Contains:

```
TestBootstrap (GameObject)
├── [Feature]TestScope       ← LifetimeScope component
└── [Feature]TestInstaller   ← MonoBehaviour, wired to TestScope
```

No AppScope. No DontDestroyOnLoad. Isolated root scope only.

---

## TestScope Template

```csharp
namespace Game.Tests
{
    public sealed class PlayerMovementTestScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private PlayerMovementTestInstaller _installer;

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

---

## TestInstaller Template

Register real services unless the scenario specifically needs a fake.

```csharp
namespace Game.Tests
{
    public sealed class PlayerMovementTestInstaller : MonoBehaviour
    {
        #region Fields

        [SerializeField] private PlayerConfiguration _config;

        #endregion

        #region Public Methods

        public void Install(IContainerBuilder builder)
        {
            if (_config == null)
                throw new InvalidOperationException("PlayerMovementTestInstaller: _config is not assigned.");

            builder.RegisterInstance(_config);
            builder.Register<PlayerService>(Lifetime.Singleton).As<IPlayerService>();
        }

        #endregion
    }
}
```

---

## PlayMode Test Template

```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using VContainer;

namespace Game.Tests
{
    [TestFixture]
    public class PlayerMovementTests
    {
        private const string ScenePath = "TestScenes/PlayerMovementTest";

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            yield return SceneManager.LoadSceneAsync(ScenePath, LoadSceneMode.Single);
            yield return null; // one frame — VContainer initializes
        }

        [UnityTest]
        public IEnumerator Player_WhenMoveInputApplied_MovesRight()
        {
            // Arrange
            var playerView = Object.FindFirstObjectByType<PlayerView>();
            Assert.IsNotNull(playerView, "PlayerView missing in test scene");
            var startPos = playerView.transform.position;

            var service = LifetimeScope.Find<PlayerMovementTestScope>()
                .Container.Resolve<IPlayerService>();

            // Act
            service.SetMoveInput(Vector2.right);
            yield return new WaitForSeconds(0.3f);

            // Assert
            Assert.Greater(playerView.transform.position.x, startPos.x);
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            // Load an empty scene to clean up — avoids state bleeding between tests
            yield return SceneManager.LoadSceneAsync("TestScenes/Empty");
        }
    }
}
```

---

## Resolving Dependencies in Tests

```csharp
// Get the container from the test scope
var scope = LifetimeScope.Find<MyFeatureTestScope>();
var service = scope.Container.Resolve<IMyService>();

// Or find a MonoBehaviour directly
var view = Object.FindFirstObjectByType<MyView>();
```

---

## Using a Fake Service in a Test Scenario

When the test needs to control a dependency (e.g., trigger an event manually):

```csharp
// In TestInstaller — register a fake implementation
public void Install(IContainerBuilder builder)
{
    builder.RegisterInstance(_config);
    builder.RegisterInstance<IEnemySpawner>(new FakeEnemySpawner()); // fake
    builder.Register<PlayerService>(Lifetime.Singleton).As<IPlayerService>(); // real
}

// Fake — minimal stub, lives in Tests/ folder
public sealed class FakeEnemySpawner : IEnemySpawner
{
    public int SpawnCallCount { get; private set; }
    public void Spawn(int count) => SpawnCallCount += count;
}
```

Access the fake in the test:

```csharp
var fake = (FakeEnemySpawner)scope.Container.Resolve<IEnemySpawner>();
Assert.AreEqual(1, fake.SpawnCallCount);
```

---

## Empty Scene for TearDown

Create `_Scenes/TestScenes/Empty.unity` — an empty scene with no GameObjects. Used in `[UnityTearDown]` to cleanly unload the test scene and reset state.

---

## Common Mistakes

```csharp
// 1. Using FindObjectOfType without null check — NullRef instead of clear failure
var view = Object.FindObjectOfType<PlayerView>(); // risky
// GOOD:
var view = Object.FindFirstObjectByType<PlayerView>();
Assert.IsNotNull(view, "PlayerView not found — is the prefab in the scene?");

// 2. No yield after LoadSceneAsync — VContainer not initialized yet
yield return SceneManager.LoadSceneAsync(path);
// BAD: immediately resolve — scope not ready
// GOOD: yield return null; first

// 3. Extending AppScope in TestScope — pollutes test with global state
public class TestScope : AppScope { } // forbidden

// 4. Missing [UnityTearDown] — state from one test bleeds into the next
```

---

## Build Settings

Test scenes are added to Build Settings automatically by `/create-test` via MCP (`manage_build`) immediately after scene creation. Test scenes always go at the end of the scene list, after all game scenes.

If a test scene was created without MCP (code-only mode), add it manually:
- `_Scenes/TestScenes/[Feature]Test.unity` → end of Build Settings list
- `_Scenes/TestScenes/Empty.unity` → end of Build Settings list (if not already there)
