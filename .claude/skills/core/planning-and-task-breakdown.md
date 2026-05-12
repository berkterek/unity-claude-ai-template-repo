---
name: planning-and-task-breakdown
description: Task decomposition discipline for /create-plan and /plan-workflow. Vertical slice, per-task acceptance criteria, and checkpoints. Enhances existing planning pipelines.
model-tier: heavy
---

# Planning and Task Breakdown (Unity)

## Genel Bakış

Çalışmayı küçük, doğrulanabilir görevlere ayır — her birinin açık acceptance criteria'sı olsun. İyi task breakdown, güvenilir çıktı üreten agent ile karmaşık bir karmaşa üreten agent arasındaki farktır. Her task; tek odaklı bir oturumda implemente edilebilir, test edilebilir ve doğrulanabilir boyutta olmalı.

## Ne Zaman Kullanılır

- `/create-plan` veya `/plan-workflow` çağrıldığında
- Bir task başlamak için çok büyük veya belirsiz göründüğünde
- Paralel agent çalışması planlanırken
- WORKFLOW.md oluşturulmadan önce

## Planlama Süreci

### Adım 1: Plan Moduna Gir (Sadece Okuma)

Kod yazmadan önce:

- Spec dosyasını ve ilgili codebase bölümlerini oku
- Mevcut pattern'ları ve kuralları tespit et (CLAUDE.md, architecture.md)
- Bileşenler arası bağımlılıkları haritala
- Riskleri ve bilinmezleri not et

**Planlama sırasında kod yazma.** Çıktı bir plan dokümanıdır, implementasyon değil.

### Adım 2: Bağımlılık Grafiğini Çiz

Ne neye bağımlı, haritala:

```
IEnemyService (interface)
    │
    ├── EnemyService (implementasyon)
    │       │
    │       ├── EnemyInstaller (VContainer kaydı)
    │       │
    │       └── EnemyTests (test)
    │
    └── EnemyProvider (MonoBehaviour — Unity API)
            │
            └── EnemyAuthoring (ECS baker, varsa)
```

Uygulama sırası bağımlılık grafiğini aşağıdan yukarıya takip eder: önce temeller.

### Adım 3: Dikey Dilimlere Böl (Vertical Slice)

Tüm interface'leri, sonra tüm service'leri, sonra tüm installer'ları yazmak yerine — bir özellik yolunu baştan sona inşa et:

**Kötü (yatay dilimleme):**
```
Task 1: Tüm interface'leri yaz
Task 2: Tüm service'leri yaz
Task 3: Tüm installer'ları yaz
Task 4: Her şeyi bağla
```

**İyi (dikey dilimleme):**
```
Task 1: Düşman spawn olur (IAudioService → AudioService → AudioInstaller → test)
Task 2: Düşman hasar alır (IHealthService → HealthService → Installer → test)
Task 3: Düşman ölür (IDeathService → DeathService + event → test)
Task 4: Düşman animasyonu tetiklenir (Provider + ECS bridge)
```

Her dikey dilim, çalışan ve test edilebilir bir işlev sunar.

### Adım 4: Görevleri Yaz

Her görev bu yapıyı takip eder:

```markdown
## Task [N]: [Kısa açıklayıcı başlık]

**Açıklama:** Bu görevin neyi başardığını açıklayan bir paragraf.

**Acceptance Criteria:**
- [ ] [Spesifik, test edilebilir koşul]
- [ ] [Spesifik, test edilebilir koşul]
- [ ] Test yeşil: `dotnet test --filter "ClassName"`
- [ ] Compile hatasız

**Bağımlılıklar:** [Bu görevin bağımlı olduğu görev numaraları veya "Yok"]

**Muhtemelen etkilenecek dosyalar:**
- `_GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs`
- `_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs`
- `_GameFolders/Scripts/Tests/AudioTests/AudioServiceTests.cs`

**Tahmini kapsam:** [Küçük: 1-2 dosya | Orta: 3-5 dosya | Büyük: 5+ dosya]
```

### Adım 5: Sırala ve Checkpoint Ekle

Görevleri şu şekilde düzenle:

1. Bağımlılıklar karşılandı (önce temel)
2. Her görev sistemi çalışır durumda bırakır
3. Her 2-3 görev sonrası doğrulama checkpoint'i
4. Yüksek riskli görevler erken (hızlı başarısız ol)

