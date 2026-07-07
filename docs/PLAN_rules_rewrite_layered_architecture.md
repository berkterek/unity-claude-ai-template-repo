# PLAN — Rules Rewrite: Layered Architecture (Mono Kabuk / Handler / Service / Provider)

> **Version:** v1 — 2026-07-07
> **Status:** ✅ COMPLETED — 2026-07-07 — T1–T13 tümü review clean, improvement branch'te, merge bekliyor
> **Scope:** `.claude/rules/` (5 dosya baştan, 3 dosya revizyon), `.claude/hooks/` (2 yeni, 2 güncelleme), `_Framework/Installers/`, `/new-module`, `/setup-project`, graph extractor
> **İlişkili plan:** `PLAN_docs_pipeline_restructure.md` — **bu plan ÖNCE uygulanır** (bkz. §9)

---

## 1. Problem Tanımı

Gözlem: "Neredeyse her şey MonoBehaviour oluyor." Kuralların niyeti tersini söylüyor (servisler pure C#, Mono sadece View/Provider/Controller) ama pratikte kural seti yapısal olarak Mono'ya itiyor. Beş kök neden:

1. **Karar kapısı yok.** `solid-oop.md` Mono'nun üç rolünü tanımlıyor ama "bu sınıf Mono olmalı mı?" ilk sorusu hiçbir kuralda sorulmuyor. Roller, zaten Mono olmaya karar vermiş sınıflar için bir taksonomi.
2. **Controller sızıntısı.** `check-no-monobehaviour-in-services.sh` sadece `*Service : MonoBehaviour`'u blokluyor. `Controller` suffix'i alan her sınıf MonoBehaviour + sınırsız logic taşıyabiliyor; ~100 satır sınırı hiçbir hook'la enforce edilmiyor.
3. **Sürtünme asimetrisi.** Pure C# servis = interface + service + Installer SO + Editor'de asset + AppInstaller.asset listesi + (gerekirse) Provider → 4-6 artefakt, ikisi Editor işlemi. MonoBehaviour = 1 dosya + drag-drop. En az sürtünmeli yol her zaman kazanır.
4. **One-caller rule yanlış okunuyor.** "Tek caller varsa interface/modül kurma" → pratikte "o zaman Mono yap" olarak yorumlanıyor. Kuralın kastı seremoniyi önlemekti, pure C#'ı yasaklamak değil.
5. **Örnek çekimi.** Kurallardaki tam boy, kopyalanabilir örnekler ağırlıkla Mono (InputView, MainMenuView, BasicAudioProvider, FadeView). Pure C# örnekleri fragment seviyesinde. LLM coder en zengin örüntüye benzetir.

Ek eksik: **VContainer EntryPoint sistemi (`ITickable`/`IStartable`/`IFixedTickable`) kurallarda hiç geçmiyor.** "Update lazım → Mono yaptım" kaçışının doğrudan cevabı bu.

İkinci sorun — installer zinciri: `ModuleInstaller (SO)` → `[Module]Installer (SO asset)` → `AppInstaller (SO asset, sıralı liste)` → `AppScope`. Modül eklemek Editor asset işlemi gerektiriyor (agent'ın en zayıf işlem türü), asset diff'leri review edilemiyor, `AppInstaller.asset` merge-conflict mıknatısı, "EventBus ilk sırada" kuralı sadece konvansiyon, null slot **sessizce atlanıyor** (reponun silent-failure doktrinine aykırı).

Üçüncü sorun — TDD uyumsuzluğu: `testing.md` "sadece interface mock'lanır" diyor (NSubstitute concrete mock'layamaz), ama one-caller rule interface'leri geciktiriyor. Tester agent testi önce yazar; seam yoksa TDD akışı tıkanır. Agent'lar "sonra interface eklerim" refactor'ünü yapmaz.

---

## 2. Hedef Model — 4 Katman

```
┌─ Tier 1: Mono Kabuk (Controller / View) ──────────────────────────────┐
│  MonoBehaviour. Ref cache'ler ([SerializeField]), handler kurar,      │
│  lifecycle iletir (Update → handler.Tick(dt)). SIFIR dallanma/hesap.  │
│  Interface ALMAZ (kimse kabuğu mock'lamaz). Hedef ≤ ~80 satır.        │
├─ Tier 2: Handler (prefab-yerel logic) ────────────────────────────────┤
│  Pure C# sınıf (Mono DEĞİL). Unity ref'leri (Rigidbody, Transform)    │
│  constructor'dan alır — Unity API'ye dokunabilir, bu bilinçli.        │
│  Prefab'la doğar, prefab'la ölür; prefab dışından referans YASAK.     │
│  Her handler'ın interface'i vardır (IMoveHandler) → NSubstitute seam. │
├─ Tier 3: Service + EntryPoint (cross-module logic) ───────────────────┤
│  Pure C#, UnityEngine API YOK (math tipleri serbest). VContainer ile  │
│  register. Update ihtiyacı → ITickable/IStartable (RegisterEntryPoint)│
│  — "Update lazım" artık Mono gerekçesi DEĞİL. Interface-first.        │
├─ Tier 4: Provider (cross-module Unity API sınırı) ────────────────────┤
│  Mevcut haliyle kalır: Service'in ihtiyaç duyduğu Unity API'yi sarar. │
│  Prefab-yerel Unity erişimi için Provider AÇILMAZ — o iş Handler'ın.  │
└───────────────────────────────────────────────────────────────────────┘
```

### 2.1 Karar kapısı (yeni Card 0 — solid-oop.md'nin ilk kuralı)

Bir sınıf **ancak** şunlardan en az biri varsa MonoBehaviour olabilir:

| Gerekçe | Örnek |
|---------|-------|
| (a) Inspector'dan sahne/prefab referansı cache'leyecek | Controller kabuk |
| (b) Unity callback alacak (collision, trigger, UGUI event) | Controller, View |
| (c) Cross-module Unity API sınırı | Provider |
| (d) Canvas UI | View |

**"Update lazım" geçerli gerekçe değildir** — prefab-yerel ise Handler.Tick (Controller iletir), global ise ITickable. Bu kapıdan geçmeyen her sınıf pure C#'tır.

### 2.2 Interface-first politikası (one-caller rule'un yeniden kapsamlanması)

- **Test bir caller'dır.** Injectable katmanlar (Handler, Service, Provider) her zaman interface ile doğar — TDD/NSubstitute seam'i için.
- One-caller rule şuna daralır: "tek caller için ayrı **modül/kayıt seremonisi** kurma" — concrete, mevcut modülün installer'ına register edilebilir.
- Interface ALMAYANLAR: Mono kabuklar, config SO'lar, event struct'ları, data/model sınıfları (model'i tüketen test model'in kendisini kullanır).

### 2.3 Handler kuralları

```csharp
// Game/Abstracts/Players/IMoveHandler.cs
public interface IMoveHandler
{
    void SetInput(Vector2 input);
    void Tick(float deltaTime);
}

// Game/Concretes/Players/MoveHandler.cs — Mono DEĞİL, sealed
public sealed class MoveHandler : IMoveHandler
{
    private readonly Rigidbody _rigidbody;        // Unity ref constructor'dan
    private readonly MoveConfiguration _config;

    public MoveHandler(Rigidbody rigidbody, MoveConfiguration config) { ... }

    public void SetInput(Vector2 input) { ... }
    public void Tick(float deltaTime) { /* hız hesabı + _rigidbody'ye uygulama */ }
}
```

- Handler'lar **birbirini görmez** — koordinasyon Controller'da (öneri; açık soru §8.2)
- Handler prefab dışından referans alınamaz; ikinci tüketici çıktığı an → Service'e terfi
- Kuruluş iki yolla:

| Handler'ın ihtiyacı | Kurulum | Yer |
|---|---|---|
| Sadece prefab bileşenleri | `new MoveHandler(_rigidbody, ...)` | Controller.Awake (injection'sız kurulum Awake'te serbest — mevcut kuralla uyumlu) |
| + container bağımlılığı (IEventBus, config) | VContainer factory: `Func<Rigidbody, IMoveHandler>` inject edilir | Factory kaydı modülün installer'ında |

Factory **zorunlu değil** — container bağımlılığı yoksa düz `new`. Her handler'a factory = installer seremonisinin geri gelmesi.

### 2.4 Controller kabuk örneği

```csharp
public sealed class PlayerController : MonoBehaviour
{
    #region Fields
    [SerializeField] private Rigidbody _rigidbody;
    private IMoveHandler _moveHandler;
    private IJumpHandler _jumpHandler;
    #endregion

    #region Lifecycle
    [Inject]
    public void Construct(Func<Rigidbody, IMoveHandler> moveFactory) { _moveHandler = moveFactory(_rigidbody); }

    private void Awake()  => _jumpHandler = new JumpHandler(_rigidbody);   // container dep'i yok
    private void Update() => _moveHandler.Tick(Time.deltaTime);            // SADECE iletim
    #endregion
}
```

Kabuk ihlali örnekleri (kural WRONG bloklarına girecek): Update içinde if/hesap, kabukta state alanı (skor, cooldown), kabuğun IEventBus publish etmesi (handler/service'in işi).

### 2.5 EntryPoint (global Update ihtiyacı)

```csharp
public sealed class WaveDirectorService : IWaveDirectorService, ITickable, IDisposable
{
    public void Tick() { ... }   // VContainer her frame çağırır — Mono YOK
}
// Modül installer'ında:
builder.RegisterEntryPoint<WaveDirectorService>().AsImplementedInterfaces();
```

### 2.6 Code-first installer (bootstrap-pattern.md'nin yeni omurgası)

SO installer zinciri kalkar. Yerine:

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs
public static class AppModules
{
    public static void Install(IContainerBuilder builder, ConfigCatalog configs)
    {
        EventBusModule.Install(builder);                 // İLK — yapısal garanti, konvansiyon değil
        AudioModule.Install(builder, configs.Audio);
        PlayerModule.Install(builder, configs.Player);
        // yeni modül = buraya bir satır (git diff'te görünür, hook'lanabilir)
    }
}

// Game/Concretes/Audio/AudioModule.cs — pure C# static
public static class AudioModule
{
    public static void Install(IContainerBuilder builder, AudioConfiguration config)
    {
        if (config == null) { Debug.LogError("[AudioModule] AudioConfiguration missing."); return; }
        builder.RegisterInstance(config);
        builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();
        builder.RegisterFactory<Rigidbody, IMoveHandler>(...);   // handler factory'leri de burada
    }
}

// Tek config asset'i — SO'ların tek meşru görevi buraya toplanır
[CreateAssetMenu(menuName = "Game/Config Catalog", fileName = "ConfigCatalog")]
public sealed class ConfigCatalog : ScriptableObject
{
    [SerializeField] private AudioConfiguration  _audio;
    [SerializeField] private PlayerConfiguration _player;
    public AudioConfiguration  Audio  => _audio;
    public PlayerConfiguration Player => _player;
}

// AppScope — hâlâ hiç değişmez
protected override void Configure(IContainerBuilder builder)
{
    if (_configCatalog == null) { Debug.LogError("[AppScope] ConfigCatalog missing."); return; }
    builder.RegisterInstance(_configCatalog);
    builder.RegisterComponentInHierarchy<UIRoot>();
    AppModules.Install(builder, _configCatalog);
    builder.RegisterBuildCallback(c => EventBusAccessor.Initialize(c.Resolve<IEventBus>()));
}
```

Kazanımlar: modül eklemek = 1 C# satırı (Editor'süz, agent-dostu, review edilebilir); sıra kodda açık; null config `LogError` ile **gürültülü**; `AppInstaller.asset` merge conflict'i tarihe karışır. Kayıp: Inspector'dan modül sıralama (agent-öncelikli template'te değeri yok). Reflection/attribute auto-discovery bilinçli reddedildi: IL2CPP stripping riski + implicit sihir + sıra belirsizliği.

> **Sıralama gerekçesi düzeltmesi:** VContainer'da kayıt sırası resolution'ı etkilemez (graph lazy kurulur); sıra yalnızca EntryPoint'lerin `Initialize`/`Tick` çalışma sırası için anlamlıdır. Kural metnine doğru gerekçe yazılır: "EventBus ilk kayıt" değil, "EventBus'ın `Initialize`'ı ilk koşmalı" — code-first modelde bu yapısal olarak sağlanır.

### 2.7 SceneModules — sahne-ömürlü pure C# servislerin evi

Mevcut yapıda sahne-ömürlü pure C# servisin (örn. yalnızca Game sahnesinde yaşayan `LevelTimerService`) yeri yok: ModuleInstaller'lar AppScope'a kurulur (yanlış lifetime — sahne değişince state sızar), GameScope ise yalnızca `RegisterComponent` yapabiliyor. İki kötü seçenek de sonuçta sınıfı Mono yapmaya itiyor — **Mono enflasyonunun gizli beslemelerinden biri.**

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/SceneModules.cs
public static class SceneModules
{
    public static void InstallGame(IContainerBuilder builder)
    {
        LevelTimerModule.Install(builder);   // scene-lifetime pure C# servisler
        // Game sahnesine özgü modüller buraya
    }

    public static void InstallMenu(IContainerBuilder builder) { ... }
}

// GameScope.Configure — sahne bileşenleri + sahne modülleri
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerController);   // sahne objesi (mevcut kural)
    SceneModules.InstallGame(builder);              // scene-lifetime servisler (yeni)
}
```

Kural revizyonu: "GameScope'ta `builder.Register<T>` yasak" → "GameScope'ta **inline** `Register` yasak — sahne servisleri `SceneModules` üzerinden kurulur." Scope hiyerarşisi sayesinde sahne modülleri AppScope servislerini (IEventBus vb.) resolve edebilir; sahne kapanınca scope ile birlikte dispose olur.

### 2.8 ConfigCatalog.Validate — yarım-kayıtlı container'ı önleme

Modül içi `LogError + return` guard'ı yarım-kayıtlı container üretir: hata dakikalar sonra bambaşka yerde "X resolve edilemedi" olarak patlar — sebep ile belirti kopuk. Çözüm: kurulum başında toplu doğrulama.

```csharp
// ConfigCatalog içinde
public bool Validate(out List<string> missing)
{
    missing = new List<string>();
    if (_audio == null)  missing.Add(nameof(_audio));
    if (_player == null) missing.Add(nameof(_player));
    return missing.Count == 0;
}

// AppScope.Configure başında
if (!_configCatalog.Validate(out var missing))
{
    Debug.LogError($"[AppScope] ConfigCatalog eksik alanlar: {string.Join(", ", missing)} — kurulum durduruldu.");
    return;   // TEK noktadan, TÜM eksikler listelenerek, yüksek sesle
}
```

Modül içi null-guard'lar son savunma hattı olarak kalır ama birincil mekanizma toplu Validate'tir.

### 2.9 TestScope'ta modül yeniden kullanımı — test/production wiring drift'inin sonu

Bugün `testing.md`'deki `[Feature]TestInstaller` kayıtları elle kopyalıyor: `builder.Register<PlayerService>(...)` hem production installer'da hem test installer'da ayrı yaşıyor → production kaydı değişince test installer güncellenmiyor, test yeşil ama gerçek wiring'i test etmiyor. SO installer test'te yeniden kullanılamıyordu (asset bağımlılığı). Code-first modülde drift yapısal olarak imkânsızlaşır:

```csharp
// PlayerMovementTestScope.Configure
protected override void Configure(IContainerBuilder builder)
{
    PlayerModule.Install(builder, _testPlayerConfig);   // PRODUCTION kayıt kodunun kendisi
    builder.Register<FakeInputService>(Lifetime.Singleton).As<IInputService>(); // sadece fake'ler override
}
```

Test artık production wiring'ini birebir kullanır; yalnızca senaryonun gerektirdiği fake'ler override edilir.

`GameScope`'un sahne-bileşen kaydı (`RegisterComponent` + SerializeField) aynen kalır — o problem değildi.

### 2.10 Bootstrap Flow — açılış akışı (preload → sahne geçişi)

Mevcut kurallar "Bootstrap scene bir kez açılır" der ama **akışı** tanımlamaz: preload'u kim başlatır, bittiğini kim bilir, sahneye kim geçer. Boşluk şöyle dolar:

```
Bootstrap.unity (build index 0)
├── [Setup]  AppScope.prefab (DontDestroyOnLoad)
└── [UI]     LoadingCanvas.prefab (progress bar)
```

```csharp
// Pure C# — Mono yok, Card 0 uyumlu. Container kurulunca VContainer başlatır.
public sealed class BootstrapFlow : IAsyncStartable
{
    private readonly IReadOnlyList<IPreloadStep> _steps;   // collection injection
    private readonly ISceneLoaderService _sceneLoader;
    private readonly AppConfiguration _config;

    public async UniTask StartAsync(CancellationToken ct)
    {
        for (int i = 0; i < _steps.Count; i++)
            await _steps[i].LoadAsync(_progress, ct);       // progress → LoadingCanvas
        await _sceneLoader.LoadAsync(_config.FirstScene, ct); // Menu veya Game
    }
}

// Modüler preload katkısı — her modül kendi adımını kendi Install'ında register eder
public interface IPreloadStep
{
    UniTask LoadAsync(IProgress<float> progress, CancellationToken ct);
}
// AudioModule.Install içinde:
// builder.Register<AudioPreloadStep>(Lifetime.Singleton).As<IPreloadStep>();
```

**Parçalar ve gerekçeleri:**

| Parça | Katman | Gerekçe |
|-------|--------|---------|
| `BootstrapFlow : IAsyncStartable` | Tier 3 | VContainer UniTask entegrasyonu tam bu iş için; akış tek yerde, Mono'suz |
| `IPreloadStep` | Tier 3 sözleşmesi | Preload listesi merkezi değil — her modül kendi adımıyla gelir, BootstrapFlow'a dokunulmaz (OCP) |
| `ISceneLoaderService` + `SceneLoaderProvider` | Tier 3 + 4 | `SceneManager` Unity API → provider sarar; Menu↔Game dahil tüm sahne geçişleri tek kapıdan |
| `LoadingCanvas` (View) | Tier 1 | `IProgress<float>` tüketir, sadece UI günceller |

**Kurallar:**
- "Singleton" dili düzeltilir: app-lifetime ihtiyaçlar = `DontDestroyOnLoad` AppScope + `Lifetime.Singleton` kayıt — singleton pattern'i yasak kalır.
- AppScope `DontDestroyOnLoad`; Menu single-mode yüklenince bootstrap sahnesi gider, scope yaşar; Menu/GameScope parent'ı AppScope (mevcut hiyerarşi kuralı değişmez).
- **Editor direct-play yardımcısı:** Game/Menu sahnesinden direkt Play'e basınca AppScope yoksa `RuntimeInitializeOnLoadMethod` ile bootstrap otomatik yüklenir (editor-only). Geliştirme konforu için şablona dahil.
- **Preload hata politikası (basit tutulur):** adım başarısız → `LogError` + LoadingCanvas'ta retry hook'u; sessiz devam YOK (silent-failure doktrini). Karmaşık retry/fallback mekanizması bilinçli olarak kapsam dışı.

### 2.11 Data Taksonomisi — SO / class / struct ayrımı

Saf data'nın hangi biçimde yazılacağı bugün kurallara dağılmış ve eksik. Tek karar tablosu:

| Data türü | Kim yazar, ne zaman? | Biçim | Suffix | Örnek |
|-----------|---------------------|-------|--------|-------|
| **Config** — designer ayarı, runtime'da salt-okunur | Designer, edit-time | `ScriptableObject` (ConfigCatalog'da toplanır) | `*Configuration` | `AudioConfiguration` |
| **Save data** — diske yazılır (JSON) | Runtime, persist eder | `[Serializable]` plain **class** — UnityEngine tipi İÇERMEZ | `*SaveData` | `PlayerSaveData` |
| **Runtime state** — oturum-içi mutable durum | Runtime, persist etmez | plain class (service/model tutar) | `*Model` | `ScoreModel` |
| **Event payload** — tek frame'lik mesaj | Publish anı | `readonly struct : IEvent` | `*Event` | `CoinsChangedEvent` (mevcut kural) |
| **ECS component** | System | `struct : IComponentData` | mevcut ECS kuralı | `HealthData` (mevcut kural) |

**Karar testi:** "Bunu kim, ne zaman yazıyor ve diski görmesi gerekiyor mu?"
- Designer Inspector'da yazıyor, runtime okuyor → **SO**
- Runtime yazıyor, diske gidecek → **`[Serializable]` class**
- Runtime yazıyor, oturumla ölecek → **Model class**
- Bir kez oluşup dağıtılıyor → **readonly struct**

**Kurallar:**
- **SO runtime'da mutate edilmez** (NON-NEGOTIABLE). Klasik tuzak: Editor'de SO mutation asset'e kalıcı yazılır, build'de resetlenir — iki ortamda farklı davranış. Config değeri runtime'da değişecekse: SO'dan Model'e kopyala, Model'i mutate et.
- **SaveData sınıfları UnityEngine tipi içermez** — `Vector3` yerine kendi `[Serializable]` karşılığı veya ayrık float alanlar. Gerekçe: JSON serializer bağımsızlığı + pure C# test edilebilirlik (EditMode).
- SaveData root'u **class** olur (nullable kontrol, versiyon alanı); küçük değer grupları struct olabilir. Her SaveData root'unda `int Version` alanı — ileriye dönük migration için.
- Save/load işleminin kendisi Tier 3 servistir (`ISaveService`); dosya IO'su `_Framework/SaveLoadSystems`'te kalır (mevcut yapı).

**SO'ya erişim yolları (feature-bağımsız kural):**

| Config'in kapsamı | Yol | Gerekçe |
|---|---|---|
| Cross-module / app-wide (`AudioConfiguration`) | ConfigCatalog → DI — Mono hiç tutmaz, servis/handler constructor'dan alır | Tek drag-drop noktası, `Validate()` güvencesi |
| Prefab-yerel designer ayarı (variant stats) | Kabukta `[SerializeField]`, handler'a constructor'dan | Card 6 mantığı: prefab'ın sahip olduğu şey Inspector'da bağlanır; variant başına farklı SO |
| Runtime dinamik asset yükleme | Addressables (feature açıksa); değilse ihtiyaç yeniden değerlendirilir | Resources buna da cevap değil |
| `Resources.Load` | **ASLA** (NON-NEGOTIABLE, addressables feature'ından bağımsız) | Build şişmesi, magic string → sessiz null, DI/knowledge graph'a görünmez gizli bağımlılık |

> **Kural taşıma notu:** "No Resources.Load" yasağı bugün `addressables.md` içinde yaşıyor — `addressables` feature'ı DISABLED olduğunda kural da devre dışı kalıyor ve hiçbir hook yakalamıyor (fiilen serbest). Yasak feature-bağımsız hale getirilir: bu bölüm kural kaynağı olur, `addressables.md`'de yalnızca Addressables-özel detaylar kalır.
> App-wide config'in Mono'larda `[SerializeField]` ile gezmesi de anti-pattern olarak kurala girer: aynı SO'nun N prefab'a elle sürüklenmesi = unutulan biri = sessiz null. App-wide config yalnızca ConfigCatalog'dan DI ile akar.

---

## 3. Rule Dosyası Değişiklikleri

| Dosya | Kapsam | İçerik |
|-------|--------|--------|
| `solid-oop.md` | **BAŞTAN** | Card 0 (karar kapısı §2.1), 4 katman tablosu, Handler kuralları, kabuk inceliği (WRONG/RIGHT), suffix tablosu (`*Handler` eklenir), Türkçe/İngilizce karışıklığı giderilir (tek dil: İngilizce) |
| `architecture.md` | **BAŞTAN** (kartlar korunarak yeniden örülür) | Katman modeli; Card 5 (one-caller) §2.2'ye göre yeniden yazılır; Card 6 (same-prefab SerializeField) kalır ama Handler bağlamına oturtulur; EntryPoint bölümü (yeni); handler factory pattern; tam boy pure C# service örneği (örnek çekimi dengelenir) |
| `bootstrap-pattern.md` | **BAŞTAN** | Code-first model (§2.6): AppModules, `[Module]Module` static, ConfigCatalog + `Validate()` (§2.8); **SceneModules** — GameScope sahne-ömürlü modül desteği (§2.7, "inline Register yasak" kuralının revizyonu); **Bootstrap Flow bölümü** (§2.10): BootstrapFlow, IPreloadStep, ISceneLoaderService, editor direct-play yardımcısı, preload hata politikası; SO zinciri (ModuleInstaller/AppInstaller) tamamen çıkar; EventBus sıralama gerekçesi düzeltilir (EntryPoint Initialize sırası); yeni modül ekleme akışı: 1 satır + ConfigCatalog alanı |
| `csharp-unity.md` | Revizyon | Naming tablosuna: `*Handler` (pure C#, prefab-yerel), `I*Handler`, `*Module` (static installer), `*SaveData` (`[Serializable]` class), `*Model` (runtime state); "no `new Service()` in Mono" kuralı → "no `new` **Service**; `new *Handler` sadece kabuk içinde serbest"; data taksonomisi karar tablosu (§2.11) |
| `testing.md` | Revizyon | Karar ağacına Handler satırları: Unity component tutan handler → PlayMode-Programmatic; tutmayan → EditMode; karmaşık hesap → pure metoda ayır + EditMode. "Interface mock" kuralı değişmez — interface-first bunu güçlendirir. **TestInstaller bölümü yeniden yazılır (§2.9):** elle kayıt kopyalama yerine production modülünün (`PlayerModule.Install`) TestScope'ta yeniden kullanımı + yalnızca fake override |
| `event-patterns.md` | Küçük | Handler'ların IEventBus'a factory üzerinden erişimi; kabuk publish edemez notu; cross-ref |
| `unity-input.md` | **BAŞTAN** | InputView (Mono) kaldırılır — Card 0'a göre Mono olma gerekçesi yoktu. Yerine: `InputService` (pure C#, `ITickable`, **PlayerControls'un tek sahibi** — çift-subscription garantisi Mono'dan servise taşınır) + prefab başına `InputHandler` (constructor'dan `IInputService` alır, kendi action'larını okur). Action map switching `IInputService` API'sinde merkezi kalır |
| `performance.md` | Küçük | SerializeField-first bölümü Handler bağlamıyla cross-ref |

| `scene-hierarchy.md` | Küçük | Bootstrap sahne içeriği satırı: `[Setup]` AppScope + `[UI]` LoadingCanvas (§2.10) |
| `unity-async.md` | Küçük | Bootstrapper pattern paragrafı §2.10'a cross-ref verir (kendi başına akış tarif etmeyi bırakır) |
| `serialization.md` | Küçük | Data taksonomisi cross-ref (§2.11); SaveData kuralları: UnityEngine tipi yok, `Version` alanı, SO runtime mutation yasağı |

| `addressables.md` | Küçük | "No Resources.Load" yasağı buradan çıkar (feature-bağımsız kaynağa taşınır, §2.11) — dosyada yalnızca Addressables-özel detaylar kalır |

`unity-prefabs.md`, `unity-lifecycle.md`, `ecs-dots.md` — değişmez (logic/visual ayrımı, lifecycle kuralları katman modeliyle zaten uyumlu).

---

## 4. Hook Değişiklikleri

| Hook | Tip | Değişiklik |
|------|-----|-----------|
| `check-no-monobehaviour-in-services.sh` | Güncelle (blocking) | `*Service` yanına `*Handler : MonoBehaviour` da bloklanır (handler Mono olamaz); `*Module` sınıfında `ScriptableObject` kalıtımı bloklanır |
| `check-new-service.sh` | **YENİ** (blocking) | Runtime kodda `new *Service(` / `new *Provider(` yasak; `new *Handler(` yalnızca `*Controller`/`*View` dosyası içinde serbest — başka yerde blok |
| `check-mono-justification.sh` | **YENİ** (warning) | MonoBehaviour sınıfında hiç `[SerializeField]` alanı VE hiç Unity callback'i yoksa → "bu sınıfın Mono olması için sebep yok — Card 0" uyarısı; Mono > 150 satır → kabuk şişmesi uyarısı (kural metnindeki hedef ~80) |
| `check-no-resources-load.sh` | **YENİ** (blocking) | Runtime kodda `Resources.Load` / `Resources.LoadAsync` yasak — `project-features.json`'daki `addressables` flag'inden **bağımsız** çalışır (§2.11 erişim yolları tablosu alternatifleri gösterir); Editor-only dosyalar muaf |
| `guard-critical-files.sh` | Güncelle | Kritik dosya listesine `AppModules.cs`, `ConfigCatalog.cs` eklenir; `AppInstaller` referansı çıkar |

Not: kabuk Update gövdesinde "iletim dışı logic" tespiti regex ile güvenilir değil — bu, hook yerine reviewer kriterine gider (§5).

---

## 5. Agent / Komut Değişiklikleri

| Hedef | Değişiklik |
|-------|-----------|
| `/new-module` | Yeni çıktı seti: `I[X]Service` + `[X]Service` + `[X]Configuration` + `[X]Module` (static) + `[X]Events` + `AppModules.cs`'e satır ekleme + `ConfigCatalog`'a alan ekleme. Editor adımı sadece ConfigCatalog asset'inde alan doldurma (tek asset) |
| `/setup-project` | Framework şablonları: `IInstaller` kalır (pure C#), `ModuleInstaller.cs` (SO base) silinir; `AppModules.cs` + `ConfigCatalog.cs` + `SceneModules.cs` şablonları eklenir; **Bootstrap seti** (§2.10): Bootstrap.unity + LoadingCanvas prefab + `BootstrapFlow` + `IPreloadStep` + `SceneLoaderService/Provider` + editor direct-play yardımcısı |
| `unity-reviewer` / `reviewer` kriterleri | Yeni maddeler: "Yeni MonoBehaviour Card 0 kapısından gerekçeli mi?", "Kabukta iletim dışı logic var mı?", "Handler prefab dışından referans alıyor mu?", "Yeni injectable interface'siz mi doğmuş?" |
| `graph-builder.py` (extractor) | VContainer installer tespiti SO tabanlı — static `*Module.Install` içindeki `builder.Register*` çağrılarını da parse edecek şekilde güncellenir; aksi halde `/knowledge-graph registrations` kör kalır |
| `.claude/docs/architecture-summary.md` | 4 katman özetine göre yeniden yazılır |
| `CLAUDE.md` | Rules tablosu satırları + Session Start bölümündeki pattern referansları güncellenir |

---

## 6. Görev Kırılımı

| Phase | Task | Dosyalar | parallel_group |
|-------|------|----------|----------------|
| 1 — Çekirdek kurallar | T1: solid-oop.md baştan yaz | rules/solid-oop.md | — |
| 1 | T2: architecture.md baştan yaz | rules/architecture.md | — (T1 sonrası — Card 0'a referans verir) |
| 1 | T3: bootstrap-pattern.md baştan yaz | rules/bootstrap-pattern.md | T2 ile paralel: 1 |
| 2 — Uydu kurallar | T4: csharp-unity.md naming + new kuralı | rules/csharp-unity.md | 2 |
| 2 | T5: testing.md Handler satırları | rules/testing.md | 2 |
| 2 | T6: unity-input.md baştan yaz (InputService + InputHandler modeli, §8.1) | rules/unity-input.md | 2 |
| 2 | T6b: event-patterns / performance küçük revizyonlar + cross-ref | 2 dosya | 2 |
| 3 — Enforcement | T7: hook güncellemeleri + 2 yeni hook + settings.json manuel talimatı | hooks/ | 3 |
| 3 | T8: reviewer kriterleri | agents/unity-reviewer.md, reviewer.md | 3 |
| 4 — Araçlar | T9: /new-module yeniden yaz | commands/new-module.md | 4 |
| 4 | T10: /setup-project şablon güncellemesi | commands/setup-project.md | 4 |
| 4 | T11: graph extractor static Module desteği | hooks/graph-builder.py (veya ilgili extractor) | 4 |
| 5 — Senkron | T12: architecture-summary.md + CLAUDE.md tabloları | docs/, CLAUDE.md | — (hepsinden sonra) |
| 6 — Doğrulama | T13: Smoke-test — `/new-module Dummy` üret, hook'ların doğru tetiklendiğini doğrula (Handler'ı Mono yap → blok; Service'i new'le → blok; kabuğa logic koy → reviewer yakalamalı), sonra Dummy sil | — | — |

Not: `settings.json` Claude tarafından düzenlenemez (`check-config-protection.sh`) — T7'deki yeni hook kayıtları kullanıcıya manuel talimat olarak verilir.

---

## 7. Bilinen Zayıflıklar / Riskler

1. **Interface enflasyonu:** interface-first politikası dosya sayısını artırır. Sınır net çizildi (§2.2 — kabuk/config/event/data almaz) ama reviewer disiplini gerekir.
2. **Handler'ın "pure" olmaması:** Rigidbody tutan handler EditMode'da tam test edilemez — PlayMode-Programmatic bilinçli kabul; karmaşık matematik pure metoda ayrılarak telafi edilir.
3. **`new` izninin erozyonu:** kabuk içinde `new Handler` serbestliği, hook (T7) olmadan `new Service`'e sızar — T7 bu yüzden Phase 3'te zorunlu, opsiyonel değil.
4. **Graph körlüğü:** T11 yapılmazsa `/knowledge-graph registrations` ve `/game-plan` (yeni: `/plan-module`) installer envanterini göremez — T11 kritik yol.
5. **Mevcut projelerle uyumsuzluk:** Bu template'ten türemiş eski projeler SO installer zinciri kullanıyor — bu plan yalnızca template'i günceller, eski projelere migrasyon ayrı iştir (kapsam dışı, README notu düşülür).
6. **Kabuk-logic ayrımının regex'le denetlenememesi:** enforcement'ın bir kısmı reviewer'a kalıyor — hook kadar deterministik değil.
7. **SceneModules erken kurulum riski:** sahne-ömürlü servis ihtiyacı projeye göre değişir — `SceneModules` şablonu boş başlar; ilk gerçek ihtiyaç doğana kadar içine modül eklenmez (boş altyapı ≠ zorunlu kullanım). Kural metnine "ihtiyaç yoksa boş bırak" notu düşülür.

---

## 8. Kararlar (2026-07-07 — kullanıcı ile netleştirildi)

1. **Input handler'a iner.** InputView (Mono) kaldırılır. Çift-subscription riskine karşı tasarım: `PlayerControls`'un **tek sahibi** pure C# `InputService` (`ITickable`) olur; prefab başına `InputHandler` `IInputService`'i constructor'dan alır. "Tek sahip" garantisi Mono'dan servise taşınır — kural ölmez, taşınır. Action map switching `IInputService` API'sinde merkezi kalır.
2. **Handler ↔ Handler iletişimi yok.** Koordinasyon kabukta; istisna gerekirse event üzerinden.
3. **Kabuk satır limiti:** hook uyarı eşiği **150**; kural metnindeki hedef ~80. (Bilinen zayıflık: şişmeyi geç yakalar — reviewer kriteri bunu dengeler.)
4. **Tek ConfigCatalog.** Alan sayısı ~15'i aşarsa domain kataloglarına bölme kuralı kural metnine not düşülür.
5. **Handler interface'leri `Games/Abstracts/<Domain>/`'e** — mevcut klasör kuralı değişmez, içerik türü genişler. (Konvansiyonel varsayılan; ayrıca sorulmadı.)

---

## 9. Sıralama — Diğer Planla İlişki

**Bu plan, `PLAN_docs_pipeline_restructure.md`'den ÖNCE uygulanmalı.** Gerekçe: yeni doc pipeline'ının üreteceği `design.md`'ler (modül tasarımları) katman modelini referans alacak; kurallar eskiyken üretilen ilk modül planları eski pattern'lerle (SO installer, Mono-ağırlıklı) yazılır ve hemen bayatlar. Doğru sıra:

```
1. PLAN_rules_rewrite_layered_architecture.md  (bu plan)   → kurallar + hooks + araçlar
2. PLAN_docs_pipeline_restructure.md                        → ROADMAP + modules/ + komutlar
3. İlk gerçek modül: /roadmap → /plan-module 1 → /orchestrate
```

---

## 10. Konuşmada Verilmiş Kararlar (kayıt)

- 4 katman modeli: Mono kabuk / Handler / Service+EntryPoint / Provider — **onaylandı**
- Handler'lar interface-first (TDD/NSubstitute seam) — **onaylandı** (kullanıcı talebi)
- Pure logic / Mono ayrımı kuralların omurgası olacak — **onaylandı**
- Installer yapısı elden geçecek — **onaylandı**; code-first + ConfigCatalog bu planın önerisi (uygulama onayı bekliyor)
- Factory yalnızca container bağımlılığı olan handler'larda — **önerildi**, itiraz gelmedi
- §8'deki 5 açık soru kullanıcı ile karara bağlandı (2026-07-07): input handler'a iner (InputService modeliyle), handler'lar izole, satır uyarısı 150, tek ConfigCatalog, interface'ler Abstracts'ta
- Installer derin incelemesi sonrası üç ekleme onaylandı (2026-07-07): **SceneModules** (§2.7 — sahne-ömürlü pure C# servis evi), **ConfigCatalog.Validate** (§2.8 — yarım-kayıtlı container önlemi), **TestScope'ta production modül yeniden kullanımı** (§2.9 — test/prod wiring drift'inin sonu)
- **Bootstrap Flow onaylandı** (2026-07-07, §2.10): BootstrapFlow (IAsyncStartable) + modüler IPreloadStep + ISceneLoaderService/Provider + LoadingCanvas; editor direct-play yardımcısı dahil; preload hatasında LogError + retry hook (sessiz devam yok); "singleton" ihtiyacı DontDestroyOnLoad AppScope + Lifetime.Singleton kayıt olarak karşılanır — singleton pattern'i yasak kalır
- **Data taksonomisi onaylandı** (2026-07-07, §2.11): Config → SO, SaveData → `[Serializable]` plain class (UnityEngine tipsiz, Version alanlı), runtime state → Model class, event → readonly struct; SO runtime mutation yasağı NON-NEGOTIABLE
- **SO erişim yolları onaylandı** (2026-07-07, §2.11): app-wide config → ConfigCatalog/DI, prefab-yerel → kabukta `[SerializeField]`, `Resources.Load` → ASLA (feature-bağımsız yasak + yeni `check-no-resources-load.sh` blocking hook — mevcut açık: yasak addressables.md'de yaşadığı için feature kapalıyken fiilen serbestti)
- Temiz kesim (kademeli geçiş yok), adımlar ayrı commit'lerde — docs planındaki kararla tutarlı
