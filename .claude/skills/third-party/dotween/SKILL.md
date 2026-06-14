---
name: dotween
description: "DOTween animation library — sequence composition, tween lifecycle, easing, kill strategies. CRITICAL: Always kill tweens in OnDestroy to prevent leaks and errors."
globs: ["**/DOTween*", "**/*Tween*.cs", "**/*Animation*.cs"]
---

# DOTween Animation Library

DOTween (Demigiant) is the standard tweening library for Unity. It provides fluent, chainable methods for animating transforms, UI elements, materials, and arbitrary values with minimal boilerplate.

## Basic Tweens

Every shortcut method follows the pattern `target.DO[Property](endValue, duration)`.

```csharp
// Transform tweens
transform.DOMove(new Vector3(0, 5, 0), 1f);           // World position
transform.DOLocalMove(new Vector3(0, 5, 0), 1f);      // Local position
transform.DOScale(Vector3.one * 1.5f, 0.3f);          // Scale
transform.DORotate(new Vector3(0, 180, 0), 0.5f);     // Euler rotation
transform.DOLocalRotateQuaternion(targetRot, 0.5f);   // Quaternion rotation

// UI tweens (CanvasGroup, Image, etc.)
canvasGroup.DOFade(0f, 0.5f);                         // Alpha fade
image.DOColor(Color.red, 0.2f);                       // Color change
image.DOFillAmount(1f, 1f);                            // Fill bar
rectTransform.DOAnchorPos(Vector2.zero, 0.3f);        // UI position

// Material tweens
renderer.material.DOColor(Color.white, 0.1f);
renderer.material.DOFloat(1f, "_Dissolve", 1f);

// Arbitrary value tween
float value = 0f;
DOTween.To(() => value, x => value = x, 10f, 1f);
```

## Sequence Composition

Sequences let you chain, overlap, and orchestrate multiple tweens as a single unit.

```csharp
Sequence seq = DOTween.Sequence();

// Append — plays after previous tween finishes
seq.Append(transform.DOMove(targetPos, 0.5f));
seq.Append(transform.DOScale(Vector3.one * 1.2f, 0.3f));

// Join — plays at the same time as the previous tween
seq.Append(transform.DOMove(targetPos, 0.5f));
seq.Join(transform.DORotate(new Vector3(0, 360, 0), 0.5f));

// Insert — plays at a specific time position in the sequence
seq.Insert(0.2f, canvasGroup.DOFade(1f, 0.3f));

// Intervals and callbacks
seq.PrependInterval(0.5f);                             // Delay before sequence starts
seq.AppendInterval(0.2f);                              // Pause between tweens
seq.AppendCallback(() => Debug.Log("Done!"));
seq.InsertCallback(1f, () => PlaySound());

// Sequence settings
seq.SetLoops(3, LoopType.Yoyo);
seq.SetUpdate(true);                                   // Unscaled time
seq.OnComplete(() => Destroy(gameObject));
```

### Nested Sequences

```csharp
Sequence innerSeq = DOTween.Sequence();
innerSeq.Append(transform.DOScale(1.2f, 0.15f));
innerSeq.Append(transform.DOScale(1f, 0.15f));

Sequence outerSeq = DOTween.Sequence();
outerSeq.Append(transform.DOMove(targetPos, 0.5f));
outerSeq.Append(innerSeq);
```

## Easing

Easing controls the interpolation curve. Choose based on the feel you want.

```csharp
transform.DOMove(target, 0.5f).SetEase(Ease.OutBounce);
transform.DOScale(1.2f, 0.2f).SetEase(Ease.OutBack);          // Pop/overshoot
transform.DOMove(target, 1f).SetEase(Ease.InOutQuad);          // Smooth start/stop
canvasGroup.DOFade(0f, 0.3f).SetEase(Ease.InQuad);             // Accelerate out
```

### Common Eases for Game Feel

| Ease | Use Case |
|------|----------|
| `Ease.OutBack` | Button press pop, element appearing with overshoot |
| `Ease.OutBounce` | Landing, dropping items |
| `Ease.InOutQuad` | Smooth camera moves, panel slides |
| `Ease.OutQuad` | Natural deceleration, most general-purpose |
| `Ease.InBack` | Element leaving with anticipation |
| `Ease.OutElastic` | Springy, playful UI elements |
| `Ease.Linear` | Progress bars, constant-speed movement |

### Custom Ease Curves

```csharp
[SerializeField] private AnimationCurve m_CustomEase;
transform.DOMove(target, 1f).SetEase(m_CustomEase);
```

