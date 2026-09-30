---
name: ui-toolkit
description: "UI Toolkit — UXML document structure, USS styling (CSS-like), UQuery, data binding, ListView virtualization, custom visual elements, design system (typography, icons, USS architecture, layout recipes, safe area)."
globs: ["**/*.uxml", "**/*.uss", "**/UIDocument*"]
---

# UI Toolkit

> **Project rule first:** `rules/ui-toolkit-runtime.md`. UI Toolkit is runtime game UI on **Unity 6 (6000.0)+** and Editor-only below that; its Card 1 routes each screen type (menus → UI Toolkit, world-anchored / Animator-driven → UGUI). Where this skill and the rule disagree, the rule wins. The rule's Cards 3, 5, 6 and 7 are field-measured traps this skill does not cover.

## UXML Structure

```xml
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:Style src="styles.uss" />

    <ui:VisualElement class="screen">
        <ui:Label text="Game Title" class="title" />

        <ui:VisualElement class="button-container">
            <ui:Button text="Play" name="btn-play" class="menu-btn" />
            <ui:Button text="Settings" name="btn-settings" class="menu-btn" />
            <ui:Button text="Quit" name="btn-quit" class="menu-btn danger" />
        </ui:VisualElement>

        <ui:Slider label="Volume" name="volume-slider" low-value="0" high-value="1" value="0.8" />
        <ui:Toggle label="Fullscreen" name="fullscreen-toggle" />
    </ui:VisualElement>
</ui:UXML>
```

## USS Styling (CSS-like)

```css
.screen {
    flex-grow: 1;
    align-items: center;
    justify-content: center;
    background-color: rgba(0, 0, 0, 0.8);
}

.title {
    font-size: 48px;
    color: white;
    -unity-font-style: bold;
    margin-bottom: 40px;
}

.menu-btn {
    width: 250px;
    height: 50px;
    margin: 8px;
    font-size: 20px;
    background-color: rgb(60, 60, 60);
    color: white;
    border-radius: 8px;
    border-width: 0;
    transition-duration: 0.2s;
}

.menu-btn:hover {
    background-color: rgb(80, 80, 80);
    scale: 1.05;
}

.menu-btn:active {
    background-color: rgb(40, 40, 40);
}

.danger {
    color: rgb(255, 100, 100);
}
```

### Key USS Differences from CSS
- Flex layout only (no floats, no grid)
- Use `-unity-` prefix for Unity-specific properties
- Colors: `rgb()`, `rgba()`, `#hex`
- Transitions: `transition-duration`, `transition-property`
- No `em`/`rem` — use `px` or `%`

## View Script

A UI Toolkit screen is a `*View` (`solid-oop.md` Card 1 — `*View` is UI-only). Query and subscribe in `OnEnable`, unsubscribe in `OnDisable`: `UIDocument` rebuilds its tree on re-enable, so references cached in `Awake`/`Start` go stale (`rules/ui-toolkit-runtime.md` Card 5).

```csharp
public sealed class MainMenuView : MonoBehaviour
{
    #region Fields

    private const string PLAY_BUTTON   = "btn-play";
    private const string VOLUME_SLIDER = "volume-slider";

    [SerializeField] private UIDocument _document;

    private IMenuService _menuService;
    private Button _playButton;
    private Slider _volumeSlider;

    #endregion

    #region Lifecycle

    [Inject]
    public void Construct(IMenuService menuService) => _menuService = menuService;

    private void OnEnable()
    {
        VisualElement root = _document.rootVisualElement;

        _playButton   = root.Q<Button>(PLAY_BUTTON);
        _volumeSlider = root.Q<Slider>(VOLUME_SLIDER);

        _playButton.clicked += OnPlayClicked;
        _volumeSlider.RegisterValueChangedCallback(OnVolumeChanged);
    }

    private void OnDisable()
    {
        _playButton.clicked -= OnPlayClicked;
        _volumeSlider.UnregisterValueChangedCallback(OnVolumeChanged);
    }

    #endregion

    #region Private Methods

    private void OnPlayClicked() => _menuService.StartGame();
    private void OnVolumeChanged(ChangeEvent<float> evt) => _menuService.SetVolume(evt.newValue);

    #endregion
}
```

No logic in the View — every handler forwards to a service. A lambda passed to `RegisterValueChangedCallback` cannot be unregistered, which is why the callback is a named method.

## Screen With a ViewModel

**Decide first:** `rules/ui-toolkit-runtime.md` Card 11 has the scenario table. The screen above
(buttons only) needs no ViewModel. A shop does: it combines two services, formats a value, and holds
state of its own (the selected item) — three of the table's rows at once.

**1. Interface — outputs are read-only, inputs are methods**

```csharp
// Games/Abstracts/Shop/IShopViewModel.cs
using System;
using R3;

namespace Game.Abstracts.Shop
{
    public interface IShopViewModel : IDisposable
    {
        ReadOnlyReactiveProperty<int>    SelectedItem { get; }
        ReadOnlyReactiveProperty<string> CoinsLabel   { get; }
        ReadOnlyReactiveProperty<bool>   CanBuy       { get; }

        void SelectItem(int index);
        void BuySelected();
    }
}
```

**2. ViewModel — pure C#, no `UnityEngine`, no `UIElements`**

```csharp
// Games/Concretes/Shop/ShopViewModel.cs
using Game.Abstracts.Shop;
using R3;

namespace Game.Concretes.Shop
{
    public sealed class ShopViewModel : IShopViewModel
    {
        #region Fields

        private readonly IWalletService      _wallet;
        private readonly IShopCatalogService _catalog;
        private readonly ReactiveProperty<int> _selectedItem = new(0);

        #endregion

        #region Constructor

        public ShopViewModel(IWalletService wallet, IShopCatalogService catalog)
        {
            _wallet  = wallet;
            _catalog = catalog;

            // Both subscribe to app-lifetime services — which is why Dispose() below is mandatory.
            CoinsLabel = _wallet.Coins
                .Select(coins => coins.ToString("N0"))
                .ToReadOnlyReactiveProperty();

            CanBuy = Observable
                .CombineLatest(_wallet.Coins, _selectedItem, (coins, item) => coins >= _catalog.PriceOf(item))
                .ToReadOnlyReactiveProperty();
        }

        #endregion

        #region IShopViewModel

        public ReadOnlyReactiveProperty<int>    SelectedItem => _selectedItem;
        public ReadOnlyReactiveProperty<string> CoinsLabel   { get; }
        public ReadOnlyReactiveProperty<bool>   CanBuy       { get; }

        public void SelectItem(int index) => _selectedItem.Value = index;
        public void BuySelected()         => _catalog.TryBuy(_selectedItem.Value); // the service owns the purchase

        public void Dispose()
        {
            CoinsLabel.Dispose();
            CanBuy.Dispose();
            _selectedItem.Dispose();
        }

        #endregion
    }
}
```

