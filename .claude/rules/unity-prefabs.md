# Prefab Rules (NON-NEGOTIABLE)

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: new GameObject() is Forbidden

**WHEN:** Creating any GameObject at runtime.

**WRONG:**
```csharp
var go = new GameObject("Enemy");
var go = new GameObject("Bullet", typeof(Rigidbody));
```

**RIGHT:**
```csharp
var instance = Instantiate(_prefab, position, rotation);
// Addressables:
var instance = await Addressables.InstantiateAsync(address).ToUniTask(ct);
```

**GOTCHA:** Even Pool, Factory, and Spawner classes cannot use `new GameObject()`. Every object must originate from a prefab. `check-no-runtime-instantiate.sh` blocks this with exit 2.

---

### Card 2: Destroy() Rules — Prefer Pool Return

**WHEN:** Removing a GameObject from the scene.

**WRONG:**
```csharp
Destroy(pooledEnemy); // outside pool class — leaks the pool slot
```

**RIGHT:**
```csharp
_pool.Return(enemy);        // return to pool
enemy.SetActive(false);     // alternative pool return pattern
// only in Pool/Manager shutdown:
Destroy(gameObject);
```

**GOTCHA:** `Destroy()` on Addressables instances must use `Addressables.ReleaseInstance()` instead, or you'll leak the handle and get a memory leak.

---

### Card 3: BaseCanvas Pattern — Never Duplicate Canvas Setup

**WHEN:** Creating any Canvas prefab (HUD, popup, overlay, joystick).

**WRONG:** Creating separate Canvas prefabs that each have their own `Canvas + CanvasScaler + GraphicRaycaster` setup with potentially different CanvasScaler reference resolutions.

**RIGHT:**
```
BaseCanvas.prefab  ← Canvas + CanvasScaler (reference 1080×1920) + GraphicRaycaster
├── CanvasHUD.prefab      ← variant, sortingOrder 0
├── CanvasPopup.prefab    ← variant, sortingOrder 100
└── CanvasOverlay.prefab  ← variant, sortingOrder 10
```

**GOTCHA:** If one Canvas drifts to a different reference resolution, layouts break on certain screen sizes with no error message. Enforce once in `BaseCanvas`, inherit everywhere.

---

### Card 4: Prefab Variants — Base vs Separate Decision

**WHEN:** Two GameObjects share most of their component structure.

**WRONG:** Copy-pasting a prefab and tweaking it — the two copies diverge silently over time.

**RIGHT:**
| Situation | Decision |
|-----------|----------|
| Same component set, 1–2 fields differ | Base + Variant |
| Completely different component structure | Separate prefab |

**GOTCHA:** Prefab Variants only make sense when the base is stable. If you find yourself overriding every property on every variant, make separate prefabs instead.

---

### Card 5: Extract Before the Second Copy (Prefab DRY)

**WHEN:** You are about to place a GameObject under the same parent for the second time — health pips, slots, inventory cells, list rows.

**WRONG:**
```
CanvasDynamic/
└── HeartRow/            ← no layout component; three children positioned by hand
    ├── Heart1           ← RectTransform + Image
    ├── Heart2           ← RectTransform + Image   (copy of Heart1)
    └── Heart3           ← RectTransform + Image   (copy of Heart1)
```

**RIGHT:**
```
UI/Utilities/Heart.prefab        ← one definition
CanvasDynamic/
└── HeartRow/                    ← HorizontalLayoutGroup
    ├── Heart (instance)         ← size comes from the prefab, not the instance
    ├── Heart (instance)
    └── Heart (instance)
```

