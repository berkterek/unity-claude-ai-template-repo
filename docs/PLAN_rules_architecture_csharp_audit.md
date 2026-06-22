# PLAN — Rules Audit: architecture.md & csharp-unity.md

> **Version:** v1 — 2026-06-19
> **Status:** Active
> **Scope:** `.claude/rules/architecture.md`, `.claude/rules/csharp-unity.md`, `.claude/rules/event-patterns.md`, `.claude/rules/unity-input.md`, `.claude/rules/solid-oop.md`

---

## Context

These rule files are loaded into every Claude Code session and drive all code generation decisions. Errors here propagate at session scale. This audit identified nine inconsistencies, three code-example violations, and five missing-rule gaps across `architecture.md` and `csharp-unity.md`. Changes are purely additive or clarifying — no existing rules are deleted. The Turkish-language block in `csharp-unity.md` is the only critical blocker because it makes the rule opaque to non-Turkish readers in an otherwise English file.

---

## Goals

- [ ] Translate the Turkish Namespace Collision Rule section in `csharp-unity.md` to English.
- [ ] Clarify `?.` null-check usage in the `event-patterns.md` Button example — add a note explaining why `?.` is acceptable on a SerializeField null-guard but NOT on destroyed-object checks.
- [ ] Fix `public class` vs `public sealed class` discrepancy in the `StoreService` example.
- [ ] Clarify the `#region` exemption threshold (total method count, not public-only).
- [ ] Clarify when `.Forget()` requires an exception handler vs when bare `.Forget()` is acceptable.
- [ ] Clarify the `Awake()` vs `Initialize()` rule: `new PlayerControls()` does not depend on injected services and is safe in `Awake()`.
- [ ] Add `CancellationTokenSource` ownership rule (creator owns, cancel before dispose, never pass CTS itself).
- [ ] Expand the namespace collision alias table with all common UnityEngine type collisions.
- [ ] Add `[field: SerializeField]` auto-property guidance.
- [ ] Add cross-references between files using the `> See also:` convention.
- [ ] Add Subscribe/Unsubscribe table row for dynamically instantiated MonoBehaviours (not VContainer-registered).
- [ ] Add missing `#region` tags to `InputView` example in `unity-input.md` and `ScoreView` example in `architecture.md`.

---

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 — Language | Task 1: Translate Turkish block in csharp-unity.md | ✅ Done | A |
| 1 — Language | Task 2: Clarify `?.` null-guard in event-patterns.md | ✅ Done | A |
| 2 — Code Examples | Task 3: Fix StoreService missing `sealed` | ✅ Done | B |
| 2 — Code Examples | Task 4: Add `#region` tags to InputView in unity-input.md | ✅ Done | B |
| 2 — Code Examples | Task 5: Add `#region` tags to ScoreView in architecture.md | ✅ Done | B |
| 3 — Clarifications | Task 6: Clarify `#region` exemption threshold | ✅ Done | C |
| 3 — Clarifications | Task 7: Clarify `.Forget()` handler requirement | ✅ Done | C |
| 3 — Clarifications | Task 8a: Clarify Awake() vs Initialize() in architecture.md | ✅ Done | C |
| 3 — Clarifications | Task 8b: Clarify Awake() exemption in solid-oop.md | ✅ Done | C |
| 3 — Clarifications | Task 9: Add CancellationTokenSource ownership rule | ✅ Done | C |
| 4 — Additions | Task 10: Expand namespace collision table | ✅ Done | D |
| 4 — Additions | Task 11: Add `[field: SerializeField]` guidance | ✅ Done | D |
| 4 — Additions | Task 12: Add dynamic MonoBehaviour row to Subscribe table | ✅ Done | D |
| 5 — Cross-References | Task 13: Add cross-references between all files | ✅ Done | E |

> **Dependency note:** Group E (Task 13) must run after all other groups complete — cross-references point to sections added or modified in Tasks 1–12.

---

## File Map

| File | Change Type | Tasks |
|------|-------------|-------|
| `.claude/rules/csharp-unity.md` | Modify | 1, 3, 6, 7, 9, 10, 11, 13 |
| `.claude/rules/architecture.md` | Modify | 5, 8a, 12, 13 |
| `.claude/rules/unity-input.md` | Modify | 4, 13 |
| `.claude/rules/event-patterns.md` | Modify | 2, 13 |
| `.claude/rules/solid-oop.md` | Modify | 8b |

