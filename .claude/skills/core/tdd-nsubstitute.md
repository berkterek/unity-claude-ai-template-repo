---
name: tdd-nsubstitute
description: TDD and NSubstitute usage pattern — project assembly structure, test templates, and mock rules
model-tier: normal
---

# TDD and NSubstitute — Usage Pattern

## Assembly Structure

```
Tests/
├── HospitalEditModeTests/   → Edit Mode, pure C# logic, NSubstitute mocks
│   └── HospitalEditModeTests.asmdef
└── HospitalPlayModelTests/  → Play Mode, MonoBehaviour lifecycle, ECS World
    └── HospitalPlayModelTests.asmdef
```

Both asmdefs require `overrideReferences: true` and the following under `precompiledReferences`:
- `nunit.framework.dll`
- `NSubstitute.dll`

---

## Test File Rules

- File name: `[TestedClass]Tests.cs` — e.g. `PlayerServiceTests.cs`
- Class name matches the file name, `public` (not `sealed`)
- Delete Unity's default scaffold files (`first_test_editmodel.cs`, `first_playmode_test.cs`)
- One test file per class — do not test multiple classes in a single file

---

## Test Method Naming

```
MethodName_WhenCondition_ExpectedBehavior
```

```csharp
[Test] public void TakeDamage_WhenHealthIsZero_PublishesPlayerDiedEvent() { }
[Test] public void Initialize_WhenConfigIsNull_ThrowsInvalidOperationException() { }
[Test] public void AddCoins_WhenAmountIsNegative_ThrowsArgumentException() { }
[Test] public void Move_WhenSpeedIsZero_DoesNotUpdatePosition() { }
```

---

## AAA Pattern (Mandatory)

Every test is divided with `// Arrange`, `// Act`, `// Assert` comments:

```csharp
[Test]
public void TakeDamage_WhenDamageExceedsHealth_SetsHealthToZero()
{
    // Arrange
    var eventBus = Substitute.For<IEventBus>();
    var sut = new PlayerService(health: 10, eventBus);

    // Act
    sut.TakeDamage(999);

    // Assert
    Assert.AreEqual(0, sut.Health);
}
```

---

## NSubstitute — Basic Usage

### Creating Mocks

```csharp
// ONLY interfaces are mocked — concrete classes are forbidden
var eventBus   = Substitute.For<IEventBus>();
var saveLoad   = Substitute.For<ISaveLoadService>();
var spawner    = Substitute.For<IEnemySpawner>();

// BAD — concrete mock is forbidden
var service = Substitute.For<PlayerService>();
```

### Configuring Return Values

```csharp
saveLoad.Load<int>(SaveKeyHelper.COINS).Returns(100);
saveLoad.HasKey(SaveKeyHelper.COINS).Returns(true);

// Throw an exception
saveLoad.When(x => x.Save(Arg.Any<string>(), Arg.Any<int>()))
        .Do(_ => throw new IOException());
```

### Verifying Calls

```csharp
// Called exactly once
eventBus.Received(1).Publish(Arg.Any<PlayerDiedEvent>());

// Never called
eventBus.DidNotReceive().Publish(Arg.Any<LevelWonEvent>());

// Called at least once
eventBus.Received().Publish(Arg.Any<CoinsChangedEvent>());

// Called with a specific argument
eventBus.Received(1).Publish(Arg.Is<CoinsChangedEvent>(e => e.NewAmount == 100));
```

### Arg Matchers

```csharp
Arg.Any<int>()              // any int
Arg.Is<int>(x => x > 0)    // int satisfying a condition
Arg.Is("specific-key")      // exact match
```

---

## Edit Mode Test Template

```csharp
using NSubstitute;
using NUnit.Framework;
using Framework.Events;

public class PlayerServiceTests
{
    private IEventBus _eventBus;
    private ISaveLoadService _saveLoad;
    private PlayerService _sut;

    [SetUp]
    public void SetUp()
    {
        _eventBus = Substitute.For<IEventBus>();
        _saveLoad = Substitute.For<ISaveLoadService>();
        _sut = new PlayerService(_eventBus, _saveLoad);
    }

    [TearDown]
    public void TearDown()
    {
        (_sut as System.IDisposable)?.Dispose();
    }

    [Test]
    public void TakeDamage_WhenHealthIsZero_PublishesPlayerDiedEvent()
    {
        // Arrange
        _sut.SetHealth(0);

        // Act
        _sut.TakeDamage(1);

        // Assert
        _eventBus.Received(1).Publish(Arg.Any<PlayerDiedEvent>());
    }

    [Test]
    public void Initialize_WhenSaveDataExists_LoadsPersistedHealth()
    {
        // Arrange
        _saveLoad.HasKey(SaveKeyHelper.HEALTH).Returns(true);
        _saveLoad.Load<int>(SaveKeyHelper.HEALTH).Returns(75);

        // Act
        _sut.Initialize();

        // Assert
        Assert.AreEqual(75, _sut.Health);
    }
}
```

---

## Play Mode Test Template (ECS)

```csharp
using NUnit.Framework;
using UnityEngine.TestTools;
using System.Collections;
using Unity.Entities;

public class EnemyMoveSystemTests
{
    private World _world;

    [SetUp]
    public void SetUp()
    {
        // Each test creates its own isolated World
        _world = World.CreateWorld("TestWorld");
    }

    [TearDown]
    public void TearDown()
    {
        _world.Dispose();
    }

    [UnityTest]
    public IEnumerator EnemyMoveSystem_WhenMoveInputSet_UpdatesPosition()
    {
        // Arrange
        var system = _world.GetOrCreateSystemManaged<EnemyMoveSystem>();
        var entity = _world.EntityManager.CreateEntity(
            typeof(EnemyEntityTag), typeof(MoveSpeedData), typeof(LocalTransform));

        // Act
        _world.Update();
        yield return null;

        // Assert
        var transform = _world.EntityManager.GetComponentData<LocalTransform>(entity);
        Assert.AreNotEqual(float3.zero, transform.Position);
    }
}
```

---

## What to Test / Not Test

| Layer | Test type | Tool |
|-------|-----------|------|
| `Games/Abstracts/` (interfaces, abstract) | Edit Mode | NUnit + NSubstitute |
| `Games/Concretes/` (services) | Edit Mode | NUnit + NSubstitute |
| `Games/Ecs/Systems/` | Play Mode | NUnit + ECS World |
| `Games/Ecs/Components/` | No test needed | — data struct |
| `Games/Ecs/Authorings/` | No test needed | — bake-time |
| MonoBehaviour Views | No test needed | — thin adapters |

---

## Common Mistakes

```csharp
// 1. Concrete mock — WRONG
var service = Substitute.For<PlayerService>(); // forbidden

// 2. Missing AAA comments — WRONG
[Test]
public void Test()
{
    var sut = new PlayerService(Substitute.For<IEventBus>());
    sut.TakeDamage(10);
    Assert.AreEqual(90, sut.Health); // which section is this?
}

// 3. Using the default World in ECS tests — WRONG
var system = World.DefaultGameObjectInjectionWorld.GetOrCreateSystem<EnemyMoveSystem>();

// 4. Unclear test method names — WRONG
[Test] public void TestDamage() { }
[Test] public void Test1() { }
```
