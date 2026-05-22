---
name: scene-hierarchy
description: Sahne hierarchy standartları — 6 container GO (Setup/Services/UI/Environment/Characters/VFX), GO sınıflandırma tablosu, prefab domain eşleştirmesi, AppScope ve CoreObjects prefab kuralları. Sahneye bir GameObject eklerken, sahneyi organize ederken, MCP ile sahne oluştururken, /scene-setup veya /unity-scene-update çalıştırırken bu skill'i kullan. Root level GO yasak — her GO doğru container'ın altına girer.
model-tier: normal
---

# Scene Hierarchy Standard

## 6 Container (Sabit Sıra)

```
Scene
├── [Setup]        ← Yalnızca VContainer LifetimeScope alt sınıfları
├── [Services]     ← Provider, Manager, Service MonoBehaviour'ları
├── [UI]           ← Tüm Canvas objeleri ve çocukları
├── [Environment]  ← Odalar, terrain, statik objeler, ışıklar, Volume'lar
├── [Characters]   ← Player, NPC, düşman prefab instance'ları
└── [VFX]          ← Standalone ParticleSystem objeleri
```

**Container kuralları:**
- Bare GO (component yok) — izin verilen tek bare GO bunlar
- Prefab değil — hierarchy organizer'ların prefab olmaması onaylı istisnâdır
- İsimler `[` parantezi ile tam olarak bu şekilde — varyasyon yok
- Sıra sabittir

## Sınıflandırma Tablosu

GO eklerken ilk eşleşen kuralı uygula:

| Sinyal | Container |
|--------|-----------|
| `LifetimeScope` component'i var | `[Setup]` |
| İsim: `*Provider`, `*Manager`, `*Service` | `[Services]` |
| `Canvas` component'i var veya isim: `*Canvas`, `*UI`, `*Panel`, `*HUD`, `*Popup` | `[UI]` |
| İsim: `*Player`, `*Hero`, `*Enemy`, `*NPC`, `*Character`, `*Boss` | `[Characters]` |
| İsim: `*VFX`, `*Effect`, `*Particle` veya top-level `ParticleSystem` var | `[VFX]` |
| Diğer her şey (oda, volume, ışık, terrain, kamera, statik mesh) | `[Environment]` |

Birden fazla kural eşleşirse üstteki kazanır.

## Prefab Domain Eşleştirmesi

Bir GO'yu prefab'a dönüştürürken kaydet:

| Sinyal | Prefab klasörü |
|--------|---------------|
| `[Characters]`'a gidiyor | `_GameFolders/Prefabs/Characters/` |
| `[UI]`'ya gidiyor | `_GameFolders/Prefabs/UI/` |
| `[VFX]`'e gidiyor | `_GameFolders/Prefabs/VFX/` |
| `*Provider`, `*Manager`, `*Service` | `_GameFolders/Prefabs/Services/` |
| `[Environment]`'a gidiyor | `_GameFolders/Prefabs/Environment/` |
| `LifetimeScope` + yalnızca SO/asset ref'leri | `_GameFolders/Prefabs/Bootstrap/` |
| `EventSystem` | `_GameFolders/Prefabs/CoreObjects/` |
| `MainCamera` veya `Camera` component'i | `_GameFolders/Prefabs/CoreObjects/` |

## AppScope Prefab Kuralı

`AppScope` tüm serialized ref'leri ScriptableObject asset'se prefab olarak kaydedilmeli:

```
_GameFolders/Prefabs/Bootstrap/
├── AppScope.prefab      ← [SerializeField] AppInstaller (SO asset)
└── GameScope.prefab     ← tüm ref'ler asset ise
```

`RegisterComponentInHierarchy` kullanan scope'lar null ref ile prefab olabilir — Inspector ataması gerekmez.

## EventSystem / MainCamera Kuralı

Her iki GO da `CoreObjects/` altında prefab olmalı — **her sahnede aynı prefab instance'ı** kullanılır, her sahne için sıfırdan bare GO oluşturulmamalı.

## MCP Sahne İşlemlerinde Zorunlu Akış

1. Sahne başında 6 container oluştur
2. Her GO için sınıflandırma tablosuna bak
3. GO'yu doğru container'ın child'ı olarak yerleştir
4. Root level yerleştirme yasak — bloklayıcıdır

## Logic / Visual Ayrımı (Tüm Prefab'larda)

```
MyObject.prefab        ← Root: logic (Provider, Controller, Collider, Rigidbody)
└── Body/              ← Child: visual (MeshRenderer, Animator, ParticleSystem)
```

Root'ta Renderer yok — `Body`'de logic script yok.