---

## Task 1 — Translate Turkish Namespace Collision Rule to English

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** A
**Test Type:** NoTest

### Problem

The "Namespace Collision Rule" prose section is written entirely in Turkish. All other content in `csharp-unity.md` is English. This is the only Turkish prose in the file; any non-Turkish reader cannot understand the enforcement details.

### Steps

1. [ ] Locate the section `### Namespace Collision Rule (NON-NEGOTIABLE)` in `csharp-unity.md` (below Card 5).
2. [ ] Replace the Turkish prose body with the English translation below. Keep the heading, the table structure, and the code block unchanged — only the prose language changes.

**Before (Turkish prose):**
```
`Game.Concretes.<Domain>` namespace adı `UnityEngine` tip adlarıyla çakışabilir. Çakışma olduğunda C# derleyicisi hangi tipi kastettiğini bilemez ve ambiguous reference hatası verir.

**Bilinen çakışmalar:**
...
**Kural:** `Game.Concretes.<Domain>` namespace'i `UnityEngine` içinde aynı adlı bir tip barındırıyorsa, o domain'in **tüm** `.cs` dosyalarının en üstüne alias ekle:
...
**Plan aşamasında kontrol:** Yeni bir domain klasörü oluşturulmadan önce Researcher, domain adının...
```

**After (English translation):**
```
The `Game.Concretes.<Domain>` namespace can collide with `UnityEngine` type names. When a collision exists the C# compiler cannot resolve which type is intended and raises an ambiguous reference error.

**Known collisions:** (see Task 10 for the full expanded table)

**Rule:** When `Game.Concretes.<Domain>` contains a type whose name matches a `UnityEngine` type, add the alias at the top of **every** `.cs` file in that domain.

**Pre-plan check:** Before creating a new domain folder, the Researcher must verify that the domain name does not match a `UnityEngine` type. If a match exists, add an alias task to the plan.
```

### Acceptance Criteria

- No Turkish characters remain in `csharp-unity.md`.
- The heading, table structure, and code block are unchanged.
- The rule meaning is identical to the original Turkish.

---

## Task 2 — Clarify `?.` Null-Guard in event-patterns.md Button Example

**Files:** `.claude/rules/event-patterns.md`
**parallel_group:** A
**Test Type:** NoTest

### Problem

Pattern 4 uses `_playButton?.onClick.AddListener(...)`. This is a null-guard on a `[SerializeField]` field (checking whether the Inspector reference was assigned), NOT a destroyed-object check. This usage is acceptable. However, without a note, a reader applying Card 2 from `csharp-unity.md` ("never use `?.` on Unity objects") may incorrectly flag this pattern as a violation.

The distinction: `?.` is **forbidden** when checking whether a Unity object has been destroyed at runtime (the `==` override handles that). `?.` is **acceptable** when checking whether a `[SerializeField]` field was assigned in the Inspector (i.e., null because the designer left it empty, not because it was destroyed).

### Steps

1. [ ] Locate the `MainMenuView` code example in Pattern 4 of `event-patterns.md`.
2. [ ] Add a note immediately after the code block:

```
> **Why `?.` is acceptable here:** `_playButton` is a `[SerializeField]` — it can be `null` if the designer left the field unassigned in the Inspector. This `?.` is a field-assignment null-guard, not a destroyed-object check. Using `?.` to check whether a Unity object has been **destroyed at runtime** is still forbidden (use `if (_target != null)` for that). See also: `rules/csharp-unity.md` → Card 2: Null Check.
```

3. [ ] Do NOT change the `?.` usage in the code example — it is correct as-is.

### Acceptance Criteria

- The note is added after the `MainMenuView` code block.
- The note clearly distinguishes field-assignment null-guard from destroyed-object check.
- The code example is unchanged.

---

## Task 3 — Fix StoreService Missing `sealed` Keyword

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** B
**Test Type:** NoTest

### Problem

The `CancellationToken` section shows `public class StoreService`. All concrete service classes must be `sealed` per the Types and File Rules section of the same file. The example directly contradicts the rule it illustrates.

### Steps

1. [ ] Locate the `StoreService` code block in the `### CancellationToken` subsection.
2. [ ] Change `public class StoreService` → `public sealed class StoreService`.