**3. View — maps outputs onto elements, forwards input, owns both lifetimes**

```csharp
// Games/Concretes/Shop/ShopView.cs
using System;
using System.Collections.Generic;
using Game.Abstracts.Shop;
using R3;
using UnityEngine;
using UnityEngine.UIElements;
using VContainer;

namespace Game.Concretes.Shop
{
    public sealed class ShopView : MonoBehaviour
    {
        #region Fields

        private const string COINS_LABEL = "coins-label";
        private const string BUY_BUTTON  = "btn-buy";
        private const string ITEM_CLASS  = "shop-item";
        private const string ACTIVE      = "is-active";

        [SerializeField] private UIDocument _document;

        private readonly CompositeDisposable _bindings = new();

        private IShopViewModel _viewModel;
        private Label _coinsLabel;
        private Button _buyButton;
        private List<VisualElement> _items;

        #endregion

        #region Lifecycle

        [Inject]
        public void Construct(Func<IShopViewModel> viewModelFactory) => _viewModel = viewModelFactory();

        private void OnEnable()
        {
            VisualElement root = _document.rootVisualElement;   // re-queried: the tree is rebuilt on re-enable
            _coinsLabel = root.Q<Label>(COINS_LABEL);
            _buyButton  = root.Q<Button>(BUY_BUTTON);
            _items      = root.Query<VisualElement>(className: ITEM_CLASS).ToList();

            for (int i = 0; i < _items.Count; i++)
            {
                _items[i].userData = i;                          // stable index, independent of sibling order
                _items[i].RegisterCallback<ClickEvent>(OnItemClicked);
            }

            _buyButton.clicked += _viewModel.BuySelected;

            _viewModel.CoinsLabel.Subscribe(text => _coinsLabel.text = text).AddTo(_bindings);
            _viewModel.CanBuy.Subscribe(canBuy => _buyButton.SetEnabled(canBuy)).AddTo(_bindings);
            _viewModel.SelectedItem.Subscribe(OnSelectedItemChanged).AddTo(_bindings);
        }

        private void OnDisable()
        {
            _bindings.Clear();                                   // bindings end with the enable cycle
            _buyButton.clicked -= _viewModel.BuySelected;

            for (int i = 0; i < _items.Count; i++)
            {
                _items[i].UnregisterCallback<ClickEvent>(OnItemClicked);
            }
        }

        private void OnDestroy() => _viewModel?.Dispose();       // the ViewModel ends with the View

        #endregion

        #region Private Methods

        private void OnItemClicked(ClickEvent evt) =>
            _viewModel.SelectItem((int)((VisualElement)evt.currentTarget).userData);

        private void OnSelectedItemChanged(int selected)
        {
            for (int i = 0; i < _items.Count; i++)
            {
                _items[i].EnableInClassList(ACTIVE, i == selected); // binding, not logic
            }
        }

        #endregion
    }
}
```

Mapping an output onto a class or a label is **binding** and belongs in the View. Deciding *what*
the output is — whether the player can afford it, how the number is written — is **logic** and
belongs in the ViewModel. `.is-active` styling itself lives in USS.

**4. Wiring — a factory in the domain's Module, never a direct registration**

```csharp
// Games/Concretes/Shop/ShopModule.cs → Install()
builder.RegisterFactory<IShopViewModel>(
    container => () => new ShopViewModel(
        container.Resolve<IWalletService>(),
        container.Resolve<IShopCatalogService>()),
    Lifetime.Scoped);
```

Each call to the factory makes a fresh ViewModel, so two open shop screens never share selection
state. A ViewModel with no container dependencies skips the factory: the View `new`s it in `Awake`.

The View itself must be known to a scope, or `Construct` never runs and `OnEnable` throws on
`_viewModel` (`rules/ui-toolkit-runtime.md` Card 12):

```csharp
// The scene's own scope — GameScope / MenuScope — never the Bootstrap AppScope
[SerializeField] private ShopView _shopView;

protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_shopView);   // scene MonoBehaviour — bootstrap-pattern.md Card 4
    SceneModules.InstallMenu(builder);
}
```

A shop opened on demand instead of placed in the scene is spawned with
`_resolver.Instantiate(_shopPrefab, _uiRoot)` — plain `Object.Instantiate` skips injection entirely.

**5. Test — EditMode, no scene, no UI**

```csharp
[Test]
public void CanBuy_WhenCoinsBelowSelectedPrice_IsFalse()
{
    // Arrange
    var wallet  = Substitute.For<IWalletService>();
    var catalog = Substitute.For<IShopCatalogService>();
    wallet.Coins.Returns(new ReactiveProperty<int>(50));
    catalog.PriceOf(0).Returns(100);
    using var sut = new ShopViewModel(wallet, catalog);

    // Act
    bool canBuy = sut.CanBuy.CurrentValue;

    // Assert
    Assert.IsFalse(canBuy);
}
```

This test is the reason the pattern exists: the "can the player afford it" rule is checked without
opening Unity's Play mode, and no MVP-style `IShopView` mock was needed to get there.

## UQuery

```csharp
VisualElement root = _document.rootVisualElement;

// By name
Button playBtn = root.Q<Button>("btn-play");

// By class
var allButtons = root.Query<Button>(className: "menu-btn").ToList();

// By type
var allLabels = root.Query<Label>().ToList();

// Nested query
var containerBtns = root.Q("button-container").Query<Button>().ToList();
```

## ListView (Virtualized Scrolling)

```csharp
ListView listView = root.Q<ListView>("inventory-list");
listView.makeItem = () => new Label(); // Create UI element
listView.bindItem = (element, index) =>
{
    ((Label)element).text = _items[index].Name;
};
listView.itemsSource = _items;
listView.fixedItemHeight = 40;
listView.selectionType = SelectionType.Single;
listView.selectionChanged += OnSelectionChanged;
```

## Custom Visual Element

```csharp
public sealed class HealthBar : VisualElement
{
    private VisualElement _fill;

    public float Value
    {
        set => _fill.style.width = new Length(value * 100f, LengthUnit.Percent);
    }

    public HealthBar()
    {
        AddToClassList("health-bar");
        _fill = new VisualElement();
        _fill.AddToClassList("health-fill");
        Add(_fill);
    }

    // Required for UXML instantiation
    public new sealed class UxmlFactory : UxmlFactory<HealthBar> { }
}
```

## Event System

```csharp
// Register callbacks
element.RegisterCallback<ClickEvent>(evt => { });
element.RegisterCallback<PointerEnterEvent>(evt => { });
element.RegisterCallback<KeyDownEvent>(evt => { });

// Unregister
element.UnregisterCallback<ClickEvent>(handler);
```

## Advanced Layout

### Flex Grow, Shrink, and Basis

Flex properties control how elements share available space within a container:

