---
name: tdd-nsubstitute
description: TDD ve NSubstitute kullanım paterni — proje assembly yapısı, test şablonları ve mock kuralları
model-tier: normal
---

# TDD ve NSubstitute — Kullanım Paterni

## Assembly Yapısı

```
Tests/
├── HospitalEditModeTests/   → Edit Mode, pure C# logic, NSubstitute mock
│   └── HospitalEditModeTests.asmdef
└── HospitalPlayModelTests/  → Play Mode, MonoBehaviour lifecycle, ECS World
    └── HospitalPlayModelTests.asmdef
```

Her iki asmdef'te `overrideReferences: true` ve `precompiledReferences` altında:
- `nunit.framework.dll`
- `NSubstitute.dll`

---

## Test Dosyası Kuralları

- Dosya adı: `[TestedClass]Tests.cs` — örn. `PlayerServiceTests.cs`
- Sınıf adı dosya adıyla aynı, `public` ve `sealed` değil
- Unity'nin default scaffold'u (`first_test_editmodel.cs`, `first_playmode_test.cs`) silinir
- Her sınıf için ayrı test dosyası — birden fazla sınıfı tek dosyada test etme

---

## Test Metod Adlandırma

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

## AAA Pattern (Zorunlu)

Her test `// Arrange`, `// Act`, `// Assert` yorumlarıyla bölümlenir:

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

## NSubstitute — Temel Kullanım

### Mock Oluşturma

```csharp
// SADECE interface mock'lanır — concrete class değil
var eventBus   = Substitute.For<IEventBus>();
var saveLoad   = Substitute.For<ISaveLoadService>();
var spawner    = Substitute.For<IEnemySpawner>();

// BAD — concrete mock yasak
var service = Substitute.For<PlayerService>();
```

### Return Değeri Tanımlama

```csharp
saveLoad.LoadDataProcess<int>("coins").Returns(100);
saveLoad.HasKeyAvailable("coins").Returns(true);

// Exception fırlat
saveLoad.When(x => x.SaveDataProcess(Arg.Any<string>(), Arg.Any<object>()))
        .Do(_ => throw new IOException());
```

### Çağrı Doğrulama

```csharp
// Tam olarak 1 kez çağrıldı mı
eventBus.Received(1).Publish(Arg.Any<PlayerDiedEvent>());

// Hiç çağrılmadı mı
eventBus.DidNotReceive().Publish(Arg.Any<LevelWonEvent>());

// En az 1 kez
eventBus.Received().Publish(Arg.Any<CoinsChangedEvent>());

// Spesifik argümanla çağrıldı mı
eventBus.Received(1).Publish(Arg.Is<CoinsChangedEvent>(e => e.NewAmount == 100));
```

### Arg Matchers

```csharp
Arg.Any<int>()              // herhangi bir int
Arg.Is<int>(x => x > 0)    // koşulu sağlayan int
Arg.Is("specific-key")      // tam eşleşme
```

---

## Edit Mode Test Şablonu

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
        // IDisposable ise dispose et
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
        _saveLoad.HasKeyAvailable("player_health").Returns(true);
        _saveLoad.LoadDataProcess<int>("player_health").Returns(75);

        // Act
        _sut.Initialize();

        // Assert
        Assert.AreEqual(75, _sut.Health);
    }
}
```

---

## Play Mode Test Şablonu (ECS)

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
        // Her test kendi izole World'ünü oluşturur
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

## Neyin Test Edildiği / Edilmediği

| Katman | Test türü | Araç |
|--------|-----------|------|
| `Games/Abstracts/` (interface, abstract) | Edit Mode | NUnit + NSubstitute |
| `Games/Concretes/` (servisler) | Edit Mode | NUnit + NSubstitute |
| `Games/Ecs/Systems/` | Play Mode | NUnit + ECS World |
| `Games/Ecs/Components/` | Test gerekmez | — veri struct'ı |
| `Games/Ecs/Authorings/` | Test gerekmez | — bake-time |
| MonoBehaviour View'ları | Test gerekmez | — ince adapter |

---

## Sık Yapılan Hatalar

```csharp
// 1. Concrete mock — YANLIŞ
var service = Substitute.For<PlayerService>(); // yasak

// 2. AAA yorumları eksik — YANLIŞ
[Test]
public void Test()
{
    var sut = new PlayerService(Substitute.For<IEventBus>());
    sut.TakeDamage(10);
    Assert.AreEqual(90, sut.Health); // hangi bölüm ne?
}

// 3. ECS testinde default World kullanmak — YANLIŞ
var system = World.DefaultGameObjectInjectionWorld.GetOrCreateSystem<EnemyMoveSystem>();

// 4. Test metodunda belirsiz isim — YANLIŞ
[Test] public void TestDamage() { }
[Test] public void Test1() { }
```