## CRITICAL: Tween Lifecycle and Kill Strategy

**Always kill tweens when the owning object is destroyed.** Tweens that target destroyed objects cause `MissingReferenceException` and memory leaks.

```csharp
public class AnimatedElement : MonoBehaviour
{
    private Tween m_ActiveTween;

    public void PlayAnimation()
    {
        // Kill any existing tween before starting a new one
        m_ActiveTween?.Kill();
        m_ActiveTween = transform.DOScale(1.2f, 0.3f)
            .SetEase(Ease.OutBack);
    }

    private void OnDestroy()
    {
        // CRITICAL: Kill all tweens targeting this transform
        transform.DOKill();

        // If you used SetId(this), also kill by ID:
        // DOTween.Kill(this);

        // Or kill a specific stored tween:
        // m_ActiveTween?.Kill();
    }
}
```

### Kill Methods

```csharp
transform.DOKill();                  // Kill all tweens on this transform
transform.DOKill(true);              // Kill and force completion
DOTween.Kill(this);                  // Kill tweens with this object as ID
DOTween.Kill("myTween");             // Kill tweens with string ID
DOTween.KillAll();                   // Nuclear option — kill everything
tween.Kill();                        // Kill a specific tween reference
```

## Tween IDs

Tag tweens with IDs for targeted operations.

```csharp
transform.DOMove(target, 1f).SetId(this);          // Object ID
transform.DOMove(target, 1f).SetId("uiTransition"); // String ID

// Later: kill, pause, or play by ID
DOTween.Kill("uiTransition");
DOTween.Pause(this);
DOTween.Play(this);
```

## SetAutoKill and Reusable Tweens

By default, tweens auto-destroy on completion. Disable for reusable tweens.

```csharp
private Tween m_BounceTween;

private void Awake()
{
    m_BounceTween = transform.DOScale(1.2f, 0.15f)
        .SetEase(Ease.OutBack)
        .SetAutoKill(false)
        .SetLoops(2, LoopType.Yoyo)
        .Pause();                    // Create paused, play on demand
}

public void Bounce()
{
    m_BounceTween.Restart();         // Replay from beginning
}

private void OnDestroy()
{
    m_BounceTween?.Kill();           // Must kill manually since AutoKill is off
}
```

## SetUpdate — Unscaled Time

For animations that should play during pause (Time.timeScale = 0):

```csharp
// Pause menu fade-in plays even when game is paused
canvasGroup.DOFade(1f, 0.3f).SetUpdate(true);

// Also works on sequences
DOTween.Sequence()
    .Append(panel.DOAnchorPos(Vector2.zero, 0.3f))
    .SetUpdate(true);
```

## SetCapacity — Startup Performance

Call once at application startup to pre-allocate tween capacity and avoid runtime resizing.

```csharp
// In a bootstrap MonoBehaviour or RuntimeInitializeOnLoadMethod
[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
private static void InitDOTween()
{
    DOTween.SetTweensCapacity(500, 50); // 500 tweeners, 50 sequences
}
```

## Punch and Shake — Game Juice

Short, impactful animations for feedback.

```csharp
// Punch — snaps back to original value
transform.DOPunchScale(Vector3.one * 0.2f, 0.3f, 6, 0.5f);
transform.DOPunchPosition(new Vector3(0, 30, 0), 0.4f, 8, 0.5f);
transform.DOPunchRotation(new Vector3(0, 0, 15), 0.3f, 8, 0.5f);

// Shake — random oscillation
transform.DOShakePosition(0.5f, strength: 10f, vibrato: 10, randomness: 90);
transform.DOShakeScale(0.3f, 0.5f);
transform.DOShakeRotation(0.5f, new Vector3(0, 0, 30));

// Camera shake
Camera.main.DOShakePosition(0.3f, 0.5f, 14, 90, false, true);
```

## Path Tweens

Move along a series of waypoints.

```csharp
Vector3[] waypoints = new[]
{
    new Vector3(0, 0, 0),
    new Vector3(5, 2, 0),
    new Vector3(10, 0, 0),
    new Vector3(15, 3, 0),
};

transform.DOPath(waypoints, 3f, PathType.CatmullRom)
    .SetEase(Ease.InOutQuad)
    .SetLookAt(0.01f);               // Face movement direction
```

## Common Patterns

### Button Press Feedback

