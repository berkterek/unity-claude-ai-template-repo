---
name: code-simplification
description: Chesterton's Fence discipline for /clean-slop. Understand why code was written before removing it. Reduces complexity while preserving behavior.
model-tier: normal
---

# Code Simplification (Unity)

## Genel Bakış

Tam davranışı koruyarak karmaşıklığı azalt. Amaç daha az satır değil — okumak, anlamak, değiştirmek ve debug etmek daha kolay kod. Her sadeleştirme basit bir testi geçmeli: "Yeni bir ekip üyesi bunu orijinalinden daha hızlı anlar mı?"

## Ne Zaman Kullanılır

- `/clean-slop` çağrıldığında
- Bir özellik çalışıyor ve testler yeşil, ama implementasyon olması gerekenden ağır göründüğünde
- Code review'da okunabilirlik veya karmaşıklık sorunları işaretlendiğinde
- Zaman baskısı altında yazılmış kodu refactor ederken

**Ne Zaman Kullanılmaz:**
- Kod zaten temiz ve okunabilir — sadeleştirme için sadeleştirme yapma
- Kodu henüz anlamıyorsan — önce anla, sonra sadeleştir
- Modülü tamamen yeniden yazacaksan — silinecek kodu sadeleştirmek zaman kaybı

## Beş İlke

### 1. Davranışı Tam Koru

Kodun ne yaptığını değiştirme — sadece nasıl ifade ettiğini. Tüm girdiler, çıktılar, yan etkiler, hata davranışları ve edge case'ler aynı kalmalı. Bir sadeleştirmenin davranışı koruyup korumadığından emin değilsen yapma.

```
HER DEĞİŞİKLİKTEN ÖNCE SOR:
→ Bu, her girdi için aynı çıktıyı üretiyor mu?
→ Bu, aynı hata davranışını koruyor mu?
→ Bu, aynı yan etkileri ve sıralamayı koruyor mu?
→ Tüm mevcut testler değiştirilmeden geçiyor mu?
```

### 2. Proje Kurallarını Takip Et

Sadeleştirme, kodu codebase ile daha tutarlı yapmak demektir — harici tercihler dayatmak değil. Sadeleştirmeden önce:

```
1. CLAUDE.md ve .claude/rules/ dosyalarını oku
2. Komşu kodun benzer pattern'ları nasıl ele aldığını incele
3. Projenin stilini takip et:
   - #region yapısı
   - VContainer registration pattern'ı
   - Event subscribe/unsubscribe lifecycle'ı
   - UniTask kullanım pattern'ı
   - Null check kuralları (Unity == null, not is null)
```

Proje tutarlılığını bozan sadeleştirme, sadeleştirme değil — gürültüdür.

### 3. Zekice Değil Açık Ol

Kompakt kod, ayrıştırmak için zihinsel duraklama gerektiriyorsa açık kod daha iyidir.

```csharp
// AÇIK DEĞİL: Yoğun ternary zinciri
var label = isNew ? "New" : isUpdated ? "Updated" : isArchived ? "Archived" : "Active";

// AÇIK: Okunabilir mapping
private string GetStatusLabel(EnemyState state)
{
    if (state.IsNew) return "New";
    if (state.IsUpdated) return "Updated";
    if (state.IsArchived) return "Archived";
    return "Active";
}
```

### 4. Dengeyi Koru

Sadeleştirmenin bir başarısızlık modu var: aşırı sadeleştirme:

- Çok agresif inlining — bir kavrama isim veren helper'ı kaldırmak, call site'ı daha zor okur yapar
- İlgisiz mantığı birleştirme — iki basit method'un tek karmaşık method'a birleştirilmesi basit değildir
- "Gereksiz" soyutlamayı kaldırma — bazı soyutlamalar genişletilebilirlik veya test edilebilirlik için vardır
- Satır sayısını optimize etme — daha az satır hedef değildir

### 5. Değişene Odaklan

Varsayılan olarak yakın zamanda değiştirilen kodu sadeleştir. Kapsam dışı kodun refactor'ünden kaçın — diff'te gürültü yaratır ve değiştirmeyi planlamadığın kodda regresyon riski oluşturur.

## Sadeleştirme Süreci