**Before:**
```csharp
public class StoreService : IInitializable, IDisposable
```

**After:**
```csharp
public sealed class StoreService : IInitializable, IDisposable
```

### Acceptance Criteria

- `StoreService` is declared `sealed` in the example.
- No other text in the block changes.

---

## Task 4 — Add `#region` Tags to InputView Example in unity-input.md

**Files:** `.claude/rules/unity-input.md`
**parallel_group:** B
**Test Type:** NoTest

### Problem

The `InputView` example in `unity-input.md` has 6 methods (`Awake`, `Construct`, `OnEnable`, `OnDisable`, `Update`, `OnJump`) — well above the 3-method threshold for `#region` tags. The example violates the `#region` rule from `csharp-unity.md` Card 4.

### Steps

1. [ ] Locate the `InputView` code block in `unity-input.md` (`## InputView Pattern` section).
2. [ ] Replace the class body with the `#region`-tagged version:

```csharp
public sealed class InputView : MonoBehaviour
{
    #region Fields

    private PlayerControls _controls;
    private PlayerSystem   _playerSystem;

    #endregion

    #region Lifecycle

    private void Awake()
    {
        _controls = new PlayerControls();
    }

    [Inject]
    public void Construct(PlayerSystem playerSystem)
    {
        _playerSystem = playerSystem;
    }

    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed += OnJump;
        _controls.Player.Attack.performed += OnAttack;
    }

    private void OnDisable()
    {
        _controls.Player.Jump.performed -= OnJump;
        _controls.Player.Attack.performed -= OnAttack;
        _controls.Player.Disable();
    }

    private void Update()
    {
        Vector2 moveInput = _controls.Player.Move.ReadValue<Vector2>();
        _playerSystem.SetMoveInput(moveInput);
    }

    #endregion

    #region Private Methods

    private void OnJump(InputAction.CallbackContext ctx)   => _playerSystem.Jump();
    private void OnAttack(InputAction.CallbackContext ctx) => _playerSystem.Attack();

    #endregion
}
```

### Acceptance Criteria

- `InputView` example uses Fields, Lifecycle, and Private Methods regions.
- All original logic is preserved — no method bodies change.
- `[Inject] Construct` stays in Lifecycle (VContainer lifecycle entry point).

---

## Task 5 — Add `#region` Tags to ScoreView Example in architecture.md

**Files:** `.claude/rules/architecture.md`
**parallel_group:** B
**Test Type:** NoTest

### Problem

The `ScoreView` example in `architecture.md` has 4 methods (`Construct`, `OnEnable`, `OnDisable`, `Display`) — above the 3-method threshold. Same violation as Task 4.

### Steps

1. [ ] Locate the `ScoreView` code block in the `### Avoid One-Caller Overfitting` section of `architecture.md`.
2. [ ] Add `#region` tags:

```csharp
public sealed class ScoreView : MonoBehaviour
{
    #region Fields

    private ScoreModel _model;

    #endregion

    #region Lifecycle

    [Inject]
    public void Construct(ScoreModel model) => _model = model;

    private void OnEnable()  => _model.OnScoreChanged += Display;
    private void OnDisable() => _model.OnScoreChanged -= Display;

    #endregion

    #region Private Methods

    private void Display(int score) => _scoreLabel.text = score.ToString();

    #endregion
}
```

### Acceptance Criteria

- `ScoreView` uses Fields, Lifecycle, and Private Methods regions.
- All original logic is preserved.

---

## Task 6 — Clarify `#region` Exemption Threshold

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** C
**Test Type:** NoTest

### Problem

Card 4 and the prose section say "helper classes with fewer than 3 methods are exempt." "Methods" is ambiguous — does it mean total methods or public methods? This causes inconsistent application.

### Steps

1. [ ] In Card 4 GOTCHA, change:

**Before:**
```
**GOTCHA:** Interface files, single-member structs/enums, and helper classes with < 3 methods are exempt.
```

**After:**
```
**GOTCHA:** Interface files, single-member structs/enums, and helper classes with fewer than 3 methods total (all access levels combined) are exempt. At 3 or more methods, `#region` is required regardless of visibility.
```

2. [ ] In the `## Script Structure — #region` prose section Exception line, change:

