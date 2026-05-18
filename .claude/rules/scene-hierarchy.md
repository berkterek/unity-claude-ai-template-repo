# Scene Hierarchy Rules

## Standard Hierarchy (NON-NEGOTIABLE)

Every scene must use exactly these six container GameObjects at the root level, in this order:

```
Scene
├── [Setup]        ← VContainer LifetimeScope subclasses only
├── [Services]     ← Provider, Manager, Service MonoBehaviours
├── [UI]           ← All Canvas objects and their children
├── [Environment]  ← Rooms, terrain, static objects, lights, Volumes
├── [Characters]   ← Player, NPC, enemy prefab instances
└── [VFX]          ← Standalone ParticleSystem objects
```

### Container Rules

- Container GameObjects are **bare** (no components, no scripts) — they are the only allowed bare GameObjects in a scene
- Container GameObjects are **not prefabs** — this is the approved exception to the "every scene GO must be a prefab" rule
- Container names use `[` brackets exactly as shown — no variations
- Container order is fixed — always in the order above
- **Every non-container GO must be a prefab instance or prefab variant** — no exceptions, including Unity built-in objects (GlobalVolume, Camera, DirectionalLight, etc.)

---

## Classification Table

When placing or moving a GameObject, apply the first matching rule:

| Signal | Container |
|--------|-----------|
| Has `LifetimeScope` component (VContainer scope) | `[Setup]` |
| Name contains `*Provider`, `*Manager`, `*Service` | `[Services]` |
| Has `Canvas` component, or name contains `*Canvas`, `*UI`, `*Panel`, `*HUD`, `*Popup` | `[UI]` |
| Name contains `*Player`, `*Hero`, `*Enemy`, `*NPC`, `*Character`, `*Boss` | `[Characters]` |
| Name contains `*VFX`, `*Effect`, `*Particle`, or has top-level `ParticleSystem` component | `[VFX]` |
| Everything else (Rooms, volumes, lights, terrain, cameras, static meshes) | `[Environment]` |

When multiple rules match, the first match wins (top of table = highest priority).

---

## Prefab Domain Mapping

When converting a bare GO to a prefab, save to:

| Signal | Prefab folder |
|--------|--------------|
| Goes to `[Characters]` | `_GameFolders/Prefabs/Characters/` |
| Goes to `[UI]` | `_GameFolders/Prefabs/UI/` |
| Goes to `[VFX]` | `_GameFolders/Prefabs/VFX/` |
| Name contains `*Provider`, `*Manager`, `*Service` | `_GameFolders/Prefabs/Services/` |
| Goes to `[Environment]` | `_GameFolders/Prefabs/Environment/` |
| Goes to `[Setup]` | Not converted — LifetimeScope objects are wired manually |

---

## Logic / Visual Separation (applies to all prefabs)

Every prefab separates logic and visual components:

```
MyObject.prefab        ← Root: logic components only (Provider, Controller, Collider, Rigidbody)
└── Body/              ← Child: visual components only (MeshRenderer, Animator, ParticleSystem)
```

- Root holds logic/physics — **no Renderer components on root**
- `Body` child holds visual — **no logic scripts on Body**

---

## Enforcement

**MCP scene operations (`unity-setup`, `unity-scene-builder`):**
- Always create all 6 containers at scene start before placing any GO
- Before placing a GO, determine its container via the classification table
- Place the GO as a child of the correct container — never at root level
- This rule is **blocking** — placing a GO at root level (outside a container) is not allowed

**`/update-scene-hierarchy`:** Reorganizes existing scene — moves misplaced GOs to correct containers.

**`/unity-scene-update`:** Full audit — reorganizes containers AND converts bare GOs to prefabs.
