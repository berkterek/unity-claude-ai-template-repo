---
name: nsubstitute
description: NSubstitute setup, configuration, and usage patterns for Unity test assemblies. Use when adding NSubstitute to a project, diagnosing mock failures, or writing substitutes.
user-invocable: true
model-tier: normal
---

# NSubstitute — Setup & Usage Guide

## Why NSubstitute Cannot Use Package Manager

NSubstitute is a .NET mocking library not distributed via Unity Package Manager. It must be placed as a precompiled DLL inside the Unity project and referenced explicitly in the test assembly definition.

---

## Installation (One-Time Per Project)

### Step 1 — Get the DLL

Download `NSubstitute.dll` from the [NSubstitute releases page](https://github.com/nsubstitute/NSubstitute/releases).

Use the `netstandard2.0` build — Unity uses .NET Standard 2.1 compatibility mode which accepts 2.0 assemblies.

### Step 2 — Place the DLL

```
Assets/
└── _GameFolders/
    └── Plugins/
        └── NSubstitute/
            └── NSubstitute.dll
```

Do NOT place it in a folder named `Editor/` — it must be accessible at runtime for Edit Mode tests.

### Step 3 — Configure the Test Assembly

The test `.asmdef` MUST have `overrideReferences: true` or NSubstitute will be silently excluded.

**`[ProjectName]EditModeTest.asmdef`** (Edit Mode — `includePlatforms: ["Editor"]`):

```json
{
    "name": "MyProjectTests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "MyProjectGames"
    ],
    "includePlatforms": ["Editor"],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": ["UNITY_INCLUDE_TESTS"],
    "versionDefines": []
}
```

`overrideReferences: true` is the critical flag. Without it, Unity ignores `precompiledReferences` and NSubstitute is not available at compile time, causing `CS0246` errors on `Substitute.For<>`.

---

## Diagnosing Assembly Errors

### Symptom: `CS0246 The type or namespace name 'Substitute' could not be found`

Checklist:
1. `NSubstitute.dll` is at `Assets/_GameFolders/Plugins/NSubstitute/NSubstitute.dll`
2. Test `.asmdef` has `"overrideReferences": true`
3. Test `.asmdef` has `"NSubstitute.dll"` in `precompiledReferences`
4. Test `.asmdef` references the target game assembly in `references`
5. Unity was refreshed after changing `.asmdef` (`mcp__UnityMCP__refresh_unity`)

### Symptom: Tests compile but `Substitute.For<ConcreteClass>()` throws at runtime

NSubstitute cannot mock concrete classes without a virtual proxy. The rule is:

**Only mock interfaces.**

```csharp
// CORRECT
var eventBus = Substitute.For<IEventBus>();

// WRONG — throws at runtime
var service = Substitute.For<EnemyService>();
```

---

## Usage Patterns

### Basic Substitute

```csharp
using NSubstitute;

var eventBus = Substitute.For<IEventBus>();
var spawner  = Substitute.For<IEnemySpawner>();
```

### Return Values

```csharp
spawner.GetCount().Returns(5);
spawner.GetEnemy(Arg.Any<int>()).Returns(fakeEnemy);
```

### Verify Calls

```csharp
// Received exactly once
eventBus.Received(1).Publish(Arg.Any<EnemyDiedEvent>());

// Never called
eventBus.DidNotReceive().Publish(Arg.Any<LevelWonEvent>());

// Received any number of times
eventBus.Received().Publish(Arg.Any<EnemyDiedEvent>());
```

### Argument Matchers

```csharp
// Any value of that type
Arg.Any<int>()

// Specific value
Arg.Is<int>(x => x > 0)

// Exact match (prefer Arg.Is for value types)
5
```

### Callbacks (When...Do)

```csharp
eventBus
    .When(x => x.Publish(Arg.Any<EnemyDiedEvent>()))
    .Do(callInfo => capturedEvent = callInfo.Arg<EnemyDiedEvent>());
```

---

## Full Test Example

```csharp
using NSubstitute;
using NUnit.Framework;

public class EnemyServiceTests
{
    [Test]
    public void TakeDamage_WhenDamageExceedsHealth_PublishesEnemyDiedEvent()
    {
        // Arrange
        var eventBus = Substitute.For<IEventBus>();
        var sut = new EnemyService(health: 10, eventBus);

        // Act
        sut.TakeDamage(999);

        // Assert
        eventBus.Received(1).Publish(Arg.Any<EnemyDiedEvent>());
    }

    [Test]
    public void TakeDamage_WhenDamageIsZero_HealthRemainsUnchanged()
    {
        // Arrange
        var eventBus = Substitute.For<IEventBus>();
        var sut = new EnemyService(health: 10, eventBus);

        // Act
        sut.TakeDamage(0);

        // Assert
        Assert.AreEqual(10, sut.Health);
        eventBus.DidNotReceive().Publish(Arg.Any<EnemyDiedEvent>());
    }
}
```

---

## Rules (Non-Negotiable)

| Rule | Why |
|------|-----|
| Only mock interfaces | NSubstitute cannot intercept non-virtual concrete methods |
| `overrideReferences: true` in test asmdef | Without it, NSubstitute.dll is silently excluded |
| One `.asmdef` per test type (Edit/Play) | Unity's test runner requires separate assemblies |
| Never place NSubstitute.dll in `Editor/` | Edit Mode tests run in non-editor context |
| Never use `new MockClass()` hand-rolls when an interface exists | Substitutes are more maintainable and type-safe |
