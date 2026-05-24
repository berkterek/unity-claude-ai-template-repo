# Bootstrap & Installer Pattern (NON-NEGOTIABLE)

## Katman Yapısı

```
IInstaller (interface)          ← Framework katmanı
    ↑
ModuleInstaller (abstract SO)   ← Framework katmanı — ScriptableObject + IInstaller
    ↑
[Module]Installer (sealed SO)   ← Game katmanı — tek modülün kayıtlarını yapar
    ↑
AppInstaller (sealed SO)        ← Game katmanı — modülleri listeler, sırayla çağırır
    ↑
AppScope (LifetimeScope)        ← Bootstrap sahnesi — AppInstaller'ı çağırır, sahne altyapısını register eder
```

---

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

- Pure C# interface — `using VContainer` gerekmez, `IContainerBuilder` parametresi yeterli
- `ModuleInstaller` ve `AppInstaller` her ikisi de bu interface'i implement eder

---

## ModuleInstaller

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

- `ScriptableObject` içerdiği için `_Framework/Installers/` altında yaşar (`Games/Abstracts/` değil — `check-pure-csharp.sh` bloklardı)
- Her `[Module]Installer` bu sınıftan türer
- Soyut — doğrudan instance alınamaz

---

## AppInstaller

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppInstaller.cs
using System.Collections.Generic;
using Framework.Installers;
using UnityEngine;
using VContainer;

namespace Game.Concretes.Infrastructure
{
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
}
```

**Kurallar:**
- `AppInstaller` sadece listeyi iterate eder — hiçbir şeyi doğrudan register etmez
- Modül sırası önemlidir: `EventBusInstaller` her zaman listenin **ilk** elemanıdır
- Null modüller sessizce atlanır — eksik slot build'i patlatmaz
- `List<ModuleInstaller>` kullanılır, array değil — Inspector'da sıralama kolaylığı için

---

## [Module]Installer

Her modülün kendi `ModuleInstaller` alt sınıfı vardır.

```csharp
// _GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs
using Framework.Installers;
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Audio
{
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
}
```

**Kurallar:**
- Config null ise `Debug.LogError` + `return` — `throw` kullanma (build context'te crash istemiyoruz)
- `.AsImplementedInterfaces()` kullan — `IInitializable`, `IDisposable` gibi lifecycle interface'leri otomatik register eder
- `[CreateAssetMenu]` path formatı: `"Game/Installers/[ModuleName]"`
- Bir installer yalnızca kendi modülünün bağımlılıklarını register eder — başka modüllere dokunmaz

### EventBusInstaller (her projede zorunlu, listede ilk)

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

- Config tutmaz — `EventBus`'ın config'i yoktur
- `.AsImplementedInterfaces()` ile `IEventBus`, `IInitializable`, `IDisposable` hepsi register edilir
- `AppInstaller._modules` listesinde **daima ilk sıradadır**

---

## AppScope

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppScope.cs
using Framework.Bootstrap;
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class AppScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private AppInstaller     _appInstaller;
        [SerializeField] private AppConfiguration _appConfiguration;

        #endregion

        #region Lifecycle

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

        #endregion
    }
}
```

**Kurallar:**
- `AppScope.cs` **asla değişmez** — yeni modül eklemek için `AppInstaller.asset`'e modül eklenir
- `EventBus` burada doğrudan register edilmez — `EventBusInstaller` bunu yapar
- Sahne altyapısı (`UIRoot`, `AudioRoot`) `RegisterComponentInHierarchy` ile register edilir — bu bileşenler sahnede fiziksel olarak bulunur
- Null guard'lar `Debug.LogError` + `return` — `Configure()` yarım kalır ama Unity crash etmez

---

## GameScope — Sahne Bazlı Wiring (NON-NEGOTIABLE)

`GameScope`, Game sahnesine özgü bağımlılıkları (sahne üzerindeki prefab referansları) register eder. AppScope'tan farklı olarak **tüm referansları `[SerializeField]` ile sahnede manuel atanır** — ScriptableObject almaz.

### AppScope vs GameScope Farkı