**Before:**
```
**Exception:** Interface files, single-member structs/enums, and helper classes with fewer than 3 methods do not require `#region`.
```

**After:**
```
**Exception:** Interface files, single-member structs/enums, and helper classes with fewer than 3 methods total (all access levels combined) do not require `#region`. At 3 or more methods, regions are mandatory.
```

### Acceptance Criteria

- Both occurrences of the exemption rule now include "total (all access levels combined)".
- No other text in the section changes.

---

## Task 7 — Clarify `.Forget()` Handler Requirement

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** C
**Test Type:** NoTest

### Problem

Card 3 RIGHT example shows a full exception handler on `.Forget()`. The `StoreService` prose example uses bare `.Forget()`. No rule states when the handler is required vs when bare `.Forget()` is acceptable. This inconsistency causes developers to guess.

### Steps

1. [ ] In the `### Fire-and-forget` subsection, add a handler rule block after the existing code example:

```
**Handler rule:**
- **Full handler (default):** Use when the async method can propagate non-cancellation exceptions.
  ```csharp
  LoadAsync(ct).Forget(ex => { if (ex is not OperationCanceledException) Debug.LogException(ex); });
  ```
- **Bare `.Forget()` (exception only):** Acceptable only when exceptions are caught internally by the method. Add a comment: `// safe: exceptions handled internally`.

When in doubt, use the full handler. Bare `.Forget()` that silently drops exceptions is equivalent to an empty catch block.
```

2. [ ] Update the `StoreService` `Initialize()` call:

**Before:**
```csharp
SetupAsync(_cts.Token).Forget();
```

**After:**
```csharp
SetupAsync(_cts.Token).Forget(ex => { if (ex is not OperationCanceledException) Debug.LogException(ex); });
```

### Acceptance Criteria

- The handler rule block appears in the Fire-and-forget subsection.
- The `StoreService` example uses the full handler.
- Card 3 RIGHT example is unchanged (already correct).

---

## Task 8a — Clarify Awake() vs Initialize() in architecture.md

**Files:** `.claude/rules/architecture.md`
**parallel_group:** C
**Test Type:** NoTest

### Problem

The `InputView` example uses `private void Awake() => _controls = new PlayerControls();`. A reader applying `solid-oop.md`'s "no initialization logic in Awake" rule may flag this incorrectly. The rule targets injected-service initialization; constructing a dependency-free generated class in `Awake` is not a violation.

### Steps

1. [ ] In `architecture.md`, directly after the `InputView` code block in `## Input System Architecture`, add:

```
> **Why `Awake()` here is correct:** `new PlayerControls()` is a Unity Input System generated class with no injected dependencies. The `solid-oop.md` rule forbids *injection-dependent initialization* in `Awake()` — service dependencies must arrive via `[Inject] Construct()`. Constructing a dependency-free generated class does not violate this rule.
```

### Acceptance Criteria

- The note appears directly after the InputView code block.
- The note explicitly distinguishes "dependency-free construction" from "injection-dependent initialization".

---

## Task 8b — Clarify Awake() Exemption in solid-oop.md

**Files:** `.claude/rules/solid-oop.md`
**parallel_group:** C
**Test Type:** NoTest

### Problem

`solid-oop.md` states the Awake rule without any exemption. The exemption for dependency-free construction (e.g., `new PlayerControls()`) needs to be documented here too so the rule is self-consistent.

### Steps

1. [ ] In `solid-oop.md`, locate the Sınırlar (Limits) bullet:

**Before:**
```
- `Awake()`/`Start()` içinde initialization logic yok — VContainer `Initialize()` bunu üstlenir
```

**After:**
```
- `Awake()`/`Start()` içinde injection-dependent initialization logic yok — VContainer `Initialize()` bunu üstlenir. İnjection gerektirmeyen generated class'lar (örn. `new PlayerControls()`) `Awake()` içinde instantiate edilebilir.
```

### Acceptance Criteria

- The bullet clarifies that dependency-free generated classes (`new PlayerControls()`) are exempt.
- The existing Turkish prose style is preserved (this file is intentionally Turkish).

---

## Task 9 — Add CancellationTokenSource Ownership Rule

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** C
**Test Type:** NoTest

### Problem

The file shows CTS creation and disposal in `StoreService` but never states the ownership rules. Without a rule, CTS instances are created in callers, shared across class boundaries, or forgotten in disposal.

### Steps

