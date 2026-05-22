---
name: bootstrap-pattern
description: Bootstrap & Installer katman yapısı — IInstaller → ModuleInstaller → [Module]Installer → AppInstaller → AppScope hiyerarşisi, yeni modül ekleme akışı, EventBusInstaller zorunluluğu. Yeni bir modül eklerken, installer yazarken, AppScope veya AppInstaller'a dokunmayı düşünürken, VContainer kayıt yapısını kurarken bu skill'i kullan. AppScope.cs asla değişmez — sadece AppInstaller.asset güncellenir.
model-tier: normal
---

# Bootstrap & Installer Pattern

## Katman Yapısı

```
IInstaller (interface)          ← _Framework/Installers/
    ↑
ModuleInstaller (abstract SO)   ← _Framework/Installers/
    ↑
[Module]Installer (sealed SO)   ← _GameFolders/Scripts/Games/Concretes/[Domain]/
    ↑
AppInstaller (sealed SO)        ← _GameFolders/Scripts/Games/Concretes/Infrastructure/
    ↑
AppScope (LifetimeScope)        ← Bootstrap sahnesi — AppInstaller'ı çağırır
```

## IInstaller

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

## ModuleInstaller

```csharp
// _Framework/Installers/ModuleInstaller.cs
public abstract class ModuleInstaller : ScriptableObject, IInstaller
{
    public abstract void Install(IContainerBuilder builder);
}
```

`ScriptableObject` içerdiği için `_Framework/Installers/` altında yaşar — `Games/Abstracts/` değil.

## [Module]Installer

```csharp
[CreateAssetMenu(menuName = "Game/Installers/Audio", fileName = "AudioInstaller")]
public sealed class AudioInstaller : ModuleInstaller
{
    #region Fields

    [SerializeField] private AudioConfiguration _config;

    #endregion

    #region ModuleInstaller

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
        {
            Debug.LogError("[AudioInstaller] AudioConfiguration is missing.", this);
            return;
        }

        builder.RegisterInstance(_config);
        builder.Register<AudioService>(Lifetime.Singleton)
            .AsImplementedInterfaces();
    }

    #endregion
}
```

**Kurallar:**
- Config null → `Debug.LogError` + `return` (throw değil)
- `.AsImplementedInterfaces()` — lifecycle interface'leri otomatik kapsar
- `[CreateAssetMenu]` format: `"Game/Installers/[ModuleName]"`

## EventBusInstaller (her projede zorunlu, listede ilk)

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

`AppInstaller._modules` listesinde **daima ilk sıradadır**.

## AppInstaller

```csharp
[CreateAssetMenu(menuName = "Game/Infrastructure/App Installer", fileName = "AppInstaller")]
public sealed class AppInstaller : ScriptableObject, IInstaller
{
    #region Fields

    [SerializeField] private List<ModuleInstaller> _modules = new();

    #endregion

    #region Public Methods

    public void Install(IContainerBuilder builder)
    {
        foreach (var module in _modules)
        {
            if (module == null) continue;
            module.Install(builder);
        }
    }

    #endregion
}
```

`List<ModuleInstaller>` kullanılır (array değil) — Inspector'da sıralama kolaylığı için.

## AppScope

```csharp
public sealed class AppScope : LifetimeScope
{
    #region Fields

    [SerializeField] private AppInstaller     _appInstaller;
    [SerializeField] private AppConfiguration _appConfiguration;

    #endregion

    #region Lifecycle

    protected override void Configure(IContainerBuilder builder)
    {
        if (_appConfiguration == null) { Debug.LogError("[AppScope] AppConfiguration missing."); return; }
        if (_appInstaller == null)     { Debug.LogError("[AppScope] AppInstaller missing."); return; }

        builder.RegisterInstance(_appConfiguration);
        builder.RegisterComponentInHierarchy<UIRoot>();
        builder.RegisterComponentInHierarchy<AudioRoot>();

        _appInstaller.Install(builder);

        builder.RegisterBuildCallback(container =>
        {
            EventBusAccessor.Initialize(container.Resolve<IEventBus>());
        });
    }

    #endregion
}
```

**AppScope.cs asla değişmez** — yeni modül eklemek için `AppInstaller.asset`'e installer eklenir.

## Yeni Modül Ekleme Akışı

1. `[Module]Installer.cs` yaz — `ModuleInstaller`'dan türet, `[CreateAssetMenu]` ekle
2. Unity'de asset oluştur: `Assets → Create → Game/Installers/[ModuleName]`
3. Inspector'da config ScriptableObject'ini ata
4. `AppInstaller.asset` → `_modules` listesine ekle
5. `AppScope.cs`'e **dokunma**

## Klasör Yapısı

```
_Framework/Installers/
├── IInstaller.cs
└── ModuleInstaller.cs

_GameFolders/Scripts/Games/Concretes/Infrastructure/
├── AppInstaller.cs
└── AppScope.cs

_GameFolders/Scripts/Games/Concretes/[Domain]/
└── [Domain]Installer.cs
```

## Yaygın Hatalar

| Hata | Çözüm |
|------|-------|
| `EventBus` `AppScope.Configure()` içinde doğrudan register | `EventBusInstaller` oluştur, listede ilk sıraya koy |
| Yeni modül için `AppScope.cs` değiştiriliyor | `AppInstaller.asset`'e installer ekle — `AppScope.cs` değişmez |
| `ModuleInstaller` `GameFolders/Abstracts/` altında | `ScriptableObject` içerdiği için `_Framework/Installers/` altında olmalı |
| `throw` ile null guard | `Debug.LogError` + `return` kullan |
| `.As<IEventBus>()` tek interface | `.AsImplementedInterfaces()` kullan |