```csharp
public class ButtonFeedback : MonoBehaviour, IPointerDownHandler, IPointerUpHandler
{
    private readonly Vector3 k_PressScale = Vector3.one * 0.9f;

    public void OnPointerDown(PointerEventData eventData)
    {
        transform.DOKill();
        transform.DOScale(k_PressScale, 0.1f).SetEase(Ease.OutQuad);
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        transform.DOKill();
        transform.DOScale(Vector3.one, 0.15f).SetEase(Ease.OutBack);
    }

    private void OnDestroy() => transform.DOKill();
}
```

### Screen Transition

```csharp
public class ScreenTransition : MonoBehaviour
{
    [SerializeField] private CanvasGroup m_CanvasGroup;
    [SerializeField] private RectTransform m_Panel;

    public Tween Show()
    {
        m_CanvasGroup.alpha = 0f;
        m_Panel.anchoredPosition = new Vector2(0, -50f);

        Sequence seq = DOTween.Sequence();
        seq.Append(m_CanvasGroup.DOFade(1f, 0.25f));
        seq.Join(m_Panel.DOAnchorPos(Vector2.zero, 0.3f).SetEase(Ease.OutQuad));
        return seq;
    }

    public Tween Hide()
    {
        Sequence seq = DOTween.Sequence();
        seq.Append(m_CanvasGroup.DOFade(0f, 0.2f));
        seq.Join(m_Panel.DOAnchorPos(new Vector2(0, 50f), 0.25f).SetEase(Ease.InQuad));
        return seq;
    }

    private void OnDestroy()
    {
        m_CanvasGroup.DOKill();
        m_Panel.DOKill();
    }
}
```

### Damage Flash

```csharp
public void FlashDamage(SpriteRenderer sr)
{
    sr.DOKill();
    Sequence seq = DOTween.Sequence();
    seq.Append(sr.DOColor(Color.red, 0.05f));
    seq.Append(sr.DOColor(Color.white, 0.15f));
    seq.SetId(sr);
}
```

### Collect Animation

```csharp
public void PlayCollectAnimation(Transform item, Vector3 targetUIPos)
{
    Sequence seq = DOTween.Sequence();
    seq.Append(item.DOScale(1.3f, 0.15f).SetEase(Ease.OutBack));
    seq.Append(item.DOMove(targetUIPos, 0.4f).SetEase(Ease.InBack));
    seq.Join(item.DOScale(0f, 0.3f).SetEase(Ease.InQuad));
    seq.OnComplete(() => Destroy(item.gameObject));
}
```

## Anti-Patterns

### DO NOT create tweens in Update

```csharp
// BAD — creates a new tween every frame, massive leak
private void Update()
{
    transform.DOMove(target.position, 0.5f);
}

// GOOD — create once, update target differently
private Tween m_MoveTween;
public void MoveTo(Vector3 target)
{
    m_MoveTween?.Kill();
    m_MoveTween = transform.DOMove(target, 0.5f);
}
```

### DO NOT forget to kill on destroy

```csharp
// BAD — tween continues after object is destroyed
public void Animate()
{
    transform.DOScale(2f, 5f).OnComplete(() => DoSomething());
}

// GOOD — always have a kill strategy
private void OnDestroy() => transform.DOKill();
```

### DO NOT create infinite loops without a kill strategy

```csharp
// BAD — no way to stop this
transform.DORotate(new Vector3(0, 360, 0), 2f, RotateMode.FastBeyond360)
    .SetLoops(-1, LoopType.Restart);

// GOOD — store reference and kill in OnDestroy
private Tween m_SpinTween;
private void Start()
{
    m_SpinTween = transform.DORotate(new Vector3(0, 360, 0), 2f, RotateMode.FastBeyond360)
        .SetLoops(-1, LoopType.Restart)
        .SetId(this);
}
private void OnDestroy() => DOTween.Kill(this);
```

## Callbacks

```csharp
transform.DOMove(target, 1f)
    .OnStart(() => Debug.Log("Started"))
    .OnUpdate(() => Debug.Log("Updating"))
    .OnComplete(() => Debug.Log("Done"))
    .OnKill(() => Debug.Log("Killed"))
    .OnStepComplete(() => Debug.Log("Loop step done"));
```

## Tween Control

```csharp
Tween tween = transform.DOMove(target, 1f);

tween.Pause();
tween.Play();
tween.Restart();
tween.Rewind();
tween.Complete();             // Jump to end
tween.Goto(0.5f, true);      // Jump to time, and play
tween.PlayForward();
tween.PlayBackwards();
tween.Flip();                 // Reverse direction
```

## Extended Reference

