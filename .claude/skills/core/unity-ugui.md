---
name: unity-ugui
description: "Unity runtime UI implementation guide using UGUI (Canvas-based). Use this skill whenever building, modifying, or debugging any runtime UI in the project — Canvas screens, Buttons, TextMeshPro labels, Scroll Views, popups, HUD elements, or any MonoBehaviour View script. Triggers on: 'add UI', 'create canvas', 'build screen', 'add button', 'popup', 'scroll view', 'HUD', 'menu screen', 'dialog', or any request involving Unity's runtime UI layer."
---

# Unity UGUI — Runtime UI

Runtime UI in this project is **UGUI only** (Canvas-based). UI Toolkit is Editor-only — never use `UIDocument` or `VisualElement` in runtime scenes.

## Quick Decision

| What you're building | Pattern |
|---------------------|---------|
| Menu / screen | View MonoBehaviour + Canvas prefab via MCP |
| HUD (health, score, timer) | View MonoBehaviour + dedicated Canvas_HUD |
| Popup / dialog | Separate Canvas prefab, show/hide via service |
| Scrollable list | ScrollRect + pool — never Instantiate per item |
| World-space label | Canvas (World Space) child of the target GO |

---

## 1. View Script Pattern

All UI logic lives in a `View` MonoBehaviour. The View is a thin adapter: it reads input events and calls a service. Zero game logic inside.

```csharp
public sealed class MainMenuView : MonoBehaviour
{
    [SerializeField] private Button _playButton;
    [SerializeField] private Button _settingsButton;
    [SerializeField] private TextMeshProUGUI _titleText;

    private IMenuService _menuService;

    [Inject]
    public void Construct(IMenuService menuService) => _menuService = menuService;

    private void OnEnable()
    {
        _playButton.onClick.AddListener(OnPlayClicked);
        _settingsButton.onClick.AddListener(OnSettingsClicked);
    }

    private void OnDisable()
    {
        _playButton.onClick.RemoveListener(OnPlayClicked);
        _settingsButton.onClick.RemoveListener(OnSettingsClicked);
    }

    private void OnPlayClicked()     => _menuService.StartGame();
    private void OnSettingsClicked() => _menuService.OpenSettings();
}
```

**Rules:**
- All references via `[SerializeField]` — no `Find`, no `GetComponent`
- Subscribe `OnEnable` / unsubscribe `OnDisable` — mandatory pair, every listener
- `AddListener` / `RemoveListener` in code only — Inspector onClick list stays empty
- No `UnityEvent` fields — use `Button.onClick.AddListener` (the only approved UnityEvent usage)
- Call service methods only — no direct state mutation in the View

---

## 2. Canvas Setup via MCP

Always build Canvas hierarchy via MCP `batch_execute`. Never place bare GameObjects.

```
batch_execute:
  1. manage_gameobject: create Canvas under [UI] container
     - add Canvas (Screen Space - Overlay)
     - add CanvasScaler (Scale With Screen Size, 1920×1080)
     - add GraphicRaycaster
  2. manage_gameobject: create background Panel child
  3. manage_gameobject: create TitleText (TextMeshProUGUI)
  4. manage_gameobject: create PlayButton (Button + TextMeshProUGUI label child)
  5. manage_gameobject: create SettingsButton (Button + TextMeshProUGUI label child)
  6. manage_components: attach View script to Canvas root
  7. manage_components: set RectTransform anchors / positions
```

Save as prefab under `_GameFolders/Prefabs/UI/` using the correct subfolder:

| Prefab type | Folder |
|-------------|--------|
| Full-screen Canvas (menu, game screen) | `UI/Canvases/` |
| Popup / dialog | `UI/Popups/` |
| Panel (sub-section of a screen) | `UI/Panels/` |
| Single reusable element (Button, Icon, Label) | `UI/Utilities/` |

### CanvasScaler (always)

```
Match Width Or Height: 0.5
Reference Resolution: 1920 × 1080
Scale Mode: Scale With Screen Size
```

---

## 3. Canvas Split Strategy

Split by update frequency — a single changing element rebuilds the entire Canvas mesh:

```
[UI]/
├── Canvas_HUD       ← updates every frame (health, timer, score)
├── Canvas_Static    ← rarely changes (backgrounds, static labels)
└── Canvas_Popups    ← show/hide dynamically (menus, dialogs)
```

Create all three in every scene. HUD View subscribes to service events and updates only its own elements.

---

## 4. HUD Pattern

```csharp
public sealed class HealthHudView : MonoBehaviour
{
    [SerializeField] private Slider _healthSlider;
    [SerializeField] private TextMeshProUGUI _healthText;

    private IHealthService _healthService;

    [Inject]
    public void Construct(IHealthService healthService) => _healthService = healthService;

    private void OnEnable()  => _healthService.OnHealthChanged += UpdateHealth;
    private void OnDisable() => _healthService.OnHealthChanged -= UpdateHealth;

    private void UpdateHealth(int current, int max)
    {
        _healthSlider.value = (float)current / max;
        _healthText.text    = $"{current}/{max}";
    }
}
```

Place HUD Views under `Canvas_HUD`. Subscribe to service events — never poll in `Update`.