Checkpoint'ler açık olsun:

```markdown
## Checkpoint: Task 1-3 Sonrası
- [ ] Tüm testler yeşil
- [ ] Unity compile hatasız
- [ ] Temel oyuncu akışı uçtan uca çalışıyor
- [ ] İlerlemeden önce insan onayı
```

## Görev Boyutu Rehberi

| Boyut | Dosya | Kapsam | Örnek |
|-------|-------|--------|-------|
| **XS** | 1 | Tek method veya config | Validation kuralı ekle |
| **S** | 1-2 | Tek component veya servis | Yeni bir event struct yaz |
| **M** | 3-5 | Bir feature dilimi | AudioService + Installer + test |
| **L** | 5-8 | Çok bileşenli özellik | Tam spawn sistemi |
| **XL** | 8+ | **Çok büyük — daha küçüğe böl** | — |

**Görevi daha küçüğe böl eğer:**
- Task başlığında "ve" geçiyorsa (iki görev işareti)
- Acceptance criteria 3 maddeden fazlaysa
- İki veya daha fazla bağımsız sisteme dokunuyorsa
- VContainer scope değişikliği + ECS değişikliği + UI değişikliği aynı anda

## WORKFLOW.md Şablonu

```markdown
# Uygulama Planı: [Özellik/Proje Adı]

## Genel Bakış
[Ne inşa ettiğimizin bir paragraflık özeti]

## Mimari Kararlar
- [Temel karar 1 ve gerekçe — veya ADR referansı]
- [Temel karar 2 ve gerekçe]

## Görev Listesi

### Faz 1: Temel Altyapı
- [ ] Task 1: ...
- [ ] Task 2: ...

### Checkpoint: Temel Altyapı
- [ ] Testler yeşil, compile temiz

### Faz 2: Çekirdek Özellikler
- [ ] Task 3: ...
- [ ] Task 4: ...

### Checkpoint: Çekirdek Özellikler
- [ ] Uçtan uca akış çalışıyor

### Faz 3: Entegrasyon
- [ ] Task 5: ...

### Checkpoint: Tamamlandı
- [ ] Tüm acceptance criteria karşılandı
- [ ] İncelemeye hazır

## Riskler ve Önlemler
| Risk | Etki | Önlem |
|------|------|-------|
| ECS migration sırasında scene referansı kaybolabilir | Yüksek | Önce test scene'de dene |

## Açık Sorular
- [İnsan girdisi gereken soru]
```

## Paralelleştirme Fırsatları

Birden fazla agent veya oturum varsa:

- **Paralelleştirebilir:** Bağımsız feature dilimleri, mevcut implementasyon için testler, dokümantasyon
- **Sıralı olmalı:** Database/schema migrasyonları, paylaşılan state değişiklikleri, bağımlılık zincirleri
- **Koordinasyon gerektirir:** Ortak interface kullanan özellikler (önce interface'i sabitle, sonra paralelleştir)

WORKFLOW.md'de `parallel_group` annotation'ı kullan — `/orchestrate` bunu otomatik algılar.

## Yaygın Bahaneler

| Bahane | Gerçek |
|--------|--------|
| "Geliştirirken çözerim" | Böyle karmaşık kod üretilir ve yeniden yazılır. 10 dakika planlama saatlerce kurtarır. |
| "Görevler belli" | Yine de yaz. Açık görevler gizli bağımlılıkları ve unutulan edge case'leri ortaya çıkarır. |
| "Planlamak fazladan iş" | Planlama görevin ta kendisi. Plan olmadan implementasyon sadece yazmaktır. |
| "Hepsini aklımda tutabilirim" | Context window sonludur. Yazılı planlar oturum sınırlarını aşar. |

## Doğrulama Listesi

Implementasyona başlamadan önce:

- [ ] Her görevin acceptance criteria'sı var
- [ ] Her görevin doğrulama adımı var (test komutu veya manuel kontrol)
- [ ] Görev bağımlılıkları belirlendi ve sıralandı
- [ ] Hiçbir görev ~5 dosyadan fazlasına dokunmuyor
- [ ] Ana fazlar arasında checkpoint'ler var
- [ ] Paralel çalışabilecek görevler `parallel_group` ile işaretlendi
- [ ] İnsan plan dokümanını onayladı
