# Tasks: [Module Name]
> Design: design.md
> Status: ⏳ Pending

> **Every task that creates a new `.cs` file MUST declare `Callers:` and `Wiring:`.**
> Files under `Tests/` are exempt. Edit tasks need no fields, except
> `FormerlySerializedAs:` when the task renames a `[SerializeField]`.
> Validated before SCOPE_GATE by `.claude/scripts/validate-plan-facts.sh`.
>
> **These fields are cross-verified by a machine, not just read by a human —**
> only specific shapes earn `cross-verified` in the validator's receipt, and
> every new `.cs` also needs an `.asmdef` owning its location — either already
> on disk, or declared as its own checkbox task whose FIRST backticked token is
> the `.asmdef` (an `.asmdef` mentioned only as a trailing aside on a `.cs`
> task's line does not count).
> - `Callers:` — **two forms, pick the one that's actually true today:**
>   - a backticked `` `Path/To/File.cs` `` token → **cross-verified**, but ONLY
>     if it resolves to a file already on disk or to another checkbox task's
>     declared path in this same plan (a task may not name itself). **If it
>     resolves to neither, the plan is REJECTED — not downgraded to
>     presence-only.** Never backtick a path you have not confirmed exists yet
>     (a green-field module has no `AppModules.cs` on disk and no task creating
>     one — backticking it there is a guaranteed violation, not a shortcut).
>   - an unbackticked reference or a task ID like `T003` → accepted as a valid
>     declaration, counted `presence-only` — the validator never machine-checks
>     it, but it is not a violation either. This is the safe default when the
>     caller doesn't exist as a file yet.
> - `Wiring:` (on a `*Service` task only) — same two-form choice, scoped to
>   exactly one backticked `` `[Domain]Module.cs` `` token: cross-verified if
>   it resolves (disk or plan task), **rejected** if it doesn't. Prose, bare
>   identifiers, two or more module tokens, or hedges ("TBD", "compare X") are
>   all `presence-only`. Per `bootstrap-pattern.md`, a service registers in a
>   domain `[Domain]Module.cs`, which then contributes one line to
>   `AppModules.cs` — naming `AppModules.cs` here never satisfies this check,
>   since a service never registers there directly.

## Phase 0 — Foundational (Blocking)

The minimum infrastructure this module needs — add it if missing, skip it if present.

- [ ] T001 `_GameFolders/Scripts/Games/Concretes/[Domain]/[Domain]Module.cs` — static class, signature `Install(IContainerBuilder builder, [Domain]Configuration config)`
  - Callers: AppModules.cs (one new line: `[Domain]Module.Install(...)`) — presence-only; do NOT backtick this path unless AppModules.cs already exists on disk or is declared by another task in THIS plan (see schema note above)
  - Wiring: n/a — this file IS the module; it is not itself wired into another module
  - Acceptance: compiles without error; registered by adding one line to AppModules.cs

## Phase 1 — PS1 (P1) 🎯 Oynanabilir Dilim

- [ ] T002 [parallel_group:1] `_GameFolders/Scripts/Games/Abstracts/[Domain]/IXxxService.cs` — interface
  ```csharp
  // Taslak
  public interface IXxxService
  {
      void DoSomething();
  }
  ```
  - Callers: `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` (implementation, T004), T003 (EditMode test)
  - Wiring: implementation is registered in `[Domain]Module.cs` via `Install()` → `Register<XxxService>().AsImplementedInterfaces()`
  - Test type: EditMode
  - Acceptance: Interface derleniyor

- [ ] T003 [parallel_group:1] `_GameFolders/Scripts/Tests/[Project]EditModeTest/XxxServiceTests.cs` — EditMode test
  - Acceptance: the test runs and passes

- [ ] T004 `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` — implementation
  - Callers: T003 (EditMode test); production caller is the owning Controller/Handler — name it once that task exists
  - Wiring: registered in `[Domain]Module.cs` via `Install()` → `Register<XxxService>().AsImplementedInterfaces()`
  - Acceptance: the T003 tests pass

**Checkpoint: PS1 Independent Test passes — [the independent verification step from spec.md PS1]**

## Phase 2 — PS2 (P2)

- [ ] T005 [parallel_group:2] ...

**Checkpoint: PS2 Independent Test passes**