```css
/* flex-grow: how much extra space this element takes (relative to siblings) */
.sidebar { flex-grow: 0; width: 200px; }   /* fixed width, no growth */
.content { flex-grow: 1; }                  /* takes all remaining space */
.inspector { flex-grow: 0; width: 300px; }  /* fixed width, no growth */

/* flex-shrink: how much this element shrinks when space is tight */
.important { flex-shrink: 0; }  /* never shrink below natural size */
.optional { flex-shrink: 1; }   /* shrink proportionally if needed */

/* flex-basis: starting size before grow/shrink is applied */
.panel { flex-basis: 25%; }     /* start at 25% of parent, then grow/shrink */
```

A common pattern for equal-width columns:
```css
.column { flex-grow: 1; flex-basis: 0; }
```

### Absolute Positioning for Overlays

Use `position: absolute` for elements that overlay the flex layout (tooltips, popups,
floating damage numbers):

```css
.tooltip {
    position: absolute;
    left: 50%;
    top: -40px;
    background-color: rgba(0, 0, 0, 0.9);
    color: white;
    padding: 8px 12px;
    border-radius: 4px;
}

.notification-badge {
    position: absolute;
    right: -8px;
    top: -8px;
    width: 20px;
    height: 20px;
    border-radius: 10px;
    background-color: red;
}
```

Absolute elements are positioned relative to their nearest positioned ancestor.

### Min/Max Width/Height Constraints

Constrain element sizing for responsive behavior:

```css
.dialog {
    min-width: 300px;
    max-width: 80%;
    min-height: 200px;
    max-height: 90%;
    flex-grow: 1;
}

.inventory-slot {
    min-width: 48px;
    min-height: 48px;
    max-width: 64px;
    max-height: 64px;
}
```

### Percentage-Based Responsive Sizing

Use percentages for layouts that adapt to screen size:

```css
.hud-bar {
    width: 30%;
    height: 4%;
    margin-left: 2%;
    margin-top: 2%;
}

.modal-overlay {
    width: 100%;
    height: 100%;
    position: absolute;
    background-color: rgba(0, 0, 0, 0.5);
    align-items: center;
    justify-content: center;
}

.modal-content {
    width: 60%;
    height: 70%;
    background-color: rgb(30, 30, 30);
    border-radius: 12px;
    padding: 20px;
}
```

## Theming System

### USS Custom Properties (Variables)

Define reusable design tokens as USS variables:

```css
:root {
    --color-primary: rgb(66, 133, 244);
    --color-primary-hover: rgb(100, 160, 255);
    --color-surface: rgb(30, 30, 30);
    --color-surface-light: rgb(50, 50, 50);
    --color-text: rgb(230, 230, 230);
    --color-text-muted: rgb(150, 150, 150);
    --color-danger: rgb(234, 67, 53);
    --spacing-sm: 4px;
    --spacing-md: 8px;
    --spacing-lg: 16px;
    --radius-sm: 4px;
    --radius-md: 8px;
    --font-size-body: 16px;
    --font-size-heading: 24px;
}

.btn {
    background-color: var(--color-primary);
    color: var(--color-text);
    padding: var(--spacing-md) var(--spacing-lg);
    border-radius: var(--radius-md);
    font-size: var(--font-size-body);
}

.btn:hover {
    background-color: var(--color-primary-hover);
}
```

### Runtime Theme Switching

Load different USS files at runtime to change the entire UI appearance:

```csharp
public sealed class ThemeManager : MonoBehaviour
{
    [SerializeField] private UIDocument _document;
    [SerializeField] private StyleSheet _darkTheme;
    [SerializeField] private StyleSheet _lightTheme;

    private StyleSheet _activeTheme;

    public void SetDarkMode()
    {
        SwapTheme(_darkTheme);
    }

    public void SetLightMode()
    {
        SwapTheme(_lightTheme);
    }

    private void SwapTheme(StyleSheet newTheme)
    {
        VisualElement root = _document.rootVisualElement;
        if (_activeTheme != null)
        {
            root.styleSheets.Remove(_activeTheme);
        }
        root.styleSheets.Add(newTheme);
        _activeTheme = newTheme;
    }
}
```

### Dark / Light Mode Pattern

Create two USS files that redefine the same variables:

```css
/* dark-theme.uss */
:root {
    --color-background: rgb(18, 18, 18);
    --color-surface: rgb(30, 30, 30);
    --color-text: rgb(230, 230, 230);
    --color-border: rgb(60, 60, 60);
}

/* light-theme.uss */
:root {
    --color-background: rgb(245, 245, 245);
    --color-surface: rgb(255, 255, 255);
    --color-text: rgb(30, 30, 30);
    --color-border: rgb(200, 200, 200);
}
```

All UI elements referencing `var(--color-background)` update automatically when
the stylesheet is swapped.

### Theme Asset Loading

For games with many themes (player-selectable UI skins), load theme assets
from Addressables or Resources:

```csharp
public sealed class ThemeLoader
{
    private readonly UIDocument _document;
    private StyleSheet _currentTheme;

    [Inject]
    public ThemeLoader(UIDocument document)
    {
        _document = document;
    }

    public async UniTask LoadThemeAsync(string themeAddress, CancellationToken token)
    {
        StyleSheet newTheme = await Addressables.LoadAssetAsync<StyleSheet>(themeAddress)
            .ToUniTask(cancellationToken: token);

        VisualElement root = _document.rootVisualElement;
        if (_currentTheme != null)
        {
            root.styleSheets.Remove(_currentTheme);
        }
        root.styleSheets.Add(newTheme);
        _currentTheme = newTheme;
    }
}
```

## Performance with Large Lists

### ListView Virtualization Tuning

ListView only creates enough visual elements to fill the visible area plus a small
overflow buffer. Key settings:

```csharp
ListView listView = root.Q<ListView>("item-list");
listView.fixedItemHeight = 40;            // MUST set for virtualization to work
listView.virtualizationMethod = CollectionVirtualizationMethod.FixedHeight;
listView.showAlternatingRowBackgrounds = AlternatingRowBackground.ContentOnly;
```

Use `fixedItemHeight` when all items are the same height (most performant).
Use `DynamicHeight` only when items genuinely vary in size.

### makeItem / bindItem Optimization

The `makeItem` callback creates reusable visual element templates. The `bindItem`
callback populates them with data. Avoid allocations in both:

```csharp
// GOOD — makeItem creates the template once, bindItem only sets values
listView.makeItem = () =>
{
    var row = new VisualElement();
    row.AddToClassList("list-row");

    var icon = new VisualElement();
    icon.AddToClassList("list-icon");
    icon.name = "icon";
    row.Add(icon);

    var label = new Label();
    label.name = "label";
    row.Add(label);

    return row;
};

listView.bindItem = (element, index) =>
{
    ItemData item = _items[index];
    element.Q<Label>("label").text = item.DisplayName;
    element.Q("icon").style.backgroundImage = new StyleBackground(item.Icon);
};

// BAD — allocates new elements in bindItem
listView.bindItem = (element, index) =>
{
    element.Clear();                          // destroys cached children
    element.Add(new Label(_items[index].Name)); // allocates every bind
};
```

