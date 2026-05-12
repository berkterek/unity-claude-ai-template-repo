---
name: primetween
description: PrimeTween kullanım paterni — kurulum, tween API'si, sequence ve UniTask entegrasyonu
model-tier: normal
---

# PrimeTween — Kullanım Paterni

## Kurulum Notu
`Assets/Plugins/PrimeTween/` altında geliyor. Scripting Define Symbol olarak `PRIME_TWEEN_INSTALLED` gerekli.
Kullanım sırasında `#if PRIME_TWEEN_INSTALLED` guard eklenmesi önerilir.

```csharp
using PrimeTween;
```

## Temel Tween API

```csharp
// Position
Tween.LocalPosition(transform, targetPos, duration);
Tween.LocalPositionY(transform, targetY, duration);
Tween.Position(transform, targetPos, duration);

// Rotation
Tween.LocalRotation(transform, targetRot, duration);
Tween.LocalEulerAngles(transform, from, to, duration);

// Scale
Tween.Scale(transform, targetScale, duration);
Tween.Scale(transform, endScale, duration, Ease.OutSine, cycles: 2, CycleMode.Yoyo);

// Color / Alpha
Tween.Color(spriteRenderer, targetColor, duration);
Tween.Alpha(canvasGroup, targetAlpha, duration);

// Custom float
Tween.Custom(startValue, endValue, duration, onValueChange: v => myField = v);
```

## Ease ve Cycle

```csharp
Tween.Scale(transform, endScale, 0.3f, Ease.OutBack);
Tween.Scale(transform, endScale, 0.2f, Ease.OutSine, cycles: 2, CycleMode.Yoyo);
// CycleMode: Yoyo (gidip gelir), Restart (başa döner), Incremental
```

## TweenSettings ile Yapılandırma

```csharp
var settings = new TweenSettings(duration: 0.4f, Ease.OutBack, endDelay: 0.1f);
Tween.LocalPosition(transform, new TweenSettings<Vector3>(targetPos, settings));
```

## Sequence — Zincirleme ve Gruplama

```csharp
// Chain: sıralı (bir bittikten sonra diğeri)
Sequence sequence = Tween.Scale(target, scaleA, 0.15f)
    .Chain(Tween.LocalPositionY(target, 1f, 0.3f))
    .Chain(Tween.LocalPositionY(target, 0f, 0.3f));

// Group: paralel (aynı anda)
Sequence sequence = Sequence.Create()
    .Group(Tween.Scale(target, endScale, 0.3f))
    .Group(Tween.Alpha(canvasGroup, 0f, 0.3f));

// Insert: belirli zamanda başlat
Sequence sequence = Sequence.Create();
sequence.Insert(delay: 0.5f, Tween.Scale(target, endScale, 0.3f));
```

## Tween / Sequence Lifecycle

```csharp
// Canlı mı kontrol et
if (!tween.isAlive) { tween = Tween.Scale(...); }
if (!sequence.isAlive) { sequence = Sequence.Create()...; }

// Durdur
tween.Stop();
sequence.Stop();

// Tamamla (sona atla)
tween.Complete();

// Duraklat / devam ettir
sequence.isPaused = true;
sequence.isPaused = false;

// İlerleme
sequence.progressTotal = 0.5f; // 0-1 arası
```

## UniTask ile Await

```csharp
// await tween
await Tween.Scale(transform, endScale, 0.3f);

// await sequence
await sequence;
```

Bu projede coroutine yasak olduğundan UniTask ile await kullanılır, `ToYieldInstruction()` kullanılmaz.

## Bu Projedeki Kurallar

- Tween'ler View/Provider katmanında kullanılır — Service sınıflarında değil
- Servis, animasyonu tetikler; View/Provider PrimeTween çağrılarını yapar
- `Tween` ve `Sequence` alanları `private` field olarak saklanır, her frame yeni tween oluşturulmaz
- `isAlive` kontrolü yapılmadan yeni tween başlatılmaz (üst üste binmeyi önler)
- Capacity ayarı Awake'te yapılır: `PrimeTweenConfig.SetTweensCapacity(100)`
