---
name: source-driven-development
description: Unity API çağrısı yazmadan önce resmi Unity dökümanını fetch et ve kaynak URL'i belirt. URP, DOTS, Addressables, Input System gibi hızlı değişen API'ler için zorunludur.
model-tier: normal
---

# Source-Driven Development (Unity)

## Genel Bakış

Her Unity API kararı resmi dökümana dayandırılmalıdır. Eğitim verisi eskiyebilir — Unity 6 ile URP Renderer Features, DOTS API'leri, Input System ve Addressables önemli ölçüde değişti. Bu skill, yazdığın koda güvenilirlik kazandırır çünkü her karar doğrulanabilir bir kaynağa dayanır.

## Ne Zaman Kullanılır

- Herhangi bir Unity API çağrısı yazmadan önce
- URP, DOTS, Addressables, Input System, Cinemachine, Physics gibi sürümler arası değişen API'lerde
- `/implement`, `/fix`, `/add-feature`, `/scene-setup` pipeline'larında Unity'e özgü pattern'lar yazılırken
- Mevcut kodda "bu doğru mu?" sorusu akla geldiğinde

**Ne Zaman Kullanılmaz:**
- Pure C# logic (döngüler, veri yapıları, matematik) — sürümden bağımsız
- Dosya taşıma, yeniden adlandırma, typo düzeltme
- Kullanıcı "hızlı yap, doğrulama" dediğinde

## Süreç

```
TESPİT → FETCH → UYGULA → KAYNAK GÖSTER
```

### Adım 1: Stack ve Sürümü Tespit Et

Projenin Unity sürümünü ve ilgili paket sürümlerini oku:

```
ProjectSettings/ProjectVersion.txt  → Unity sürümü
Packages/manifest.json              → Tüm paket sürümleri
Packages/packages-lock.json         → Kilitli sürümler
```

Bulduğunu açıkça belirt:

```
STACK TESPİT EDİLDİ:
- Unity 6000.0.x (ProjectVersion.txt'den)
- com.unity.render-pipelines.universal: 17.0.x
- com.unity.inputsystem: 1.x
→ URP 17 dökümanleri fetch ediliyor.
```

Sürüm belirsizse kullanıcıya sor — tahmin etme.

### Adım 2: Resmi Dökümanleri Fetch Et

İlgili sayfayı fetch et. Ana sayfayı değil, o özelliğin sayfasını.

**Kaynak hiyerarşisi (öncelik sırasıyla):**

| Öncelik | Kaynak | Örnek |
|---------|--------|-------|
| 1 | Unity resmi dökümantasyonu | docs.unity3d.com/6000.0/Documentation/Manual/ |
| 2 | Unity Packages dökümantasyonu | docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/ |
| 3 | Unity Blog / Changelog | blog.unity.com, unity.com/releases |
| 4 | Unity Forum — resmi Unity yanıtları | forum.unity.com |

**Yetkili olmayan kaynaklar — birincil kaynak olarak kullanma:**
- Stack Overflow
- Blog yazıları, YouTube tutorialları
- Kendi eğitim verisi (doğrulamadan)

**Spesifik fetch yap:**

```
YANLIŞ: Unity dökümantasyon ana sayfasını fetch et
DOĞRU:  docs.unity3d.com/6000.0/Documentation/Manual/urp/renderer-feature-how-to-add.html fetch et

YANLIŞ: "URP Renderer Feature best practices" ara
DOĞRU:  docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/manual/renderer-features/intro-to-renderer-features.html fetch et
```

Fetch sonrası: deprecation uyarıları, migration notları ve API signature değişikliklerini not et.

Resmi kaynaklar çelişirse (migration guide vs API referansı) bu durumu kullanıcıya bildir ve hangisinin mevcut sürüme uygulandığını doğrula.

### Adım 3: Dökümana Göre Uygula

- Dokümandaki API signature'ı kullan, hafızadan değil
- Döküman yeni bir yaklaşım gösteriyorsa yeni yaklaşımı kullan
- Döküman bir pattern'ı deprecated işaretlediyse kullanma
- Döküman bir şeyi kapsamıyorsa bunu açıkça belirt

**Mevcut kodla çelişki varsa:**

```
ÇAKIŞMA TESPİT EDİLDİ:
Mevcut kodda OnRenderObject() callback kullanılıyor,
ancak URP 17 dökümantasyonu bu callback'in URP'de
çalışmadığını ve RenderPipelineManager.beginCameraRendering
kullanılması gerektiğini belirtiyor.
(Kaynak: docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/...)

Seçenekler:
A) Yeni yaklaşım — güncel dökümanla uyumlu
B) Mevcut kod — projeyle tutarlı ama döküman dışı
→ Hangisini tercih edersiniz?
```

Sessizce karar verme — çakışmayı kullanıcıya sun.

### Adım 4: Kaynak Göster

Her Unity'e özgü pattern için kaynak belirt. Kullanıcı her kararı doğrulayabilmeli.

**Kod yorumunda:**

```csharp
// URP 17 Renderer Feature kaydı
// Kaynak: https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/api/UnityEngine.Rendering.Universal.ScriptableRendererFeature.html
public override void Create() { }
```

**Konuşmada:**

```
InputSystem 1.x'te performed callback kullanıyorum,
started değil — çünkü performed tetikleyicisi
basış + bırakışın tamamlanmasını bekler.
Kaynak: https://docs.unity3d.com/Packages/com.unity.inputsystem@1.x/manual/Actions.html#started-performed-and-canceled-callbacks
```

**Kaynak kuralları:**
- Tam URL, kısaltılmış değil
- Mümkünse anchor ile derin link (`#usage`, `#api-reference`)
- Açık olmayan kararlar için ilgili pasajı alıntıla
- Dokümanda bulamazsan açıkça belirt:

```
DOĞRULANMADI: Bu pattern için resmi döküman bulunamadı.
Bu eğitim verisine dayanıyor ve güncel olmayabilir.
Production'da kullanmadan önce doğrulayın.
```

## Unity'e Özgü Doğrulama Listesi

- [ ] Unity sürümü ve paket sürümleri `ProjectVersion.txt` / `manifest.json`'dan okundu
- [ ] İlgili Unity API için resmi döküman fetch edildi
- [ ] Deprecated API'ler migration guide'dan kontrol edildi
- [ ] API signature dökümandaki ile eşleşiyor (hafızadan değil)
- [ ] Her Unity'e özgü pattern için kaynak URL eklendi
- [ ] Dökümanla çakışan mevcut kod varsa kullanıcıya soruldu
- [ ] Doğrulanamayan pattern'lar açıkça işaretlendi