### Batch Updates

When the data source changes, avoid rebuilding per item. Use `RefreshItems`
to trigger a single batch rebind:

```csharp
// After adding/removing items from the source list
_items.Add(newItem);
listView.RefreshItems(); // rebinds only visible items

// For full data source replacement
listView.itemsSource = newDataList;
listView.Rebuild(); // recreates the visual tree
```

### ScrollView vs ListView Decision

| Use ScrollView | Use ListView |
|----------------|-------------|
| < 50 static items | 50+ items or dynamic data |
| Complex mixed layouts | Uniform repeating rows |
| Nested scrollable areas | Inventory, leaderboard, chat log |
| No virtualization needed | Virtualization required for perf |

ScrollView creates all child elements immediately. ListView virtualizes and
recycles elements. For lists exceeding ~50 items, always use ListView.

## Input and Focus Management

### Focus Ring and Tab Order

UI Toolkit supports keyboard navigation via the focus ring. Set `tabIndex` to
control tab order:

```csharp
VisualElement root = _document.rootVisualElement;
root.Q<Button>("btn-play").tabIndex = 0;
root.Q<Button>("btn-settings").tabIndex = 1;
root.Q<Button>("btn-quit").tabIndex = 2;

// Exclude an element from tab navigation
root.Q("decorative-element").focusable = false;
```

Elements with `tabIndex >= 0` participate in tab navigation in ascending order.
Elements with `tabIndex = -1` are skipped by tab but can still receive programmatic focus.

### Keyboard Navigation

Handle arrow keys and Enter for gamepad/keyboard-friendly menus:

```csharp
root.RegisterCallback<NavigationMoveEvent>(evt =>
{
    // evt.direction is Up, Down, Left, Right
    // UI Toolkit handles focus movement automatically
    // Use this callback for custom behavior (e.g., grid navigation)
});

root.RegisterCallback<NavigationSubmitEvent>(evt =>
{
    // Enter/gamepad A pressed on focused element
    if (evt.target is Button button)
    {
        button.clickable.SimulateSingleClick(evt);
    }
});
```

### Custom Focusable Elements

Make a custom VisualElement focusable for keyboard navigation:

```csharp
public sealed class SelectableCard : VisualElement
{
    public SelectableCard()
    {
        focusable = true;
        AddToClassList("selectable-card");

        RegisterCallback<FocusInEvent>(evt => AddToClassList("focused"));
        RegisterCallback<FocusOutEvent>(evt => RemoveFromClassList("focused"));
        RegisterCallback<KeyDownEvent>(OnKeyDown);
    }

    private void OnKeyDown(KeyDownEvent evt)
    {
        if (evt.keyCode == KeyCode.Return || evt.keyCode == KeyCode.Space)
        {
            // Activate card
            evt.StopPropagation();
        }
    }

    public new sealed class UxmlFactory : UxmlFactory<SelectableCard> { }
}
```

### Input Capture (Prevent Event Propagation)

Stop events from bubbling up to parent elements:

```csharp
// Stop a click from reaching elements behind a popup
popupOverlay.RegisterCallback<ClickEvent>(evt =>
{
    evt.StopPropagation();
});

// Prevent scroll events from passing through a modal
modal.RegisterCallback<WheelEvent>(evt =>
{
    evt.StopPropagation();
});

// Use TrickleDown phase to intercept events before children see them
parent.RegisterCallback<PointerDownEvent>(evt =>
{
    // Handle before any child gets it
    evt.StopImmediatePropagation();
}, TrickleDownPhase.TrickleDown);
```

## Screens, Popups and Motion

Governed by `rules/ui-toolkit-runtime.md` Cards 13 (screen infrastructure) and 14 (motion). The code
below is that infrastructure — written once per project, after which a new screen contains **no
animation code and no navigation plumbing**. It maps onto what you know from the web: USS
`transition` ≈ CSS `transition`, `AddToClassList` ≈ `classList.add`, `TransitionEndEvent` ≈
`transitionend`. There is no `@keyframes` — see step 7.

### 1. Motion catalog — `_GameFolders/UI/Theme/Motion.uss`

```css
:root {
    --motion-fast: 150ms;
    --motion-base: 240ms;
    --motion-slow: 400ms;
}

/* Screens: fade */
.anim-fade         { opacity: 0; transition-property: opacity;
                     transition-duration: var(--motion-base); transition-timing-function: ease-out-cubic; }
.anim-fade.is-open { opacity: 1; }

/* Screens: slide up (bottom sheet) */
.anim-slide         { opacity: 0; translate: 0 48px; transition-property: opacity, translate;
                      transition-duration: var(--motion-base); transition-timing-function: ease-out-cubic; }
.anim-slide.is-open { opacity: 1; translate: 0 0; }

/* Popups: the root is the backdrop, the panel pops. The panel rule is written against the ROOT's
   state — the open class is only ever added to the root. */
.anim-pop                        { opacity: 0; transition-property: opacity; transition-duration: var(--motion-fast);
                                   background-color: var(--color-scrim); position: absolute;
                                   left: 0; top: 0; right: 0; bottom: 0; align-items: center; justify-content: center; }
.anim-pop.is-open                { opacity: 1; }
.anim-pop .popup-panel           { scale: 0.9 0.9; transition-property: scale;
                                   transition-duration: var(--motion-base); transition-timing-function: ease-out-back; }
.anim-pop.is-open .popup-panel   { scale: 1 1; }
```

Every animation class transitions `opacity` — that is the single property the helper in step 2 waits
for. A new animation kind is a new class here, never durations inside a screen's own USS.

### 2. `UssTransition` — flip a class, await the real end

