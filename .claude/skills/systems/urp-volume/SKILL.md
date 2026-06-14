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

URP Volume sistemi SRP Core üzerine inşa edilmiştir. Tüm Volume işlemleri `manage_graphics` tool'u
üzerinden `action` parametresi ile yapılır.

## Hallucination Guard — Bunlar Mevcut Değil

```
❌ volume_create(...)          → manage_graphics(action="volume_create", ...) kullan
❌ postprocess_add_effect(...) → manage_graphics(action="volume_add_effect", ...) kullan
❌ manage_volume(...)          → böyle bir tool yok
❌ volume_set_bloom(...)       → manage_graphics(action="volume_set_effect", ...) kullan
```

Tüm action'lar `manage_graphics` üzerinden geçer. Action prefix'i `volume_` dir.

## Mevcut Actions

| Action | Ne yapar |
|--------|----------|
| `volume_create` | Volume GameObject oluşturur (global veya local), isteğe bağlı VolumeProfile ile |
| `volume_create_profile` | Bağımsız VolumeProfile asset'i oluşturur |
| `volume_set_profile` | Mevcut Volume'a farklı bir profile atar |
| `volume_add_effect` | VolumeProfile'a bir effect override ekler |
| `volume_set_effect` | Effect'in parametrelerini set eder |
| `volume_list_effects` | Volume üzerindeki mevcut effect'leri listeler |
| `volume_get_info` | Volume'un detaylarını (weight, priority, profile, effects) okur |
| `volume_remove_effect` | Effect override'ı siler — tehlikeli, geri alınamaz |
| `volume_set_properties` | Volume'un weight, priority, isGlobal değerlerini değiştirir |

## Temel İş Akışı

### 1. Ortam kontrolü

URP kurulu değilse tüm volume action'ları hata döner. Önce kontrol et:

```python
manage_graphics(action="pipeline_get_info")
# → pipeline_type: "URP" olmalı
```

### 2. Global post-processing Volume oluştur

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

`is_global: false` ise Volume bir Collider ile birleşerek lokal efekt verir (fog zone, dark room vb.).

### 3. Effect ekle

```python
manage_graphics(
    action="volume_add_effect",
    target="GlobalPostProcessVolume",
    properties={"type": "Bloom"}
)
```

**Effect isimleri tam olarak yazılmalı.** Kısaltma kabul etmez:

| Doğru | Yanlış |
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

### 4. Parametre set etmeden önce gerçek isimleri öğren

```python
# Önce effect'in gerçek parameter isimlerini oku
manage_graphics(
    action="volume_get_info",
    target="GlobalPostProcessVolume"
)
```

Geri dönen `components[].parameters` listesindeki gerçek isimleri kullan. Tahmin etme.

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

## Sık Kullanılan Effect Parametreleri

### Bloom
```
intensity     → float (0-1+ arası)
threshold     → float (parlaklık eşiği)
scatter       → float (0-1, yayılma)
tint          → Color
```

### Depth of Field (URP)
```
mode          → "Gaussian" veya "Bokeh"
focusDistance → float (metre cinsinden)
aperture      → float (f/stop, Bokeh için)
focalLength   → float (mm, Bokeh için)
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

## Local Volume Kullanımı

Lokal Volume, Collider sınırları içinde aktif olur (fog zone, karanlık oda, su altı efekti vb.):

```python
# 1. Local volume oluştur
manage_graphics(
    action="volume_create",
    properties={
        "name": "FogZoneVolume",
        "is_global": False,
        "weight": 1.0,
        "priority": 2
    }
)

# 2. BoxCollider ekle (trigger olarak)
manage_components(
    action="add",
    target="FogZoneVolume",
    component="BoxCollider",
    properties={"isTrigger": True, "size": [10, 5, 10]}
)

# 3. Effect ekle
manage_graphics(action="volume_add_effect", target="FogZoneVolume", properties={"type": "Fog"})
```

## VolumeProfile Asset Yönetimi

Profil'i ayrı asset olarak kaydetmek sahneden bağımsız yeniden kullanım sağlar:

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

## Doğrulama Adımları

Her Volume değişikliğinden sonra:

```python
read_console(types=["error", "warning"], count=5)
manage_graphics(action="volume_get_info", target="GlobalPostProcessVolume")
```

Hata yoksa `manage_camera(action="screenshot", include_image=True)` ile görsel doğrula.
