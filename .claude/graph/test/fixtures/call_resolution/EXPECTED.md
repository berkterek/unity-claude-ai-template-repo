# call_resolution fixtures — expected extraction/resolution facts

Minimal, self-contained `.cs` fixtures for the RC1–RC4 call-edge-resolution
fixes (see `docs/PLAN_graph_call_resolution.md`). Each file is committed here
so verification never depends on an external repo. `test_extractor_pubsub.py`
asserts extractor-level facts against these files; the incremental/tie-breaker
builder-level scenarios in `test_traversal_resolution.py` construct their own
in-memory variants of the same shapes (no file I/O) so they can control which
file is "changed" between two consecutive builds.

| Fixture | Root cause covered | Expected facts |
|---|---|---|
| `ISoundService.cs` | RC4 | Interface `ISoundService` (namespace `Game.Abstracts.Audio`) with method `Play`. |
| `SoundManager.cs` | RC1 / RC4 | Class `SoundManager` implements `ISoundService`; `classes[0].implements == ["ISoundService"]`; declares method `Play`. |
| `PlayerController.cs` | RC1 / RC4 | Class `PlayerController` has a field `_soundService` of declared type `ISoundService`; method `OnJump` calls `_soundService.Play("jump")` → extractor emits `callee == "ISoundService.Play"` (the resolved receiver type is the DECLARED/interface type, per architecture.md's Provider-via-interface pattern — this is the DI-routing shape RC4's `interface_bridge` match exists for), `callee_file=None`, `callee_class=None` at extraction time. After `graph-builder.resolve_call_targets` runs over `SoundManager.cs` + `ISoundService.cs` + this file, the edge resolves `callee_class=None`/`callee_file=None` still (head token is `ISoundService`, an interface, which IS indexed by `resolve_call_targets` since it also indexes `interfaces` — so it resolves to `ISoundService.cs`). A `callers SoundManager` query then reaches this caller via the `interface_bridge` match in `graph_bfs_core.match_keys`, not via `resolve_call_targets`. |
| `ScoreTweenController.cs` | RC2 | `DOTween.To(() => _value, x => _value = x, target, 1f).SetEase(Ease.Linear)` → two call edges: `DOTween.To` (direct PascalCase-receiver resolution) and `DOTween.SetEase` (chained call, falls back to `_receiver_head_token` walk — head is `DOTween`). Neither callee string contains `(`, `)`, `=>`, or a newline. |
| `InputMapLoader.cs` | RC3 | `var asset = InputActionAsset.FromJson(json); asset.FindActionMap("gameplay");` → `asset` is typed `InputActionAsset` via the PascalCase-static-receiver heuristic; the `FindActionMap` call edge has `callee == "InputActionAsset.FindActionMap"` and `confidence == "INFERRED"` (heuristic-derived receiver type, not a verified return type). |

## Not covered by static fixtures (constructed in-memory instead)

- **REV4 same-name tie-breaker** (production `Foo.cs` vs. a same-named `Tests/Foo.cs`, and the two-non-test-`Foo` ambiguous case) — built as in-memory `classes`/`interfaces` lists inside `test_traversal_resolution.py` so the test can freely vary file paths without committing near-duplicate fixture files.
- **Incremental-retention blocker** (two consecutive incremental builds editing only the callee's file) — exercised directly against `graph-builder.merge_call_edges` with constructed `existing_calls`/`changed_cs` inputs; no real two-pass file build is needed to prove the retention predicate.
- **REV5 `method_match`** — exercised directly against `graph-builder.resolve_call_targets` with constructed `classes`/`calls` inputs (populated vs. empty `methods[]`).
