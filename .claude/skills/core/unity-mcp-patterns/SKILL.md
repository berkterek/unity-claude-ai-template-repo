---
name: unity-mcp-patterns
description: "How to use unity-mcp tools effectively — batch_execute for speed, read_console for verification, resource queries for project state, tool organization patterns."
alwaysApply: true
---

# Unity MCP Patterns

The unity-mcp server gives Claude Code direct control over the Unity Editor. These patterns ensure you use it efficiently and safely.

## Rule 1: batch_execute for Everything

Individual MCP calls have network overhead. `batch_execute` bundles multiple operations into one call — **10-100x faster**.

```
// BAD — 5 separate calls, 5 round trips
manage_gameobject → create Player
manage_components → add Rigidbody2D to Player
manage_components → add BoxCollider2D to Player
manage_components → add SpriteRenderer to Player
manage_components → configure Rigidbody2D

// GOOD — 1 batch call
batch_execute → [
  create Player,
  add Rigidbody2D,
  add BoxCollider2D,
  add SpriteRenderer,
  configure Rigidbody2D
]
```

Always batch when doing 2+ operations.

## Rule 2: read_console After Every Change

After writing scripts, creating objects, or modifying components, always check the console:

```
1. Write/Edit C# file
2. read_console → check for compilation errors
3. If errors: fix and repeat
4. Continue with MCP operations
5. read_console → check for runtime warnings
```

The console is your feedback loop. Don't assume operations succeeded.

## Rule 3: project_info Before Assumptions

Before making decisions about the project, read its state:

```
project_info resource → Unity version, platform, render pipeline
```

Don't assume:
- The project uses URP (might be Built-in or HDRP)
- The project targets PC (might be mobile)
- Certain packages are installed

## Rule 4: Tool Selection Guide

| Task | Tool | Key Actions |
|------|------|-------------|
| Create/load/save scene | `manage_scene` | create, load, save, validate |
| Create/modify GameObjects | `manage_gameobject` | create, modify, delete, find |
| Add/configure components | `manage_components` | add, remove, configure, get |
| Physics setup | `manage_physics` | settings, layers, materials, joints |
| Camera/Cinemachine | `manage_camera` | create, configure presets, extensions |
| Materials/Shaders | `manage_material` / `manage_shader` | create, assign, configure |
| Animation | `manage_animation` | clips, controllers, states |
| UI elements | `manage_ui` | create, layout, style |
| VFX | `manage_vfx` | particles, effects |
| Prefabs | `manage_prefabs` | create, instantiate, modify |
| ScriptableObjects | `manage_scriptable_object` | create, edit |
| Packages | `manage_packages` | install, remove, search |
| Builds | `manage_build` | configure, build, switch platform |
| Tests | `run_tests` | execute, get results |
| Profiling | `manage_profiler` | sessions, timing, memory |
| Graphics stats | `manage_graphics` | rendering stats, pipeline |
| Console output | `read_console` | errors, warnings, logs |
| API inspection | `unity_reflect` | live C# reflection |
| Documentation | `unity_docs` | official Unity docs |
| C# scripts | `create_script` / `validate_script` | create, validate |

## Rule 5: Scene Templates

When creating new scenes, use templates for quick setup:

```
manage_scene action:"create" template:"3d_basic"
// Creates scene with: Main Camera, Directional Light

manage_scene action:"create" template:"2d_basic"
// Creates scene with: Main Camera (orthographic)
```

## Rule 6: Error Recovery

If an MCP operation fails:
1. `read_console` — get the error message
2. Fix the underlying issue (missing reference, wrong type, etc.)
3. Retry the operation
4. If the error persists, fall back to writing an Editor script

## Rule 7: MCP vs File Editing

| Operation | Use MCP | Use File Edit |
|-----------|---------|---------------|
| Create GameObjects | Yes | Never |
| Edit scenes | Yes | Never |
| Edit prefabs | Yes | Never |
| Write C# scripts | Either | Preferred for complex scripts |
| Configure components | Yes | Never |
| Modify ProjectSettings | Yes | Never |
| Edit .shader/.hlsl files | No (Write tool) | Yes |
| Edit .uxml/.uss files | No (Write tool) | Yes |
| Edit .asmdef files | No (Write tool) | Yes |

## Rule 8: Multi-Instance

If the user has multiple Unity Editor instances:
```
unity_instances resource → list all running editors
set_active_instance → route commands to specific editor
```

