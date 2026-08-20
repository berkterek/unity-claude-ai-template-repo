---
name: input-system
description: New Input System — pull-based InputService (pure C#) + per-prefab InputHandler, action map switching, the FixedUpdate latch rule, legacy Input API ban. Use when writing anything input-related, when you see Input.GetKey/GetAxis in code, or when switching action maps. The legacy Input API is banned outright.
model-tier: normal
---

# Input System

> **`.claude/rules/unity-input.md` is the authority.** Read it before writing input code — this skill is the short form, the rule file carries the cards, the full `InputService`/`InputHandler` listings and the enforcement table. On any conflict, the rule file wins.

## The shape

```
InputService   ← pure C#, Singleton, owns PlayerControls. PULL-BASED: every property
                 reads the Input System on demand. No Tick/FixedTick of any kind.
InputHandler   ← pure C#, one per prefab. Reads only what that prefab needs from
                 IInputService and calls its domain service. Ticked by its Mono shell.
```

```csharp
public sealed class InputService : IInputService, IInitializable, IDisposable
{
    private readonly PlayerControls _controls; // the only field — no cached frame state

    public Vector2 MoveInput   => _controls.Player.Move.ReadValue<Vector2>();
    public bool    JumpPressed => _controls.Player.Jump.WasPressedThisFrame();

    public void Initialize() => _controls.Player.Enable();
    public void Dispose()    { _controls.Player.Disable(); _controls.Dispose(); }
}
```

Registration — one instance, always:

```csharp
builder.RegisterEntryPoint<InputService>().AsImplementedInterfaces();
```

`Singleton` is the requirement; `RegisterEntryPoint` is just how `Initialize`/`Dispose` get wired. Two instances mean `PlayerControls` is enabled twice and every action fires twice.

## Non-negotiables

| Rule | Why |
|---|---|
| **`InputView` does not exist** — it was removed | Input is not a MonoBehaviour concern; the service is pure C#, the handler is pure C# |
| `InputService` exposes **no** `Tick`/`FixedTick`/`LateTick`, not even an empty one | Nothing to advance; an empty tick invites a cache, and a cache reintroduces the ordering bug between the container's tick and `MonoBehaviour.Update` |
| Continuous input via `ReadValue<T>()`, discrete via `WasPressedThisFrame()` | Frame-scoped by the Input System; reading does not consume, so N consumers agree in any order |
| A press consumed in `FixedUpdate` is latched **by the consuming handler** | `FixedUpdate` runs 0..N times per frame — unlatched, the press is dropped or double-consumed. A latch in the shared service would be raced over by every consumer |
| `InputHandler` is pure C#, never a MonoBehaviour | No `[SerializeField]` needed; `IInputService` arrives via constructor — Card 0 is not satisfied |
| Map switching only via `IInputService.EnableGameplay()` / `EnableUI()` | Single owner; callers never touch `_controls` |
| Legacy `Input.GetKey` / `GetAxis` / `GetButton` | Blocked by hook |

Full cards, the latch example and the `PlayerInputHandler`/`PlayerController` listings: `.claude/rules/unity-input.md`.
