# Input System Rules (NON-NEGOTIABLE)

The New Input System package is **mandatory**. Legacy `Input.GetKey`/`Input.GetAxis` is **BLOCKED** by hooks.

The input architecture uses two layers:
- `InputService` (pure C#, **pull-based — no tick of any kind**) — owns `PlayerControls`, handles action map switching, cross-module singleton
- `InputHandler` (pure C#, per-prefab) — reads specific actions for one prefab, calls its service

## Cards

### Card 1: InputService is Pure C# and Pull-Based — No Cached Frame State

**WHEN:** Implementing the global input reader.

**WRONG — MonoBehaviour:**
```csharp
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private void Awake() => _controls = new PlayerControls();
    private void OnEnable() { _controls.Player.Enable(); }
    private void Update() => _playerService.SetMoveInput(_controls.Player.Move.ReadValue<Vector2>());
}
```

**ALSO WRONG — pure C#, but caches per-frame state behind a tick:**
```csharp
public sealed class InputService : IInputService, ITickable, IInitializable, IDisposable
{
    public void Tick()
    {
        _moveInput   = _controls.Player.Move.ReadValue<Vector2>();
        _jumpPressed = false; // who clears vs. who reads is now an ordering question
    }

    private void OnJump(InputAction.CallbackContext _) => _jumpPressed = true;
}
```

**RIGHT — read on demand, store nothing:**
```csharp
public sealed class InputService : IInputService, IInitializable, IDisposable
{
    private readonly PlayerControls _controls;
    public InputService() => _controls = new PlayerControls();

    public Vector2 MoveInput   => _controls.Player.Move.ReadValue<Vector2>();
    public bool    JumpPressed => _controls.Player.Jump.WasPressedThisFrame();

    public void Initialize() { _controls.Player.Enable(); }
    public void Dispose()    { _controls.Player.Disable(); _controls.Dispose(); }
}
```

**GOTCHA:** The middle version is the trap, and it is what this rule file itself used to prescribe. It splits **who advances the state** (VContainer's tick) from **who consumes it** (a MonoBehaviour `Update`), which makes correctness depend on the relative PlayerLoop position of the two — and VContainer publishes no ordering guarantee between `ITickable` and `MonoBehaviour.Update`. Pull-based deletes the question rather than answering it: `ReadValue()` and `WasPressedThisFrame()` are frame-scoped by the Input System, so N consumers reading in the same frame all get the same answer, in any order, with nothing to clear. Do **not** add a `Tick()`/`FixedTick()` to `InputService` "in case it is needed later" — an empty tick method is an invitation for the next refactor to reintroduce the cache. Hand-rolling frame-edge detection with a `performed` callback plus a bool flag also violates `csharp-unity.md` Card 6 (Reuse Before You Hand-Roll): `WasPressedThisFrame()` already ships it.

---

### Card 2: InputHandler is Pure C# — NOT MonoBehaviour

**WHEN:** Routing input to a specific prefab's service (player, vehicle, turret…).

**WRONG:**
```csharp
public sealed class PlayerInputView : MonoBehaviour
{
    [Inject] private IInputService _input;
    [Inject] private IPlayerService _player;
    private void Update() => _player.SetMoveInput(_input.MoveInput);
}
```

**RIGHT:**
```csharp
public sealed class PlayerInputHandler : IPlayerInputHandler
{
    private readonly IInputService  _inputService;
    private readonly IPlayerService _playerService;

    public PlayerInputHandler(IInputService inputService, IPlayerService playerService)
    {
        _inputService  = inputService;
        _playerService = playerService;
    }

    public void Tick(float deltaTime)
    {
        _playerService.SetMoveInput(_inputService.MoveInput);
        if (_inputService.JumpPressed) _playerService.Jump();
    }
}
```

**GOTCHA:** `InputHandler` needs no `[SerializeField]` and no Unity lifecycle callbacks — it receives `IInputService` via constructor. The MonoBehaviour shell (`PlayerController`) calls `_inputHandler.Tick(Time.deltaTime)` in its own `Update()`.

---

### Card 3: ONE InputService — Duplicate Subscriptions are Fatal

**WHEN:** Registering `InputService` in an installer.

**WRONG:**
```csharp
// Registered by both InputModule and PlayerModule → two PlayerControls instances, two subscriptions
builder.Register<InputService>(Lifetime.Transient).AsImplementedInterfaces();
```

**RIGHT:**
```csharp
builder.RegisterEntryPoint<InputService>().AsImplementedInterfaces();
// Singleton lifetime + wires IInitializable/IDisposable (Enable/Disable). No ITickable to wire.
```

**GOTCHA:** Two `InputService` instances means `PlayerControls` is enabled twice — every action fires twice. The load-bearing part of this card is **Singleton**, not the registration call: a plain `builder.Register<InputService>(Lifetime.Singleton).AsImplementedInterfaces()` prevents the duplicate just as well, and is the right choice if the service ever stops needing `Initialize`/`Dispose`. `RegisterEntryPoint` is preferred here only because `IInitializable`/`IDisposable` still carry the `Enable`/`Disable` pair — it is no longer about a tick. Do not read this card as "the mechanism is mandatory"; read it as "one instance is mandatory".

---

### Card 4: Action Map Switching via IInputService — Never Direct

**WHEN:** Opening a pause menu, dialog, or any UI that consumes input.

**WRONG:**
```csharp
_controls.Player.Disable();
_controls.UI.Enable();
```

**RIGHT:**
```csharp
_inputService.EnableUI();      // pause menu opens
_inputService.EnableGameplay(); // pause menu closes
```

**GOTCHA:** Calling `_controls` directly from outside `InputService` breaks the "single owner" contract. Any class that holds `IInputService` must use the switching API — never access `PlayerControls` directly.

---

### Card 5: A Discrete Press Consumed in FixedUpdate Needs a Latch — In the Handler, Not the Service

**WHEN:** A one-frame press (jump, dash, fire) drives physics, so it is consumed inside `FixedUpdate`/`FixedTick` rather than `Update`.

**WRONG:**
```csharp
// PlayerController
private void FixedUpdate() => _movementHandler.FixedTick(Time.fixedDeltaTime);

// MovementHandler.FixedTick — reads the frame-scoped press directly
if (_inputService.JumpPressed) Jump();
```

**RIGHT:**
```csharp
// PlayerController — shell stays state-free: latch in Update, consume in FixedUpdate
private void Update()      => _movementHandler.LatchJump(_inputService.JumpPressed);
private void FixedUpdate() => _movementHandler.FixedTick(Time.fixedDeltaTime);

// MovementHandler — owns the latch, consumes it exactly once
public void LatchJump(bool pressed) { if (pressed) _jumpLatched = true; }

public void FixedTick(float fixedDeltaTime)
{
    _rigidbody.velocity = ReadMove() * _config.MoveSpeed; // continuous — no latch needed

    if (_jumpLatched)
    {
        _jumpLatched = false;
        _rigidbody.AddForce(Vector3.up * _config.JumpForce, ForceMode.Impulse);
    }
}
```

**GOTCHA:** `FixedUpdate` runs **zero or more** times per rendered frame, not exactly once. Reading a frame-scoped press inside it therefore fails in both directions: on a frame where `FixedUpdate` does not run, the press is silently dropped; on a frame where it runs twice, the same press is consumed twice and the player double-jumps. Continuous values (`MoveInput`) have neither problem — they are sampled, not consumed — so do **not** latch them. The latch belongs to the handler that consumes it, never to `InputService`: a latch inside the shared service would be a single flag raced over by every consumer, where whichever handler ticks first eats the press for all of them. Keeping it in the handler also keeps the shell state-free per `solid-oop.md` (no state fields on a Controller).

---

## Generated C# Class (Preferred Approach)

1. Create `Assets/Input/PlayerControls.inputactions` — define all action maps
2. Enable "Generate C# Class" in the asset inspector → generates `PlayerControls.cs`
3. Use the generated class exclusively inside `InputService` — no other class touches it

---

## InputService — Pure C#, Pull-Based

`InputService` is the single owner of `PlayerControls`. It is registered as a `Singleton` entry point — VContainer calls `Initialize()` once to enable the maps and `Dispose()` once to tear them down. **It is never ticked, by VContainer or by anyone else**: every property reads the Input System on demand, so there is no per-frame state to advance.

```csharp
// Game/Abstracts/Input/IInputService.cs
using UnityEngine;

namespace Game.Abstracts.Input
{
    public interface IInputService
    {
        /// <summary>Current move axis value, read from the device on every call.</summary>
        /// <remarks>
        /// Postcondition: Normalized direction or zero vector when no input is held.
        /// Idempotent: Yes — repeated reads within one frame return the same value.
        /// </remarks>
        Vector2 MoveInput { get; }

        /// <summary>True for the duration of the frame in which the Jump action was pressed.</summary>
        /// <remarks>
        /// Postcondition: Stays true for every read within that frame; false from the next frame on.
        /// Idempotent: Yes — reading does NOT consume the press, so any number of consumers may read it.
        /// Side effect: None. A consumer that must consume the press exactly once owns its own latch (Card 5).
        /// </remarks>
        bool JumpPressed { get; }

        /// <summary>Disables UI map, enables Player map.</summary>
        void EnableGameplay();

        /// <summary>Disables Player map, enables UI map.</summary>
        void EnableUI();
    }
}
```

```csharp
// Game/Concretes/Input/InputService.cs
using System;
using Game.Abstracts.Input;
using UnityEngine;
using UnityEngine.InputSystem;
using VContainer.Unity;

namespace Game.Concretes.Input
{
    public sealed class InputService : IInputService, IInitializable, IDisposable
    {
        #region Fields

        private readonly PlayerControls _controls; // the only field — no cached frame state

        #endregion

        #region Constructor

        public InputService()
        {
            _controls = new PlayerControls(); // dependency-free generated class — allowed in constructor
        }

        #endregion

        #region IInputService

        public Vector2 MoveInput   => _controls.Player.Move.ReadValue<Vector2>();
        public bool    JumpPressed => _controls.Player.Jump.WasPressedThisFrame();

        public void EnableGameplay()
        {
            _controls.UI.Disable();
            _controls.Player.Enable();
        }

        public void EnableUI()
        {
            _controls.Player.Disable();
            _controls.UI.Enable();
        }

        #endregion

        #region Lifecycle

        public void Initialize()
        {
            _controls.Player.Enable();
        }

        public void Dispose()
        {
            _controls.Player.Disable();
            _controls.Dispose();
        }

        #endregion
    }
}
```

> No `Tick()`, no `performed` subscription, no flag to clear — and therefore no unsubscribe to forget in `Dispose()`. `WasPressedThisFrame()` is frame-scoped by the Input System, so the frame-edge detection the old `performed`-plus-bool pattern hand-rolled is already provided.

> `new PlayerControls()` in the constructor is correct — `PlayerControls` is a dependency-free generated class. The same logic that permits it in `Awake()` (per `solid-oop.md` Awake clarification) applies to constructors.

---

## InputHandler — Pure C#, Per-Prefab

Each prefab that needs to respond to input gets its own `InputHandler`. The handler reads only the actions it needs from `IInputService` and delegates to its domain service.

```csharp
// Game/Abstracts/Input/IPlayerInputHandler.cs
namespace Game.Abstracts.Input
{
    public interface IPlayerInputHandler
    {
        void Tick(float deltaTime);
    }
}
```

```csharp
// Game/Concretes/Players/PlayerInputHandler.cs
using Game.Abstracts.Input;
using Game.Abstracts.Players;

namespace Game.Concretes.Players
{
    public sealed class PlayerInputHandler : IPlayerInputHandler
    {
        #region Fields

        private readonly IInputService  _inputService;
        private readonly IPlayerService _playerService;

        #endregion

        #region Constructor

        public PlayerInputHandler(IInputService inputService, IPlayerService playerService)
        {
            _inputService  = inputService;
            _playerService = playerService;
        }

        #endregion

        #region IPlayerInputHandler

        public void Tick(float deltaTime)
        {
            _playerService.SetMoveInput(_inputService.MoveInput);

            if (_inputService.JumpPressed)
            {
                _playerService.Jump();
            }
        }

        #endregion
    }
}
```

The MonoBehaviour shell wires and drives it:

```csharp
// Game/Concretes/Players/PlayerController.cs
using Game.Abstracts.Input;
using UnityEngine;
using VContainer;

namespace Game.Concretes.Players
{
    public sealed class PlayerController : MonoBehaviour
    {
        #region Fields

        private IPlayerInputHandler _inputHandler;

        #endregion

        #region Lifecycle

        [Inject]
        public void Construct(IPlayerInputHandler inputHandler)
        {
            _inputHandler = inputHandler;
        }

        private void Update() => _inputHandler.Tick(Time.deltaTime);

        #endregion
    }
}
```

> If `PlayerInputHandler` depends only on services already in the container, register it normally and inject `IPlayerInputHandler` into `PlayerController`. If it needs no container dependencies beyond `IInputService`, wire it with `new` inside `Construct`.

---

## InputModule (Registration)

Register `InputService` once — in the module that owns input, not in every prefab's installer.

```csharp
// Game/Concretes/Input/InputModule.cs
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Input
{
    public static class InputModule
    {
        public static void Install(IContainerBuilder builder)
        {
            // Singleton lifetime + wires IInitializable/IDisposable (map Enable/Disable). No tick.
            builder.RegisterEntryPoint<InputService>().AsImplementedInterfaces();

            // InputHandler is registered in the module that owns the prefab (e.g. PlayerModule)
            // builder.Register<PlayerInputHandler>(Lifetime.Singleton).As<IPlayerInputHandler>();
        }
    }
}
```

In `AppModules.cs` (or equivalent): `InputModule.Install(builder);`

---

## Rules

| Rule | Why |
|------|-----|
| **Enable in `Initialize()`, disable + unsubscribe in `Dispose()`** | VContainer lifecycle — not Unity lifecycle |
| **Continuous input read on demand via `ReadValue<T>()`** | No cached state to go stale, and no ordering dependency between reader and writer |
| **Discrete input read on demand via `WasPressedThisFrame()`** | Frame-scoped by the Input System; reading does not consume, so N consumers agree (Card 1) |
| **`InputService` exposes NO `Tick`/`FixedTick`/`LateTick` — not even an unused one** | Nothing to advance; an empty tick invites a cache, and a cache brings the ordering bug back |
| **A press consumed in `FixedUpdate` is latched by the consuming handler** | `FixedUpdate` runs 0..N times per frame — an unlatched press is dropped or double-consumed (Card 5) |
| **Action map switching via `IInputService.EnableGameplay()`/`EnableUI()`** | Single point of control — callers never touch `_controls` directly |
| **ONE `InputService` in the project (`Singleton`)** | Prevents duplicate `PlayerControls` subscriptions. `Singleton` is the requirement; `RegisterEntryPoint` is just how `Initialize`/`Dispose` get wired (Card 3) |
| **`InputHandler` is pure C# — NOT MonoBehaviour** | No `[SerializeField]` needed, `IInputService` injected via constructor — Card 0 condition not met |
| **Never use legacy Input API** | `Input.GetKey`, `Input.GetAxis`, `Input.GetButton` are BLOCKED by hook |

---

## Action Map Switching

All map switching goes through `IInputService`. Callers never access `PlayerControls` directly.

```csharp
// Pause menu opens
_inputService.EnableUI();

// Pause menu closes
_inputService.EnableGameplay();
```

`InputService.EnableGameplay()` and `EnableUI()` always disable the outgoing map before enabling the incoming one — multiple gameplay maps active simultaneously is prevented by design.

> See also: `rules/solid-oop.md` → Card 0 (MonoBehaviour justification), Tier 2 (a Handler is ticked by its owning shell), and EntryPoint (`ITickable` is not used in this project — a service that needs a frame tick exposes `Tick(float)` and its domain's Mono shell forwards it); `rules/csharp-unity.md` → Card 4 (#region for 3+ methods) and Card 6 (Reuse Before You Hand-Roll)
