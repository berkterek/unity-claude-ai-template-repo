---
name: urp-post-processing
description: Use when setting up URP post-processing volumes (Bloom, Depth of Field, Motion Blur, SSAO, Tonemapping, Color Grading, Vignette), creating runtime volume controllers, or debugging post-processing not appearing in scene.
globs: ["**/*Volume*.cs", "**/*PostProcess*.cs", "**/*VolumeProfile*.asset", "**/*PostFX*.cs"]
---

# URP Post-Processing

## Setup Checklist

Post-processing not showing? Work through this list:

- [ ] Camera component → **Post Processing** checkbox enabled
- [ ] Camera → Anti-aliasing: FXAA or SMAA (not Off, unless using MSAA)
- [ ] Pipeline Asset → **HDR** enabled (required for Bloom and Color Grading)
- [ ] A **Volume** component exists in the scene with a **Volume Profile** assigned
- [ ] Volume layer matches Camera's **Volume Mask** setting
- [ ] Volume is **Global** or its box collider overlaps the camera

---

## Volume Framework

### Volume Types

| Type | Influence | Use |
|------|-----------|-----|
| **Global** | Whole scene | Base look, always active |
| **Local** | Inside collider | Zone-specific effects (cave = heavy vignette) |
| **Custom Pass** | Scripted | Dynamic effects at runtime |

### Layer Setup

1. Create a layer: `PostProcessing`
2. Camera → Volume Mask: `PostProcessing`
3. All Volume components → assign to `PostProcessing` layer

Multiple volumes with the same priority blend additively by weight.

### Volume Priority and Blending

```csharp
// Local volume overrides global — set higher priority
Volume localVolume = GetComponent<Volume>();
localVolume.priority = 10f;   // higher = takes precedence
localVolume.weight   = 1f;    // 0-1, full override at 1
localVolume.blendDistance = 5f; // meters over which it blends in
```

---

## Bloom

Creates a glow around bright areas. Requires HDR.

### Recommended Values

| Setting | Cinematic | Game | Stylized |
|---------|-----------|------|----------|
| Threshold | 0.9 | 1.1 | 0.5 |
| Intensity | 0.3–0.6 | 0.2–0.4 | 1.0–2.0 |
| Scatter | 0.7 | 0.5 | 0.9 |
| Clamp | 65536 | 65536 | 65536 |
| Tint | White | White | Custom |

**Threshold:** brightness level above which bloom starts (HDR units). Set above 1.0 to avoid blooming non-emissive surfaces.

**Scatter:** controls bloom spread. Higher = softer, wider. Lower = tighter, more defined.

```csharp
// Animate bloom intensity for hit effects
private Bloom _bloom;

private void Awake()
{
    _globalVolume.profile.TryGet(out _bloom);
}

public async UniTask FlashBloomAsync(float peakIntensity, CancellationToken ct)
{
    float original = _bloom.intensity.value;
    _bloom.intensity.Override(peakIntensity);
    await UniTask.Delay(100, cancellationToken: ct);
    _bloom.intensity.Override(original);
}
```

---

## Color Grading & Tonemapping

Always pair these two together.

### Tonemapping Mode

| Mode | Look | Use |
|------|------|-----|
| None | Raw HDR, clipped | Never in production |
| Neutral | Minimal color shift | Default, safe choice |
| ACES | Film-like, warm highlights | Cinematic, action games |

### Color Adjustments

```
Post Exposure:  0.0   (EV100 — adjust scene brightness without touching lights)
Contrast:       0–10  (subtle — heavy contrast looks dated)
Color Filter:   White (tint all light)
Hue Shift:      0
Saturation:     0–10  (stylized can go higher)
```

### Lift / Gamma / Gain (Color Wheels)

- **Lift** — shadows color
- **Gamma** — midtones
- **Gain** — highlights

Day exterior: warm Gain (slight orange), cool Lift (blue-grey shadows).
Underground: green-tinted Gamma, desaturated Gain.

### LUT (Lookup Table)

For high-quality color grading, bake to a LUT:

1. Grade in DaVinci Resolve or Photoshop using the Identity LUT
2. Export as 32x1024 PNG or 32x32x32 PNG
3. Import as **2D** texture, **no** compression, **no** mipmaps, clamp all axes
4. Color Grading → Mode: External → assign LUT

