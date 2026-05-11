---
name: documentation-and-adrs
description: Mimari kararları ADR (Architecture Decision Record) olarak kaydet. /adr komutuyla tetiklenir. Neden VContainer, neden struct event, neden UniTask gibi kararları docs/decisions/ klasörüne yazar.
model-tier: normal
---

# Documentation and ADRs (Unity)

## Genel Bakış

Kodu değil kararları belgele. En değerli dokümantasyon *neden* sorusunu yanıtlar — o kararı ortaya çıkaran bağlamı, kısıtlamaları ve trade-off'ları. Kod *neyin* inşa edildiğini gösterir; ADR *neden bu şekilde yapıldığını* ve *hangi alternatiflerin değerlendirildiğini* açıklar.

## Ne Zaman Kullanılır

- Önemli bir mimari karar alınırken (VContainer vs Zenject, UniTask vs Coroutine, ECS vs MonoBehaviour)
- Birbiriyle rekabet eden yaklaşımlar arasında seçim yapılırken
- Yeni bir modül, sistem veya paket eklenmeden önce
- Projeye yeni bir geliştirici (veya yeni bir Claude oturumu) başladığında "neden böyle yapılmış?" sorusunu önlemek için
- Aynı şeyi tekrar tekrar açıklarken

**Ne Zaman Kullanılmaz:** Açık kodu belgeleme. Kodu zaten anlatan yorumlar yazma. Geçici prototip kodu için ADR açma.

## Architecture Decision Records (ADRs)

ADR'lar önemli teknik kararların gerekçesini yakalar. Yazılabilecek en değerli dokümantasyon türüdür.

### ADR Ne Zaman Yazılır

- Framework, kütüphane veya büyük bağımlılık seçimi (VContainer, UniTask, Addressables, DOTS)
- Render pipeline kararı (Built-in → URP, URP → HDRP)
- Mimari pattern seçimi (ECS vs MonoBehaviour, event bus vs direct call)
- Paket versiyonu kararları (neden bu sürümde kalmak, neden upgrade)
- Geri alınması pahalı olan herhangi bir karar

### ADR Şablonu

ADR'ları `docs/decisions/` klasörüne sıralı numaralandırmayla kaydet:

```markdown
# ADR-001: VContainer Kullanımı (Zenject Yerine)

## Durum
Kabul Edildi | ADR-XXX tarafından Değiştirildi | Kullanımdan Kaldırıldı

## Tarih
2025-01-15

## Bağlam
Proje genelinde dependency injection çerçevesi gerekiyor. Temel gereksinimler:
- Unity 6 uyumluluğu
- Compile-time güvenlik (runtime reflection yerine)
- VContainer, Zenject, Manual DI

## Karar
VContainer kullanılacak.

## Değerlendirilen Alternatifler

### Zenject
- Artılar: Geniş ekosistem, çok sayıda örnek
- Eksiler: Unity 6'da bakımı yavaş, daha ağır API
- Reddedildi: VContainer performans açısından üstün ve aktif geliştirilmiş

### Manual DI (Factory + Constructor)
- Artılar: Sıfır bağımlılık, tam kontrol
- Eksiler: Scope yönetimi elle, Dispose lifecycle manuel
- Reddedildi: Kapsam ve lifecycle yönetimi project büyüdükçe karmaşıklaşır

## Sonuçlar
- AppScope → MenuScope → GameScope hiyerarşisi zorunlu
- Tüm servisler interface üzerinden kaydedilecek
- Singleton pattern tamamen kaldırıldı
```

### ADR Yaşam Döngüsü

```
ÖNERILDI → KABUL EDİLDİ → (DEĞİŞTİRİLDİ veya KALDIRILDI)
```

- **Eski ADR'ları silme.** Tarihsel bağlamı yakalarlar.
- Bir karar değişince eski ADR'a referans veren yeni bir ADR yaz.

## /adr Komutu

Kullanıcı bir mimari karar almak istediğinde:

```
/adr VContainer yerine Zenject kullanmama kararı
/adr UniTask neden Coroutine yerine seçildi
/adr Addressables ile Resources.Load karşılaştırması
/adr ECS DOTS ne zaman MonoBehaviour yerine tercih edilmeli
```

