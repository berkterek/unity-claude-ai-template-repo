---
name: srp-batcher-mcp
description: Use when verifying or enabling SRP Batcher on a URP asset, auditing UI Raycast Targets, removing unused post-processing Volume components (Bloom, etc.), or verifying FadeOverlay Canvas settings via Unity MCP execute_code
---

# URP Optimization via Unity MCP

## Overview

These patterns let you audit and fix common URP performance issues entirely via `execute_code` without manual Editor navigation.

## Check SRP Batcher Status

```python
execute_code("""
var urpAsset = UnityEngine.Rendering.GraphicsSettings.defaultRenderPipeline
    as UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset;
if (urpAsset != null)
{
    UnityEngine.Debug.Log("SRP Batcher: " + urpAsset.useSRPBatcher);
    UnityEngine.Debug.Log("Dynamic Batching: " + urpAsset.supportsDynamicBatching);
}
return null;
""")
```

**Enable SRP Batcher if off:**
```python
execute_code("""
var urpAsset = UnityEngine.Rendering.GraphicsSettings.defaultRenderPipeline
    as UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset;
if (urpAsset != null)
{
    urpAsset.useSRPBatcher = true;
    urpAsset.supportsDynamicBatching = false; // conflicts with SRP Batcher
    UnityEditor.EditorUtility.SetDirty(urpAsset);
    UnityEngine.Debug.Log("SRP Batcher enabled.");
}
return null;
""")
```

> SRP Batcher and Dynamic Batching conflict — disable Dynamic Batching when enabling SRP Batcher.

## Audit UI Raycast Targets

Non-interactive UI elements with `raycastTarget=true` add unnecessary raycast cost every frame.

```python
execute_code("""
var graphics = UnityEngine.Object.FindObjectsByType<UnityEngine.UI.Graphic>(
    UnityEngine.FindObjectsInactive.Include, UnityEngine.FindObjectsSortMode.None);
int fixedCount = 0;
foreach (var g in graphics)
{
    bool isInteractive = g.GetComponent<UnityEngine.UI.Selectable>() != null;
    if (!isInteractive && g.raycastTarget)
    {
        g.raycastTarget = false;
        UnityEditor.EditorUtility.SetDirty(g);
        UnityEngine.Debug.Log("raycastTarget disabled: " + g.gameObject.name);
        fixedCount++;
    }
}
UnityEngine.Debug.Log("Fixed: " + fixedCount);
return null;
""")
```

## Inspect Volume Profile Components

```python
execute_code("""
var volumes = UnityEngine.Object.FindObjectsByType<UnityEngine.Rendering.Volume>(
    UnityEngine.FindObjectsInactive.Include, UnityEngine.FindObjectsSortMode.None);
foreach (var v in volumes)
{
    var profile = v.sharedProfile ?? v.profile;
    string profName = profile != null ? profile.name : "NONE";
    UnityEngine.Debug.Log(v.gameObject.name + " isGlobal=" + v.isGlobal + " profile=" + profName);
    if (profile != null)
        foreach (var c in profile.components)
            UnityEngine.Debug.Log("  " + c.GetType().Name + " active=" + c.active);
}
return null;
""")
```

## Remove Bloom from Volume Profile

```python
execute_code("""
var volumes = UnityEngine.Object.FindObjectsByType<UnityEngine.Rendering.Volume>(
    UnityEngine.FindObjectsInactive.Include, UnityEngine.FindObjectsSortMode.None);
foreach (var v in volumes)
{
    var profile = v.sharedProfile ?? v.profile;
    if (profile == null) continue;
    var bloom = profile.components.Find(c => c is UnityEngine.Rendering.Universal.Bloom);
    if (bloom != null)
    {
        profile.Remove<UnityEngine.Rendering.Universal.Bloom>();
        UnityEditor.EditorUtility.SetDirty(profile);
        UnityEngine.Debug.Log("Bloom removed from: " + profile.name);
    }
}
return null;
""")
```

## Verify FadeOverlay Canvas

```python
execute_code("""
// FadeOverlay should: renderMode=ScreenSpaceOverlay, no GraphicRaycaster, Image raycastTarget=false
var canvases = UnityEngine.Object.FindObjectsByType<UnityEngine.Canvas>(
    UnityEngine.FindObjectsInactive.Include, UnityEngine.FindObjectsSortMode.None);
foreach (var c in canvases)
{
    if (!c.gameObject.name.ToLower().Contains("fade")) continue;
    bool hasRaycaster = c.GetComponent<UnityEngine.UI.GraphicRaycaster>() != null;
    UnityEngine.Debug.Log("FadeOverlay: " + c.gameObject.name
        + " renderMode=" + c.renderMode
        + " hasRaycaster=" + hasRaycaster);
    // Check Image raycastTarget
    var img = c.GetComponentInChildren<UnityEngine.UI.Image>(true);
    if (img != null)
        UnityEngine.Debug.Log("  Image raycastTarget=" + img.raycastTarget);
}
return null;
""")
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| SRP Batcher not taking effect | Disable Dynamic Batching too (they conflict) |
| UHFPS / third-party URP asset | Cast to `UniversalRenderPipelineAsset` — same API |
| `sharedProfile` vs `profile` | Always `sharedProfile ?? profile`; inline profiles have `sharedProfile=null` |
| Volume profile has 0 components | Bloom was never added — no action needed |
| `SetDirty` missing | Without `SetDirty`, changes don't persist after domain reload |
