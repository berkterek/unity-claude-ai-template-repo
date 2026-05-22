---
name: input-system
description: New Input System & InputView pattern — PlayerControls generated class kullanımı, OnEnable/OnDisable abonelik kuralları, action map switching, legacy Input API yasağı. Input ile ilgili herhangi bir şey yazarken, InputView oluştururken, Input.GetKey/GetAxis gören kodda, action map geçişi yaparken bu skill'i kullan. Legacy Input API tamamen yasak — her input New Input System üzerinden geçer.
model-tier: normal
---

# Input System — InputView Pattern

## Kurulum

1. `Assets/Input/PlayerControls.inputactions` oluştur — tüm action map'leri tanımla
2. Inspector'da "Generate C# Class" aktif et → `PlayerControls.cs` üretilir
3. `InputView` MonoBehaviour yaz — `PlayerControls`'a dokunan tek sınıf

## InputView — Tam Örnek

```csharp
public sealed class InputView : MonoBehaviour
{
    #region Fields

    private PlayerControls _controls;
    private IPlayerService _playerService;

    #endregion

    #region Lifecycle

    private void Awake()
    {
        _controls = new PlayerControls();
    }

    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed   += OnJump;
        _controls.Player.Attack.performed += OnAttack;
    }

    private void OnDisable()
    {
        _controls.Player.Jump.performed   -= OnJump;
        _controls.Player.Attack.performed -= OnAttack;
        _controls.Player.Disable();
    }

    private void Update()
    {
        _playerService.SetMoveInput(_controls.Player.Move.ReadValue<Vector2>());
    }

    #endregion

    #region Constructor

    [Inject]
    public void Construct(IPlayerService playerService)
    {
        _playerService = playerService;
    }

    #endregion

    #region Private Methods

    private void OnJump(InputAction.CallbackContext ctx)   => _playerService.Jump();
    private void OnAttack(InputAction.CallbackContext ctx) => _playerService.Attack();

    #endregion
}
```

## Zorunlu Kurallar

| Kural | Sebep |
|-------|-------|
| `Enable` → `OnEnable`, `Disable` → `OnDisable` | Enable eksikse sıfır input gelir; Disable eksikse ghost callback + leak |
| `+=` ve `-=` aynı method'a | Her Subscribe'ın eşleşen Unsubscribe'ı olmalı |
| Sürekli input (`ReadValue`) → `Update` | FixedUpdate farklı rate'de çalışır, input kaçar |
| Fizik için input cache'le, `FixedUpdate`'de uygula | Physics force'lar cached değeri kullanır |
| `Input.GetKey` / `Input.GetAxis` yasak | Hook tarafından bloklanır (exit 2) |
| Bir sahnede tek `InputView` | Duplicate subscription önler |

## Action Map Switching

```csharp
// Gameplay → UI (pause menu açılırken)
_controls.Player.Disable();
_controls.UI.Enable();

// UI → Gameplay (menu kapanırken)
_controls.UI.Disable();
_controls.Player.Enable();
```

Mevcut map'i devre dışı bırak, **sonra** yenisini aç. Aynı anda birden fazla gameplay map açık kalmamalı.

## Service Tarafı

Servisler input'tan habersizdir — sadece komut alır:

```csharp
public interface IPlayerService
{
    void SetMoveInput(Vector2 input);
    void Jump();
    void Attack();
}
```

`InputView` ince bir adaptör — okur, iletir, sıfır logic.

## Yasak Kullanımlar

```csharp
// YASAK — legacy API, hook bloklar
Input.GetKey(KeyCode.Space)
Input.GetAxis("Horizontal")
Input.GetButton("Fire1")

// YASAK — InputView dışında PlayerControls oluşturmak
var controls = new PlayerControls(); // başka sınıfta

// DOĞRU
_controls.Player.Move.ReadValue<Vector2>()
_controls.Player.Jump.performed += OnJump;
```