- [PITFALLS.md](./PITFALLS.md) — 30+ concrete pitfalls with source anchors (leaked tweens, From() traps, Sequence ordering, SetUpdate misuse)
- [LIFETIME.md](./LIFETIME.md) — SetLink, Kill strategies, OnDisable/OnDestroy cleanup patterns
---

# DOTween Pitfalls

Sub-doc of [dotween-design](./SKILL.md). Every item is a real production bug. Format: ❌ wrong → ✅ right, with WHY.

---

### 1. Tween outlives target — Safe Mode swallows the warning

```csharp
void StartAnim()
{
    transform.DOMoveX(5f, 10f); // 10 second tween
}
// GameObject destroyed at t=5 → Safe Mode logs Warning, tween dies silently.
// Production debugging becomes a "why is this not finishing?" mystery.
```

```csharp
// ✅ Explicit lifetime binding
transform.DOMoveX(5f, 10f).SetLink(gameObject, LinkBehaviour.KillOnDestroy);
```

**Why**: Safe Mode catches MissingReferenceException (`DOTween.cs:49,51`) and kills the tween. `SetLink` makes intent explicit.

---

### 2. `SetAutoKill(false)` without explicit `.Kill()` — pool leak

```csharp
// ❌ Pool fills up over sessions
var idle = transform.DOScale(1.1f, 0.5f)
    .SetLoops(-1, LoopType.Yoyo)
    .SetAutoKill(false);
// (never killed — stays in pool when scene unloads)
```

```csharp
// ✅ Kill on destroy or scene exit
idle.SetLink(gameObject, LinkBehaviour.KillOnDestroy);
// or
void OnDestroy() { idle?.Kill(); }
```

---

### 3. Append when you meant Join — animations serialize unexpectedly

```csharp
// ❌ Rotation waits until Move finishes
DOTween.Sequence()
    .Append(transform.DOMove(a, 1f))
    .Append(transform.DORotate(b, 1f));
```

```csharp
// ✅ Parallel
DOTween.Sequence()
    .Append(transform.DOMove(a, 1f))
    .Join(transform.DORotate(b, 1f));
```

---

### 4. `DOTween.KillAll()` kills UI tweens too

```csharp
// ❌ Wipes everything — including persistent UI animations
void OnLevelComplete() { DOTween.KillAll(); }
```

```csharp
// ✅ Use ID grouping
// Earlier: button.DOColor(red, 0.5f).SetId("ui");
DOTween.KillAll(false, "ui"); // kill all except UI-tagged

// OR kill only gameplay-tagged tweens
DOTween.Kill("gameplay");
```

---

### 5. Multiple tweens on same property — collision

```csharp
// ❌ Two concurrent tweens fighting for position
transform.DOMoveX(5f, 1f);
transform.DOMoveX(0f, 1f); // fights with the first
```

```csharp
// ✅ Kill previous before starting new
transform.DOKill();
transform.DOMoveX(5f, 1f);
```

DOTween extension `transform.DOKill()` is shorthand for `DOTween.Kill(transform)`.

---

### 6. `SetLoops(-1)` + `OnComplete` — callback never fires

```csharp
// ❌ OnComplete never fires on infinite loop
transform.DORotate(Vector3.forward * 360, 2f)
    .SetLoops(-1, LoopType.Incremental)
    .OnComplete(() => Debug.Log("done")); // never fires
```

```csharp
// ✅ Use OnStepComplete for per-iteration, OnKill for final
transform.DORotate(Vector3.forward * 360, 2f)
    .SetLoops(-1, LoopType.Incremental)
    .OnStepComplete(() => StepHandler())
    .OnKill(() => FinalHandler());
```

---

### 7. `SetRelative` + absolute reasoning

```csharp
// ❌ Expected to end at x=5
transform.position = new Vector3(3, 0, 0);
transform.DOMoveX(5f, 1f).SetRelative(true); // ends at x = 3 + 5 = 8
```

`SetRelative` means "add N", not "end at N". Use without SetRelative for absolute.

---

### 8. `Ease.Flash` without 3-param overload

```csharp
// ❌ Uses default amplitude/period — may not flash visibly
transform.DOScale(Vector3.one, 1f).SetEase(Ease.Flash);
```

```csharp
// ✅ Explicit flash count + period
transform.DOScale(Vector3.one, 1f).SetEase(Ease.Flash, 5, 0.2f);
```

Source: `TweenSettingsExtensions.cs:204` — the 3-param SetEase overload.

---

### 9. `DOShakePosition` parameter order confusion

```csharp
// ❌ Meant 90° randomness, got 90 strength
transform.DOShakePosition(1f, 90f); // second arg IS strength (float)
```