```csharp
// Swap LUT at runtime (e.g., different biomes)
ColorLookup colorLookup;
_volume.profile.TryGet(out colorLookup);
colorLookup.texture.Override(newLutTexture);
colorLookup.contribution.Override(1.0f);
```

---

## Depth of Field

### Two Modes

| Mode | Quality | Performance | Use |
|------|---------|-------------|-----|
| Gaussian | Lower | Cheap | Mobile, stylized |
| Bokeh | High | Expensive | Cinematics, high-end PC |

### Focus Distance Control

```csharp
public sealed class DOFFocusController : MonoBehaviour
{
    [SerializeField] private Volume    _volume;
    [SerializeField] private Transform _target;

    private DepthOfField _dof;
    private Camera       _mainCamera;

    private void Awake()
    {
        _volume.profile.TryGet(out _dof);
        _mainCamera = Camera.main;
    }

    private void Update()
    {
        if (_dof == null || _target == null) return;

        float distance = Vector3.Distance(_mainCamera.transform.position, _target.position);
        _dof.focusDistance.Override(distance);
    }
}
```

### Focus via Raycast (Auto-Focus)

```csharp
private void Update()
{
    Ray ray = new Ray(_mainCamera.transform.position, _mainCamera.transform.forward);

    if (Physics.Raycast(ray, out RaycastHit hit, 100f))
    {
        float target = Mathf.Lerp(_dof.focusDistance.value, hit.distance, Time.deltaTime * 5f);
        _dof.focusDistance.Override(target);
    }
}
```

### Cinematic Cutscene DOF Values

```
Focal Length:    85mm
Aperture:        f/2.8
Focus Distance:  dynamic (raycast to subject)
Blade Count:     5
Blade Curvature: 0.5
```

---

## Motion Blur

**Mode: Camera** — blurs based on camera movement. Cheap, good for fast camera pans.
**Mode: Object** — per-object velocity buffer. Expensive, needed for fast-moving characters.

```
Intensity:   0.1–0.3  (higher = more blur per frame)
Clamp:       0.2      (max blur per pixel — prevents extreme smearing)
Quality:     Low/Medium for mobile, High for PC
```

**Disable during gameplay input** — motion blur feels wrong when the player is in direct control. Enable only during cinematic camera moves:

```csharp
public void SetMotionBlur(bool enabled, float intensity = 0.2f)
{
    MotionBlur motionBlur;
    if (_volume.profile.TryGet(out motionBlur))
    {
        motionBlur.active = enabled;
        motionBlur.intensity.Override(intensity);
    }
}
```

---

## SSAO (Screen Space Ambient Occlusion)

Adds contact shadows in crevices and corners. Available as a **Renderer Feature** (not a Volume override in URP).

### Enable SSAO

1. Select Universal Renderer Data asset
2. Add Renderer Feature → Screen Space Ambient Occlusion
3. Configure settings:

| Setting | Mobile | PC |
|---------|--------|-----|
| Intensity | 0.5 | 1.0 |
| Radius | 0.05 | 0.1 |
| Direct Lighting Strength | 0.25 | 0.5 |
| Quality | Low | High |
| Downsample | On | Off |
| After Opaque | On | On |

### SSAO Performance Cost

- Mobile: use Low quality + Downsample. Or disable entirely on Low tier.
- PC: High quality, no downsample. Adds ~0.5–1ms on modern hardware.

---

## Vignette

Darkens screen edges — draws focus to center, adds tension.

```
Intensity:  0.2–0.3  (subtle, always on)
            0.5–0.7  (hit effect, temporary)
Smoothness: 0.2      (sharp edge)
            0.7      (soft fade)
Rounded:    On       (oval) / Off (rectangular)
```

```csharp
// Pulse vignette on damage
public async UniTask DamageVignetteAsync(CancellationToken ct)
{
    Vignette vignette;
    _volume.profile.TryGet(out vignette);

    vignette.intensity.Override(0.65f);
    vignette.color.Override(new Color(0.8f, 0.1f, 0.1f));

    await UniTask.Delay(200, cancellationToken: ct);

    // Fade out
    float elapsed = 0f;
    float duration = 0.8f;
    while (elapsed < duration)
    {
        elapsed += Time.deltaTime;
        float t = elapsed / duration;
        vignette.intensity.Override(Mathf.Lerp(0.65f, 0.2f, t));
        await UniTask.Yield(ct);
    }

    vignette.intensity.Override(0.2f);
    vignette.color.Override(Color.black);
}
```