```csharp
// Games/Concretes/UI/UssTransition.cs
using System;
using System.Threading;
using Cysharp.Threading.Tasks;
using Framework.Logging;
using UnityEngine.UIElements;

namespace Game.Concretes.UI
{
    public static class UssTransition
    {
        private const string WAIT_PROPERTY = "opacity";                         // every Motion.uss class animates it
        private static readonly TimeSpan SafetyTimeout = TimeSpan.FromSeconds(1); // NOT a duration — a net for a lost event

        public static async UniTask SetStateAsync(VisualElement element, string stateClass, bool on, CancellationToken ct)
        {
            var done = new UniTaskCompletionSource();

            // The target check matters: both events bubble, so a child's hover transition would end this wait.
            void OnEnd(TransitionEndEvent e)       { if (e.target == element && e.stylePropertyNames.Contains(WAIT_PROPERTY)) done.TrySetResult(); }
            void OnCancel(TransitionCancelEvent e) { if (e.target == element && e.stylePropertyNames.Contains(WAIT_PROPERTY)) done.TrySetResult(); }

            element.RegisterCallback<TransitionEndEvent>(OnEnd);
            element.RegisterCallback<TransitionCancelEvent>(OnCancel);   // interrupted → cancel, not end
            try
            {
                element.EnableInClassList(stateClass, on);

                // The end event may never come (no previous style state, transition removed) — never hang on it.
                bool timedOut = await done.Task.AttachExternalCancellation(ct).TimeoutWithoutException(SafetyTimeout);
                if (timedOut)
                {
                    DLog.Warning(LogTag.General, $"No transition end on '{element.name}' for '{stateClass}' — is an anim-* class on it?");
                }
            }
            finally
            {
                element.UnregisterCallback<TransitionEndEvent>(OnEnd);
                element.UnregisterCallback<TransitionCancelEvent>(OnCancel);
            }
        }
    }
}
```

`LogTag.UI` does **not exist yet**: the framework package's `LogTag` enum is closed (`General`,
`EventBus`, `SaveLoad`) and `DLog` accepts nothing else, so a game cannot add a domain tag today even
though `logging.md` Card 3 asks for one. Until the package offers a game-side tag, use
`LogTag.General` in these three calls. The warning is the diagnostic for the most
common authoring mistake — a screen whose root has no `anim-*` class simply appears/disappears after
one second.

### 3. Contracts — `Games/Abstracts/UI/`

```csharp
public interface IScreen
{
    UniTask ShowAsync(CancellationToken ct);
    UniTask HideAsync(CancellationToken ct);
}

public interface IPopup<TResult> : IScreen
{
    /// <remarks>Precondition: ShowAsync has completed. Completes once, when the player answers.</remarks>
    UniTask<TResult> WaitForResultAsync(CancellationToken ct);
}

public interface IScreenService
{
    void Register(IScreen screen);
    void Unregister(IScreen screen);

    /// <remarks>Side effect: hides the current screen first. Showing the screen already on top is a no-op.</remarks>
    UniTask ShowAsync<TScreen>(CancellationToken ct) where TScreen : IScreen;

    /// <remarks>No-op on the first screen of the scene.</remarks>
    UniTask BackAsync(CancellationToken ct);

    /// <remarks>Postcondition: the popup has finished its close transition before the result is returned.</remarks>
    UniTask<TResult> ShowPopupAsync<TPopup, TResult>(CancellationToken ct) where TPopup : IPopup<TResult>;
}
```

### 4. `ScreenView` — the base every screen and popup inherits

```csharp
// Games/Concretes/UI/ScreenView.cs
using System.Threading;
using Cysharp.Threading.Tasks;
using Game.Abstracts.UI;
using UnityEngine;
using UnityEngine.UIElements;

namespace Game.Concretes.UI
{
    public abstract class ScreenView : MonoBehaviour, IScreen
    {
        #region Fields

        private const string ROOT_CLASS = "screen";   // the UXML root: class="screen anim-fade"
        private const string OPEN_CLASS = "is-open";

        [SerializeField] protected UIDocument _document;

        private IScreenService _screens;

        #endregion

        #region Properties

        protected IScreenService Screens => _screens;
        private VisualElement Root => _document.rootVisualElement.Q(className: ROOT_CLASS); // re-queried: tree is rebuilt per activation

        #endregion

        #region Lifecycle

        protected virtual void OnDestroy() => _screens?.Unregister(this);  // subclasses override and call base

        #endregion

        #region Public Methods

        public async UniTask ShowAsync(CancellationToken ct)
        {
            gameObject.SetActive(true);                 // OnEnable: UIDocument rebuilds the tree, the subclass binds
            await UniTask.NextFrame(ct);                // a transition only starts after the element's first frame
            await UssTransition.SetStateAsync(Root, OPEN_CLASS, true, ct);
        }

        public async UniTask HideAsync(CancellationToken ct)
        {
            await UssTransition.SetStateAsync(Root, OPEN_CLASS, false, ct);
            gameObject.SetActive(false);                // only now — deactivating destroys the tree and the exit animation
        }

        #endregion

        #region Protected Methods

        /// <summary>Call from the subclass's [Inject] Construct.</summary>
        protected void Attach(IScreenService screens)
        {
            _screens = screens;
            screens.Register(this);
        }

        #endregion
    }
}
```

`Attach` is called from each subclass's own `Construct` rather than the base having an `[Inject]`
method, so nothing depends on how VContainer treats inherited inject methods.

### 5. `ScreenService` — history, serialised transitions, popups

```csharp
// Games/Concretes/UI/ScreenService.cs — pure C#, Tier 3, one per scene scope
using System;
using System.Collections.Generic;
using System.Threading;
using Cysharp.Threading.Tasks;
using Framework.Logging;
using Game.Abstracts.UI;

namespace Game.Concretes.UI
{
    public sealed class ScreenService : IScreenService, IDisposable
    {
        #region Fields

        private readonly Dictionary<Type, IScreen> _screens = new();
        private readonly Stack<IScreen> _history = new();
        private readonly SemaphoreSlim _gate = new(1, 1);   // one transition at a time — double taps queue, never overlap

        #endregion

        #region Public Methods

        public void Register(IScreen screen)   => _screens[screen.GetType()] = screen;
        public void Unregister(IScreen screen) => _screens.Remove(screen.GetType());

        public async UniTask ShowAsync<TScreen>(CancellationToken ct) where TScreen : IScreen
        {
            if (!TryGet(typeof(TScreen), out IScreen next)) return;

            await _gate.WaitAsync(ct);
            try
            {
                if (_history.Count > 0 && ReferenceEquals(_history.Peek(), next)) return; // already on top
                if (_history.Count > 0) await _history.Peek().HideAsync(ct);
                _history.Push(next);
                await next.ShowAsync(ct);
            }
            finally { _gate.Release(); }
        }

        public async UniTask BackAsync(CancellationToken ct)
        {
            await _gate.WaitAsync(ct);
            try
            {
                if (_history.Count < 2) return;
                await _history.Pop().HideAsync(ct);
                await _history.Peek().ShowAsync(ct);
            }
            finally { _gate.Release(); }
        }

        public async UniTask<TResult> ShowPopupAsync<TPopup, TResult>(CancellationToken ct) where TPopup : IPopup<TResult>
        {
            if (!TryGet(typeof(TPopup), out IScreen screen)) return default;
            var popup = (TPopup)screen;

            await _gate.WaitAsync(ct);
            try { await popup.ShowAsync(ct); } finally { _gate.Release(); }

            // The gate is NOT held while the player decides — a popup may open another popup.
            TResult result = await popup.WaitForResultAsync(ct);

            await _gate.WaitAsync(ct);
            try { await popup.HideAsync(ct); } finally { _gate.Release(); }
            return result;
        }

        public void Dispose() => _gate.Dispose();

        #endregion

        #region Private Methods

        private bool TryGet(Type type, out IScreen screen)
        {
            if (_screens.TryGetValue(type, out screen)) return true;
            DLog.Error(LogTag.General, $"{type.Name} is not registered — is it a [SerializeField] on this scene's scope?");
            return false;
        }

        #endregion
    }
}
```

