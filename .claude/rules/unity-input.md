# Input System Rules (NON-NEGOTIABLE)

The New Input System package is **mandatory**. Legacy `Input.GetKey`/`Input.GetAxis` is **BLOCKED** by hooks.

## Generated C# Class (Preferred Approach)

1. Create `Assets/Input/PlayerControls.inputactions` — define all action maps
2. Enable "Generate C# Class" in the asset inspector → generates `PlayerControls.cs`
3. Use the generated class in InputView (see architecture rules)

## InputView Pattern

```csharp
// InputView — the ONLY place that touches PlayerControls
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private PlayerSystem _playerSystem;

    private void Awake()
    {
        _controls = new PlayerControls();
    }

    [Inject]
    public void Construct(PlayerSystem playerSystem)
    {
        _playerSystem = playerSystem;
    }

    // MANDATORY: Enable actions in OnEnable
    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed += OnJump;
        _controls.Player.Attack.performed += OnAttack;
    }

    // MANDATORY: Disable actions and unsubscribe in OnDisable
    private void OnDisable()
    {
        _controls.Player.Jump.performed -= OnJump;
        _controls.Player.Attack.performed -= OnAttack;
        _controls.Player.Disable();
    }

    // Read continuous input in Update, cache for systems
    private void Update()
    {
        Vector2 moveInput = _controls.Player.Move.ReadValue<Vector2>();
        _playerSystem.SetMoveInput(moveInput);
    }

    private void OnJump(InputAction.CallbackContext ctx) => _playerSystem.Jump();
    private void OnAttack(InputAction.CallbackContext ctx) => _playerSystem.Attack();
}
```

## Rules

| Rule | Why |
|------|-----|
| **Enable in OnEnable, Disable in OnDisable** | Missing Enable = zero input received. Missing Disable = ghost callbacks, leaks |
| **Subscribe in OnEnable, unsubscribe in OnDisable** | Every `+=` must have a matching `-=` in OnDisable |
| **Read continuous input in Update** | FixedUpdate runs at different rate — input can be missed |
| **Cache input, apply in FixedUpdate** | Physics forces use cached values, not raw reads |
| **Never use legacy Input API** | `Input.GetKey`, `Input.GetAxis`, `Input.GetButton` are BLOCKED |
| **InputView is a View** | Pure thin adapter — reads input, calls Systems. Zero logic |
| **One InputView per scene** | Centralized input reading prevents duplicate subscriptions |

## Action Map Switching

```csharp
// Gameplay → UI (e.g., opening pause menu)
_controls.Player.Disable();
_controls.UI.Enable();

// UI → Gameplay (closing menu)
_controls.UI.Disable();
_controls.Player.Enable();
```

Always disable the current map **before** enabling the next. Never leave multiple gameplay maps enabled simultaneously.
