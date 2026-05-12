---
name: primetween
description: PrimeTween usage pattern — setup, tween API, sequences, and UniTask integration
model-tier: normal
---

# PrimeTween — Usage Pattern

## Installation Note
Located at `Assets/Plugins/PrimeTween/`. Requires the `PRIME_TWEEN_INSTALLED` scripting define symbol.
Add a `#if PRIME_TWEEN_INSTALLED` guard where needed.

```csharp
using PrimeTween;
```

## Core Tween API

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

## Ease and Cycles

```csharp
Tween.Scale(transform, endScale, 0.3f, Ease.OutBack);
Tween.Scale(transform, endScale, 0.2f, Ease.OutSine, cycles: 2, CycleMode.Yoyo);
// CycleMode: Yoyo (back and forth), Restart (resets to start), Incremental
```

## TweenSettings for Configuration

```csharp
var settings = new TweenSettings(duration: 0.4f, Ease.OutBack, endDelay: 0.1f);
Tween.LocalPosition(transform, new TweenSettings<Vector3>(targetPos, settings));
```

## Sequence — Chaining and Grouping

```csharp
// Chain: sequential (next starts after previous finishes)
Sequence sequence = Tween.Scale(target, scaleA, 0.15f)
    .Chain(Tween.LocalPositionY(target, 1f, 0.3f))
    .Chain(Tween.LocalPositionY(target, 0f, 0.3f));

// Group: parallel (all run at the same time)
Sequence sequence = Sequence.Create()
    .Group(Tween.Scale(target, endScale, 0.3f))
    .Group(Tween.Alpha(canvasGroup, 0f, 0.3f));

// Insert: start at a specific time offset
Sequence sequence = Sequence.Create();
sequence.Insert(delay: 0.5f, Tween.Scale(target, endScale, 0.3f));
```

## Tween / Sequence Lifecycle

```csharp
// Check if alive
if (!tween.isAlive) { tween = Tween.Scale(...); }
if (!sequence.isAlive) { sequence = Sequence.Create()...; }

// Stop
tween.Stop();
sequence.Stop();

// Complete (jump to end)
tween.Complete();

// Pause / resume
sequence.isPaused = true;
sequence.isPaused = false;

// Progress
sequence.progressTotal = 0.5f; // 0–1
```

## Awaiting with UniTask

```csharp
// await a tween
await Tween.Scale(transform, endScale, 0.3f);

// await a sequence
await sequence;
```

Coroutines are forbidden in this project, so always await with UniTask — do not use `ToYieldInstruction()`.

## Project Rules

- Tweens are used in View/Provider layer — not in Service classes
- The service triggers the animation; View/Provider makes the PrimeTween calls
- `Tween` and `Sequence` fields are stored as `private` fields — do not create new tweens every frame
- Always check `isAlive` before starting a new tween to prevent overlapping animations
- Set capacity in Awake: `PrimeTweenConfig.SetTweensCapacity(100)`