**The test is three conditions together — not "same component set":**
1. They sit under the same parent,
2. They have the same component set,
3. They are edited together (change one's sprite or size and the others must change too).

All three true means it is a duplicate. `Blocker` and `Heart` are both RectTransform+Image but fail the third condition — they do not need a shared prefab.

**GOTCHA:** Extraction requires a layout component (`HorizontalLayoutGroup` / `GridLayoutGroup`) on the parent first. Without one, every instance carries its own `anchoredPosition` as an override — exactly the "overriding every property on every variant" failure Card 4 names. Adding the layout and extracting the prefab is one package, never split. Second trap: never move a component off an atom prefab's **root** into a child later — `[SerializeField]` arrays pointing at that root (`Image[] _hearts`) silently become `None`, with no error and no log, and the field simply stops updating.

> **"Zero transform overrides on the instances" is NOT the goal — it is unreachable.** Unity serializes a RectTransform's anchors, pivot, size and position as instance overrides on every UI prefab instance; `PrefabUtility.RevertObjectOverride` does not stick, because the layout pass immediately recomputes and rewrites them. Measured while doing this extraction for real: the canvas's own `BaseCanvas` variant root carried the identical 17 overrides and always had.
>
> The goal that override count was standing in for is **size authority**: set `childControlWidth` / `childControlHeight` to `true` on the layout group and give the atom prefab a `LayoutElement`. Size then flows from the prefab, the serialized override becomes dead data, and changing the atom propagates to every instance — which was the whole point of extracting it.

**Verification (at the gate of any module that touches prefabs or scenes):**
```bash
python3 .claude/scripts/check-duplicate-siblings.py        # whole tree
python3 .claude/scripts/check-duplicate-siblings.py <path> # one folder or file
```
Exit 0 is the only pass. `NO PREFAB OR SCENE FILES FOUND` is **not** a pass — the script says so itself; it means the path was wrong.

The check is **structural — it never looks at names.** Conditions 1 and 2 above are measurable, so the script measures exactly those: same parent, same component set. Condition 3 is human judgement, so a hit is a question for the gate, not a verdict — close it by extracting the prefab, or by recording why it is not duplication. Never by editing the script.

> **Why not a `grep` over `m_Name:`.** This card originally verified with one, matching names ending in a digit (`Heart1`, `Heart2`). It was measured against real files and found blind to `Heart (1)` / `Heart (2)` — Unity's own default naming when you press Cmd+D in the Hierarchy, which is the most common way a duplicate is created at all. It also flagged `Level01`/`Level02` as duplicates while testing neither of the card's first two conditions. Do not reintroduce a name-based test.

Bare Transform-only GameObjects are excluded: those are the six mandated scene containers, and `scene-hierarchy.md` both requires them and forbids them from being prefabs — without the exclusion they are a permanent false positive in every scene.

This is a smoke alarm — it measures **difference**, not presence. A presence check like `HudView 5/5 bound` is blind to copy-paste by construction, which is why no gate in the module that shipped `Heart1/Heart2/Heart3` ever fired.


Every GameObject placed in a scene must be an instance of a prefab. Bare (non-prefab) GameObjects are forbidden — except scene separators/organizers (empty GameObjects used purely as hierarchy dividers with no components).

**Why:** Bare GameObjects cannot be reused, are hard to maintain across scenes, and break Addressables-based spawning.

## new GameObject() is Forbidden (NON-NEGOTIABLE)

`new GameObject()` is forbidden in all runtime code — no exceptions. This includes Pool, Factory, and Spawner classes. Every GameObject must originate from a prefab.

```csharp
// BAD — forbidden everywhere in runtime code
var go = new GameObject("Enemy");
var go = new GameObject("Bullet", typeof(Rigidbody));

// GOOD — instantiate from prefab
var instance = Instantiate(_prefab, position, rotation);
var instance = Instantiate(_prefab, parent, false);

// GOOD — Addressables
var instance = await Addressables.InstantiateAsync(address).ToUniTask(ct);
```

**Why:** `new GameObject()` produces a bare object with no prefab backing — it cannot be tracked by Addressables, has no variant chain, and breaks the single-source-of-truth prefab model. Even pools and factories must instantiate from a prefab; they just manage the lifecycle of those instances.

The `check-no-runtime-instantiate` hook blocks this with exit 2 on every Write/Edit.

## Destroy() Rules

`Destroy()` usage depends on context:

**Outside Pool/Manager/Spawner classes — warn:**
If an object is pool-managed, call `pool.Return()` or `SetActive(false)` instead of `Destroy()`. The hook warns when `Destroy()` is found outside Pool/Manager/Spawner files.

**Inside Pool/Manager/Spawner classes — two allowed cases:**

```csharp
// Case 1 — Pool capacity trim: pool exceeds max capacity, destroy the excess
public void ReturnToPool(GameObject obj)
{
    if (_pool.Count >= MAX_CAPACITY)
        Destroy(obj);       // over capacity — destroy the excess
    else
        _pool.Enqueue(obj); // under limit — keep it
}

// Case 2 — Manager shutdown: the pool/manager is no longer needed (e.g. level change)
public void Shutdown()
{
    Destroy(gameObject); // destroys manager + all pooled children
}
```

**Rules:**
- Pool capacity limit is defined as a constant in the pool class (`private const int MAX_CAPACITY = 50`)
- Never destroy pooled objects below the capacity limit — return them to the pool instead
- Manager shutdown (`Destroy(gameObject)`) is only valid when the entire pool is being decommissioned — never use it to release individual objects

## Prefab Variants for Shared Behavior

When multiple objects share a common base, create a base prefab and derive variants from it. Never duplicate prefabs manually.

```
BaseEnemy.prefab          ← base: shared components, default values
├── FastEnemy.prefab      ← variant: overrides Speed, visual
└── TankEnemy.prefab      ← variant: overrides Health, Size, visual
```

- Variants inherit all components and values from the base
- Only override what actually differs — keep overrides minimal
- Never copy-paste a prefab and tweak it — use Prefab Variants

### When to Use Base + Variant vs Separate Prefab

| Situation | Decision |
|-----------|----------|
| 2+ prefabs share the same component set | Base + Variant |
| Only 1–2 fields differ (Sort Order, Layer, speed) | Base + Variant |
| Completely different component structure | Separate prefab |
| Name is similar but content is fundamentally different | Separate prefab |

### Canvas Prefabs — BaseCanvas Pattern (NON-NEGOTIABLE)

Every project that has multiple Canvas prefabs **must** use a `BaseCanvas` prefab with Prefab Variants. Never create independent Canvas prefabs that duplicate the same `Canvas` + `CanvasScaler` + `GraphicRaycaster` setup.

```
_GameFolders/Prefabs/UI/Canvases/
├── BaseCanvas.prefab           ← Canvas + CanvasScaler (reference resolution) + GraphicRaycaster
├── CanvasHUD.prefab            ← variant: Sort Order 0, HUD children
├── CanvasJoystick.prefab       ← variant: Sort Order 1
├── CanvasOverlay.prefab        ← variant: Sort Order 10
└── CanvasPopup.prefab          ← variant: Sort Order 100
```

**BaseCanvas holds:**
- `Canvas` component — Render Mode: Screen Space - Overlay (default)
- `CanvasScaler` — Scale Mode: Scale With Screen Size, Reference Resolution (e.g. 1080×1920), Match: 0.5
- `GraphicRaycaster`
- Any project-wide safe area or resolution handler script

**Variants override only:**
- `Canvas.sortingOrder` — each canvas has its own layer order
- `Canvas.renderMode` — if a specific canvas needs Camera or World Space
- Children (HUD elements, joystick widgets, popup containers)

**Why:** `CanvasScaler` reference resolution and match settings must be identical across all canvases. A BaseCanvas enforces this — change it once, all variants inherit it. Without a base, one canvas will inevitably drift to a different resolution setting and break layout on certain screen sizes.

## Folder Structure

All prefabs live under `_GameFolders/Prefabs/`, grouped by domain:

```
_GameFolders/
└── Prefabs/
    ├── Enemies/
    │   ├── BaseEnemy.prefab
    │   ├── FastEnemy.prefab
    │   └── TankEnemy.prefab
    ├── UI/
    │   ├── Canvases/      ← full-screen Canvas prefabs (MainMenuCanvas, GameCanvas…)
    │   ├── Popups/        ← popup and dialog prefabs
    │   ├── Panels/        ← panel prefabs
    │   └── Utilities/     ← single reusable elements (Button, Icon, Label…)
    ├── VFX/
    │   └── ExplosionEffect.prefab
    └── Environment/
        └── Platform.prefab
```

- One subfolder per domain — never dump prefabs directly into `Prefabs/`
- Subfolder name matches the domain (Enemies, UI, VFX, Environment, Player, Projectiles…)
- Base prefabs and their variants live in the same subfolder

## Logic vs Visual Separation (NON-NEGOTIABLE)

Every prefab separates logic components from visual components across two levels:

```
Player.prefab                  ← Root: logic components only
├── PlayerProvider.cs
├── PlayerController.cs
└── Body/                      ← Child: visual components only
    ├── MeshRenderer
    ├── Animator
    └── SkinnedMeshRenderer
```

- **Root GameObject** — holds Provider, Controller, Collider, Rigidbody, and any injected MonoBehaviours
- **`Body` child** (or `Visual`, `Mesh` — be consistent per project) — holds Renderer, Animator, particle systems, and any purely visual components
- Logic scripts never sit on the same GameObject as a Renderer
- Visual child has no logic scripts; root has no Renderer components

**Why:** Swapping visuals (skin, LOD, VFX) never touches logic. Animating, hiding, or replacing the visual subtree is isolated — root stays stable.

## Rules Summary

| Rule | Why |
|------|-----|
| Every scene GameObject is a prefab instance | Reusability, Addressables compatibility |
| Shared-base objects use Prefab Variants | Single source of truth, easier iteration |
| Prefabs grouped by domain under `_GameFolders/Prefabs/` | Predictable location, clean Project window |
| Never duplicate a prefab manually | Use Prefab Variants instead |
| Empty hierarchy organizers are the only bare GameObjects allowed | No components = no logic = no maintenance cost |
| Extract to a prefab (+ layout on the parent) before placing a second copy | Editing spreads across N places as copies accumulate — Card 5 |
| Logic components on root, visual components on `Body` child | Decouples visual swaps from logic, clear responsibility |
| `AppScope` / `LifetimeScope` with only ScriptableObject refs → `Prefabs/Bootstrap/` | Asset refs are stored on the prefab; no scene-time drag-and-drop needed |
| `EventSystem` and `MainCamera` → `Prefabs/CoreObjects/`, same prefab in every scene | Consistent settings, single source of truth across all scenes |

## Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)

Prefabs that ship inside a third-party UPM package (under `Library/PackageCache/<name>@<version>/`) or an Asset Store package (under `Assets/Plugins/<vendor>/`) must NEVER be referenced directly from a scene, a Resources reference, an Addressables entry, or another prefab.

**Why:** Package contents are immutable from the project's perspective — UPM rewrites `Library/PackageCache/` on every resolve, and Asset Store updates overwrite `Assets/Plugins/`. Any in-scene reference to a package GUID breaks with a "missing prefab" error on version bump; any in-package edit is silently lost.

### Procedure

1. Identify the source prefab inside the package directory.
2. Choose a category folder under `_GameFolders/Prefabs/<Category>/` matching the existing domain folders.
3. Duplicate the prefab using **Project window → right-click → Duplicate**. Do NOT copy `.meta` files from the package — Unity will mint a fresh GUID.
4. Replace any in-scene/in-prefab reference to the package GUID with the new GUID from the duplicate.
5. Apply the Logic vs Visual Separation rule to the duplicate.

### Rules

| Rule | Why |
|------|-----|
| Never drag a `Library/PackageCache/...` prefab into a scene | Reference breaks on package upgrade |
| Always duplicate into `_GameFolders/Prefabs/<Category>/` first | Project owns the GUID and the asset lifecycle |
| Never edit a package prefab in place | UPM resolve overwrites it; Asset Store update overwrites it |
| Never copy `.meta` files from the package source | Forces Unity to assign a fresh GUID |
| Place duplicates by category, not by package | Keeps the project-side prefab tree organized by domain, not by vendor |

See also: `/discover` writes the per-package duplication plan into `.claude/skills/plugins/<package>/SKILL.md` under the `## Prefabs` section.
