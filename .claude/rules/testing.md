# Testing Rules

## Mandatory TDD

Every class under `_GameFolders/Scripts/` must have a corresponding test. Rule: **write test first, then implementation**.

---

## Test Type Decision Tree

Before writing any test, apply this tree top-to-bottom — stop at the first match:

```
Is it a NoTest type? (stop here if any match)
├── LifetimeScope subclass       → NoTest  (DI wiring — tested via integration)
├── ScriptableObject config      → NoTest  (data container — no logic)
├── IComponentData struct        → NoTest  (data only)
├── Baker<T> inner class         → NoTest  (bake-time only)
└── NO → continue below

Is the target a Handler (pure C# class with Unity refs via constructor)?
├── Does it contain complex calculation logic (physics math, pathfinding, etc.)?
│   └── YES → Extract the pure math to a parameterless method → test that method in EditMode
│             (full Handler test → PlayMode-Programmatic)
└── Has Unity component refs (Rigidbody, Transform) passed via constructor?
    ├── YES → PlayMode-Programmatic
    │         (new GameObject() with required component, pass to Handler constructor)
    └── NO (pure C# deps only) → EditMode

Is the target a MonoBehaviour?
├── NO  → Is it an ISystem / SystemBase?
│         ├── YES → PlayMode-ECS  (isolated World, no scene)
│         └── NO  → EditMode  (pure C# / NSubstitute)
└── YES → Does Unity lifecycle (Awake / OnEnable / OnDisable / Update) matter?
          ├── NO  → EditMode  (if logic is fully injectable, no lifecycle needed)
          └── YES → PlayMode
                    └── Does the test require ANY of:
                        • VContainer scope hierarchy (AppScope → GameScope)
                        • Physics, triggers, or collisions
                        • Real prefab loaded from disk
                        • Wiring between multiple scene objects
                        ├── YES → PlayMode-Scene  (load scene + TestBootstrap)
                        └── NO  → PlayMode-Programmatic
                                  (new GameObject().AddComponent<>(), no scene)
```

**Key insight:** A MonoBehaviour that only subscribes to a service in `OnEnable` and updates a value does NOT need a scene. `PlayMode-Programmatic` covers ~80% of MonoBehaviour tests. Reserve `PlayMode-Scene` for production wiring verification.

### PlayMode-Programmatic: Handler with Unity Component Refs

A Handler that takes Unity components (Rigidbody, Transform) via constructor is not a MonoBehaviour — but it still requires a Play Mode context because Unity physics components only function at runtime. Create the GameObject in the test, add the required component, then pass it to the Handler constructor:

```csharp
[UnityTest]
public IEnumerator MoveHandler_WhenTickCalled_MovesRigidbodyForward()
{
    // Arrange
    var go = new GameObject();
    var rb = go.AddComponent<Rigidbody>();
    var config = ScriptableObject.CreateInstance<MoveConfiguration>();
    config.Speed = 5f;
    var sut = new MoveHandler(rb, config);
    sut.SetInput(Vector2.up);

    // Act
    sut.Tick(0.1f);
    yield return new WaitForFixedUpdate();

    // Assert
    Assert.Greater(rb.position.z, 0f);

    // Cleanup
    Object.Destroy(go);
    Object.Destroy(config);
}
```

## Test Types

| Type | Assembly | When |
|------|----------|------|
| **Edit Mode** | `[ProjectName]EditModeTest` | Pure C# logic, interface mocking, ECS component tests |
| **Play Mode — Programmatic** | `[ProjectName]PlayModeTest` | MonoBehaviour lifecycle tested via `new GameObject().AddComponent<>()` — no scene loading |
| **Play Mode — ECS World** | `[ProjectName]PlayModeTest` | ECS System integration with isolated World |
| **Play Mode — Scene** | `[ProjectName]PlayModeTest` | VContainer scope hierarchy, physics/collision, real prefab wiring across scene objects |

---

## What Requires Tests

| Folder | Test Type | Tool |
|--------|-----------|------|
| `Games/Abstracts/` | Edit Mode | NUnit + NSubstitute |
| `Games/Concretes/` (pure C#) | Edit Mode | NUnit + NSubstitute |
| `Games/Concretes/` (MonoBehaviour, isolated) | Play Mode — Programmatic | NUnit + new GameObject() |
| `Games/Concretes/` (MonoBehaviour, scene wiring) | Play Mode — Scene | NUnit + TestBootstrap scene |
| `Games/Concretes/<Domain>/` (Handler, Unity component refs) | Play Mode — Programmatic | NUnit + new GameObject().AddComponent<>() |
| `Games/Concretes/<Domain>/` (Handler, pure C# deps only) | Edit Mode | NUnit + NSubstitute |
| `Games/Ecs/Systems/` | Play Mode — ECS World | NUnit + isolated World |
| `Games/Ecs/Components/` | — | Data struct — no test needed |
| `Games/Ecs/Authorings/` | — | Baker bake-time — no test needed |
| `LifetimeScope` subclasses | — | DI wiring — tested via integration, not unit tests |
| `ScriptableObject` configs | — | Data container — no logic to test |

---

## Assembly Definition Setup

```json
// [ProjectName]EditModeTest.asmdef  (Edit Mode — includePlatforms: ["Editor"])
{
    "name": "[ProjectName]EditModeTest",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[ProjectName]Games"
    ],
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "defineConstraints": ["UNITY_INCLUDE_TESTS"]
}

// [ProjectName]PlayModeTest.asmdef  (Play Mode — all platforms)
{
    "name": "[ProjectName]PlayModeTest",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "[ProjectName]Games"
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
    ├── [ProjectName]EditModeTest/
    │   └── EnemySpawnerTests.cs     ← Edit Mode test
    └── [ProjectName]PlayModeTest/
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
└── [ProjectName]PlayModeTest/
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
    [SerializeField] private PlayerConfiguration _testConfig;

    public void Install(IContainerBuilder builder)
    {
        // Use the PRODUCTION module — never hand-copy registrations
        PlayerModule.Install(builder, _testConfig);

        // Override only what the scenario specifically requires to be fake
        builder.Register<FakeInputService>(Lifetime.Singleton).As<IInputService>();
    }
}
```

**Rule:** TestInstallers never hand-copy production registrations. Use the production `[Module]Module.Install()` method directly — only override the specific dependencies the test scenario requires to be faked. This prevents test/production wiring drift.

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
