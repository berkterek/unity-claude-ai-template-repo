Read at: mini-fixture

Base `S` = `Assets/Mini`. Line ranges are hints; the symbol is the reference.

| Task(s) | File (repo-relative) | Symbol | Lines (hint) | Why it matters |
|---|---|---|---|---|
| T001 | `S/MiniService.cs` | `MiniService` | 5-40 | Type row: located, behaviour from doc |
| T002 | `S/MiniTicker.cs` | `MiniTicker.Tick(float)` | 10-18 | Method row: located, behaviour from callers |
| T003 | `S/MiniModel.cs` | `Score` | 8 | Property row: located, no behaviour fact |
| T004 | `S/MiniController.cs` | `_ticks` | 7 | Field row: start line only, so not located; no fact |
| T005 | `S/MiniModule.cs` | `RegisterEntryPoint<MiniBoot>` | 12 | Registration row: located by line, behaviour from registration |
| T006 | `S/Mini.uxml` | `panel-main` | — | Out of scope (uxml) |