Always check which instance is active before sending commands.

## Rule 9: Play-Mode & Test Traps (four measured symptoms; each invites a wrong diagnosis)

Every trap here produces a **plausible wrong diagnosis**, and acting on that diagnosis is
more expensive than the trap. Rule out the boring cause before believing the interesting one.

### 9.1 Play from the boot scene, not the scene you are testing

`play` on the gameplay scene can hang in `is_changing: true` for ~30s and return an empty
console. That reads as "the Editor lost focus" or "MCP is stuck" — both wrong.

Most likely cause — inferred, not measured; the remedy is the same either way: the scene's
`LifetimeScope` has its parent in the bootstrap scene, so nothing initialises. Open the boot
scene (`Bootstrap.unity`) and play from there.

Two cheap measurements that kill the wrong diagnoses first: a `Debug.Log` probe proves
`read_console` is alive (silence then means *the game never ran*, not that logging failed),
and `Application.runInBackground` tells you whether focus is even relevant. Do both before
touching Editor settings.

### 9.2 `execute_code` does not *reliably* drop Play mode — chain it, and check

**Measured:** five consecutive `execute_code` calls inside one Play session, all `codedom`,
all returning `isPlaying=True`. A whole win/lose/next/restart sequence was driven over that
chain. So read `isPlaying` out of each call's return value instead of assuming the session
died — the one-call rule is a fallback, not a constraint. The original note said it *can*
drop Play mode; reading that as "chaining is impossible" closed off Play-mode verification
entirely.

**Not measured — the cause.** A domain reload comes from recompiling *project* scripts, not
from CodeDom's in-memory assembly, so the likely story is that Play died in sessions where
agents were writing `.cs` files and `execute_code` was merely what ran at the time. That was
never reproduced on purpose. It also cannot be stated as fact for a second reason: whether a
mid-Play recompile stops Play at all is a **per-user Editor preference that lives outside the
repo** — Preferences → General → `Script Changes While Playing` takes
`RecompileAndContinuePlaying`, `RecompileAfterFinishedPlaying` or `StopPlayingAndRecompile`.
Under the first, writing a `.cs` mid-Play stops nothing.

> Provenance, because the first version of this note got it wrong: the three values were
> read by reflection on 2026-09-10 from a type named `ScriptCompilationDuringPlay` — which
> resolves out of `JetBrains.Rider.Unity.Editor.Plugin`, i.e. **Rider's model of the Unity
> setting, not a Unity API**. The values are right and the load-bearing claim (a three-mode
> per-user preference outside the repo) stands; the authority did not. Cite the Preferences
> UI, and if you need the API, verify it against `UnityEditor` yourself.

**So the practical rule is about the recompile, not about `execute_code`:** avoid writing
`.cs` files during a Play session you intend to keep, because you cannot know which of the
three modes the machine is set to — and if Play does die mid-chain, that preference is the
first thing to check, not the MCP tool.

### 9.3 `GraphicRaycaster` cannot see a graphic activated in the same call

Activate a panel and raycast in one call → **0 hits**. The next call returns the correct
hit stack.

This produces a false negative identical to a genuinely broken raycast target — so an
automated UI check that activates and raycasts in one call will report working UI as broken.
Split them across two calls, always. Use `ExecuteHierarchy` with a real `GraphicRaycaster`
for the click, not a synthetic event.

### 9.4 `tests_running` has two causes, and the fix for one is wrong for the other

`run_tests` returning `blocked_reason: "tests_running"` looks like a single condition. It is
two, and they need opposite responses:

| Cause | Signal | Response |
|---|---|---|
| A PlayMode job stalled because the Editor window is not focused | `stuck_suspected: true`, `blocked_reason: "editor_unfocused"` | `run_tests(clear_stuck=true)`, then ask the user to keep the Unity window in front |
| MCP is pointed at **another Unity project** | nothing local looks wrong — the block is real, in a different Editor | Run the `mcp-preflight` skill: pin the instance and verify `Application.dataPath` resolves inside this repo |

Both were measured. The second is the dangerous one: `clear_stuck` on a wrong-instance block
is a plausible move on right-looking evidence, and it clears a job in a project you were not
supposed to be touching. Verify `dataPath` before reaching for `clear_stuck` — and treat any
measurement taken while the instance was unverified as invalid, not merely suspect.
