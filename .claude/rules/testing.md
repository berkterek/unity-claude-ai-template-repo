# Testing Rules

## Mandatory TDD

Every class under `_GameFolders/Scripts/` must have a corresponding test. Rule: **write test first, then implementation**.

---

## Test Types

| Type | Assembly | When |
|------|----------|------|
| **Edit Mode** | `[Project]Tests` | Pure C# logic, interface mocking, ECS component tests |
| **Play Mode (ECS World)** | `[Project]PlayTests` | ECS System integration with isolated World |
| **Play Mode (Scene)** | `[Project]PlayTests` | MonoBehaviour lifecycle, VContainer wiring, real prefab behavior |

---

## What Requires Tests

| Folder | Test Type | Tool |
|--------|-----------|------|
| `Games/Abstracts/` | Edit Mode | NUnit + NSubstitute |
| `Games/Concretes/` | Edit Mode | NUnit + NSubstitute |
| `Games/Ecs/Systems/` | Play Mode | NUnit + ECS World |
| `Games/Ecs/Components/` | — | Data struct — no test needed |
| `Games/Ecs/Authorings/` | — | Baker bake-time — no test needed |

---

## Assembly Definition Setup

```json
// [Project]Tests.asmdef  (Edit Mode — includePlatforms: ["Editor"])
{
    "name": "[Project]Tests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[Project]Games"
    ],
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "defineConstraints": ["UNITY_INCLUDE_TESTS"]
}

// [Project]PlayTests.asmdef  (Play Mode — all platforms)
{
    "name": "[Project]PlayTests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[Project]Games"
    ],
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "defineConstraints": ["UNITY_INCLUDE_TESTS"]
}
```

**NSubstitute installation:** NSubstitute cannot be installed via Package Manager. Place `NSubstitute.dll` manually in `Assets/Plugins/NSubstitute/` and reference it via `precompiledReferences` with `overrideReferences: true`.

---

## Test File Location and Naming

```
_GameFolders/Scripts/
├── Games/
│   └── Concretes/
│       └── EnemySpawner.cs          ← class under test
└── Tests/
    ├── [Project]Tests/
    │   └── EnemySpawnerTests.cs     ← Edit Mode test
    └── [Project]PlayTests/
        └── EnemyMoveSystemTests.cs  ← Play Mode ECS test
```

**Rule:** `[TestedClass]Tests.cs` — one test file per tested class.

---

## Test Method Naming

```
MethodName_WhenCondition_ExpectedBehavior
```

```csharp
// GOOD
[Test] public void TakeDamage_WhenHealthIsZero_RaisesOnDeathEvent() { }
[Test] public void Spawn_WhenPoolIsEmpty_ThrowsInvalidOperationException() { }
[Test] public void Move_WhenSpeedIsNegative_ThrowsArgumentException() { }

// BAD
[Test] public void Test1() { }
[Test] public void SpawnEnemy() { }
```

---

## AAA Pattern (Mandatory)

Every test uses Arrange / Act / Assert sections with explicit comments:

```csharp
[Test]
public void TakeDamage_WhenDamageExceedsHealth_SetsHealthToZero()
{
    // Arrange
    var eventBus = Substitute.For<IEventBus>();
    var enemy = new ConcreteEnemy(health: 10, eventBus);

    // Act
    enemy.TakeDamage(999);

    // Assert
    Assert.AreEqual(0, enemy.Health);
}
```

---

## NSubstitute Rules

**Only interfaces are mocked.** Mocking concrete classes with `Substitute.For<T>()` is forbidden.

```csharp
// GOOD — interface mock
var eventBus = Substitute.For<IEventBus>();
var spawner  = Substitute.For<IEnemySpawner>();

// BAD — concrete mock
var service = Substitute.For<EnemySpawner>();
```

### Call Verification

```csharp
// At least 1 call
eventBus.Received(1).Publish(Arg.Any<EnemyDiedEvent>());

// Never called
eventBus.DidNotReceive().Publish(Arg.Any<LevelWonEvent>());

// Return value
spawner.Spawn(Arg.Any<int>()).Returns(fakeEntity);
```

### Constructor Injection Makes Mocking Trivial

```csharp
// Class
public class EnemySpawner : IEnemySpawner
{
    private readonly IEventBus _eventBus;
    public EnemySpawner(IEventBus eventBus) => _eventBus = eventBus;
}

// Test — inject the mock directly
var eventBus = Substitute.For<IEventBus>();
var sut = new EnemySpawner(eventBus);
```

---

## ECS System Tests (Play Mode)

Create an isolated `World` per test — never use `World.DefaultGameObjectInjectionWorld`.

```csharp
[UnityTest]
public IEnumerator EnemyMoveSystem_WhenMoveInputSet_UpdatesTranslation()
{
    // Arrange
    var world  = World.CreateWorld("TestWorld");
    var system = world.GetOrCreateSystemManaged<EnemyMoveSystem>();
    var entity = world.EntityManager.CreateEntity(
        typeof(EnemyEntityTag), typeof(MoveInput), typeof(LocalTransform));

    world.EntityManager.SetComponentData(entity, new MoveInput { Value = new float3(1, 0, 0) });

    // Act
    world.Update();
    yield return null;

    // Assert
    var transform = world.EntityManager.GetComponentData<LocalTransform>(entity);
    Assert.AreNotEqual(float3.zero, transform.Position);

    // Cleanup
    world.Dispose();
}
```