1. [ ] In the `### CancellationToken` subsection, add the following table immediately after the `StoreService` code example:

```
**CancellationTokenSource ownership rules:**

| Rule | Detail |
|------|--------|
| Creator owns it | The class that calls `new CancellationTokenSource()` is responsible for `.Cancel()` and `.Dispose()` |
| Cancel before Dispose | Always call `_cts.Cancel()` before `_cts.Dispose()` — cancels in-flight tasks first |
| Dispose in `Dispose()` | For `IDisposable` classes: `Dispose()`. For MonoBehaviour: `OnDestroy()` |
| Never pass the CTS | Pass only `_cts.Token` to callees — never the `CancellationTokenSource` itself |
| Null-guard before use | `_cts?.Cancel(); _cts?.Dispose();` — CTS may be null if `Initialize()` was never called |
```

### Acceptance Criteria

- The ownership table appears after the `StoreService` example.
- No existing example text changes.

---

## Task 10 — Expand Namespace Collision Alias Table

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** D
**Test Type:** NoTest

### Problem

The known-collisions table lists only `Camera` and `Random`. Card 5 and the rule prose mention `Object`, `Input`, `Physics`, `Collider`, `Transform` in text but not in the table. A developer creating `Game.Concretes.Physics` gets no alias guidance.

### Steps

1. [ ] Locate the known-collisions table in `### Namespace Collision Rule`.
2. [ ] Replace the two-row table with the expanded nine-row table:

```
| Domain namespace | Colliding UnityEngine type | Alias |
|-----------------|---------------------------|-------|
| `Game.Concretes.Camera` | `UnityEngine.Camera` | `using UCamera = UnityEngine.Camera;` |
| `Game.Concretes.Random` | `UnityEngine.Random` | `using URandom = UnityEngine.Random;` |
| `Game.Concretes.Object` | `UnityEngine.Object` | `using UObject = UnityEngine.Object;` |
| `Game.Concretes.Input` | `UnityEngine.Input` | `using UInput = UnityEngine.Input;` |
| `Game.Concretes.Physics` | `UnityEngine.Physics` | `using UPhysics = UnityEngine.Physics;` |
| `Game.Concretes.Collider` | `UnityEngine.Collider` | `using UCollider = UnityEngine.Collider;` |
| `Game.Concretes.Transform` | `UnityEngine.Transform` | `using UTransform = UnityEngine.Transform;` |
| `Game.Concretes.Time` | `UnityEngine.Time` | `using UTime = UnityEngine.Time;` |
| `Game.Concretes.Component` | `UnityEngine.Component` | `using UComponent = UnityEngine.Component;` |
```

3. [ ] Update Card 5 GOTCHA to reference the prose table:

**Before:**
```
**GOTCHA:** Check domain name against UnityEngine types before creating the folder. Add the alias to every `.cs` file in that domain.
```

**After:**
```
**GOTCHA:** Check domain name against UnityEngine types before creating the folder. Consult the full collision table in `### Namespace Collision Rule`. Add the alias to every `.cs` file in that domain.
```

### Acceptance Criteria

- The table has 9 rows.
- Card 5 GOTCHA references the prose table instead of listing types inline.
- All 9 alias names follow the `U<TypeName>` pattern.

---

## Task 11 — Add `[field: SerializeField]` Auto-Property Guidance

**Files:** `.claude/rules/csharp-unity.md`
**parallel_group:** D
**Test Type:** NoTest

### Problem

`csharp-unity.md` documents `[SerializeField] private float _moveSpeed` but never mentions `[field: SerializeField]` auto-property syntax. Developers using auto-properties either avoid serialization or use public fields unnecessarily.

### Steps

1. [ ] In `## Field Declarations`, add the following block after the existing `[SerializeField]` examples:

```csharp
// [field: SerializeField] — auto-property with Inspector serialization.
// Use when a public getter with Inspector visibility is needed on a data class or ScriptableObject.
[field: SerializeField] public float MoveSpeed { get; private set; } = 5f;

// Equivalent explicit form (preferred in most cases):
[SerializeField] private float _moveSpeed = 5f;
public float MoveSpeed => _moveSpeed;
```