Full signature: `DOShakePosition(duration, strength, vibrato, randomness, snapping, fadeOut, randomnessMode)`. Source: `ShortcutExtensions.Camera:125` and similar.

---

### 10. `DOPath` defaulting to 3D for 2D games

```csharp
// ❌ 2D sprite jitters through Z axis
spriteTransform.DOPath(waypoints, 2f); // defaults to PathType.Linear, PathMode.Full3D
```

```csharp
// ✅ 2D-correct
spriteTransform.DOPath(waypoints, 2f, PathType.Linear, PathMode.Sidescroller2D);
```

---

### 11. `DOVirtual.Float` without Kill — never garbage collected

```csharp
// ❌ Virtual tween with closure capture — stays alive until manually killed
DOVirtual.Float(0, 1, 10f, t => _buffer.Fill(t));
// If the enclosing MonoBehaviour is destroyed, this tween keeps capturing the destroyed buffer.
```

```csharp
// ✅ Link to caller lifetime
DOVirtual.Float(0, 1, 10f, t => _buffer.Fill(t))
    .SetTarget(gameObject)
    .OnKill(() => _buffer = null);
// OR in OnDestroy: DOTween.Kill(gameObject);
```

---

### 12. `OnUpdate` closure allocates per call

```csharp
// ❌ String concat every frame
tween.OnUpdate(() => Debug.Log("pos " + transform.position));
```

```csharp
// ✅ Cache or skip debug in hot paths
```

---

### 13. `Image.DOFade` vs `CanvasGroup.DOFade` scope mismatch

```csharp
// ❌ Only this Image fades; children don't
image.DOFade(0f, 0.3f);
```

```csharp
// ✅ For fading a group (image + children)
canvasGroup.DOFade(0f, 0.3f);
```

---

### 14. TextMeshPro `.DOText` but wrong module

```csharp
tmp.DOText("hello", 1f); // CS1061: TMP_Text does not contain DOText
```

**Fix**: Tools → Demigiant → DOTween Utility Panel → add `DOTween Pro` TMP Module (Pro only) or use `DG.Tweening.TMPro` community module.

---

### 15. Sequence `SetLoops(-1)` + inner tween `SetAutoKill(false)`

```csharp
// ❌ Inner tween autoKill conflicts with Sequence loop
var innerTween = transform.DOMoveX(5, 1f).SetAutoKill(false);
var seq = DOTween.Sequence()
    .Append(innerTween)
    .SetLoops(-1);
// Behavior: inner tween may not reset between sequence loops
```

Inner tweens inside a Sequence should be transient (default autoKill=true). Control looping at the Sequence level only.

---

### 16. `DOPunchScale` + subsequent `DOScale` — fights

```csharp
// Punch restores to original scale, but DOScale set end value
transform.DOPunchScale(Vector3.one * 0.2f, 0.3f);
transform.DOScale(Vector3.one * 2, 1f); // may start from already-modified scale
```

**Fix**: Sequence them, or `.Kill()` the punch before scaling:

```csharp
transform.DOKill();
transform.DOScale(Vector3.one * 2, 1f);
```

---

### 17. Test Runner — stale tweens across tests

```csharp
// ❌ Tween from previous test still alive
[Test] public void TestA() { transform.DOMove(a, 10f); }
[Test] public void TestB() { /* still sees TestA's tween */ }
```

```csharp
[TearDown]
public void TearDown() { DOTween.Clear(destroy: true); }
```

---

### 18. `Sequence` killed then `.Append` called

```csharp
// ❌ ObjectDisposedException or no-op (Safe Mode)
var seq = DOTween.Sequence().Append(t1);
seq.Kill();
seq.Append(t2); // seq is disposed
```

Check `seq.IsActive()` before appending, or restart by creating a new Sequence.

---

### 19. `DOTween.PauseAll()` broader than intended

```csharp
// ❌ Pauses UI animations too (including critical dialogs)
DOTween.PauseAll();
```

```csharp
// ✅ Scope with ID
// Setup: gameplayTween.SetId("gameplay");
DOTween.Pause("gameplay");
```

---

### 20. `SetUpdate(UpdateType.Fixed)` + high `Time.timeScale`

```csharp
// ❌ Fixed tween at timeScale=3 steps 3x more per fixed frame — tween ends 3x faster
transform.DOMove(a, 1f).SetUpdate(UpdateType.Fixed);
Time.timeScale = 3f;
```