---

## 5. Popup / Dialog Pattern

Popups are separate Canvas prefabs. A `IPopupService` shows/hides them — Views never show each other directly.

```csharp
public sealed class ConfirmPopupView : MonoBehaviour
{
    [SerializeField] private Button _confirmButton;
    [SerializeField] private Button _cancelButton;
    [SerializeField] private TextMeshProUGUI _messageText;

    private Action _onConfirm;
    private Action _onCancel;

    public void Show(string message, Action onConfirm, Action onCancel)
    {
        _messageText.text = message;
        _onConfirm        = onConfirm;
        _onCancel         = onCancel;
        gameObject.SetActive(true);
    }

    public void Hide() => gameObject.SetActive(false);

    private void OnEnable()
    {
        _confirmButton.onClick.AddListener(OnConfirmClicked);
        _cancelButton.onClick.AddListener(OnCancelClicked);
    }

    private void OnDisable()
    {
        _confirmButton.onClick.RemoveListener(OnConfirmClicked);
        _cancelButton.onClick.RemoveListener(OnCancelClicked);
    }

    private void OnConfirmClicked() { _onConfirm?.Invoke(); Hide(); }
    private void OnCancelClicked()  { _onCancel?.Invoke();  Hide(); }
}
```

**Visibility toggle:** use `CanvasGroup` when you need fade or to block raycasts without rebuilding:

```csharp
// Show
_canvasGroup.alpha          = 1f;
_canvasGroup.blocksRaycasts = true;
_canvasGroup.interactable   = true;

// Hide (no SetActive → no Canvas rebuild on re-enable)
_canvasGroup.alpha          = 0f;
_canvasGroup.blocksRaycasts = false;
_canvasGroup.interactable   = false;
```

---

## 6. Scroll View / List Pattern

Never Instantiate/Destroy list items at runtime. Use a pool.

```csharp
public sealed class ItemListView : MonoBehaviour
{
    [SerializeField] private ScrollRect   _scrollRect;
    [SerializeField] private Transform    _content;
    [SerializeField] private ItemEntryView _entryPrefab;

    private readonly List<ItemEntryView> _pool = new();

    public void Populate(IReadOnlyList<ItemData> items)
    {
        EnsurePoolSize(items.Count);

        for (int i = 0; i < _pool.Count; i++)
        {
            bool active = i < items.Count;
            _pool[i].gameObject.SetActive(active);
            if (active) _pool[i].Bind(items[i]);
        }

        _scrollRect.normalizedPosition = Vector2.up; // scroll to top
    }

    private void EnsurePoolSize(int required)
    {
        while (_pool.Count < required)
        {
            var entry = Instantiate(_entryPrefab, _content);
            _pool.Add(entry);
        }
    }
}
```

For very large lists (100+ items): use a virtual scroll — only render visible items.

---

## 7. Safe Area (Mobile)

Apply to the root panel of any full-screen Canvas:

```csharp
public sealed class SafeAreaPanel : MonoBehaviour
{
    private void Awake()
    {
        var rt        = GetComponent<RectTransform>();
        var safeArea  = Screen.safeArea;
        var anchorMin = new Vector2(safeArea.xMin / Screen.width,  safeArea.yMin / Screen.height);
        var anchorMax = new Vector2(safeArea.xMax / Screen.width,  safeArea.yMax / Screen.height);
        rt.anchorMin  = anchorMin;
        rt.anchorMax  = anchorMax;
    }
}
```

Attach `SafeAreaPanel` to the root Panel inside each full-screen Canvas.

---

## 8. Performance Rules

| Rule | Why |
|------|-----|
| Disable **Raycast Target** on non-interactive images and text | Avoids unnecessary raycast overhead every frame |
| Never use `LayoutGroup` in scroll views | Triggers expensive layout recalculation; use manual RectTransform |
| Pool scroll list items — never Instantiate/Destroy | GC spikes and frame drops on large lists |
| Use `CanvasGroup` to hide, not `SetActive(false)` | `SetActive` causes full Canvas rebuild on re-enable |
| Separate Canvas per update frequency | One dynamic element rebuilds the whole Canvas mesh |
| `TextMeshPro` for all text | Better performance and quality than Unity's built-in Text |

---

## 9. TextMeshPro Rules

- Always `TextMeshProUGUI` (not legacy `Text`)
- Set `Raycast Target = false` on pure display labels
- Use `TMP_Text` as the field type for maximum flexibility:

```csharp
[SerializeField] private TMP_Text _scoreLabel;
```

---

## 10. MCP Scene Setup Checklist

When building a new UI screen end-to-end:

1. Read `scene-hierarchy.md` — all Canvas objects go under `[UI]` container
2. Create Canvas with CanvasScaler via `batch_execute`
3. Create child Panel → Buttons → Labels in one batch
4. Attach View script and set `[SerializeField]` references via `manage_components`
5. Configure RectTransform anchors (anchor to corners, stretch as needed)
6. Disable Raycast Target on all non-interactive elements
7. Save as prefab to correct subfolder (`UI/Canvases/`, `UI/Popups/`, `UI/Panels/`, or `UI/Utilities/`)
8. `read_console` — verify no errors