Add after the code block:
```
**Rule:** Prefer the explicit backing-field form (`_moveSpeed` + read-only property) in `MonoBehaviour` and service classes — it keeps the underscore naming convention, is easier to debug in the Inspector, and works on all Unity versions. Use `[field: SerializeField]` only in `[Serializable]` data classes or `ScriptableObject` configs where a clean public getter is the primary API.
```

### Acceptance Criteria

- `[field: SerializeField]` syntax is documented with a code example.
- The rule clearly states when to use it vs the explicit form.

---

## Task 12 — Add Dynamic MonoBehaviour Row to Subscribe/Unsubscribe Table

**Files:** `.claude/rules/architecture.md`
**parallel_group:** D
**Test Type:** NoTest

### Problem

The Subscribe/Unsubscribe table covers three cases: plain C#, MonoBehaviour via `RegisterComponent`, and MonoBehaviour with `OnEnable`/`OnDisable`. Runtime-instantiated MonoBehaviours (pooled enemies, spawned projectiles — not registered via VContainer) have no guidance.

### Steps

1. [ ] Locate the `### Subscribe / Unsubscribe Rules` table in `architecture.md`.
2. [ ] Add a fourth row:

```
| MonoBehaviour — runtime instantiated (Instantiate, not VContainer-registered) | `OnEnable()` | `OnDisable()` |
```

3. [ ] Add a note below the table:

```
> **Dynamic instances:** MonoBehaviours created via `Instantiate()` are not registered with VContainer and have no `Initialize()`/`Dispose()` lifecycle. Use `OnEnable()`/`OnDisable()` — `OnDisable` is called before `OnDestroy`, so unsubscribing there is safe. Do NOT rely solely on `OnDestroy()` for IEventBus unsubscription.
```

### Acceptance Criteria

- The table has four rows.
- The note explains why `OnDisable` (not `OnDestroy`) is the correct unsubscription point for dynamic instances.

---

## Task 13 — Add Cross-References Between Files

**Files:** `.claude/rules/architecture.md`, `.claude/rules/csharp-unity.md`, `.claude/rules/event-patterns.md`, `.claude/rules/unity-input.md`
**parallel_group:** E
**Test Type:** NoTest

### Problem

Files are read independently in every session. Overlapping concerns (SerializeField, MonoBehaviour role limits, null checks, namespace collisions) are defined once but not linked. Claude can apply a rule from one file without knowing a contradicting or extending rule exists elsewhere.

### Steps

1. [ ] In `architecture.md`, end of `## IEvent System for Communication`, add:
```
> See also: `rules/event-patterns.md` → Decision Tree, Pattern 1 (IEventBus), Pattern 4 (UGUI Button)
```

2. [ ] In `architecture.md`, end of `## Input System Architecture`, add:
```
> See also: `rules/unity-input.md` → InputView Pattern; `rules/solid-oop.md` → MonoBehaviour Sınırlar (Awake clarification); `rules/csharp-unity.md` → Card 4 (#region for 3+ methods)
```

3. [ ] In `architecture.md`, end of `## Provider Pattern`, add:
```
> See also: `rules/solid-oop.md` → MonoBehaviour Rol Sınırları (View/Provider/Controller roles)
```

4. [ ] In `csharp-unity.md`, end of `### Card 2: Null Check`, add:
```
> See also: `rules/event-patterns.md` → Pattern 4 note (field-assignment null-guard vs destroyed-object check)
```

5. [ ] In `csharp-unity.md`, end of `## Field Declarations`, add:
```
> See also: `rules/architecture.md` → Card 6 (Same Prefab SerializeField rule); `rules/performance.md` → Component References section
```

6. [ ] In `event-patterns.md`, end of `## Pattern 4: UGUI Button.onClick`, add:
```
> See also: `rules/csharp-unity.md` → Card 2 (null-check: field-assignment `?.` vs destroyed-object `== null`)
```

7. [ ] In `unity-input.md`, end of `## InputView Pattern`, add:
```
> See also: `rules/architecture.md` → Card 6 (SerializeField for same-prefab refs); `rules/csharp-unity.md` → Card 4 (#region for 3+ methods)
```

### Acceptance Criteria

- Each cross-reference follows the format `` > See also: `rules/file.md` → Section ``.
- No more than one `> See also:` block per section.
- No circular references that would confuse the reader (A→B pointing to a sub-section B covers is fine).

---

*No existing plan in `docs/` covers these files — confirmed by git log and Docs/ listing.*