`UpdateType.Fixed` uses `Time.fixedDeltaTime` scaled by `Time.timeScale`. Be aware when applying slow-motion via timeScale.

---

### 21. `TweenCallback<T>` generic missing

```csharp
// ❌ OnWaypointChange expects TweenCallback<int>, not TweenCallback
tween.OnWaypointChange(i => Debug.Log(i));
```

Most callbacks are `TweenCallback` (no args). Some (`OnWaypointChange`, `OnTargetChange`) are `TweenCallback<T>`. Source: `Core/Delegates.cs`.

---

### 22. Addressables-instantiated tween target + bundle release race

Covered in [INTEGRATION.md](./INTEGRATION.md). Always `SetLink` or await tween before `Addressables.ReleaseInstance`.

---

### 23. Netcode — tween state diverges across clients

Covered in [INTEGRATION.md](./INTEGRATION.md). Use `UpdateType.Manual` driven by server tick, or reconstruct tween on each client from synced parameters.

---

### 24. `DOTween.MarkDirty` causing test flakes

`DOTween.MarkDirty` is an internal optimization trigger. External code rarely calls it. If a test fails intermittently around tween ordering, check whether you're triggering `MarkDirty` via `DOTween.To(...)` + `SetTarget(null)` (null target triggers internal cleanup).

---

### 25. `DOPath` start position != current target position

```csharp
// ❌ Waypoints don't include start position — tween jumps to first waypoint
transform.position = Vector3.zero;
transform.DOPath(new[] { Vector3.right * 5, Vector3.right * 10 }, 2f);
// Jumps to (5,0,0) on frame 1.
```

```csharp
// ✅ Include start position or use relative
transform.DOPath(new[] {
    transform.position,  // start here
    Vector3.right * 5,
    Vector3.right * 10
}, 2f);
```

---

### 26. `SetRecyclable(true)` + cached tween references

```csharp
// ❌ Cached reference points to recycled tween
_cachedTween = transform.DOMove(a, 1f);
_cachedTween.Kill();
// DOTween recycles the Tween instance. Another caller may have it now.
_cachedTween.Restart(); // ?? restarts some other tween
```

```csharp
// ✅ Disable recycling for cached references
_cachedTween = transform.DOMove(a, 1f).SetRecyclable(false);
```

---

### 27. `SetId(object)` boxing

```csharp
// ❌ Boxes the int every call
tween.SetId(42);
```

```csharp
// ✅ Use typed overload
tween.SetId(42); // object overload first; ensure compiler picks int overload via explicit cast if ambiguous
```

Source: `TweenSettingsExtensions.cs:79`. Use string ID for clarity: `tween.SetId("intro");`.

---

### 28. `Tween.Goto(time)` vs `Restart` — state machine

```csharp
tween.Goto(0.5f, andPlay: true);   // seek + play from 0.5s
tween.Restart();                   // reset to 0, play
```

`Goto` does NOT reset loop counters. For a Sequence with loops, `Goto(0)` continues in the current loop iteration. `Restart` resets everything.

---

### 29. IL2CPP AOT + generic `TweenerCore` stripping

On iOS / WebAssembly with IL2CPP, aggressive stripping can remove `TweenerCore<Vector3, Vector3, VectorOptions>` instantiations that are only created via reflection / generic paths.

```xml
<!-- link.xml -->
<linker>
  <assembly fullname="DOTween">
    <type fullname="DG.Tweening.Core.TweenerCore`3" preserve="all"/>
  </assembly>
</linker>
```

Tools → Demigiant → DOTween Utility Panel → "Create ASMDEF" adds this automatically.

---

### 30. DOTween Pro API (`DOTweenAnimation` component) in Free project

```csharp
// ❌ Fails to compile in Free version
gameObject.GetComponent<DOTweenAnimation>();
```

DOTween Pro APIs (the `DOTweenAnimation` component, path editor, animation tab) are NOT in the Free source. If you must support both, gate with `#if DOTWEEN_PRO` (not an official define — define it yourself in Pro-only asmdef's Define Constraints).

---

## How to use this list

- **Code review**: Scan PRs for any of these patterns before approving.
- **Onboarding**: New devs read this once before writing their first tween.
- **Bug hunts**: When "tween doesn't fire", start from #6, #17, #18. When "NRE in tween", start from #1, #11. When "tween runs too fast/slow", start from #7, #20.

Safe Mode is a safety net, not a solution — every Safe Mode warning in the console represents a real lifecycle bug that should be fixed.

---

# DOTween Lifetime & Ownership

