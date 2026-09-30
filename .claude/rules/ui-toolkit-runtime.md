# UI Toolkit for Game UI (Unity 6+)

> Read the **Cards** section first. The prose below is reference detail.

UI Toolkit is a **runtime** UI system for game menus on **Unity 6 (6000.0) and newer**. On any
Unity older than 6000.0 it stays what it always was in this template: an **Editor-only** tool
(custom inspectors, EditorWindows). The version is read from `ProjectSettings/ProjectVersion.txt`
(`m_EditorVersion`), never assumed.

This rule was written from an actual read of a shipping system, not from memory: the MIT
[unity-ui-toolkit-design-system](https://github.com/sinanata/unity-ui-toolkit-design-system)
(`com.sinanata.designsystem`, v1.5.2, used in *Leap of Legends*; package minimum `6000.0`, host
project `6000.5.2f1`), plus Unity's own comparison page and the *Timberborn* case study. Every
GOTCHA below that says "measured" was measured there, not here.

## Cards

### Card 1: Pick the UI System by Unity Version and Screen Type — Never by Habit

**WHEN:** Starting any new runtime screen.

**WRONG:** "The last screen was UGUI, so this one is too" — or the reverse: porting a world-space
health bar to UI Toolkit on 6000.0 because the menus already are.

**RIGHT:**

| Screen | Unity < 6000.0 | 6000.0 – 6000.4 | 6000.5+ |
|---|---|---|---|
| Full-screen menus, settings, shop, inventory, popups, list screens | UGUI | **UI Toolkit** | **UI Toolkit** |
| World-anchored UI (health bar, nameplate, in-world screen) | UGUI | UGUI | UI Toolkit allowed (verify on target platform) |
| Custom shader / material on a UI element | UGUI | UGUI below 6000.3; UI Toolkit Shader Graph UI material from 6000.3 | UI Toolkit |
| UI driven by Animator, Animation Clips or Timeline | UGUI | UGUI | UGUI — UI Toolkit has no Timeline/clip integration in any version |
| Editor tools (inspectors, windows) | UI Toolkit | UI Toolkit | UI Toolkit |

**GOTCHA:** One screen is one system. UI Toolkit panels (`PanelSettings.sortingOrder`) and UGUI
canvases (`Canvas.sortingOrder`) are layered by two independent mechanisms, so a UGUI popup meant to
cover a UI Toolkit menu can silently render underneath it. When both systems exist in one scene,
write the layer order down once (e.g. in the domain's `ARCHITECTURE.md`) instead of discovering it.
World-space UI Toolkit on WebGL needs engine workarounds for custom materials — the design system's
`docs/MATERIALS.md` documents two independent engine defects; do not promise it on WebGL without testing.

---

### Card 2: Styling Values Come Only From Tokens

**WHEN:** Writing any USS rule.

**WRONG:**
```css
.menu-btn { background-color: rgb(60, 60, 60); height: 50px; border-radius: 8px; transition-duration: 0.2s; }
```

**RIGHT:**
```css
/* Theme/DesignTokens.uss — the only file that holds raw values */
:root { --color-surface: #1F2937; --space-3: 12px; --radius-md: 8px; --transition-fast: 150ms; }

/* Components/Buttons.uss */
.ds-btn { background-color: var(--color-surface); padding-left: var(--space-3); border-radius: var(--radius-md); }
```

**GOTCHA:** This is the single biggest reason agent-written UI looks amateur: every file invents its
own grey, its own 14px, its own 0.2s, and no two screens agree. With tokens, a theme swap is one
stylesheet on the root and the `var()` cascade repaints every `:hover`/`:disabled`/`:checked` state
by itself. If a value you need has no token, **add the token first**. Same principle as
`web-tool-design-system.md` Cards 1–2.

---

### Card 3: Never `var(...)` Inside an Inline UXML `style=` Attribute

**WHEN:** Writing UXML.

**WRONG:**
```xml
<ui:VisualElement style="background-color: var(--color-surface);" />
```

**RIGHT:**
```xml
<ui:VisualElement class="menu-card" />
```
```css
.menu-card { background-color: var(--color-surface); }
```

**GOTCHA:** Unity 6's clone-time `StyleVariableResolver` throws on it, and the whole
`VisualTreeAsset` fails to clone — the error is "The UXML file set for the UIDocument could not be
cloned", which names neither the attribute nor the variable. `var()` is fine inside `.uss` files.
Inline `style=` is a smell anyway (it bypasses Card 2); keep UXML to structure plus classes.

---

### Card 4: One PanelSettings Asset — The UI Toolkit Equivalent of BaseCanvas

**WHEN:** Creating the first `UIDocument` (or `PanelRenderer`) in the project.

**WRONG:** Letting each screen create its own `PanelSettings`, or building them in code per scene.

**RIGHT:** One shared asset at `_GameFolders/UI/Settings/GamePanelSettings.asset`:
- Scale Mode: **Scale With Screen Size**, Reference Resolution identical to `BaseCanvas`
  (1080×1920 portrait by default), Screen Match Mode **Match Width Or Height**, Match **0.5**
- Theme Style Sheet: the project's runtime `.tss`
- `sortingOrder` chosen against the UGUI canvases per Card 1

**It is the CanvasScaler you already know, field for field:**

| UGUI `CanvasScaler` | UI Toolkit `PanelSettings` |
|---|---|
| Constant Pixel Size | Constant Pixel Size |
| Scale With Screen Size + Reference Resolution + Match | Scale With Screen Size + Reference Resolution + Match Width Or Height + Match |
| Constant Physical Size + Reference / Fallback DPI | Constant Physical Size + Reference / Fallback DPI |
| `Screen.safeArea` → RectTransform anchors | `Screen.safeArea` → root padding via `RuntimePanelUtils.ScreenToPanel` (skill → Safe Area) |

So a USS `px` is a **reference-resolution pixel**, exactly like a RectTransform size under Scale With
Screen Size: a 200px button in a 1080×1920 mockup is `width: 200px`, and it scales the same way the
UGUI one would. Figma frames drawn at the reference resolution translate number-for-number. Beyond
fixed sizes, `%`, `flex-grow` and `min-`/`max-width` replace most anchor-stretch setups.

**GOTCHA:** `Screen.safeArea` is in physical pixels with a bottom-left origin; panel units are
scaled and top-left. Writing it straight into `style.padding*` is wrong on every device that is not
at the reference resolution — flip Y and convert through the panel.

Second trap, the same failure as `unity-prefabs.md` Card 3: two PanelSettings drift to different
reference resolutions and one screen's layout breaks on one device class, with no error. A screen that
genuinely needs a different sort order gets its own asset **only** for that; the scale fields must
stay identical.

---

### Card 5: A Screen Is a `*View` That Queries in OnEnable and Forwards to a Service

**WHEN:** Writing the C# side of a UI Toolkit screen.

**WRONG:**
```csharp
public sealed class MainMenuView : MonoBehaviour
{
    private void Start()
    {
        var root = GetComponent<UIDocument>().rootVisualElement;
        root.Q<Button>("btn-play").clicked += () => SceneManager.LoadScene("Game"); // logic + Unity API in a View, never removed
    }
}
```

**RIGHT:**
```csharp
public sealed class MainMenuView : MonoBehaviour
{
    #region Fields

    private const string PLAY_BUTTON = "btn-play";

    [SerializeField] private UIDocument _document;

    private IMenuService _menuService;
    private Button _playButton;

    #endregion

    #region Lifecycle

    [Inject]
    public void Construct(IMenuService menuService) => _menuService = menuService;

    private void OnEnable()
    {
        _playButton = _document.rootVisualElement.Q<Button>(PLAY_BUTTON);
        _playButton.clicked += OnPlayClicked;
    }

    private void OnDisable() => _playButton.clicked -= OnPlayClicked;

    #endregion

    #region Private Methods

    private void OnPlayClicked() => _menuService.StartGame();

    #endregion
}
```

**GOTCHA:** `UIDocument` rebuilds its visual tree when it is re-enabled, so an element reference
cached in `Awake`/`Start` points at a detached element after the first disable/enable cycle — the
button keeps its handler and never fires again, with no error. Query in `OnEnable`, unsubscribe in
`OnDisable`: the same pair as `event-patterns.md` Pattern 4. Values the screen renders arrive as an R3
`ReadOnlyReactiveProperty` (`event-patterns.md` Card 5); the View holds no state and no logic
(`solid-oop.md` Card 1 — `*View` is UI-only). Assign `_document` in the Inspector, never
`GetComponent` (`performance.md`).

---

### Card 6: Animate Transforms, and Never Put a Transition on the Theme Swap

**WHEN:** Adding motion to a screen.

**WRONG:**
```css
.panel { transition-property: height; }           /* layout property — relayout every frame */
.panel.is-open { height: auto; }                  /* 0 ↔ auto never transitions at all */
.ds-root * { transition-property: background-color; transition-duration: 240ms; } /* "smooth theme swap" */
```

**RIGHT:**
```css
.panel { transition-property: translate, opacity; transition-duration: var(--transition-base); }
.panel.is-open { translate: 0 0; opacity: 1; }
.ds-no-transition, .ds-no-transition * { transition-property: none; }
```
```csharp
root.AddToClassList("ds-no-transition");      // for the frames the theme swap lands in
ApplyTheme(root, theme);
root.schedule.Execute(() => root.RemoveFromClassList("ds-no-transition")).ExecuteLater(120);
```

**GOTCHA:** `translate`/`scale`/`rotate`/`opacity` avoid relayout; `width`/`height`/`top`/`left` do not.
The universal-transition theme swap is the expensive one, **measured** in the design system: every
running transition pins a `ComputedStyle` snapshot from `Allocator.Domain`; swapping faster than they
retire stacks them until Unity logs `Allocator.Domain has reached its limit of 262144 tracked
allocations` and the app freezes — a few dozen swaps on a ~1,000-element screen. USS cannot loop an
animation (spinners, shimmer): drive those from C# in the View's owning handler, not from a
never-ending transition.

---

### Card 7: A Font Without an Explicit Fallback Chain Is a Bug — the Editor Hides It

**WHEN:** Choosing fonts, or shipping any language other than English.

**WRONG:** Judging multilingual text by how it looks in the Editor.

**RIGHT:** A `FontAsset` with an explicit fallback chain covering every shipped script, verified
against a **player build**, and, for Chinese/Japanese/Korean, the face picked **per language**.

**GOTCHA:** Unity serves a missing glyph from an OS font, so Arabic shows as Arial and Japanese as
Microsoft YaHei **in the Editor** and as empty boxes in a WebGL build — no warning in either.
A chain resolves per codepoint, not per language, so the first CJK font in it wins all the shared Han
characters and Chinese renders in Japanese letterforms while every coverage check passes. UI Toolkit
uses TextCore `FontAsset`s (`Create > Text Core > Font Asset`), built from the **same `.ttf`/`.otf`
files** the TMP assets use. Whether a TMP font asset can be reused directly is unconfirmed by Unity for
Unity 6 and UI Builder does not list them — plan one TextCore asset per font until it is verified in
the project's own Unity version. Fonts are imported at **edit
time**; do not ship a runtime font download (the design system's `DsGoogleFonts` fetches from
GitHub at runtime — fine for a showcase, a network dependency in a game).

---

### Card 8: Touch Layout Is One Class on the Root; Radii Are Half the Height

**WHEN:** The game targets touch, or supports both desktop and mobile.

**WRONG:** Duplicating UXML per platform, or `border-radius: 999px` for a pill.

**RIGHT:** One UXML. A `.mobile` class on the screen root; every touch override lives in a
`Mobile.uss` imported **last**, prefixed `.mobile` (48px minimum touch target). Pill radius is a
token equal to half the element's height (`--radius-pill-12` for a 24px chip).

**GOTCHA:** Unity clamps `border-radius` per axis to half the side length, so `999px` on a
non-square element renders an **ellipse**, not a pill. `Mobile.uss` must stay last: specificity ties
resolve by import order, and the responsive pass is the first thing a reorder breaks. Scope any rule
that targets Unity's internal classes (`.unity-scroll-view__*`, `.unity-base-slider__*`) under your
root class — unscoped, it re-skins every scrollbar in the Inspector and UI Builder too.

---

### Card 9: The Design System Is a Pinned Package — Never Copied Into Assets/

**WHEN:** Adopting `com.sinanata.designsystem` (optional — the recommended starting point instead
of hand-writing 42 components).

**WRONG:** Copying `Assets/DesignSystem/` into the project, or editing its USS to fit the game.

**RIGHT:**
```json
"com.sinanata.designsystem": "https://github.com/sinanata/unity-ui-toolkit-design-system.git?path=/Assets/DesignSystem#v1.5.2"
```
Attach `DesignSystem.uss` once, put `ds-root` on the top element, compose screens from `ds-*` BEM
classes (`.ds-btn`, `.ds-btn__icon`, `.ds-btn--primary`, state `.is-active`). The game's own palette
is a theme stylesheet (or a baked `ThemeData` asset) attached **after** it; game-specific components
are the game's own USS, also loaded after — never an edit to the package.

**GOTCHA:** Vendoring fails twice. It drifts — the same measured failure as this template's own
framework (`packages/framework/`: ten of twelve copied files diverged before anyone looked). And the
package's C# legitimately breaks rules that bind **our** code — it auto-attaches a MonoBehaviour to
every `UIDocument` via `[RuntimeInitializeOnLoadMethod]`, calls `FindObjectsByType`, logs with
`Debug.Log`, and loads shaders via `Resources.Load` — so a copy under `Assets/` would trip content
hooks on code nobody here wrote. Under `Packages/` it is third-party code, like VContainer. Its
material FX pipeline and `PanelRenderer` backend compile only on 6000.5+ (`#if UNITY_6000_5_OR_NEWER`);
tokens, components, themes and the `UIDocument` backend work from 6000.0. It requires
`com.unity.modules.unitywebrequest` only for the runtime font download.

---

### Card 10: A Screen Is Done When It Was Looked At — At Two Widths

**WHEN:** Closing any UI task.

**WRONG:** "It compiles and the console is clean."

**RIGHT:** Enter Play mode, capture the Game view at the reference resolution **and** at a `.mobile`
/ narrow width, and compare against the approved mockup. Use the UI Toolkit Debugger to read the
selector chain of anything that looks off.

**GOTCHA:** Nothing in this repo can judge a layout — no hook, no reviewer, no test. The design
system itself has no unit tests for exactly this reason: its showcase scene is its test suite. A
screen no one looked at is unverified, however green everything else is (`rules/roadmap-milestones.md`
Card 3 is the same lesson one level up).

---

### Card 11: MVVM With R3 — and Only Where the Screen Has State of Its Own

**WHEN:** Deciding what sits between a UI Toolkit screen and the services it shows.

**The pattern is MVVM, not MVC and not MVP.**
- **MVC** — `*Controller` already means the gameplay Mono shell (`solid-oop.md` Card 1). A UI
  "Controller" gives one suffix two meanings, for agents and for hooks alike.
- **MVP** — the Presenter needs an `I*View` interface to talk back to the View, and `solid-oop.md` →
  Interface Scope says a View gets **no** interface. It pays that cost for the testability MVVM
  already gives.
- **MVVM** — a pure C# ViewModel exposes state, the View binds to it and forwards input. The
  ViewModel is the one unit of screen logic that tests in EditMode with no scene.

**The binding is R3, not Unity's runtime data binding.** Unity's `binding-path`/`dataSource` is less
code, but a path is a string — `binding-path="PlayerNmae"` compiles and silently shows nothing — its
API is flagged HIGH risk in `docs/engine-reference/unity/breaking-changes.md`, and change
notification needs `[CreateProperty]` plus `INotifyBindablePropertyChanged` plumbing. An R3
`Subscribe` is checked by the compiler and is already the rule for rendered values
(`event-patterns.md` Card 5).

**Which scenario gets which shape:**

| Scenario | Shape | Example |
|---|---|---|
| Buttons only, nothing displayed that changes | **View → Service**, no ViewModel | main menu, pause menu, quit confirm |
| Shows one service's values **unchanged** | **View subscribes to the service's `ReadOnlyReactiveProperty`**, no ViewModel | coin counter, level number |
| State that belongs to **the screen, not the game** | **ViewModel** | selected tab, filter, sort order, current page, expanded row |
| **Derived or formatted** display values | **ViewModel** | `"3/10"`, `"1.2K"`, "locked" computed from level + currency, a button disabled while unaffordable |
| **Combines two or more services** | **ViewModel** | shop (wallet + catalogue + inventory), level select (progress + config) |
| A form: **draft vs committed** values | **ViewModel** | settings with Apply/Cancel, name entry with validation |
| A list | **ViewModel exposes the items; the View uses `ListView` `makeItem`/`bindItem`**; a per-row ViewModel only if a row has its own state | inventory, shop items, leaderboard |
| A popup that returns one answer | **No ViewModel** — the caller awaits `IScreenService.ShowPopupAsync<TPopup, TResult>()` (Card 13) | "Are you sure?" dialog |

**The test, in one line:** if you are about to write an `if`, a format string or a second service
field inside the View, the screen needs a ViewModel. If not, it does not.

**Shape — the Handler pattern applied to a screen:**

| File | Holds |
|---|---|
| `Abstracts/<Domain>/I<Screen>ViewModel.cs` | `ReadOnlyReactiveProperty<T>` outputs, `void` input methods, `IDisposable` |
| `Concretes/<Domain>/<Screen>ViewModel.cs` | pure C#, `sealed`, no `UnityEngine`, no `UIElements` |
| `Concretes/<Domain>/<Screen>View.cs` | `UIDocument` shell: creates the ViewModel, binds in `OnEnable`, unbinds in `OnDisable`, disposes it in `OnDestroy` |

- The ViewModel is **never registered on its own and never shared**. The View creates it: plain
  `new` when it needs no container dependency, a `Func<I<Screen>ViewModel>` factory registered in the
  domain's `Module.Install` when it does (`architecture.md` Card 6, Pattern B).
- **No `UnityEngine.UIElements` in the ViewModel.** It never sees a `Label` or a `VisualElement`;
  the View maps its outputs onto elements. That boundary is what keeps it testable.
- **Inputs are methods, outputs are read-only properties.** The View calls `SelectTab(2)`, never
  writes a ReactiveProperty.
- **Persistent state stays in services.** The coin balance lives in the wallet service; the
  ViewModel only shapes it for this screen. A ViewModel that saves to disk or publishes on
  `IEventBus` has taken over a service's job.

**GOTCHA:** The ViewModel usually subscribes to app-lifetime services — `wallet.Coins.Select(...)`
is a subscription held **by the service's** ReactiveProperty. If nobody disposes the ViewModel, the
service keeps it alive and the dead screen's formatting code keeps running for the rest of the
session: a leak with no error, growing every time the screen is opened. So there are two lifetimes,
and they are not the same one: the View's **bindings** to the ViewModel are made in `OnEnable` and
cleared in `OnDisable`; the **ViewModel itself** is created once and disposed in the View's
`OnDestroy`. Full worked example: `skills/systems/ui-toolkit/SKILL.md` → Screen With a ViewModel.

---

### Card 12: The Container Only Injects a View It Knows About — and Only Before OnEnable If It Built First

**WHEN:** Wiring any UI Toolkit `*View` (with or without a ViewModel) to VContainer.

MVVM and the container do not conflict: the container resolves services and hands the View a
`Func<I<Screen>ViewModel>`; the View owns the ViewModel from there. What breaks is *whether* and
*when* `[Inject] Construct` runs — and a View whose `Construct` has not run throws a
`NullReferenceException` in `OnEnable` on its first line, far from the cause.

**WRONG:**
```csharp
// 1. The View sits in the scene but no scope registers it — [Inject] never runs.
// 2. A popup View spawned with plain Instantiate — no injection at all.
var popup = Object.Instantiate(_popupPrefab, _uiRoot);
```

**RIGHT:**

| How the View exists | How it gets injected |
|---|---|
| Placed in the scene | The scene's own scope (`GameScope` / `MenuScope`) holds it as a `[SerializeField]` and calls `builder.RegisterComponent(_shopView)` (`bootstrap-pattern.md` Card 4) |
| Spawned at runtime (popup, screen opened on demand) | `IObjectResolver.Instantiate(prefab, parent)` from the service/provider that opens it — never `Object.Instantiate` |
| Needs a ViewModel | Its domain `Module.Install` registers `RegisterFactory<I<Screen>ViewModel>(…)` in the scope that owns the ViewModel's services; a child scope resolves it through the parent |

**Why the order works, and when it stops working** (read from VContainer's source, not assumed):
- `LifetimeScope` carries `[DefaultExecutionOrder(-5000)]` and builds + injects in its own `Awake`,
  so in the **same scene** every registered View is injected before its own `Awake`/`OnEnable`.
- `IObjectResolver.Instantiate` deactivates the prefab, instantiates, injects, then restores the
  active flag — so a spawned View is injected before its `Awake`/`OnEnable` too.
- It stops working when the View's scope is **not in the View's scene** (a Menu-scene View relying on
  the Bootstrap `AppScope` — a scope injects only what it registers, never another scene's objects),
  when a scope has `autoRun` off and is built later, or when someone puts a `[DefaultExecutionOrder]`
  lower than `-5000` on a View. All three produce the same `OnEnable` NRE.

**GOTCHA:** The ViewModel made by the factory is **not owned by the container** — VContainer never
disposes it. That is intentional (one ViewModel per View instance, its lifetime tied to the View),
and it is why the View's `OnDestroy` dispose from Card 11 is not optional. Do not "fix" it by
registering the ViewModel as `Lifetime.Singleton` so the scope disposes it: two open instances of the
screen would then share one selection state, and the ViewModel would outlive every screen that used
it. Never resolve anything in the ViewModel from `IObjectResolver` — it takes its services as
constructor interfaces like any Tier 3 class; a ViewModel holding the resolver is a service locator
(`architecture.md` → NO GameContext / Service Locator).

---

### Card 13: Screens and Popups Go Through One `IScreenService` — Views Never Open Each Other

**WHEN:** A second screen or the first popup appears in a scene.

**WRONG:**
```csharp
// One UIRoot mediator holding every screen, children wired back to it by hand
public sealed class UIRoot : MonoBehaviour
{
    [SerializeField] private MainMenuView _mainMenu;
    [SerializeField] private SettingsView _settings;
    public async UniTaskVoid ShowSettings() { await _mainMenu.HideAsync(ct); await _settings.ShowAsync(ct); }
}
// ...and a popup that fades out by SetActive(false) — the exit animation never plays
private void OnNoClicked() => gameObject.SetActive(false);
```

**RIGHT:**
```csharp
// A View asks the service; it never holds another View
private void OnSettingsClicked() =>
    _screens.ShowAsync<SettingsView>(destroyCancellationToken).Forget(LogUnlessCancelled);

// A popup is awaited for its answer — show, wait, hide are all the service's job
bool quit = await _screens.ShowPopupAsync<ConfirmPopupView, bool>(ct);
```

The shape, fixed for every project:

| Piece | Where | Is |
|---|---|---|
| `IScreen`, `IPopup<TResult>`, `IScreenService` | `Abstracts/UI/` | The contracts. `IScreen` = `ShowAsync` / `HideAsync`; `IPopup<T>` adds `WaitForResultAsync` |
| `ScreenView` | `Concretes/UI/` | Abstract MonoBehaviour base every screen and popup inherits. Owns show/hide: activate → one frame → open transition; close transition → deactivate |
| `ScreenService` | `Concretes/UI/` | Pure C#, one per scene scope. Screen history for `BackAsync`, serialises transitions, runs popups |
| `ScreenModule` | `Concretes/UI/` | `Register<ScreenService>(Lifetime.Scoped)`, installed from `SceneModules.InstallMenu` / `InstallGame` |

- **One `UIDocument` per screen or popup**, each on its own prefab (`UIDocument` + its `*View`), all
  sharing the one `PanelSettings` (Card 4). Layer order is `UIDocument.sortingOrder`, fixed per
  kind: screens `0`, popups `100`, overlays `200` — the BaseCanvas variant table, again.
- **Every screen and popup is registered by its scene's own scope** — a `[SerializeField]` on
  `MenuScope`/`GameScope` plus `builder.RegisterComponent(...)` (Card 12). Its `Construct` hands itself
  to `IScreenService.Register`. Nothing is found by scanning the hierarchy.
- **Screens start inactive in the scene.** An `IAsyncStartable` entry point in `SceneModules` shows the
  first one. Hidden = GameObject inactive, so hidden screens cost nothing.
- **A popup's root element is its backdrop**: full-screen, a scrim colour, and — because it has a
  background and default `picking-mode` — it swallows every click meant for what is below it.

**GOTCHA:** `ScreenView` implements `IScreen` — the one View that gets an interface, and the reason is
not mocking (`solid-oop.md` → Interface Scope): it is the seam that keeps `ScreenService` a Tier 3
class with no MonoBehaviour type in it, and therefore EditMode-testable. Two more traps, both measured
in a baseline design written from these files before this card existed: a popup whose open class
lands only on the backdrop leaves its panel at `opacity: 0` forever (the panel's rule must be written
as a descendant of the root's state — `.is-open .popup-panel`), and a mediator that calls `Bind()` on
its children from its own `OnEnable` races the children's `OnEnable`, whose order across GameObjects
Unity does not guarantee. Two popups of the same type at once is not supported — the service keys by
type.

---

### Card 14: Motion — USS Plays It, C# Only Flips a Class and Awaits the End

**WHEN:** Any fade, slide, pop, hover or press animation on a UI Toolkit element.

**WRONG:**
```csharp
element.AddToClassList("is-visible");
await UniTask.Delay(TimeSpan.FromSeconds(_config.FadeSeconds), cancellationToken: ct); // a second copy of the USS duration
```
```csharp
root.RegisterCallback<TransitionEndEvent>(_ => gameObject.SetActive(false)); // fires for ANY child's transition too
```

**RIGHT:**
```css
/* _GameFolders/UI/Theme/Motion.uss — the only file that says how things move */
.anim-fade         { opacity: 0; transition-property: opacity;
                     transition-duration: var(--motion-base); transition-timing-function: ease-out-cubic; }
.anim-fade.is-open { opacity: 1; }
```
```csharp
await UssTransition.SetStateAsync(root, "is-open", true, ct);   // flips the class, awaits the real end
```

| Need | Tool |
|---|---|
| Fade, slide, pop, hover, press, selected-state — any A → B | USS transition + a state class (`is-open`, `is-active`) |
| Waiting for it to finish | `UssTransition.SetStateAsync` — never raw `TransitionEndEvent`, never `Delay` |
| Count-up numbers, infinite loops (spinner, pulse), multi-step sequences | C# tween — the project's **existing** library: PrimeTween ≥ 1.3.1 animates `VisualElement` natively; DOTween via the generic `DOTween.To(getter, setter, …)`. Never both. Kill rules from `unity-lifecycle.md` apply unchanged |
| Blur / grayscale / drop-shadow on an element | USS `filter` — **6000.3+** only |
| Blur of what is behind a popup | USS `backdrop-filter` — **6000.6+** only; below that the backdrop is a flat `--color-scrim` |

- Durations and easings are **tokens** (`--motion-fast`, `--motion-base`, `--motion-slow`) — one file
  retimes the whole game (Card 2). C# never states a duration; the helper's timeout is a safety net,
  not a copy of it.
- Every animation class transitions `opacity`, and `opacity` is what the helper waits for — one
  property, one completion signal, whichever other properties also move.
- Screens pick an animation in UXML (`class="screen anim-fade"`); the screen's C# contains no motion.
- **ViewModels never know animation exists.** They expose state; the View flips a class on change.
- `experimental.animation` is not used — the namespace says the API may change.

**GOTCHA:** Four documented behaviours make a hand-rolled wait wrong, and `UssTransition` exists only to
absorb them: `TransitionEndEvent` **bubbles** (a child's hover transition ends your "close" wait);
an interrupted transition sends **`TransitionCancelEvent`, not** `TransitionEndEvent`; the end event
**may never arrive** when there was no previous style state or the transition was removed; and a
transition only starts **after the element's first frame** — a class added in the same frame the
element appears snaps with no animation. Deactivating the GameObject before the close transition ends
destroys the tree and the exit animation with it. `@keyframes` does not exist in USS — anything written
with keyframes in an HTML mockup is rewritten as a C# tween, so keep mockups to `transition` on
transform/opacity and the port stays mechanical.

> **Not yet measured in this repo — verify in the first project that adopts this card, then delete the
> line that proved true:** (a) whether `TransitionEndEvent` arrives once per property or once per
> transition (the helper filters on `opacity`, so it is correct either way); (b) that `var()` works
> inside `transition-duration` (the design system relies on it); (c) that one frame is enough after
> activating a `UIDocument`; (d) whether `filter` itself is transitionable.

---

## Folder Layout

```
_GameFolders/UI/
├── Settings/GamePanelSettings.asset     ← Card 4, one asset
├── Theme/                               ← DesignTokens.uss (or the game theme over ds-*), Motion.uss (Card 14), runtime .tss
├── Components/                          ← reusable UXML templates + their USS (Card 2 tokens only)
└── Screens/<Screen>/                    ← <Screen>.uxml + <Screen>.uss
_GameFolders/Scripts/Games/Concretes/<Domain>/<Screen>View.cs   ← Card 5
```

`.uxml`/`.uss` are assets, not scripts, so they never go under `Scripts/`. The View stays in its
domain folder like every other MonoBehaviour.

## Design Workflow

Unity is the worst place to *design* a screen and a fine place to *build* one. Decide the look first
— a Figma frame, or an HTML/CSS mockup an agent can iterate on in a browser — then translate. USS is a
CSS subset and Figma Auto Layout is flexbox, so the translation is mechanical. Figma → UI Toolkit
converters exist (open-source `FigmaToUnity`, commercial D.A. Assets); evaluate one before hand-porting
a large Figma file.

## What UI Toolkit Still Lacks (every version)

- Animation Clip / Timeline integration and keyframed animation → UGUI (Card 1)
- Serialized (Inspector-wired) events — irrelevant here: `event-patterns.md` forbids Inspector wiring anyway
- In-scene authoring — screens are authored in UXML/UI Builder, not in the Hierarchy, so the MCP
  `manage_gameobject`/`manage_components` tools place the `UIDocument` but do not lay out the screen

## Common Mistakes

| Mistake | Solution |
|---|---|
| UI Toolkit runtime UI on Unity < 6000.0 | UGUI — UI Toolkit is Editor-only there (Card 1) |
| World-space or shader UI Toolkit on 6000.0–6000.4 | UGUI for those screens (Card 1) |
| Raw hex / px / ms in a component rule | A token in `DesignTokens.uss` (Card 2) |
| `var()` in UXML `style=` | A USS class (Card 3) |
| A PanelSettings per screen | One shared asset, BaseCanvas-identical scaling (Card 4) |
| Element refs cached in `Awake`/`Start` | Query in `OnEnable`, unsubscribe in `OnDisable` (Card 5) |
| Transition on `height`/`width`, or on the theme swap | `translate`/`opacity`; `ds-no-transition` during a swap (Card 6) |
| Trusting multilingual text in the Editor | Explicit fallback chain, verified in a build (Card 7) |
| `border-radius: 999px` pill | Half-height pill token (Card 8) |
| Copying the design system into `Assets/` | Pinned UPM git dependency (Card 9) |
| "Done" without looking at it | Game-view capture at two widths (Card 10) |
| A ViewModel for every screen, including a three-button menu | View → Service directly unless the screen has state of its own (Card 11) |
| An `if`, a format string or two service fields in the View | Move them into a ViewModel (Card 11) |
| An MVC "UI Controller" or an MVP `I*View` interface | MVVM — the suffix rule and the interface rule already decide this (Card 11) |
| Unity `binding-path` strings for screen state | R3 subscriptions, checked by the compiler (Card 11) |
| ViewModel never disposed | Dispose it in the View's `OnDestroy`; bindings clear in `OnDisable` (Card 11) |
| NRE on the first line of a View's `OnEnable` | `Construct` never ran — register the View in its scene's scope, or spawn it with `IObjectResolver.Instantiate` (Card 12) |
| A Menu-scene View relying on the Bootstrap `AppScope` | The View's own scene scope registers it (Card 12) |
| ViewModel registered as a Singleton so the container disposes it | Factory + View-owned dispose; a Singleton shares state across screen instances (Card 12) |
| A View holding another View, or a `UIRoot` mediator | `IScreenService.ShowAsync<T>` / `BackAsync` (Card 13) |
| A popup closed with `SetActive(false)` | `ScreenView.HideAsync` — close transition first, then deactivate (Cards 13–14) |
| `UniTask.Delay(duration)` to wait for a transition | `UssTransition.SetStateAsync` — the duration lives only in USS (Card 14) |
| Raw `TransitionEndEvent` callback | It bubbles and may never fire — `UssTransition` (Card 14) |
| `@keyframes` ported from a mockup | No keyframes in USS — a C# tween (Card 14) |