### Komut Akışı

1. `docs/decisions/` klasörünü tara — mevcut ADR sayısını bul (sonraki numara için)
2. Kullanıcıdan bağlamı al: neden bu karar şu an alınıyor?
3. En az 2 alternatif değerlendir
4. ADR dosyasını `docs/decisions/NNN-konu.md` olarak yaz
5. CLAUDE.md'deki ilgili bölüme referans ekle (gerekiyorsa)

## Unity Projesi için Örnek ADR'lar

Bir template projesinde başlangıçta oluşturulması önerilen ADR'lar:

| ADR | Konu |
|-----|------|
| ADR-001 | VContainer seçimi |
| ADR-002 | UniTask ve CancellationToken stratejisi |
| ADR-003 | IEventBus struct event pattern'ı |
| ADR-004 | Addressables — Resources.Load yasağı |
| ADR-005 | New Input System ve InputView mimarisi |
| ADR-006 | URP render pipeline seçimi |
| ADR-007 | NSubstitute + AAA test stratejisi |

## Kod İçi Dokümantasyon

### Ne Zaman Yorum Yazılır

*Neden* yorum yaz, *ne* değil:

```csharp
// YANLIŞ: Kodu tekrar eder
// counter'ı 1 artır
_retryCount++;

// DOĞRU: Açık olmayan niyeti açıklar
// VContainer Dispose() sırası garantisiz — önce unsubscribe et,
// sonra null ata. Aksi halde destroyed object callback'i tetikler.
_eventBus?.Unsubscribe<LevelStartedEvent>(OnLevelStarted);
_eventBus = null;
```

### Ne Zaman Yorum Yazılmaz

```csharp
// Açıklayan isimleri olan kodu yorumlama
public void TakeDamage(int amount) => _health -= amount;

// TODO yorumları bırakma — ya hemen yap ya da ADR'a yaz
// TODO: null check ekle  ← Hemen ekle

// Yorumlanmış kod bırakma — git history var
// private IEnumerator OldCoroutine() { ... }  ← Sil
```

### Bilinen Tuzakları Belgele

```csharp
// ÖNEMLI: Bu method AppScope.Configure() içinde çağrılmalı,
// RegisterBuildCallback'ten önce. Sonra çağrılırsa EventBusAccessor
// ilk ECS System güncellemesinde null reference verir.
// Bkz: ADR-003
public static void Initialize(IEventBus bus) => _instance = bus;
```

## CLAUDE.md ve Rules Dosyaları

AI agent bağlamı için özel dikkat:

- **CLAUDE.md** — Proje kuralları güncel tutulmalı; agent her oturumda okur
- **`.claude/rules/`** — Mimari kararlar burada kurallar olarak yansıtılmalı
- **ADR'lar** — Agent'ın geçmiş kararları "neden" anlamasını sağlar, yeniden karar vermesini önler
- **Inline gotcha'lar** — Agent'ın bilinen tuzaklara düşmesini engeller

## Yaygın Bahaneler

| Bahane | Gerçek |
|--------|--------|
| "Kod kendini açıklıyor" | Kod neyi gösterir, neden değil. Alternatifleri ve kısıtlamaları açıklamaz. |
| "API kararlı olunca yazarız" | ADR yazmak tasarımı hızlandırır. ADR, tasarımın ilk testidir. |
| "Kimse dökümantasyon okumaz" | Agent'lar okur. Gelecekteki geliştiriciler okur. 3 ay sonraki sen okursun. |
| "ADR fazladan iş" | 10 dakikalık bir ADR, 6 ay sonra aynı konuda yapılacak 2 saatlik tartışmayı önler. |

## Doğrulama Listesi

- [ ] Önemli mimari kararlar için ADR var
- [ ] Her ADR en az 2 alternatifi değerlendiriyor
- [ ] ADR numaralandırması sıralı (`docs/decisions/`)
- [ ] Bilinen tuzaklar kod içinde belgelenmiş
- [ ] Yorumlanmış kod yok
- [ ] CLAUDE.md ve rules dosyaları güncel
- [ ] ECS, URP, Input System gibi Unity-specific kararlar ADR'da gerekçelendirilmiş
