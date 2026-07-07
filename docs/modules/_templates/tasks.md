# Tasks: [Modül Adı]
> Design: design.md
> Status: ⏳ Pending

## Phase 0 — Foundational (Blocking)

Bu modülün gerektirdiği minimum altyapı — yoksa ekle, varsa atla.

- [ ] T001 `_GameFolders/Scripts/Games/Concretes/[Domain]/[Domain]Module.cs` — static class, `Install(IContainerBuilder builder, [Domain]Configuration config)` imzası
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
  - Test type: EditMode
  - Acceptance: Interface derleniyor

- [ ] T003 [parallel_group:1] `_GameFolders/Scripts/Tests/[Project]EditModeTest/XxxServiceTests.cs` — EditMode test
  - Acceptance: Test çalışıyor, başarıyla geçiyor

- [ ] T004 `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` — implementation
  - Acceptance: T003 testleri geçiyor

**Checkpoint: PS1 Independent Test geçer — [spec.md PS1'deki bağımsız doğrulama adımı]**

## Phase 2 — PS2 (P2)

- [ ] T005 [parallel_group:2] ...

**Checkpoint: PS2 Independent Test geçer**