---

## Chromatic Aberration

Color fringing at screen edges — adds camera lens feel.

```
Intensity: 0.05–0.1  (always on, subtle)
           0.3–0.5   (hit effect, temporary)
```

Avoid > 0.5 — becomes distracting quickly.

---

## Film Grain

Adds texture to flat areas — helps with banding in dark scenes.

```
Type:      Thin or Medium (Coarse looks like TV static)
Intensity: 0.1–0.2
Response:  0.8  (grain responds to luminance — less grain in bright areas)
```

---

## Lens Distortion

Barrel/pincushion distortion for lens simulation or stylized drunk/hit effects.

```
Intensity:   0.0   (off, default)
             -0.3  (barrel distortion — wide-angle look)
              0.3  (pincushion — telephoto look)
X/Y Multiplier: 1.0
Scale:         1.05 (slightly zoom to hide edge stretching)
```

---

## Performance Budget Per Effect

| Effect | Mobile Cost | PC Cost | Notes |
|--------|-------------|---------|-------|
| Bloom | Medium | Low | Required HDR — disable on Low tier |
| Tonemapping | Negligible | Negligible | Always on |
| Color Adjustments | Negligible | Negligible | Always on |
| LUT | Low | Negligible | 32x32x32 tex sample |
| DOF (Gaussian) | Low | Negligible | |
| DOF (Bokeh) | High | Low | Disable on mobile |
| Motion Blur | Medium | Low | Disable during gameplay |
| SSAO | High | Medium | Low quality on mobile |
| Vignette | Negligible | Negligible | Always on |
| Chromatic Aberration | Negligible | Negligible | |
| Film Grain | Low | Negligible | |

### Mobile Post-Processing Stack (recommended)

```
Always on:  Tonemapping (ACES) + Color Adjustments + Vignette
Optional:   Bloom (threshold 1.2, intensity 0.2, Low quality)
Disable:    DOF Bokeh, Motion Blur, SSAO (or Low quality)
```

---

## Runtime Volume Stack Pattern

```csharp
public sealed class PostProcessController : IInitializable, IDisposable
{
    #region Fields

    private readonly Volume  _globalVolume;
    private readonly IEventBus _eventBus;

    private Bloom             _bloom;
    private Vignette          _vignette;
    private ChromaticAberration _chromatic;
    private ColorAdjustments  _colorAdjustments;
    private DepthOfField      _dof;

    #endregion

    #region Constructor

    public PostProcessController(Volume globalVolume, IEventBus eventBus)
    {
        _globalVolume = globalVolume;
        _eventBus     = eventBus;
    }

    #endregion

    #region Lifecycle

    public void Initialize()
    {
        var profile = _globalVolume.profile;
        profile.TryGet(out _bloom);
        profile.TryGet(out _vignette);
        profile.TryGet(out _chromatic);
        profile.TryGet(out _colorAdjustments);
        profile.TryGet(out _dof);

        _eventBus.Subscribe<PlayerDamagedEvent>(OnPlayerDamaged);
    }

    public void Dispose()
    {
        _eventBus.Unsubscribe<PlayerDamagedEvent>(OnPlayerDamaged);
    }

    #endregion

    #region Private Methods

    private void OnPlayerDamaged(PlayerDamagedEvent evt)
    {
        // Flash effects handled via UniTask fire-and-forget
    }

    #endregion
}
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Post-processing not visible | Enable Post Processing on Camera; check Volume layer matches Camera Volume Mask |
| Bloom on everything | Raise Threshold above 1.0 — only emissive surfaces should glow |
| DOF always at fixed distance | Drive `focusDistance` from raycast or target distance |
| `profile.TryGet` returns null | Effect not added to the Volume Profile — add override in Editor |
| Mutating `volume.profile` directly | Clone with `profile.Clone()` for per-instance overrides |
| Motion blur in gameplay | Disable during player control, enable in cutscenes only |
| SSAO on mobile without Downsample | Always enable Downsample on mobile SSAO |
| HDR disabled but Bloom enabled | Enable HDR in Pipeline Asset — Bloom requires it |