```csharp
// Games/Concretes/UI/ScreenModule.cs
public static class ScreenModule
{
    public static void Install(IContainerBuilder builder) =>
        builder.Register<ScreenService>(Lifetime.Scoped).AsImplementedInterfaces();
}
```

### 6. A screen, a popup, and the wiring

```xml
<!-- Screens/Settings/Settings.uxml -->
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:VisualElement class="screen anim-fade settings">
        <ui:Button name="btn-back" text="Back" class="ds-btn" />
    </ui:VisualElement>
</ui:UXML>

<!-- Popups/Confirm/ConfirmPopup.uxml — the root IS the backdrop -->
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:VisualElement class="screen anim-pop">
        <ui:VisualElement class="popup-panel">
            <ui:Label name="lbl-message" />
            <ui:Button name="btn-yes" text="Yes" class="ds-btn ds-btn--primary" />
            <ui:Button name="btn-no"  text="No"  class="ds-btn" />
        </ui:VisualElement>
    </ui:VisualElement>
</ui:UXML>
```

```csharp
public sealed class SettingsView : ScreenView
{
    private const string BACK_BUTTON = "btn-back";

    private Button _backButton;

    [Inject]
    public void Construct(IScreenService screens) => Attach(screens);

    private void OnEnable()
    {
        _backButton = _document.rootVisualElement.Q<Button>(BACK_BUTTON);
        _backButton.clicked += OnBackClicked;
    }

    private void OnDisable() => _backButton.clicked -= OnBackClicked;

    private void OnBackClicked() =>
        Screens.BackAsync(destroyCancellationToken).Forget(ex =>
        {
            if (ex is OperationCanceledException) return;
            DLog.Error(LogTag.General, "Back navigation failed.", ex);
        });
}

public sealed class ConfirmPopupView : ScreenView, IPopup<bool>
{
    private const string YES_BUTTON = "btn-yes";
    private const string NO_BUTTON  = "btn-no";

    private UniTaskCompletionSource<bool> _answer;
    private Button _yesButton;
    private Button _noButton;

    [Inject]
    public void Construct(IScreenService screens) => Attach(screens);

    private void OnEnable()
    {
        _answer = new UniTaskCompletionSource<bool>();   // fresh per showing — ShowAsync activates before WaitForResultAsync
        VisualElement root = _document.rootVisualElement;
        _yesButton = root.Q<Button>(YES_BUTTON);
        _noButton  = root.Q<Button>(NO_BUTTON);
        _yesButton.clicked += OnYesClicked;
        _noButton.clicked  += OnNoClicked;
    }

    private void OnDisable()
    {
        _yesButton.clicked -= OnYesClicked;
        _noButton.clicked  -= OnNoClicked;
    }

    public UniTask<bool> WaitForResultAsync(CancellationToken ct) => _answer.Task.AttachExternalCancellation(ct);

    private void OnYesClicked() => _answer.TrySetResult(true);    // Try*: a double tap answers once
    private void OnNoClicked()  => _answer.TrySetResult(false);
}
```

```csharp
// The scene's own scope registers every screen and popup — they start INACTIVE in the scene
public sealed class MenuScope : LifetimeScope
{
    [SerializeField] private MainMenuView     _mainMenu;
    [SerializeField] private SettingsView     _settings;
    [SerializeField] private ConfirmPopupView _confirmPopup;

    protected override void Configure(IContainerBuilder builder)
    {
        builder.RegisterComponent(_mainMenu);
        builder.RegisterComponent(_settings);
        builder.RegisterComponent(_confirmPopup);
        SceneModules.InstallMenu(builder);
    }
}

// SceneModules.InstallMenu
ScreenModule.Install(builder);
builder.RegisterEntryPoint<MenuEntryPoint>();   // IAsyncStartable: await _screens.ShowAsync<MainMenuView>(ct)

// Anywhere a decision needs the player
bool quit = await _screens.ShowPopupAsync<ConfirmPopupView, bool>(ct);
```

Prefab `UIDocument.sortingOrder`: screens `0`, popups `100`, overlays `200`. Scene transitions and
cross-scene data (Play → Game scene, selected level) are `bootstrap-pattern.md` Card 7.

### 7. What USS cannot do — C# tween

No `@keyframes`, no looping transitions. Count-up numbers, spinners, pulses and multi-step sequences
are C# tweens driven by the View (or a Handler it `new`s when the code grows), using the library the
project already has:

```csharp
// DOTween — no UI Toolkit shortcuts, so the generic form
_coinsTween?.Kill();
_coinsTween = DOTween.To(() => _shownCoins, v => { _shownCoins = v; _coinsLabel.text = v.ToString("N0"); }, target, 0.4f);

// PrimeTween ≥ 1.3.1 — VisualElement is supported natively
Tween.VisualElementOpacity(_badge, endValue: 1f, duration: 0.2f);
```

Kill the tween before starting the next one and in `OnDisable` (`unity-lifecycle.md`). A ViewModel
never starts a tween — it exposes the value, the View animates towards it.

### Hover and Active State Animations

Pseudo-classes need no C# at all:

```css
.inventory-slot {
    scale: 1 1;
    border-color: var(--color-border);
    transition-property: scale, border-color;
    transition-duration: var(--motion-fast);
    transition-timing-function: ease-out-cubic;
}

.inventory-slot:hover  { scale: 1.08 1.08; border-color: var(--color-border-strong); }
.inventory-slot:active { scale: 0.95 0.95; }
.inventory-slot.is-active { border-color: var(--color-primary); }
```

Animatable without relayout: `opacity`, `translate`, `scale`, `rotate`, colours. `width`, `height`,
margins, paddings and `top`/`left` are animatable too but relayout every frame — `rules/ui-toolkit-runtime.md`
Card 6. Easings: `ease`, `linear`, and `ease-in` / `ease-out` / `ease-in-out` × `sine`, `cubic`,
`circ`, `elastic`, `back`, `bounce`.

### Transform Origin for Scale Effects

Control the pivot point for scale and rotate transitions:

```css
/* Scale from center (default) */
.popup { transform-origin: center; }

/* Scale from top-left (dropdown menus) */
.dropdown { transform-origin: left top; }

/* Scale from bottom (toast notifications rising up) */
.toast { transform-origin: center bottom; }
```

### Class Toggle for State-Driven Animation