Sub-doc of [dotween-design](./SKILL.md). This is where most DOTween bugs live: tweens running on destroyed targets, tween pool exhaustion, tweens surviving scene load.

## `SetTarget` — grouping by owner

`TweenSettingsExtensions.cs:116`:

```csharp
public static T SetTarget<T>(this T t, object target) where T : Tween;
```

**Shortcut extensions set target automatically** (`transform.DOMove(...)` → target = transform). `DOTween.To(getter, setter, ...)` does NOT — manual `.SetTarget(yourObject)` required for later `DOTween.Kill(target)` to work.

Usage:

```csharp
// Kill all tweens on this GameObject
DOTween.Kill(gameObject);

// Kill all tweens matching a specific target
DOTween.Kill(myCustomObject);

// Kill all tweens with additional filter
DOTween.KillAll(false, gameObject); // exclude tweens targeting gameObject
```

## `SetId` — grouping by tag

`TweenSettingsExtensions.cs:59,69,79`:

```csharp
public static T SetId<T>(this T t, object objectId) where T : Tween;
public static T SetId<T>(this T t, string stringId) where T : Tween;   // typed for perf
public static T SetId<T>(this T t, int intId) where T : Tween;         // typed for perf
```

Three typed overloads avoid boxing the ID. Use string or int IDs for GC-sensitive paths.

```csharp
transform.DOMove(a, 1f).SetId("intro");
otherTransform.DORotate(b, 1f).SetId("intro");

// Kill all tweens tagged "intro"
DOTween.Kill("intro");
```

## `SetLink` — bind lifecycle to GameObject

`TweenSettingsExtensions.cs:91,103`:

```csharp
public static T SetLink<T>(this T t, GameObject gameObject) where T : Tween;
public static T SetLink<T>(this T t, GameObject gameObject, LinkBehaviour behaviour) where T : Tween;
```

`LinkBehaviour` (source: `LinkBehaviour.cs:11-35` — **11 public values**):

| Value | Effect |
|-------|--------|
| `PauseOnDisable` | Pause tween when link target is disabled |
| `PauseOnDisablePlayOnEnable` | Pause on disable, Play on enable |
| `PauseOnDisableRestartOnEnable` | Pause on disable, Restart on enable |
| `PlayOnEnable` | Play on enable |
| `RestartOnEnable` | Restart on enable |
| `KillOnDisable` | Kill tween when target is disabled |
| `KillOnDestroy` | Kill when target destroyed (becomes NULL). **Always active even if another behaviour is chosen** |
| `CompleteOnDisable` | Complete tween (jump to end) when target is disabled |
| `CompleteAndKillOnDisable` | Complete + kill on disable |
| `RewindOnDisable` | Rewind (delay excluded) when target is disabled |
| `RewindAndKillOnDisable` | Rewind + kill on disable |

**Key fact** (`LinkBehaviour.cs:25-26`): `KillOnDestroy` behavior applies automatically — destroying the linked GameObject kills the tween regardless of which `LinkBehaviour` you picked.

```csharp
// Common: tween on UI that should stop if panel is closed
image.DOFade(1f, 0.3f).SetLink(gameObject, LinkBehaviour.KillOnDisable);
// Destruction of gameObject also kills it (KillOnDestroy is always active).
```

**Without `SetLink`, destroyed targets are handled by Safe Mode** — tween is caught on exception, logged, and killed. Safe Mode is OK for shipping but you should still prefer `SetLink` for explicit ownership.

## `SetAutoKill` — survive completion?

`TweenSettingsExtensions.cs:39,49`:

```csharp
public static T SetAutoKill<T>(this T t) where T : Tween;                  // autoKill = true
public static T SetAutoKill<T>(this T t, bool autoKillOnCompletion) where T : Tween;
```

Default **true**: tween is killed on completion → cannot be replayed.

```csharp
// Replayable tween (e.g. idle animation loop trigger)
var idle = transform.DOScale(1.1f, 0.5f)
    .SetEase(Ease.InOutSine)
    .SetLoops(-1, LoopType.Yoyo)
    .SetAutoKill(false);

// Start/stop
idle.Play(); idle.Pause(); idle.Restart();

// Explicit cleanup when done forever
idle.Kill();
```

**Always pair `SetAutoKill(false)` with a clear explicit `.Kill()` path** — else tween pool leaks.

## `SetRecyclable` — tween instance pooling

`TweenSettingsExtensions.cs:237,246`:

```csharp
public static T SetRecyclable<T>(this T t) where T : Tween;
public static T SetRecyclable<T>(this T t, bool recyclable) where T : Tween;
```