---

## Play Mode Scene Tests

Play Mode scene tests verify real MonoBehaviour and VContainer behavior using actual Unity scenes and prefabs. They complement Edit Mode unit tests — not replace them.

### When to Use

| Use scene test | Use Edit Mode test |
|---------------|-------------------|
| MonoBehaviour lifecycle (`Awake`, `Start`, `OnEnable`) | Pure service logic |
| VContainer injection works correctly in scene | Interface contract behavior |
| Prefab behaves correctly at runtime | ECS component data |
| Physics / trigger / collision | Event bus publish/subscribe |
| Visual state driven by service | Calculation, state machine |

### Folder Structure

```
_Scenes/
└── TestScenes/
    ├── PlayerMovementTest.unity       ← one scene per scenario
    ├── EnemySpawnTest.unity
    └── CombatSystemTest.unity

_GameFolders/Prefabs/
└── TestBootstrap/
    └── TestBootstrap.prefab           ← shared bootstrap prefab

_GameFolders/Scripts/Tests/
└── [Project]PlayTests/
    ├── PlayerMovementTests.cs
    └── EnemySpawnTests.cs
```

### TestBootstrap Prefab (NON-NEGOTIABLE)

Every test scene contains exactly **one** `TestBootstrap` prefab instance. No other bootstrap or AppScope is present.

```
TestBootstrap.prefab
├── [Feature]TestScope.cs     ← VContainer LifetimeScope for this scenario
└── [Feature]TestInstaller.cs ← registers only what the scenario needs
```

`TestScope` is a `LifetimeScope` that registers real or fake services for the scenario. It does **not** extend AppScope — it is a root scope.

```csharp
// PlayerMovementTestScope.cs
public sealed class PlayerMovementTestScope : LifetimeScope
{
    [SerializeField] private PlayerMovementTestInstaller _installer;

    protected override void Configure(IContainerBuilder builder)
    {
        _installer.Install(builder);
    }
}

// PlayerMovementTestInstaller.cs
public sealed class PlayerMovementTestInstaller : MonoBehaviour
{
    [SerializeField] private PlayerConfiguration _config;

    public void Install(IContainerBuilder builder)
    {
        builder.RegisterInstance(_config);
        builder.Register<PlayerService>(Lifetime.Singleton).As<IPlayerService>();
        // Use real services unless the scenario specifically needs a fake
    }
}
```

### Scene Setup Rules

- Scene name: `[Feature]Test.unity` — matches the PlayMode test class name
- TestBootstrap prefab must be the **first** object in hierarchy
- All other GameObjects in the scene must be **prefab instances** (same rule as production scenes)
- No AppScope, no persistent objects, no `DontDestroyOnLoad`
- Scene must be added to **Build Settings** for CI compatibility

### PlayMode Test Pattern

```csharp
[TestFixture]
public class PlayerMovementTests
{
    private const string ScenePath = "TestScenes/PlayerMovementTest";

    [UnitySetUp]
    public IEnumerator SetUp()
    {
        yield return SceneManager.LoadSceneAsync(ScenePath, LoadSceneMode.Single);
        yield return null; // one frame for VContainer to initialize
    }

    [UnityTest]
    public IEnumerator Player_WhenMoveInputApplied_MovesInCorrectDirection()
    {
        // Arrange
        var playerView = Object.FindFirstObjectByType<PlayerView>();
        Assert.IsNotNull(playerView, "PlayerView not found in test scene");
        var startPos = playerView.transform.position;

        // Act
        var container = LifetimeScope.Find<PlayerMovementTestScope>().Container;
        var service = container.Resolve<IPlayerService>();
        service.SetMoveInput(Vector2.right);
        yield return new WaitForSeconds(0.3f);

        // Assert
        Assert.Greater(playerView.transform.position.x, startPos.x);
    }

    [UnityTearDown]
    public IEnumerator TearDown()
    {
        yield return SceneManager.LoadSceneAsync("Assets/_Scenes/Empty.unity");
    }
}
```

### Rules

| Rule | Reason |
|------|--------|
| One `TestBootstrap` per scene | Predictable initialization, no scope conflicts |
| `TestScope` never extends `AppScope` | Isolation — tests must not depend on global state |
| Real services unless scenario requires fake | Tests should catch real wiring bugs |
| `[UnitySetUp]` / `[UnityTearDown]` mandatory | Clean state between tests |
| One test class per scene | Naming stays 1:1 between scene and test file |
| `Assert.IsNotNull` on every `FindFirstObjectByType` result | Fails fast with clear message instead of NullRef |
| Add scene to Build Settings | CI compatibility |

### What NOT to Test in Scene Tests

- Pure C# logic (belongs in Edit Mode)
- ECS Systems in isolation (use isolated World)
- Things that can be constructor-injected (use Edit Mode + NSubstitute)

---

## Sample Test Templates

Keep `SampleEditModeTests.cs` and `SamplePlayModeTests.cs` in the test assemblies — they show AAA structure and naming for new contributors. Delete Unity's auto-generated `first_test.cs` / `first_play_test.cs` scaffold files immediately.
