# /update-scene-hierarchy — Scene Hierarchy Organizer

Reorganizes an existing Unity scene to match the standard hierarchy defined in `.claude/rules/scene-hierarchy.md`. Moves misplaced GameObjects into the correct containers. Does **not** convert bare GOs to prefabs — use `/unity-scene-update` for that.

## Usage

```
/update-scene-hierarchy                  ← active open scene
/update-scene-hierarchy GameScene        ← specific scene by name
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

Read the full scene hierarchy: all root-level GameObjects and their immediate children.

---

## Step 2 — Audit

Read `.claude/rules/scene-hierarchy.md` classification table.

For each root-level GO:
- Is it a container (`[Setup]`, `[Services]`, `[UI]`, `[Environment]`, `[Characters]`, `[VFX]`)? → **skip**
- Otherwise → classify it using the table, record: `{ name, current_parent, correct_container }`

For GOs already inside a container, check if they're in the **correct** container:
- Correct → skip
- Wrong container → record for move

Build two lists:
- `misplaced[]` — already in a container but wrong one
- `at_root[]` — floating at root level (not in any container)

---

## Step 3 — Show Plan

Print the audit report before making any changes:

```
Scene Hierarchy Audit: GameScene
=================================

Missing containers: [VFX]

At root (will move to container):
  GlobalVolume          → [Environment]
  SpiritAudioProvider   → [Services]
  HeroPlayer            → [Characters]

Misplaced (wrong container):
  Canvas_Popups  [Services] → [UI]

Containers that already exist and are correct:
  [Setup], [Services], [UI], [Environment], [Characters]

No bare GameObjects detected (use /unity-scene-update to convert bare GOs to prefabs).
```

If zero changes needed:
```
GameScene hierarchy is already correct. No changes needed.
```
and stop.

---

## Step 4 — Confirm

Ask: **"Apply these changes? (yes / no)"**

Wait for explicit confirmation.

---

## Step 5 — Apply via MCP

Use `batch_execute` for all operations:

1. Create missing containers (bare GameObjects, no components, in correct order)
2. Move misplaced GOs to correct containers (re-parent via MCP)
3. Move root-level GOs into correct containers

Container creation order must be: `[Setup]` → `[Services]` → `[UI]` → `[Environment]` → `[Characters]` → `[VFX]`

---

## Step 6 — Verify

Read the scene hierarchy again via MCP and confirm:
- All 6 containers present
- No non-container GOs at root level
- All previously misplaced GOs are now in correct containers

If verification fails, report what remains incorrect.

---

## Step 7 — Report

```
update-scene-hierarchy complete — GameScene
  Containers created:  1  ([VFX])
  GOs moved:           4
  Already correct:     3
```

Do NOT commit. User commits via `/smart-commit`.