Controls whether killed tween objects return to DOTween's internal pool or are discarded. Default comes from `DOTween.defaultRecyclable`.

**Recycling = faster allocation but more confusion**: when recycled, a Tween reference in user code may point to a now-reused instance for a different target. If you cache tween references, set `SetRecyclable(false)`.

## `DOTween.Kill` / `DOTween.KillAll`

`DOTween.cs:864,872,884,892`:

```csharp
public static int KillAll(bool complete = false);
public static int KillAll(bool complete, params object[] idsOrTargetsToExclude);
public static int Kill(object targetOrId, bool complete = false);
public static int Kill(object target, object id, bool complete = false);
```

Return value: number of tweens killed (useful for debugging).

```csharp
// Kill on scene exit
DOTween.KillAll();

// Kill everything EXCEPT UI tweens
DOTween.KillAll(false, "ui");

// Kill only tweens on this target
DOTween.Kill(gameObject);

// Kill tweens on this target with this ID
DOTween.Kill(gameObject, "fade-in");
```

`complete: true` → jumps each killed tween to end value (fires `OnComplete` if withCallbacks via Tween.Complete(true) semantics).

## Safe Mode — destroyed target protection

`DOTween.cs:49,51`:

```csharp
public static bool useSafeMode = true;
public static SafeModeLogBehaviour safeModeLogBehaviour = SafeModeLogBehaviour.Warning;
```

When Safe Mode is ON and a tween's target is destroyed mid-tween:
1. The tween's next update throws MissingReferenceException / NullReferenceException.
2. Safe Mode catches the exception.
3. The tween is killed internally.
4. Depending on `safeModeLogBehaviour`:
   - `None` → no log
   - `Warning` (default) → `Debug.LogWarning("DOTween reports:...")`
   - `Error` → `Debug.LogError(...)`
5. For nested tweens inside a Sequence, `nestedTweenFailureBehaviour` applies.

**Trade-off**:
- Safe Mode ON: robustness at small CPU cost.
- Safe Mode OFF: crashes immediately on missing targets — forces you to fix with `SetLink` / `Kill` / proper lifetime scoping.

Recommended: OFF during development bug hunts, ON in release.

## Tween pool capacity

`DOTween.cs:301`:

```csharp
public static void SetTweensCapacity(int tweenersCapacity, int sequencesCapacity);
```

Defaults: **200 Tweeners + 50 Sequences**. Exceeding either triggers a runtime expansion with a warning log — one-time hiccup but visible in Profiler.

```csharp
// For a particle-heavy scene with 500 simultaneous tweens
DOTween.SetTweensCapacity(1000, 100);
```

Call AFTER `DOTween.Init(...)` or pass via `Init().SetCapacity(...)` chain.

Symptom of capacity miss: `Max Tweens reached: capacity has been automatically increased` in console at first frame of a scene.

## `DOTween.Clear`

`DOTween.cs:311`:

```csharp
public static void Clear(bool destroy = false);
```

- `false` (default): kill all tweens, reset pool, keep driver GameObject.
- `true`: also destroy `[DOTween]` GameObject. Next tween creation will re-init and re-create the driver.

Use `Clear(true)` in Test Runner teardown to guarantee a clean state across tests.

## `ClearCachedTweens`

`DOTween.cs:353`:

```csharp
public static void ClearCachedTweens();
```

Shrinks the pool back to capacity, discarding pooled-but-unused tweens. Useful for memory-sensitive mobile builds between large scene transitions.

## Lifetime checklist

- [ ] Every long-running / infinite tween has **either** `SetLink(gameObject, ...)` **or** a manual `Kill()` path.
- [ ] `SetAutoKill(false)` tweens have a matching explicit `.Kill()` call in teardown.
- [ ] `DOTween.To(...)` custom-tweens explicitly `.SetTarget(yourObject)` for kill grouping.
- [ ] `SetId` used for scene-scoped groups (intro, cutscene, UI pop-in) — killable in bulk.
- [ ] `DOTween.KillAll()` on scene teardown OR scene-specific `SetId` groups for selective kills.
- [ ] `SetTweensCapacity` sized for the hottest scene's concurrent count.
- [ ] Safe Mode stays ON in release; deliberately OFF for bug hunts.
- [ ] Test Runner tests call `DOTween.Clear(true)` in `[TearDown]`.

See [PITFALLS.md](./PITFALLS.md) for lifetime bugs (dangling tweens on pooled GameObjects, Safe Mode hiding NREs, pool exhaustion).
