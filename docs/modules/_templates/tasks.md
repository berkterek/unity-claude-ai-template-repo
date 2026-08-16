# Tasks: [Modül Adı]
> Design: design.md
> Status: ⏳ Pending

> **Every task that creates a new `.cs` file MUST declare `Callers:` and `Wiring:`.**
> Files under `Tests/` are exempt. Edit tasks need no fields, except
> `FormerlySerializedAs:` when the task renames a `[SerializeField]`.
> Validated before SCOPE_GATE by `.claude/scripts/validate-plan-facts.sh`.
>
> **These fields are cross-verified by a machine, not just read by a human —**
> only specific shapes earn `cross-verified` in the validator's receipt:
> - `Callers:` — cross-verified only for backticked `` `Path/To/File.cs` `` tokens
>   that resolve either to a file already on disk or to another checkbox task's
>   declared path in this same plan (a task may not name itself). A task-ID
>   reference like `T003` is a valid declaration, but it is only `presence-only`
>   — the validator cannot resolve a task ID to a path, so it never machine-checks it.
> - `Wiring:` (on a `*Service` task only) — cross-verified only when the line
>   contains **exactly one** backticked `` `[Domain]Module.cs` `` token that
>   resolves the same way (disk or plan task). Prose, bare identifiers, two or
>   more module tokens, or hedges ("TBD", "compare X") are all `presence-only`
>   — still a valid declaration, just not machine-verified. Per
>   `bootstrap-pattern.md`, a service registers in a domain `[Domain]Module.cs`,
>   which then contributes one line to `AppModules.cs` — naming `AppModules.cs`
>   here never satisfies this check, since a service never registers there directly.

## Phase 0 — Foundational (Blocking)

Bu modülün gerektirdiği minimum altyapı — yoksa ekle, varsa atla.

- [ ] T001 `_GameFolders/Scripts/Games/Concretes/[Domain]/[Domain]Module.cs` — static class, `Install(IContainerBuilder builder, [Domain]Configuration config)` imzası
  - Callers: `_GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs` (one new line: `[Domain]Module.Install(...)`)
  - Wiring: n/a — this file IS the module; it is not itself wired into another module
  - Acceptance: Derleme hatası yok; AppModules.cs'e bir satır eklenerek kaydolur

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
  - Acceptance: Test çalışıyor, başarıyla geçiyor

- [ ] T004 `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` — implementation
  - Callers: T003 (EditMode test); production caller is the owning Controller/Handler — name it once that task exists
  - Wiring: registered in `[Domain]Module.cs` via `Install()` → `Register<XxxService>().AsImplementedInterfaces()`
  - Acceptance: T003 testleri geçiyor

**Checkpoint: PS1 Independent Test geçer — [spec.md PS1'deki bağımsız doğrulama adımı]**

## Phase 2 — PS2 (P2)

- [ ] T005 [parallel_group:2] ...

**Checkpoint: PS2 Independent Test geçer**