| | AppScope | GameScope |
|--|----------|-----------|
| Referans tipi | ScriptableObject (asset) | Sahne üzerindeki prefab instance |
| Prefab olarak kaydedilir mi? | Evet — `Prefabs/Bootstrap/` | Evet — `Prefabs/Bootstrap/` |
| Referanslar nerede atanır? | Prefab üzerinde (Inspector'da asset sürüklenir) | Sahnedeki instance üzerinde (Inspector'da sahne objesi sürüklenir) |
| `Configure()` içeriği | `_appInstaller.Install(builder)` + altyapı kayıtları | `[SerializeField]` alanları doğrudan `builder.RegisterInstance(...)` ile register edilir |
| Değişir mi? | `AppScope.cs` asla değişmez | Yeni modül eklenince `GameScope.cs`'e `[SerializeField]` eklenir |

### GameScope Örneği

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/GameScope.cs
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class GameScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private PlayerProvider _playerProvider;
        [SerializeField] private UIRoot         _uiRoot;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            if (_playerProvider == null)
            {
                Debug.LogError("[GameScope] PlayerProvider is missing.");
                return;
            }

            builder.RegisterComponent(_playerProvider);
            builder.RegisterComponent(_uiRoot);
        }

        #endregion
    }
}
```

### Kurulum Akışı

1. `GameScope.prefab` oluştur → `_GameFolders/Prefabs/Bootstrap/` altına kaydet
2. Prefab üzerinde `Parent` alanını `AppScope` olarak işaretle (VContainer parent scope)
3. Game sahnesine `GameScope.prefab` instance'ını yerleştir → `[Setup]` container'ı altına
4. **Sahnedeki instance üzerinde** `[SerializeField]` alanlarını sahne objeleriyle doldur — prefab üzerinde değil
5. Yeni sahne objesi eklenince: `GameScope.cs`'e yeni `[SerializeField]` ekle → sahnede instance'ı güncelle

### Kurallar

- `GameScope.cs`'te `builder.Register<T>(...)` **yasaktır** — pure C# servisler AppScope üzerinden `AppInstaller` ile register edilir
- `GameScope` yalnızca `builder.RegisterComponent(...)` kullanır — sahne üzerindeki MonoBehaviour'ları container'a bildirir
- Prefab üzerindeki `[SerializeField]` alanları boş kalır; her sahnede instance bazlı doldurulur
- `Debug.LogError` + `return` guard — null sahne objesi build'i crashlememeli

---

## Yeni Modül Ekleme Akışı (NON-NEGOTIABLE)

1. `[Module]Installer.cs` yaz — `ModuleInstaller`'dan türet, `[CreateAssetMenu]` ekle
2. Unity'de asset oluştur: `Assets → Create → Game/Installers/[ModuleName]`
3. Inspector'da config ScriptableObject'ini ata
4. `AppInstaller.asset` aç → yeni installer'ı `_modules` listesine ekle
5. `AppScope.cs`'e **dokunma**

---

## Klasör Yapısı

```
_Framework/
└── Installers/
    ├── IInstaller.cs          ← interface
    └── ModuleInstaller.cs     ← abstract base

_GameFolders/
├── Scripts/Games/Concretes/Infrastructure/
│   ├── AppInstaller.cs        ← modül listesi
│   └── AppScope.cs            ← bootstrap scope
└── Scripts/Games/Concretes/[Domain]/
    └── [Domain]Installer.cs   ← modüle özgü installer
```

---

## Yaygın Hatalar

| Hata | Çözüm |
|------|-------|
| `EventBus` `AppScope.Configure()` içinde doğrudan register ediliyor | `EventBusInstaller` oluştur, `AppInstaller` listesine ilk sıraya ekle |
| `AppScope` yeni modül register etmek için değiştiriliyor | `AppInstaller.asset`'e yeni installer ekle — `AppScope.cs` değişmez |
| `ModuleInstaller` `GameFolders/Abstracts/` altında | `ScriptableObject` içerdiği için `_Framework/Installers/` altında olmalı |
| `Debug.LogError` yerine `throw` kullanılıyor | Config null guard'da `return` + `LogError` — build context crash riski |
| `.As<IEventBus>()` ile tek interface register | `.AsImplementedInterfaces()` kullan — lifecycle interface'leri de kapsar |
| `AppInstaller._modules` array olarak tanımlı | `List<ModuleInstaller>` kullan — Inspector'da sıralama desteği için |
