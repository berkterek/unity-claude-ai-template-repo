# Testing Rules

## Mandatory TDD

Every class under `_GameFolders/Scripts/` must have a corresponding test. Rule: **write test first, then implementation**.

---

## Test Types

| Type | Assembly | When |
|------|----------|------|
| **Edit Mode** | `[Project]Tests` | Pure C# logic, interface mocking, ECS component tests |
| **Play Mode** | `[Project]PlayTests` | MonoBehaviour lifecycle, ECS World + System integration |

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

## Sample Test Templates

Keep `SampleEditModeTests.cs` and `SamplePlayModeTests.cs` in the test assemblies — they show AAA structure and naming for new contributors. Delete Unity's auto-generated `first_test.cs` / `first_play_test.cs` scaffold files immediately.