Toggling a state class is the primary pattern, and it is already implemented — use
`UssTransition.SetStateAsync` (Screens, Popups and Motion → step 2). Do not hand-write the toggle plus
a raw `TransitionEndEvent` callback: the event bubbles from children, is replaced by
`TransitionCancelEvent` when interrupted, and may never arrive at all; and an element cached in
`Awake` is detached after the first disable/enable (`rules/ui-toolkit-runtime.md` Cards 5 and 14).
`display` is not animatable — toggling it in the same frame as the class skips the transition.

---

## Design System

### USS File Architecture

Organize stylesheets in three layers. Each layer imports from the one below it:

```
_GameFolders/UI/        (layout: rules/ui-toolkit-runtime.md → Folder Layout)
├── tokens.uss        ← design tokens only (colors, spacing, type scale)
├── components.uss    ← reusable component classes (.btn, .card, .badge…)
└── screens/
    ├── hud.uss       ← screen-specific overrides
    ├── menu.uss
    └── inventory.uss
```

Every UXML file imports the layers it needs:

```xml
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:Style src="../Styles/tokens.uss" />
    <ui:Style src="../Styles/components.uss" />
    <ui:Style src="../Styles/screens/hud.uss" />
    ...
</ui:UXML>
```

Keep `tokens.uss` free of layout rules — only `:root` variable definitions. This is the single source of truth for every color, size, and spacing value in the project.

---

### Typography System

**1. Register fonts in the project**

Place `.otf` / `.ttf` files under `_GameFolders/UI/Fonts/`. UI Toolkit renders through **TextCore** — create a TextCore `FontAsset` from each (a `TMP_FontAsset` is not dropped in as-is), and give it an explicit fallback chain for every shipped script. The Editor silently fills missing glyphs from OS fonts, so verify in a player build (`rules/ui-toolkit-runtime.md` Card 7).

**2. Define the type scale in tokens.uss**

```css
:root {
    /* sizes */
    --font-size-xs:      11px;
    --font-size-sm:      13px;
    --font-size-body:    16px;
    --font-size-lg:      20px;
    --font-size-heading: 28px;
    --font-size-display: 48px;

    /* weights — map to your actual font assets */
    --font-regular: url("/Assets/_GameFolders/UI/Fonts/Inter-Regular SDF.asset");
    --font-bold:    url("/Assets/_GameFolders/UI/Fonts/Inter-Bold SDF.asset");

    /* line-height */
    --line-height-tight:  1.1;
    --line-height-normal: 1.4;
    --line-height-loose:  1.8;
}
```

**3. Apply via utility classes in components.uss**

```css
.text-xs      { font-size: var(--font-size-xs); }
.text-sm      { font-size: var(--font-size-sm); }
.text-body    { font-size: var(--font-size-body); }
.text-lg      { font-size: var(--font-size-lg); }
.text-heading { font-size: var(--font-size-heading); -unity-font-style: bold; }
.text-display { font-size: var(--font-size-display); -unity-font-style: bold; }

.text-muted   { color: var(--color-text-muted); }
.text-danger  { color: var(--color-danger); }
.text-success { color: var(--color-success); }

.text-center  { -unity-text-align: middle-center; }
.text-right   { -unity-text-align: middle-right; }
```

**Key USS typography properties**

| Property | Values | Notes |
|----------|--------|-------|
| `font-size` | `px` only | No em/rem in USS |
| `-unity-font-style` | `normal`, `bold`, `italic`, `bold-and-italic` | Unity-specific |
| `-unity-text-align` | `upper-left`, `middle-center`, `lower-right` … | 9 combinations |
| `-unity-text-overflow-position` | `start`, `middle`, `end` | Where `…` appears |
| `white-space` | `normal`, `nowrap` | `nowrap` prevents line breaks |
| `overflow` | `visible`, `hidden` | Clip long text |

---

### Icon and Sprite Usage

**Referencing our own assets — `url()`, never `resource()`**

`resource("X")` resolves only inside a `Resources/` folder, and everything under `Resources/` ships in
every build whether a screen uses it or not — the reason `Resources.Load` is avoided here. `url()`
points at the asset where it already lives (`_GameFolders/Arts/...`). Prefer the absolute
`/Assets/...` form — a relative path breaks the moment the `.uss` moves one folder; UI Builder itself
writes `project://database/Assets/...?guid=...`, which also survives a rename. A sprite inside a
multi-sprite texture is addressed with a `#SpriteName` suffix. The design system's own `resource()`
icons are fine — they are its package's assets, not ours.

**Our sprites work as-is.** `background-image` and the `Image` element accept a `Sprite`:
- **9-slice:** borders set in the Sprite Editor are honoured; `-unity-slice-*` in USS overrides them
  for that one element only.
- **Sprite Atlas:** reference the original sprite; the atlased copy is used at runtime
  transparently and batches like UGUI. There are forum reports of an atlased background rendering
  the *whole* atlas instead of its region — if you see it, verify on your Unity version before
  designing around atlases.
- **Tint:** `-unity-background-image-tint-color` (white-fill artwork tints cleanly; dark-fill does not).
- **Aspect:** `-unity-background-scale-mode: scale-to-fit | scale-and-crop | stretch-to-fill` —
  the `Image.preserveAspect` equivalent.

**Background image (preferred for icons)**

```css
.icon-play {
    background-image: url("/Assets/_GameFolders/Arts/UI/Icons/play.png");
    width: 32px;
    height: 32px;
    /* tinting via -unity-background-image-tint-color */
    -unity-background-image-tint-color: rgb(255, 255, 255);
}

.icon-play:hover {
    -unity-background-image-tint-color: var(--color-primary);
}
```

**Slice a sprite for scalable borders (9-slice)**

```css
.dialog-frame {
    background-image: url("/Assets/_GameFolders/Arts/UI/Frames/dialog-frame.png"); /* Sprite Editor borders apply; the lines below override them */
    /* left, top, right, bottom slice offsets in px */
    -unity-slice-left:   16;
    -unity-slice-top:    16;
    -unity-slice-right:  16;
    -unity-slice-bottom: 16;
    -unity-slice-scale:  1;
}
```

**Set via C# when the icon is dynamic**

```csharp
VisualElement icon = root.Q("item-icon");
icon.style.backgroundImage = new StyleBackground(sprite);

// Tint from code
icon.style.unityBackgroundImageTintColor = new StyleColor(Color.yellow);
```

**Icon button pattern (image + label stacked)**

```xml
<ui:VisualElement class="icon-btn" name="btn-craft">
    <ui:VisualElement class="icon-btn__image icon-craft" />
    <ui:Label text="Craft" class="icon-btn__label text-xs" />
</ui:VisualElement>
```

