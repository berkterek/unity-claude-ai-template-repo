# /unity-scene-update — Full Scene Audit & Fix

Full scene audit: reorganizes containers AND converts bare GameObjects to prefabs. Run after adding or modifying GameObjects in a scene.

## Usage

```
/unity-scene-update                  ← active open scene
/unity-scene-update GameScene        ← specific scene by name
```

---

## Step 0 — MCP Preflight

Check MCP connectivity via `unity-mcp-skill`. If MCP is disconnected, stop and print:
```
MCP is not connected. Open Unity Editor and ensure MCP for Unity is running, then retry.
```

---

## Step 1 — Load Scene

If a scene name was provided, open it via MCP (`manage_scene`). Otherwise use the currently active scene.

Read the full scene hierarchy: all root-level GameObjects and their immediate children, including component lists for each.

---

## Step 2 — Full Audit

Read `.claude/rules/scene-hierarchy.md`.

Classify every non-container GO using the classification table. For each GO, determine:

```json
{
  "name": "GlobalVolume",
  "is_container": false,
  "is_prefab_instance": false,
  "current_parent": "root",
  "correct_container": "[Environment]",
  "prefab_domain": "Environment",
  "needs_prefab_conversion": true,
  "components": ["Volume", "GlobalVolume"],
  "has_renderer": false
}
```

**Bare GO detection:** A GO is bare (needs prefab conversion) if:
- It is not a prefab instance
- It is not a container (`[Setup]` etc.)

**Exception — `[Setup]` targets:** GOs classified as `[Setup]` (LifetimeScope subclasses) are NOT converted to prefabs — they are wired manually. Record them for container placement only.

Build three lists:
- `needs_prefab[]` — bare GOs that must be converted to prefabs
- `misplaced[]` — prefab instances in wrong container
- `at_root[]` — anything floating at root outside a container

---

## Step 3 — Show Plan

Print full audit before any changes:

```
Scene Full Audit: GameScene
============================

Missing containers: (none)

Bare GOs → will convert to prefab + move:
  GlobalVolume          → Prefabs/Environment/GlobalVolume.prefab    → [Environment]
  SpiritAudioProvider   → Prefabs/Services/SpiritAudioProvider.prefab → [Services]
  Canvas_Popups         → Prefabs/UI/Canvas_Popups.prefab            → [UI]

Prefab instances in wrong container:
  HeroPlayer  [Services] → [Characters]

Already correct:
  [Setup]  GameScope (prefab instance, correct container)
```

If zero changes needed:
```
GameScene is fully compliant. No changes needed.
```
and stop.

---

## Step 4 — Confirm

Ask: **"Apply these changes? (yes / no)"**

Wait for explicit confirmation.

---

## Step 5 — Convert Bare GOs to Prefabs

For each GO in `needs_prefab[]`, in this order:

### 5a — Determine prefab path
Use the Prefab Domain Mapping from `.claude/rules/scene-hierarchy.md`.

### 5b — Apply Logic / Visual separation
Before saving as prefab, ensure the GO follows the rule:
- Root: logic components only (Provider, Controller, Collider, Rigidbody, injected MonoBehaviours)
- If any Renderer/Animator/ParticleSystem is on the root: create a `Body` child and move visual components there

For Unity built-in components (GlobalVolume, Camera, Light):
- These have no renderers on root — no separation needed
- Save as-is

### 5c — Canvas check before saving
If the GO has a `Canvas` component:
1. Check if `_GameFolders/Prefabs/UI/Canvases/BaseCanvas.prefab` exists
2. If NOT → create BaseCanvas first: `Canvas` + `CanvasScaler` (Scale With Screen Size, 1080×1920, match 0.5) + `GraphicRaycaster`. Save to `_GameFolders/Prefabs/UI/Canvases/BaseCanvas.prefab`
3. Save the Canvas GO as a **Prefab Variant of BaseCanvas** — not as a standalone prefab
4. Set only overrides: `Canvas.sortingOrder` and children

### 5d — Save prefab
Save to `_GameFolders/Prefabs/<Domain>/<GOName>.prefab` via MCP.

### 5e — Replace in scene
Replace the bare GO in the scene with the newly created prefab instance.

---

## Step 6 — Organize Containers

After prefab conversion:

1. Create any missing containers (`[Setup]` → `[Services]` → `[UI]` → `[Environment]` → `[Characters]` → `[VFX]`)
2. Move all GOs (prefab instances + `[Setup]` targets) to correct containers
3. Use `batch_execute` for all MCP operations

---

## Step 7 — Verify

Read the scene hierarchy again via MCP and confirm:
- All 6 containers present
- No non-container GOs at root level
- All converted GOs are now prefab instances
- All GOs are in correct containers

If verification fails, report remaining issues.

---

## Step 8 — Report

```
unity-scene-update complete — GameScene
  Prefabs created:    3  (GlobalVolume, SpiritAudioProvider, Canvas_Popups)
  Prefabs moved:      1  (HeroPlayer → [Characters])
  Containers created: 0
  Already correct:    1
  Skipped ([Setup]):  1  (GameScope — manual wiring)
```

Do NOT commit. User commits via `/smart-commit`.
