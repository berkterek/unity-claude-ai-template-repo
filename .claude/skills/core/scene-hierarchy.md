---
name: scene-hierarchy
description: Scene hierarchy standards — 6 container GOs (Setup/Services/UI/Environment/Characters/VFX), GO classification table, prefab domain mapping, AppScope and CoreObjects prefab rules. Use this skill when adding a GameObject to a scene, organizing a scene, creating a scene with MCP, or running /scene-setup or /unity-scene-update. Root level GOs are forbidden — every GO goes under the correct container.
model-tier: normal
---

# Scene Hierarchy Standard

## 6 Containers (Fixed Order)

```
Scene
├── [Setup]        ← VContainer LifetimeScope subclasses only
├── [Services]     ← Provider, Manager, Service MonoBehaviours
├── [UI]           ← All Canvas objects and their children
├── [Environment]  ← Rooms, terrain, static objects, lights, Volumes
├── [Characters]   ← Player, NPC, enemy prefab instances
└── [VFX]          ← Standalone ParticleSystem objects
```

**Container rules:**
- Bare GO (no components) — these are the only allowed bare GOs
- Not prefabs — hierarchy organizers being non-prefabs is the approved exception
- Names use `[` brackets exactly as shown — no variations
- Order is fixed

## Classification Table

When adding a GO, apply the first matching rule:

| Signal | Container |
|--------|-----------|
| Has `LifetimeScope` component | `[Setup]` |
| Name: `*Provider`, `*Manager`, `*Service` | `[Services]` |
| Has `Canvas` component or name: `*Canvas`, `*UI`, `*Panel`, `*HUD`, `*Popup` | `[UI]` |
| Name: `*Player`, `*Hero`, `*Enemy`, `*NPC`, `*Character`, `*Boss` | `[Characters]` |
| Name: `*VFX`, `*Effect`, `*Particle` or has top-level `ParticleSystem` | `[VFX]` |
| Everything else (room, volume, light, terrain, camera, static mesh) | `[Environment]` |

If multiple rules match, the first one wins.

## Prefab Domain Mapping

When converting a GO to a prefab, save to:

| Signal | Prefab folder |
|--------|--------------|
| Going to `[Characters]` | `_GameFolders/Prefabs/Characters/` |
| Going to `[UI]` | `_GameFolders/Prefabs/UI/` |
| Going to `[VFX]` | `_GameFolders/Prefabs/VFX/` |
| `*Provider`, `*Manager`, `*Service` | `_GameFolders/Prefabs/Services/` |
| Going to `[Environment]` | `_GameFolders/Prefabs/Environment/` |
| `LifetimeScope` + only SO/asset refs | `_GameFolders/Prefabs/Bootstrap/` |
| `EventSystem` | `_GameFolders/Prefabs/CoreObjects/` |
| `MainCamera` or has `Camera` component | `_GameFolders/Prefabs/CoreObjects/` |

## AppScope Prefab Rule

`AppScope` must be saved as a prefab when all serialized refs are ScriptableObject assets:

```
_GameFolders/Prefabs/Bootstrap/
├── AppScope.prefab      ← [SerializeField] AppInstaller (SO asset)
└── GameScope.prefab     ← if all refs are assets
```

Scopes using `RegisterComponentInHierarchy` can be prefabs with null refs — no Inspector assignment needed.

## EventSystem / MainCamera Rule

Both GOs must be prefabs under `CoreObjects/` — the **same prefab instance** is used in every scene; a new bare GO must not be created from scratch for each scene.

## Mandatory Flow for MCP Scene Operations

1. Create the 6 containers at the start of the scene
2. For each GO, consult the classification table
3. Place the GO as a child of the correct container
4. Root level placement is forbidden — it is a blocking violation

## Logic / Visual Separation (All Prefabs)

```
MyObject.prefab        ← Root: logic (Provider, Controller, Collider, Rigidbody)
└── Body/              ← Child: visual (MeshRenderer, Animator, ParticleSystem)
```

No Renderer on root — no logic scripts on `Body`.
