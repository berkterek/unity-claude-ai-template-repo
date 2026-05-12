---
name: audio-mixer-mcp
description: Use when configuring Unity AudioMixer exposed parameters, AudioSource routing, or verifying audio setup via Unity MCP tools (execute_code, find_gameobjects, manage_asset)
---

# AudioMixer Configuration via Unity MCP

## Overview

Use `execute_code` to inspect and configure AudioMixer exposed parameters and AudioSource routing at runtime in the Unity Editor. This fills the gap between C# audio patterns and MCP-based execution.

## Verify Exposed Parameters Exist

```python
# Check what parameters are exposed on a mixer
execute_code("""
using UnityEngine;
using UnityEngine.Audio;

var mixer = AssetDatabase.LoadAssetAtPath<AudioMixer>(
    "Assets/_GameFolders/Audio/MainMixer.mixer");
if (mixer == null) { Debug.LogError("Mixer not found"); return; }

// List all exposed parameters
var exposed = new System.Collections.Generic.List<string>();
// Unity doesn't have a public API to list exposed params — check via GetFloat
string[] paramNames = { "MasterVolume", "SfxVolume", "AmbientVolume" };
foreach (var p in paramNames)
{
    if (mixer.GetFloat(p, out float val))
        Debug.Log($"[OK] {p} = {val}");
    else
        Debug.LogError($"[MISSING] {p} not exposed");
}
""")
```

## Assign Mixer to AudioMixerController

```python
# Read the MonoBehaviour field, then set via manage_components or execute_code
execute_code("""
using UnityEngine;
using UnityEngine.Audio;
using UnityEditor;

var mixer = AssetDatabase.LoadAssetAtPath<AudioMixer>(
    "Assets/_GameFolders/Audio/MainMixer.mixer");

// Find the AudioMixerController MonoBehaviour in scene
var go = GameObject.Find("AudioRoot");  // adjust name
if (go == null) { Debug.LogError("AudioRoot not found"); return; }

var controller = go.GetComponent<Game.Concretes.Audio.AudioMixerController>();
if (controller == null) { Debug.LogError("AudioMixerController not found"); return; }

// Use SerializedObject to set private [SerializeField]
var so = new SerializedObject(controller);
so.FindProperty("_mixer").objectReferenceValue = mixer;
so.ApplyModifiedProperties();
EditorUtility.SetDirty(go);
Debug.Log("Mixer assigned to AudioMixerController");
""")
```

## Inspect AudioSource Routing

```python
# Find all AudioSources and check their mixer group and spatialBlend
execute_code("""
using UnityEngine;
using UnityEngine.Audio;

var sources = Object.FindObjectsByType<AudioSource>(FindObjectsSortMode.None);
foreach (var s in sources)
{
    string group = s.outputAudioMixerGroup != null ? s.outputAudioMixerGroup.name : "NONE";
    Debug.Log($"{s.gameObject.name}: group={group} spatialBlend={s.spatialBlend}");
}
""")
```

## Set AudioSource SpatialBlend for 3D Sources

```python
execute_code("""
using UnityEngine;
using UnityEditor;

// Tag 3D AudioSources (e.g. on enemy/environment GameObjects) — adjust filter as needed
var sources = Object.FindObjectsByType<AudioSource>(FindObjectsSortMode.None);
foreach (var s in sources)
{
    bool is3D = s.gameObject.CompareTag("Enemy") || s.gameObject.CompareTag("Environment");
    if (is3D && s.spatialBlend != 1f)
    {
        var so = new SerializedObject(s);
        so.FindProperty("m_panLevelCustomCurve").animationCurveValue =
            AnimationCurve.Constant(0, 1, 1);  // spatialBlend=1
        so.ApplyModifiedProperties();
        EditorUtility.SetDirty(s.gameObject);
        Debug.Log($"Set spatialBlend=1 on {s.gameObject.name}");
    }
}
""")
```

## Verify Mixer Group Routing

```python
execute_code("""
using UnityEngine;
using UnityEngine.Audio;
using UnityEditor;

var mixer = AssetDatabase.LoadAssetAtPath<AudioMixer>(
    "Assets/_GameFolders/Audio/MainMixer.mixer");
var masterGroup = mixer.FindMatchingGroups("Master")[0];
var sfxGroup    = mixer.FindMatchingGroups("SFX")[0];
var ambientGroup = mixer.FindMatchingGroups("Ambient")[0];

var sources = Object.FindObjectsByType<AudioSource>(FindObjectsSortMode.None);
foreach (var s in sources)
{
    if (s.outputAudioMixerGroup == null)
        Debug.LogWarning($"[UNROUTED] {s.gameObject.name} has no mixer group");
}
""")
```

## Set SpatialBlend=1 (3D) via SerializedProperty

`spatialBlend` is NOT directly a SerializedProperty — it's stored as `panLevelCustomCurve` (AnimationCurve).

```python
execute_code("""
var allSources = UnityEngine.Object.FindObjectsByType<UnityEngine.AudioSource>(
    UnityEngine.FindObjectsInactive.Include, UnityEngine.FindObjectsSortMode.None);
foreach (var s in allSources)
{
    // Filter by name or tag to target only 3D world sources
    if (!s.gameObject.name.ToLower().Contains("spirit")) continue;
    var so = new UnityEditor.SerializedObject(s);
    // AnimationCurve.Constant(0,1,1) = spatialBlend locked to 1.0 across all distances
    so.FindProperty("panLevelCustomCurve").animationCurveValue =
        UnityEngine.AnimationCurve.Constant(0f, 1f, 1f);
    so.ApplyModifiedProperties();
    UnityEditor.EditorUtility.SetDirty(s.gameObject);
    UnityEngine.Debug.Log("spatialBlend=1 set on: " + s.gameObject.name);
}
return null;
""")
```

> `AnimationCurve.Constant(0, 1, 1)` → spatialBlend = 1.0 (fully 3D).
> `AnimationCurve.Constant(0, 1, 0)` → spatialBlend = 0.0 (fully 2D, use for UI/music).

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Parameter name mismatch | Exact match required — "MasterVolume" not "Master Volume" |
| `mixer.GetFloat` returns false | Parameter not exposed in AudioMixer Exposed Parameters list |
| `outputAudioMixerGroup` is null | AudioSource not routed — assign via SerializedObject |
| `spatialBlend` direct SerializedProperty | Property doesn't exist — use `panLevelCustomCurve` AnimationCurve instead |
| `FindObjectsOfType` (old API) | Use `FindObjectsByType<T>(FindObjectsInactive.Include, FindObjectsSortMode.None)` |