### Adım 1: Dokunmadan Önce Anla (Chesterton's Fence)

Herhangi bir şeyi değiştirmeden veya silmeden önce neden orada olduğunu anla. Bu Chesterton's Fence'tir: yolun üzerindeki çiti anlayamıyorsan yıkma. Önce nedenini anla, sonra sebebin hâlâ geçerli olup olmadığına karar ver.

```
SADELEŞTİRMEDEN ÖNCE YANİTLA:
- Bu kodun sorumluluğu ne?
- Kim çağırıyor? Neyi çağırıyor?
- Edge case'ler ve hata yolları neler?
- Bu davranışı tanımlayan testler var mı?
- Neden böyle yazılmış olabilir? (Performans? Platform kısıtlaması? Unity lifecycle?)
- git blame: bu kodun orijinal bağlamı neydi?
```

Bunları yanıtlayamıyorsan sadeleştirmeye hazır değilsin. Önce daha fazla bağlam oku.

**Unity'e özgü Chesterton Çitleri:**

```csharp
// Bu null check "paranoyak" görünebilir — ama Unity'de gerekli
if (_target == null) return;  // Silme: destroyed object'i kontrol eder

// Bu #if bloku gereksiz görünebilir — ama build'i kırar
#if UNITY_EDITOR
using UnityEditor;
#endif

// Bu ?.Forget() "şişirilmiş" görünebilir — ama exception'ı yutar
InitAsync(ct).Forget();  // async void değil; exception handling için kasıtlı

// Bu cache "erken optimizasyon" görünebilir — ama Update'te zorunlu
private Camera _mainCamera;  // Camera.main her çağrıda FindObjectOfType yapar
```

### Adım 2: Sadeleştirme Fırsatlarını Bul

Bu pattern'ları tara:

**Yapısal karmaşıklık:**

| Pattern | Sinyal | Sadeleştirme |
|---------|--------|-------------|
| 3+ seviye nesting | Kontrol akışını takip etmek zor | Guard clause veya helper method'a çıkar |
| 50+ satır method | Birden fazla sorumluluk | Odaklı method'lara böl |
| İç içe ternary | Zihinsel yığın gerektirir | if/else zinciri veya switch |
| Boolean flag parametreler | `DoThing(true, false, true)` | Options objesi veya ayrı method'lar |
| Tekrarlanan koşullar | Aynı if kontrolü birden fazla yerde | İyi isimlendirilmiş predicate method'a çıkar |

**İsimlendirme ve okunabilirlik:**

| Pattern | Sinyal | Sadeleştirme |
|---------|--------|-------------|
| Genel isimler | `data`, `result`, `temp`, `val` | İçeriği tanımla: `enemyStats`, `validationErrors` |
| Kısaltılmış isimler | `btn`, `evt`, `cfg` | Tam kelime kullan (`id`, `url` gibi evrensel kısaltmalar hariç) |
| "Ne" açıklayan yorumlar | `// counter'ı artır` üzerinde `_count++` | Yorumu sil — kod yeterince açık |
| "Neden" açıklayan yorumlar | `// VContainer Dispose sırası belirsiz` | Bunları koru — bu intentional bağlamdır |

**Fazlalık:**

| Pattern | Sinyal | Sadeleştirme |
|---------|--------|-------------|
| Tekrarlanan logic | Birden fazla yerde aynı 5+ satır | Paylaşılan method'a çıkar |
| Ölü kod | Erişilemeyen branch, kullanılmayan değişken | Gerçekten ölü olduğunu doğrula, sil |
| Gereksiz soyutlama | Değer katmayan wrapper | Wrapper'ı inline yap |
| Aşırı mühendislik | Factory-of-factory, tek stratejili Strategy | Basit doğrudan yaklaşımla değiştir |

### Adım 3: Değişiklikleri Artımlı Uygula

Bir seferde bir sadeleştirme yap. Her değişikten sonra testleri çalıştır.

```
HER SADELEŞTİRME İÇİN:
1. Değişikliği yap
2. Test suite'i çalıştır (Unity Test Runner veya dotnet test)
3. Testler geçiyorsa → devam et
4. Testler başarısız → geri al ve yeniden düşün
```

