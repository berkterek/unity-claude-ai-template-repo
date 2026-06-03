# UI RectTransform Guard — Design Spec

**Date:** 2026-06-03  
**Status:** Approved for implementation

---

## Problem

When creating UI GameObjects via MCP `manage_gameobject`, Unity assigns a regular `Transform` instead of `RectTransform` if the parent is not a Canvas at creation time or if no UI component triggers the auto-conversion. This causes broken UI prefabs — UI objects with `Transform` cannot be positioned or sized correctly on a Canvas.

---

## Root Cause

Unity auto-converts `Transform` → `RectTransform` only when:
1. A GameObject is created **as a child of a Canvas** (parent specified at creation time)
2. A UI component (`Image`, `Button`, `TextMeshProUGUI`, etc.) is added to it

If `manage_gameobject` creates the GO at scene root or without the Canvas `parentPath`, it gets a plain `Transform`. Saving it as a prefab at that point locks in the wrong component.

---

## Solution: B + C — Mandatory `manage_components` Step + Pre-Save `execute_code` Verification

### Discriminator: How to Identify a UI GameObject

**Primary signal (deterministic) — `parentPath`:**
If `parentPath` resolves to a `Canvas` or any child of a `Canvas`, the GO is a UI object and requires `RectTransform`.

**Secondary signal (supporting) — UI-specific components:**
Used only when `parentPath` is ambiguous. These component names are definitive UI signals:

| UI signal (RectTransform required) | NOT a UI signal |
|------------------------------------|-----------------|
| `Image`, `RawImage` | `TextMeshPro` (3D world-space) |
| `Button`, `Toggle`, `Slider` | `MeshRenderer`, `SpriteRenderer` |
| `TextMeshProUGUI` | `Collider` types, `Rigidbody` |
| `ScrollRect`, `InputField`, `CanvasGroup` | Any physics component |

> `TextMeshPro` (without `UGUI`) is 3D — it is NOT a UI signal.

---

## Workflow Change

### Current (broken)
```
manage_gameobject → create UI GO (may get Transform)
manage_prefabs → save as prefab (Transform locked in)
```

### New (correct)
```
manage_gameobject → create UI GO with Canvas parentPath     ← always specify parent
manage_components → set RectTransform anchor properties     ← confirms RectTransform exists
execute_code → verify GetComponent<RectTransform>() != null ← pre-save guard
manage_prefabs → save as prefab                             ← RectTransform guaranteed
```

---

## Implementation Targets

Three files need to be updated — no new files.

### 1. `.claude/agents/unity-ui-builder.md`

Add a **NON-NEGOTIABLE** rule block after Step 2 (Build Canvas via MCP):

```
## RectTransform Guard (NON-NEGOTIABLE)

For EVERY UI GameObject created via manage_gameobject:

1. **Always specify parentPath pointing to the Canvas or a Canvas child.**
   Unity auto-assigns RectTransform only when the parent is a Canvas at creation time.
   Never create a UI GO at scene root and reparent later.

2. **After creation, call manage_components to set RectTransform properties.**
   This step confirms RectTransform exists. If Unity returns an error on this call,
   the GO has a plain Transform — stop and diagnose before saving the prefab.

3. **Before saving as prefab, run this execute_code verification:**

   var go = GameObject.Find("SettingsPanel"); // replace with actual path
   var rt = go.GetComponent<RectTransform>();
   if (rt == null)
       Debug.LogError($"[RectTransformGuard] {go.name} has Transform, not RectTransform — fix before saving prefab.");
   else
       Debug.Log($"[RectTransformGuard] {go.name} OK — RectTransform confirmed.");

   If LogError appears → DO NOT save the prefab. Fix the GO first.

### UI GO Discriminator

A GO is a UI GO when:
- PRIMARY: parentPath points to a Canvas or any child of a Canvas
- SECONDARY (only if parentPath is ambiguous): the GO receives Image, RawImage, Button,
  Toggle, Slider, TextMeshProUGUI, ScrollRect, InputField, or CanvasGroup component

TextMeshPro (3D, without UGUI suffix) is NOT a UI signal.
```

---

### 2. `.claude/skills/core/unity-ugui.md`

Add a **Pre-Prefab Checklist** section after the Canvas Setup block:

```
## Pre-Prefab Checklist (NON-NEGOTIABLE)

Before saving any UI GO as a prefab, all three conditions must be true:

- [ ] GO was created with parentPath pointing to Canvas or Canvas child
- [ ] manage_components set RectTransform anchors without error
- [ ] execute_code GetComponent<RectTransform>() returned non-null (LogError = stop)

### UI GO Discriminator

PRIMARY: parentPath resolves to Canvas or Canvas child → UI GO → RectTransform required
SECONDARY: component list contains Image / Button / TextMeshProUGUI / Toggle / Slider /
           ScrollRect / InputField / CanvasGroup → UI GO → RectTransform required
NEVER: TextMeshPro (3D) is NOT a UI signal
```

---

### 3. `.claude/agents/unity-setup.md`

Add to the **Prefab Creation** section under the checklist:

```
- [ ] UI prefabs: parentPath was Canvas or Canvas child at creation time
- [ ] UI prefabs: manage_components set RectTransform without error
- [ ] UI prefabs: execute_code RectTransform guard passed (no LogError) before save
```

---

## Spec Self-Review

- **Placeholders:** None — all file paths and code snippets are concrete.
- **Consistency:** Discriminator rule (parentPath primary, component secondary) is identical across all three files.
- **Scope:** Three agent/skill files updated, no new files, no hooks required.
- **Ambiguity:** `TextMeshPro` vs `TextMeshProUGUI` distinction is explicit in all three locations.
