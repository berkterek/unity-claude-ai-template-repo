---
name: vcontainer
description: VContainer dependency injection for Unity — scope hierarchy, installer pattern (IInstaller → ModuleInstaller → AppInstaller → AppScope), registration patterns, and DI failure diagnosis. Use whenever wiring a new service, creating an installer, debugging injection errors, adding a module to AppInstaller, or designing scope structure. Trigger on any mention of AppScope, ModuleInstaller, AppInstaller, LifetimeScope, [Inject], VContainer, DI registration, or "how do I add a new service/module".

user-invocable: true
model-tier: normal
---

# VContainer — Setup & Usage Guide

> Full bootstrap/installer pattern (IInstaller → ModuleInstaller → AppInstaller → AppScope katman kuralları) için bkz. `rules/bootstrap-pattern.md`.

## What VContainer Does

VContainer is a fast, zero-allocation dependency injection container for Unity. It replaces singletons, static accessors, and `FindObjectOfType` with explicit constructor injection wired at scope boundaries.

---

## Scope Hierarchy

```
AppScope (Bootstrap scene — DontDestroyOnLoad)
├── MenuScope  (Menu scene — child of AppScope)
└── GameScope  (Game scene — child of AppScope)
```

- Bootstrap scene (Build index 0) loads once and never unloads
- `AppScope` registers global services via `AppInstaller` — never directly
- Child scopes resolve from parent — `GameScope` can use `IAudioService` registered in `AppScope`
- Sibling scopes are isolated — `MenuScope` cannot access `GameScope` registrations
- A scope disposes all its registrations when the scene unloads

---

## AppScope Pattern

`AppScope.cs` **asla değişmez.** Yeni modül eklemek için `AppInstaller.asset`'e yeni installer eklenir.

```csharp
public sealed class AppScope : LifetimeScope
{
    [SerializeField] private AppInstaller     _appInstaller;
    [SerializeField] private AppConfiguration _appConfiguration;

    protected override void Configure(IContainerBuilder builder)
    {
        if (_appConfiguration == null)
        {
            Debug.LogError("[AppScope] AppConfiguration reference is missing.");
            return;
        }

        if (_appInstaller == null)
        {
            Debug.LogError("[AppScope] AppInstaller reference is missing.");
            return;
        }

        builder.RegisterInstance(_appConfiguration);

        builder.RegisterComponentInHierarchy<UIRoot>();
        builder.RegisterComponentInHierarchy<AudioRoot>();

        _appInstaller.Install(builder);

        builder.RegisterBuildCallback(container =>
        {
            EventBusAccessor.Initialize(container.Resolve<IEventBus>());
        });
    }
}
```

**Önemli:**
- `EventBus` burada doğrudan register edilmez — `EventBusInstaller` bunu yapar
- Sahne bileşenleri (`UIRoot`, `AudioRoot`) `RegisterComponentInHierarchy` ile bulunur
- Null guard'lar `Debug.LogError + return` — `throw` değil

---

## Installer Katmanı

### IInstaller

```csharp
// _Framework/Installers/IInstaller.cs
namespace Framework.Installers
{
    public interface IInstaller
    {
        void Install(IContainerBuilder builder);
    }
}
```

### ModuleInstaller (abstract base)

```csharp
// _Framework/Installers/ModuleInstaller.cs
using UnityEngine;
using VContainer;

namespace Framework.Installers
{
    public abstract class ModuleInstaller : ScriptableObject, IInstaller
    {
        public abstract void Install(IContainerBuilder builder);
    }
}
```

### AppInstaller (modül listesi)

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppInstaller.cs
[CreateAssetMenu(menuName = "Game/Infrastructure/App Installer", fileName = "AppInstaller")]
public sealed class AppInstaller : ScriptableObject, IInstaller
{
    [SerializeField] private List<ModuleInstaller> _modules = new();

    public void Install(IContainerBuilder builder)
    {
        foreach (var module in _modules)
        {
            if (module == null) continue;
            module.Install(builder);
        }
    }
}
```

- `List<ModuleInstaller>` kullan — array değil (Inspector'da sıralama için)
- `EventBusInstaller` **daima listenin ilk elemanıdır**

---

## [Module]Installer Yazma

Her modülün kendi installer'ı vardır. Config varsa null guard zorunludur.

```csharp
[CreateAssetMenu(menuName = "Game/Installers/Audio", fileName = "AudioInstaller")]
public sealed class AudioInstaller : ModuleInstaller
{
    [SerializeField] private AudioConfiguration _config;

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
        {
            Debug.LogError("[AudioInstaller] AudioConfiguration is missing.", this);
            return;
        }

        builder.RegisterInstance(_config);
        builder.Register<AudioService>(Lifetime.Singleton)
            .AsImplementedInterfaces();  // IInitializable, IDisposable otomatik register
    }
}
```

### EventBusInstaller (her projede zorunlu)

```csharp
[CreateAssetMenu(menuName = "Game/Installers/EventBus", fileName = "EventBusInstaller")]
public sealed class EventBusInstaller : ModuleInstaller
{
    public override void Install(IContainerBuilder builder)
    {
        builder.Register<EventBus>(Lifetime.Singleton)
            .AsImplementedInterfaces();
    }
}
```

Config tutmaz. `AppInstaller._modules` listesinde **her zaman ilk sıradadır**.

### Yeni modül ekleme akışı

1. `[Domain]Installer.cs` yaz, `ModuleInstaller`'dan türet
2. Unity'de asset oluştur: `Assets → Create → Game/Installers/[Domain]`
3. Config SO'yu Inspector'da ata
4. `AppInstaller.asset` → yeni installer'ı `_modules` listesine ekle
5. `AppScope.cs`'e **dokunma**

---

## Registration Patterns

### Pure C# Service

```csharp
// GOOD — interface üzerinden resolve
builder.Register<AudioService>(Lifetime.Singleton).As<IAudioService>();