```css
.icon-btn {
    align-items: center;
    justify-content: center;
    width: 64px;
    cursor: link;
}

.icon-btn__image {
    width: 40px;
    height: 40px;
    -unity-background-image-tint-color: var(--color-text);
    transition: scale 0.15s ease-out;
}

.icon-btn:hover .icon-btn__image {
    scale: 1.15;
    -unity-background-image-tint-color: var(--color-primary);
}

.icon-btn__label {
    margin-top: 2px;
    color: var(--color-text-muted);
}
```

---

### Common Layout Recipes

#### HUD Bar (health / stamina / mana)

```xml
<ui:VisualElement class="hud-bar" name="health-bar-root">
    <ui:VisualElement class="hud-bar__track">
        <ui:VisualElement class="hud-bar__fill" name="health-fill" />
    </ui:VisualElement>
    <ui:Label text="100 / 100" name="health-label" class="hud-bar__label text-sm" />
</ui:VisualElement>
```

```css
.hud-bar {
    flex-direction: row;
    align-items: center;
    height: 24px;
    width: 200px;
}

.hud-bar__track {
    flex-grow: 1;
    height: 12px;
    background-color: rgba(0, 0, 0, 0.5);
    border-radius: 6px;
    overflow: hidden;
}

.hud-bar__fill {
    height: 100%;
    width: 100%;          /* set via C#: style.width = Length.Percent(pct) */
    background-color: var(--color-success);
    transition: width 0.3s ease-out;
}

.hud-bar__label {
    margin-left: 8px;
    color: var(--color-text);
    min-width: 64px;
    -unity-text-align: middle-right;
}
```

```csharp
// Update fill width
float pct = (float)current / max * 100f;
root.Q("health-fill").style.width = new StyleLength(Length.Percent(pct));
root.Q<Label>("health-label").text = $"{current} / {max}";
```

---

#### Modal Dialog

```xml
<ui:VisualElement class="modal-overlay" name="modal-overlay">
    <ui:VisualElement class="modal">
        <ui:Label text="Confirm" class="modal__title text-heading" />
        <ui:Label text="Are you sure you want to quit?" class="modal__body text-body" />
        <ui:VisualElement class="modal__actions">
            <ui:Button text="Cancel" name="btn-cancel" class="btn btn--ghost" />
            <ui:Button text="Confirm" name="btn-confirm" class="btn btn--danger" />
        </ui:VisualElement>
    </ui:VisualElement>
</ui:VisualElement>
```

```css
.modal-overlay {
    position: absolute;
    left: 0; top: 0; right: 0; bottom: 0;
    background-color: rgba(0, 0, 0, 0.6);
    align-items: center;
    justify-content: center;
}

.modal {
    background-color: var(--color-surface);
    border-radius: var(--radius-lg);
    padding: 32px;
    min-width: 360px;
    max-width: 480px;
}

.modal__title  { margin-bottom: 12px; }
.modal__body   { color: var(--color-text-muted); margin-bottom: 24px; }

.modal__actions {
    flex-direction: row;
    justify-content: flex-end;
}

.modal__actions .btn { margin-left: 8px; }
```

---

#### Inventory Grid

```csharp
// Build grid from C# — UI Toolkit has no native grid container
VisualElement grid = root.Q("inventory-grid");
grid.Clear();

for (int i = 0; i < _items.Count; i++)
{
    var slot = new InventorySlot(_items[i]);
    grid.Add(slot);
}
```

```css
.inventory-grid {
    flex-direction: row;
    flex-wrap: wrap;         /* wraps items to next row */
    padding: 8px;
}

.inventory-slot {
    width: 64px;
    height: 64px;
    margin: 4px;
    background-color: var(--color-surface-light);
    border-radius: var(--radius-sm);
    border-width: 1px;
    border-color: rgba(255, 255, 255, 0.1);
    align-items: center;
    justify-content: center;
    transition: border-color 0.15s ease, scale 0.1s ease-out;
}

.inventory-slot:hover  { border-color: var(--color-primary); scale: 1.06; }
.inventory-slot.filled { background-color: var(--color-surface); }
.inventory-slot.selected {
    border-color: var(--color-primary);
    border-width: 2px;
}
```

---

### Safe Area / Notch Handling

Mobile devices have notches, punch-holes, and rounded corners. The safe area
is the region guaranteed to be unobstructed.

**Convert through the panel, not raw pixels.** `Screen.safeArea` is in physical screen pixels with a
bottom-left origin; USS `padding` is in panel units with a top-left origin. Under **Scale With
Screen Size** the two differ by the panel scale, so writing `Screen.safeArea` straight into
`style.padding*` is wrong on every device whose resolution is not the reference resolution — the
notch inset comes out too large or too small, never correct. Flip Y, then convert with
`RuntimePanelUtils.ScreenToPanel`, which applies the panel's scaling:

```csharp
public sealed class SafeAreaView : MonoBehaviour
{
    #region Fields

    [SerializeField] private UIDocument _document;

    private VisualElement _root;

    #endregion

    #region Lifecycle

    private void OnEnable()
    {
        _root = _document.rootVisualElement;
        _root.RegisterCallback<GeometryChangedEvent>(OnGeometryChanged); // fires on resize and rotation
    }

    private void OnDisable() => _root.UnregisterCallback<GeometryChangedEvent>(OnGeometryChanged);

    #endregion

    #region Private Methods

    private void OnGeometryChanged(GeometryChangedEvent evt) => ApplySafeArea();

    private void ApplySafeArea()
    {
        Rect safe = Screen.safeArea;
        IPanel panel = _root.panel;

        // Screen origin is bottom-left, panel origin is top-left: flip Y before converting.
        Vector2 topLeft     = RuntimePanelUtils.ScreenToPanel(panel, new Vector2(safe.xMin, Screen.height - safe.yMax));
        Vector2 bottomRight = RuntimePanelUtils.ScreenToPanel(panel, new Vector2(safe.xMax, Screen.height - safe.yMin));
        Vector2 full        = RuntimePanelUtils.ScreenToPanel(panel, new Vector2(Screen.width, Screen.height));

        _root.style.paddingLeft   = topLeft.x;
        _root.style.paddingTop    = topLeft.y;
        _root.style.paddingRight  = full.x - bottomRight.x;
        _root.style.paddingBottom = full.y - bottomRight.y;
    }

    #endregion
}
```

Apply `SafeAreaView` to the root `UIDocument` GameObject. Child panels
that should ignore safe area (e.g. full-bleed backgrounds) use `position:
absolute` with explicit 0 offsets to break out of the padding.

```css
/* Full-bleed background — ignores safe area padding */
.background-image {
    position: absolute;
    left: 0; top: 0; right: 0; bottom: 0;
}

/* HUD content — stays inside safe area (inherits padding from root) */
.hud-container {
    flex-grow: 1;
}
```

**No `Update` polling for orientation.** `GeometryChangedEvent` on the root already fires when the panel is resized, which is what a rotation does.
