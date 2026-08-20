---
name: urp-volume
description: >
  URP Volume setup via MCP — create global/local Volume GameObjects, create VolumeProfile assets,
  add and configure post-processing effect overrides (Bloom, Depth of Field, Tonemapping, Vignette,
  Color Adjustments, SSAO, etc.). Use when asked to add post-processing, create a Volume, set up
  a skybox environment, configure Bloom or DOF, or tune any URP Volume component via manage_graphics.
globs: ["**/*Volume*.cs", "**/*PostProcess*.cs", "**/*VolumeProfile*.asset"]
---

# URP Volume — MCP Skill

The URP Volume system is built on SRP Core. Every Volume operation goes through the `manage_graphics`
tool via its `action` parameter.

## Hallucination Guard — These Do Not Exist

```
❌ volume_create(...)          → manage_graphics(action="volume_create", ...) kullan
❌ postprocess_add_effect(...) → manage_graphics(action="volume_add_effect", ...) kullan
❌ manage_volume(...)          → no such tool
❌ volume_set_bloom(...)       → manage_graphics(action="volume_set_effect", ...) kullan
```

All actions go through `manage_graphics`. The action prefix is `volume_`.

## Mevcut Actions

| Action | Ne yapar |
|--------|----------|
| `volume_create` | Creates a Volume GameObject (global or local), optionally with a VolumeProfile |
| `volume_create_profile` | Creates a standalone VolumeProfile asset |
| `volume_set_profile` | Assigns a different profile to an existing Volume |
| `volume_add_effect` | VolumeProfile'a bir effect override ekler |
| `volume_set_effect` | Effect'in parametrelerini set eder |
| `volume_list_effects` | Lists the effects currently on a Volume |
| `volume_get_info` | Reads a Volume's details (weight, priority, profile, effects) |
| `volume_remove_effect` | Deletes an effect override — destructive, not undoable |
| `volume_set_properties` | Changes a Volume's weight, priority and isGlobal values |

## Core Workflow

### 1. Environment check

Every volume action errors out if URP is not installed. Check first:

```python
manage_graphics(action="pipeline_get_info")
# → pipeline_type must be "URP"
```

### 2. Create a global post-processing Volume

```python
manage_graphics(
    action="volume_create",
    properties={
        "name": "GlobalPostProcessVolume",
        "is_global": True,
        "priority": 1,
        "profile_path": "Assets/Settings/GlobalVolumeProfile.asset"
    }
)
```

With `is_global: false` the Volume pairs with a Collider to give a local effect (fog zone, dark room, etc.).

### 3. Effect ekle

```python
manage_graphics(
    action="volume_add_effect",
    target="GlobalPostProcessVolume",
    properties={"type": "Bloom"}
)
```

**Effect names must be written in full.** Abbreviations are rejected:

| Correct | Wrong |
|-------|--------|
| `Bloom` | `bloom`, `BloomEffect` |
| `DepthOfField` | `DOF`, `DepthOfFieldEffect` |
| `Tonemapping` | `ToneMapping`, `ToneMap` |
| `Vignette` | `VignetteEffect` |
| `ColorAdjustments` | `ColorGrading`, `ColorAdjustment` |
| `MotionBlur` | `MotionBlurEffect` |
| `ScreenSpaceAmbientOcclusion` | `SSAO`, `AmbientOcclusion` |
| `WhiteBalance` | `WhiteBalanceEffect` |
| `FilmGrain` | `FilmGrainEffect` |

### 4. Learn the real parameter names before setting anything

```python
# read the effect's real parameter names first
manage_graphics(
    action="volume_get_info",
    target="GlobalPostProcessVolume"
)
```

Use the real names from the returned `components[].parameters` list. Never guess.

### 5. Parametre set et

```python
manage_graphics(
    action="volume_set_effect",
    target="GlobalPostProcessVolume",
    properties={
        "type": "Bloom",
        "parameters": {
            "intensity": 1.2,
            "threshold": 0.8,
            "scatter": 0.7
        }
    }
)
```

### 6. Birden fazla parametreyi tek seferde set et

```python
manage_graphics(
    action="volume_set_effect",
    target="GlobalPostProcessVolume",
    properties={
        "type": "DepthOfField",
        "parameters": {
            "mode": "Bokeh",
            "focusDistance": 5.0,
            "aperture": 5.6,
            "focalLength": 50
        }
    }
)
```

## Commonly Used Effect Parameters

### Bloom
```
intensity     → float (0-1+)
threshold     → float (brightness threshold)
scatter       → float (0-1, spread)
tint          → Color
```

### Depth of Field (URP)
```
mode          → "Gaussian" veya "Bokeh"
focusDistance → float (metre cinsinden)
aperture      → float (f/stop, for Bokeh)
focalLength   → float (mm, for Bokeh)
```

### Tonemapping
```
mode → "None", "Neutral", "ACES"
```

### Vignette
```
color     → Color
intensity → float (0-1)
smoothness → float (0-1)
rounded    → bool
```

### Color Adjustments
```
postExposure     → float (EV)
contrast         → float (-100 to 100)
colorFilter      → Color
hueShift         → float (-180 to 180)
saturation       → float (-100 to 100)
```

## Using a Local Volume

A local Volume becomes active inside its Collider bounds (fog zone, dark room, underwater effect, etc.):

```python
# 1. create the local volume
manage_graphics(
    action="volume_create",
    properties={
        "name": "FogZoneVolume",
        "is_global": False,
        "weight": 1.0,
        "priority": 2
    }
)

# 2. add a BoxCollider (as a trigger)
manage_components(
    action="add",
    target="FogZoneVolume",
    component="BoxCollider",
    properties={"isTrigger": True, "size": [10, 5, 10]}
)

# 3. Effect ekle
manage_graphics(action="volume_add_effect", target="FogZoneVolume", properties={"type": "Fog"})
```

## VolumeProfile Asset Management

Saving the profile as a separate asset makes it reusable independently of any scene:

```python
manage_graphics(
    action="volume_create_profile",
    properties={"path": "Assets/Settings/NightProfile.asset"}
)

# Mevcut volume'a profili ata
manage_graphics(
    action="volume_set_profile",
    target="GlobalPostProcessVolume",
    properties={"profile_path": "Assets/Settings/NightProfile.asset"}
)
```

## Verification Steps

After every Volume change:

```python
read_console(types=["error", "warning"], count=5)
manage_graphics(action="volume_get_info", target="GlobalPostProcessVolume")
```

If there are no errors, verify visually with `manage_camera(action="screenshot", include_image=True)`.
