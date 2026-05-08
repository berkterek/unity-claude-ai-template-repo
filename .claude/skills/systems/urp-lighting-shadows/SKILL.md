---
name: urp-lighting-shadows
description: Use when configuring URP lighting (directional, point, spot, area), tuning shadow cascades, fixing shadow bias artifacts (peter-panning, shadow acne), setting up light layers, light cookies, or reflection probes in URP.
globs: ["**/URP*.asset", "**/*Light*.cs", "**/*Shadow*.cs", "**/*Lighting*.cs"]
---

# URP Lighting & Shadows

## Lighting Architecture in URP

```
Main Directional Light   → shadows, sun direction, GI contribution
Additional Lights        → point, spot (limited per object in Forward)
Reflection Probes        → specular indirect lighting
Light Probes             → diffuse indirect for dynamic objects
Ambient (Skybox/Color)   → global fill light
```

---

## Main Directional Light

The single most important light. Casts shadows globally.

### Recommended Settings

| Setting | Value | Notes |
|---------|-------|-------|
| Mode | Realtime | Or Mixed for baked GI + realtime shadows |
| Intensity | 1.0–1.5 | HDR allows > 1.0 |
| Color Temperature | 6500 K (day) / 3200 K (sunset) | Enable "Use Color Temperature" |
| Shadow Type | Soft Shadows | Hard Shadows for mobile performance |
| Shadow Strength | 0.8–1.0 | < 1.0 for softer look |
| Shadow Bias | See bias section below | Critical for artifact-free shadows |

### Realtime vs Mixed vs Baked

| Mode | Shadows | GI | Use |
|------|---------|-----|-----|
| Realtime | Dynamic | No baked GI | Open-world, fully dynamic scenes |
| Mixed | Dynamic + baked | Baked indirect | Best quality/performance ratio |
| Baked | Static only | Baked direct+indirect | Static scenes, mobile |

---

## Shadow Cascades

Cascades divide the shadow map into zones — close objects get more shadow map resolution.

### Cascade Count Guidelines

| Platform | Cascades | Rationale |
|----------|----------|-----------|
| Low-end mobile | 0–1 | Shadow map is expensive |
| Mid mobile | 2 | Good balance |
| High-end mobile / PC | 4 | Full quality |

### Cascade Split Ratios (4 cascades)

Default Unity splits: `0.067 / 0.2 / 0.467`

Tuned for third-person action game:
```
Cascade 1: 0.05  (5% of shadow distance — very close, high res)
Cascade 2: 0.15  (15%)
Cascade 3: 0.40  (40%)
Cascade 4: 1.0   (remaining — lowest res, far shadows)
```

Tuned for first-person / indoor:
```
Cascade 1: 0.03
Cascade 2: 0.10
Cascade 3: 0.30
Cascade 4: 1.0
```

Visualize cascades: Scene View → Shading Mode → Shadow Cascades.

### Shadow Distance

```
Shadow Distance = camera far plane * 0.5 is a safe starting point.

Typical values:
  Mobile outdoor: 40–60
  PC outdoor:     100–150
  Indoor scene:   15–30
```

Objects beyond shadow distance receive no shadows. Fade the cutoff with "Shadow Fade Distance" on the Pipeline Asset.

---

## Shadow Bias — Fixing Artifacts

Shadow bias is the #1 source of shadow bugs. Two artifacts with opposite fixes:

| Artifact | Cause | Fix |
|----------|-------|-----|
| **Shadow acne** (self-shadowing stripes) | Bias too low | Increase Depth Bias |
| **Peter-panning** (shadow detached from object) | Bias too high | Decrease Depth Bias |

### URP Shadow Bias Settings

| Setting | Location | Description |
|---------|----------|-------------|
| Depth Bias | Pipeline Asset → Shadows | Pushes shadow map receiver away from light |
| Normal Bias | Pipeline Asset → Shadows | Shrinks shadow casting silhouette |
| Per-Light Bias | Light component → Shadow Bias slider | Overrides Pipeline Asset for that light |

### Starting Values

```
Depth Bias:   1.0   (start here, decrease if peter-panning)
Normal Bias:  1.0   (start here, increase if acne on steep surfaces)
```

For stylized / toon games with large flat surfaces:
```
Depth Bias:   0.5
Normal Bias:  0.5
```

For organic terrain:
```
Depth Bias:   1.5
Normal Bias:  0.8
```

### Per-Object Bias Override

```csharp
// Override shadow bias on a specific light at runtime
Light light = GetComponent<Light>();
light.shadowBias       = 0.5f;  // depth bias
light.shadowNormalBias = 0.4f;  // normal bias
```

---

## Additional Lights (Point / Spot)

### Per-Object Light Limit (Forward Renderer)

Forward Renderer has a per-object additional light limit (set in Pipeline Asset):

| Platform | Recommended | Notes |
|----------|------------|-------|
| Mobile | 2–4 | Each adds a full shading pass |
| PC | 4–8 | SRP Batcher helps amortize cost |
| Forward+ | No limit | Uses clustered lighting |