// GOOD — lifecycle interface'leri de dahil
builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();

// BAD — concrete bağımlılık
builder.Register<AudioService>(Lifetime.Singleton);
```

### MonoBehaviour / Component

```csharp
// Sahnede hazır bulunan — hierarchy'de arar
builder.RegisterComponentInHierarchy<InputView>();

// Inspector'dan sürüklenmiş referans
builder.RegisterComponent(_audioRoot);

// Prefab'dan instantiate
builder.RegisterComponentInNewPrefab(prefab, Lifetime.Scoped);
```

### ScriptableObject Config

```csharp
builder.RegisterInstance(_appConfiguration);
```

`RegisterInstance` construction yapmaz — nesne zaten var. SO'lar ve pre-built instance'lar için kullanılır.

### Factory

```csharp
builder.RegisterFactory<EnemyService>(container =>
    new EnemyService(container.Resolve<IEventBus>(), container.Resolve<IPoolService>()));
```

---

## Lifetime Options

| Lifetime | Instances | Ne zaman |
|----------|-----------|----------|
| `Singleton` | Scope başına 1 | Uygulama geneli servisler |
| `Scoped` | Scope başına 1 | Sahneye özel servisler |
| `Transient` | Her resolve'da yeni | Stateless yardımcılar |

Pratikte servisler için `Singleton` kullan.

---

## Injection Methods

### Constructor Injection (pure C# için tercih)

```csharp
public sealed class ScoreService : IScoreService
{
    private readonly IEventBus _eventBus;
    private readonly ScoreConfiguration _config;

    public ScoreService(IEventBus eventBus, ScoreConfiguration config)
    {
        _eventBus = eventBus;
        _config   = config;
    }
}
```

VContainer constructor parametrelerini otomatik çözümler — attribute gerekmez.

### Method Injection (MonoBehaviour için)

```csharp
public sealed class PlayerView : MonoBehaviour
{
    private IPlayerService _playerService;

    [Inject]
    public void Construct(IPlayerService playerService)
    {
        _playerService = playerService;
    }
}
```

MonoBehaviour'u scope'a bildirmek için:

```csharp
builder.RegisterComponentInHierarchy<PlayerView>();
```

### IInitializable / IDisposable Lifecycle

```csharp
public sealed class AudioService : IAudioService, IInitializable, IDisposable
{
    public void Initialize()
    {
        _eventBus.Subscribe<MuteChangedEvent>(OnMuteChanged);
    }

    public void Dispose()
    {
        _eventBus.Unsubscribe<MuteChangedEvent>(OnMuteChanged);
    }
}
```

`.AsImplementedInterfaces()` ile `IInitializable` ve `IDisposable` otomatik register edilir.

---

## Child Scope Setup

```csharp
public sealed class GameScope : LifetimeScope
{
    [SerializeField] private GameInstaller _gameInstaller;

    protected override void Configure(IContainerBuilder builder)
    {
        _gameInstaller.Install(builder);
    }
}
```

Inspector'da `Parent` alanını `AppScope`'a bağla — global kayıtlar miras alınır.

---

## No GameContext / Service Locator (NON-NEGOTIABLE)

```csharp
// BAD — gizli bağımlılık, her sınıf her şeyi alır
public class GameContext
{
    public IPlayerService Player { get; }
    public IScoreService Score { get; }
}

// GOOD — her sınıf sadece kendi ihtiyacını bildirir
public sealed class ScoreView : MonoBehaviour
{
    [Inject]
    public void Construct(IScoreService score) { }
}
```

---

## Diagnosing DI Failures

### `VContainerException: Unable to find type registration`

1. İlgili `[Module]Installer.Install()` içinde `builder.Register<T>()` var mı?
2. O installer `AppInstaller.asset → _modules` listesinde mi?
3. Bağımlılığı isteyen scope, register eden scope'u görebiliyor mu? (parent/child ilişkisi)

### `[Inject] method never called`

MonoBehaviour scope'a bildirilmemiş:
```csharp
builder.RegisterComponentInHierarchy<MyMonoBehaviour>();
```

### `IInitializable.Initialize()` never called

```csharp
builder.Register<MyService>(Lifetime.Singleton)
    .As<IMyService>()
    .AsImplementedInterfaces();
```

### Circular dependency

A → B → A. VContainer build time'da fırlatır. Çözüm: ortak concern'i üçüncü bir servis C'ye taşı ya da `IEventBus` kullan.

### `RegisterBuildCallback`

Container build'i tamamlandıktan sonra resolved instance'lara erişmek için:

```csharp
builder.RegisterBuildCallback(container =>
{
    EventBusAccessor.Initialize(container.Resolve<IEventBus>());
});
```

---

## Rules (Non-Negotiable)

| Rule | Why |
|------|-----|
| `.AsImplementedInterfaces()` kullan | `IInitializable`, `IDisposable` lifecycle'ları otomatik kapsar |
| Her zaman interface'e register et | Caller contract'a bağımlı olur, implementasyona değil |
| `AppScope.cs` asla değişmez | Yeni modül → `AppInstaller.asset`'e installer ekle |
| `EventBusInstaller` listede ilk | Diğer tüm modüller `IEventBus`'a bağımlı — önce register edilmeli |
| Config null guard'ı `LogError + return` | `throw` build context'te crash riski taşır |
| `OnDestroy()` yerine `Dispose()`'da unsubscribe | VContainer scope destroy'dan önce dispose eder |
| `FindObjectOfType` / `GetComponent` servis için kullanma | DI'yi bypass eder, hidden coupling yaratır |