Birden fazla sadeleştirmeyi test edilmeden birleştirme. Bir şey bozulursa hangisinin neden olduğunu bilmen gerekir.

### Adım 4: Sonucu Doğrula

Tüm sadeleştirmelerden sonra:

```
ÖNCE VE SONRA KARŞILAŞTIR:
- Sadeleştirilmiş versiyon gerçekten daha kolay anlaşılıyor mu?
- Codebase ile tutarsız yeni pattern'lar tanıttın mı?
- Diff temiz ve incelenebilir mi?
- Bir takım arkadaşı bu değişikliği onaylar mıydı?
```

"Sadeleştirilmiş" versiyon anlamak veya incelemek için daha zorsa geri al. Her sadeleştirme girişimi başarılı olmaz.

## Unity'e Özgü Rehber

```csharp
// SADELEŞTİR: Gereksiz async wrapper
// Önce
public async UniTask<Enemy> GetEnemyAsync(CancellationToken ct)
{
    return await _spawner.SpawnAsync(ct);
}
// Sonra
public UniTask<Enemy> GetEnemyAsync(CancellationToken ct)
    => _spawner.SpawnAsync(ct);

// SADELEŞTİR: Gereksiz else branch
// Önce
public void TakeDamage(int amount)
{
    if (_health > 0)
    {
        _health -= amount;
    }
    else
    {
        return;
    }
}
// Sonra
public void TakeDamage(int amount)
{
    if (_health <= 0) return;
    _health -= amount;
}

// SADELEŞTİR: Tekrarlanan event subscribe pattern
// Önce
_eventBus.Subscribe<LevelStartedEvent>(OnLevelStarted);
_eventBus.Subscribe<LevelEndedEvent>(OnLevelEnded);
_eventBus.Subscribe<PlayerDiedEvent>(OnPlayerDied);
// Her biri ayrı yerde unsubscribe...
// Sonra: varsa proje genelinde SubcriptionList helper pattern'ını kullan
```

## Yaygın Bahaneler

| Bahane | Gerçek |
|--------|--------|
| "Çalışıyor, dokunma" | Okunması zor çalışan kod, bozulduğunda düzeltmesi de zor olacak. |
| "Daha az satır her zaman daha basittir" | 1 satırlık iç içe ternary, 5 satırlık if/else'den basit değildir. |
| "Bu ilgisiz kodu da hızlıca sadeleştiririm" | Kapsam dışı sadeleştirme diff'te gürültü yaratır ve kasıtsız regresyon riski oluşturur. |
| "Orijinal yazarın sebebi vardı" | Belki. git blame — Chesterton's Fence uygula. Ama birikmiş karmaşıklığın çoğunun sebebi yoktur. |
| "Bu özelliği eklerken refactor da yaparım" | Refactor'ü özellik çalışmasından ayır. Karışık değişiklikler incelemek, geri almak ve geçmişte anlamak için daha zordur. |

## Kırmızı Bayraklar

- Geçmesi için testleri değiştirmen gereken sadeleştirme (davranışı değiştirmişsindir)
- Orijinalden daha uzun ve anlaması daha zor "sadeleştirilmiş" kod
- Unity'e özgü null kontrolünü veya lifecycle guard'ını kaldırma
- Henüz tam anlamadığın kodu sadeleştirme
- Birçok sadeleştirmeyi tek büyük, incelemesi zor bir commit'e toplama

## Doğrulama Listesi

- [ ] Tüm mevcut testler değiştirilmeden geçiyor
- [ ] Unity compile hatasız
- [ ] Her sadeleştirme incelenebilir artımlı bir değişiklik
- [ ] Diff temiz — ilgisiz değişiklikler karışmamış
- [ ] Sadeleştirilmiş kod proje kurallarını takip ediyor (CLAUDE.md ile kontrol edildi)
- [ ] Hiçbir hata işleme kaldırılmadı veya zayıflatılmadı
- [ ] Unity null check'leri (`== null`) korundu (`is null` ile değiştirilmedi)
- [ ] `#if UNITY_EDITOR` guard'ları korundu
- [ ] Bir takım arkadaşı veya review agent bu değişikliği net bir iyileştirme olarak onaylar