### Shadow-Casting Additional Lights

Enable in Pipeline Asset → Additional Lights → Cast Shadows. Then on each Light component → Shadow Type.

Additional light shadows are expensive — limit to 0–2 shadow-casting point/spot lights on mobile.

### Light Range and Attenuation

```csharp
// Physically-based attenuation follows inverse-square law
// Use range to control cutoff — NOT to dim the light
// Dim with Intensity, not Range

Light light = GetComponent<Light>();
light.intensity = 5f;   // lumens (physically-based) or arbitrary
light.range     = 10f;  // cutoff distance — not a volume multiplier
```

---

## Light Layers (URP 12+)

Light Layers allow lights to affect only specific objects. Requires enabling in Pipeline Asset → Additional Lights → Use Per-Object Light Layers.

```csharp
// Assign layer on light
Light light = GetComponent<Light>();
var lightData = light.GetUniversalAdditionalLightData();
lightData.renderingLayers = (uint)(1 << 0 | 1 << 1); // layers 0 and 1

// Assign matching layers on renderer
MeshRenderer renderer = GetComponent<MeshRenderer>();
renderer.renderingLayerMask = (uint)(1 << 0); // only affected by layer 0 lights
```

Use cases:
- Interior lights that don't bleed through exterior walls
- Player-only rim lights
- Separate lighting for UI elements rendered in world space

---

## Light Cookies

Cookies project a texture pattern from a light (stained glass, venetian blinds, foliage dapple).

### Setup

1. Import texture → Texture Type: Cookie, wrap mode: Repeat or Clamp
2. Assign to Light component → Cookie field
3. Set Cookie Size (directional) or let point/spot use it automatically

```csharp
// Apply cookie at runtime
Light light = GetComponent<Light>();
light.cookie = cookieTexture;
light.cookieSize = 10f; // directional only — world-space projection scale
```

### Cookie Performance

- Directional cookies: cheapest, one texture lookup per fragment
- Point cookies: uses Cubemap → more expensive
- Spot cookies: standard 2D projection → moderate cost
- Disable cookies on mobile unless essential

---

## Reflection Probes

Reflection Probes capture a 360° cubemap for specular indirect lighting.

### Types

| Type | Updates | Use |
|------|---------|-----|
| Baked | Editor only | Static environments |
| Realtime | Every frame or on-demand | Dynamic objects (moving vehicles, water) |
| Custom | Manual cubemap | Stylized / pre-authored |

### Placement Rules

- Place probes at eye height where the player sees reflections
- Set influence volume to cover the reflection zone only — probes blend at volume edges
- One probe per distinct environment (indoor room, outdoor area)
- Never overlap large probes — blending is expensive

### Realtime Probe Budget

```csharp
// Control realtime probe update frequency
ReflectionProbe probe = GetComponent<ReflectionProbe>();
probe.refreshMode    = ReflectionProbeRefreshMode.ViaScripting;
probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.AllFacesAtOnce;

// Trigger update only when camera enters trigger zone
public void OnTriggerEnter(Collider other)
{
    if (other.CompareTag("Player"))
    {
        probe.RenderProbe();
    }
}
```

---

## Light Probes

Light Probes provide diffuse indirect lighting for **dynamic** objects (characters, vehicles, debris).

### Placement Guidelines

- Place at head height along player paths
- Denser near light transitions (doorways, window edges)
- Minimum 4 probes to form a tetrahedron — objects inside get interpolated lighting
- Never place inside geometry — probes inside walls receive wrong values

### Probe Groups

Use multiple Light Probe Groups:
- One for indoor areas (dense, near light sources)
- One for outdoor areas (sparser, at path intervals)

---

## Ambient Lighting

| Mode | Use |
|------|-----|
| Skybox | Outdoor, time-of-day changes, best quality |
| Gradient | Fast indoor — set sky/equator/ground colors |
| Color | Flat ambient, cheapest, stylized games |

```csharp
// Change ambient at runtime for day/night
RenderSettings.ambientSkyColor     = dayColor;
RenderSettings.ambientEquatorColor = horizonColor;
RenderSettings.ambientGroundColor  = groundColor;
RenderSettings.ambientIntensity    = 1.0f;
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Shadow acne on all surfaces | Increase Depth Bias to 1.5, Normal Bias to 1.0 |
| Peter-panning (floating shadows) | Decrease Depth Bias to 0.3–0.5 |
| Too many additional lights per object | Raise Pipeline Asset limit or switch to Forward+ |
| Realtime reflection probe every frame | Use `ViaScripting` and trigger on enter |
| Light Probes inside geometry | Always place in open air — check with Probe Visualization |
| `light.range` used to dim lights | Use `light.intensity` — range is a cutoff, not a dimmer |
| Shadows disabled on mobile to save perf | Use 1 cascade + hard shadows instead of disabling entirely |
