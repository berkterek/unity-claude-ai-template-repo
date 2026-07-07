# Input System Rules (NON-NEGOTIABLE)

The New Input System package is **mandatory**. Legacy `Input.GetKey`/`Input.GetAxis` is **BLOCKED** by hooks.

The input architecture uses two layers:
- `InputService` (pure C#, `ITickable`) — owns `PlayerControls`, handles action map switching, cross-module singleton
- `InputHandler` (pure C#, per-prefab) — reads specific actions for one prefab, calls its service

## Cards

### Card 1: InputService is Pure C# — NOT MonoBehaviour

**WHEN:** Implementing the global input reader.

**WRONG:**
```csharp
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private void Awake() => _controls = new PlayerControls();
    private void OnEnable() { _controls.Player.Enable(); }
    private void Update() => _playerService.SetMoveInput(_controls.Player.Move.ReadValue<Vector2>());
}
```

**RIGHT:**
```csharp
public sealed class InputService : IInputService, ITickable, IInitializable, IDisposable
{
    private readonly PlayerControls _controls;
    public InputService() => _controls = new PlayerControls();
    public void Initialize() { _controls.Player.Enable(); /* ... */ }
    public void Tick()       { _moveInput = _controls.Player.Move.ReadValue<Vector2>(); }
    public void Dispose()    { _controls.Player.Disable(); _controls.Dispose(); }
}
```

**GOTCHA:** `InputService` has no `[SerializeField]` and no Unity callbacks it cannot handle in `Initialize`/`Dispose`. Card 0 in `solid-oop.md` says MonoBehaviour is only justified when one of those is required — neither applies here. VContainer's `ITickable` replaces `Update()`.

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
// Registered in both AppInstaller and PlayerInstaller → two PlayerControls instances, two subscriptions
builder.Register<InputService>(Lifetime.Transient).AsImplementedInterfaces();
```

**RIGHT:**
```csharp
builder.RegisterEntryPoint<InputService>().AsImplementedInterfaces();
// RegisterEntryPoint uses Singleton lifetime and wires ITickable/IInitializable/IDisposable automatically
```

**GOTCHA:** Two `InputService` instances means `PlayerControls` is enabled twice — every action fires twice. Always `Singleton`, always `RegisterEntryPoint`.

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

## Generated C# Class (Preferred Approach)

1. Create `Assets/Input/PlayerControls.inputactions` — define all action maps
2. Enable "Generate C# Class" in the asset inspector → generates `PlayerControls.cs`
3. Use the generated class exclusively inside `InputService` — no other class touches it

---

## InputService — Pure C#, ITickable

`InputService` is the single owner of `PlayerControls`. It is registered as a `Singleton` entry point — VContainer calls `Initialize()` once and `Tick()` every frame.

```csharp
// Game/Abstracts/Input/IInputService.cs
using UnityEngine;

namespace Game.Abstracts.Input
{
    public interface IInputService
    {
        /// <summary>Current move axis value. Updated every Tick.</summary>
        /// <remarks>
        /// Postcondition: Normalized direction or zero vector when no input is held.
        /// </remarks>
        Vector2 MoveInput { get; }

        /// <summary>True only on the frame the Jump action was performed.</summary>
        /// <remarks>
        /// Postcondition: Reset to false at the start of the next Tick.
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
    public sealed class InputService : IInputService, ITickable, IInitializable, IDisposable
    {
        #region Fields

        private readonly PlayerControls _controls;
        private Vector2 _moveInput;
        private bool    _jumpPressed;

        #endregion

        #region Constructor

        public InputService()
        {
            _controls = new PlayerControls(); // dependency-free generated class — allowed in constructor
        }

        #endregion

        #region IInputService

        public Vector2 MoveInput  => _moveInput;
        public bool    JumpPressed => _jumpPressed;

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
            _controls.Player.Jump.performed += OnJump;
        }

        public void Tick()
        {
            _jumpPressed = false; // clear one-frame flag before consumers read it
            _moveInput   = _controls.Player.Move.ReadValue<Vector2>();
        }

        public void Dispose()
        {
            _controls.Player.Jump.performed -= OnJump;
            _controls.Player.Disable();
            _controls.Dispose();
        }

        #endregion

        #region Private Methods

        private void OnJump(InputAction.CallbackContext _) => _jumpPressed = true;

        #endregion
    }
}
```

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
            // RegisterEntryPoint: Singleton lifetime + wires ITickable, IInitializable, IDisposable
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
| **Continuous input read in `Tick()`, cleared each frame** | Prevents stale input crossing frame boundaries |
| **Discrete input via `performed` callback, stored as bool flag** | Reliable one-frame detection; `ReadValue` misses button presses between ticks |
| **Action map switching via `IInputService.EnableGameplay()`/`EnableUI()`** | Single point of control — callers never touch `_controls` directly |
| **ONE `InputService` in the project (Singleton via `RegisterEntryPoint`)** | Prevents duplicate `PlayerControls` subscriptions — the primary risk of the old MonoBehaviour pattern |
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

> See also: `rules/solid-oop.md` → Card 0 (MonoBehaviour justification); `rules/architecture.md` → ITickable / RegisterEntryPoint pattern; `rules/csharp-unity.md` → Card 4 (#region for 3+ methods)
