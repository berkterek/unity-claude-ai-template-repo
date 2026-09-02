# `/setup-project` Compile Probe

Answers one question: **does the project `/setup-project` generates actually compile?**

Fifth test layer in this repo, and the second deterministic one. Plain extraction plus a real
`Unity -batchmode` — no model in the loop.

## The gap this covers

| Layer | Measures | Deterministic? |
|---|---|---|
| `.claude/hooks/tests/` — 48 bats suites | a hook's exit code on planted input | yes |
| `.claude/scripts/validate-generated-asmdefs.py` | the assembly graph matches the code inside it | yes — but it is text analysis, not a compile |
| `.claude/tests/reviewer-fixtures/` | which criteria a reviewer prompt fires | no — costs an agent |
| `.claude/tests/pipeline-dry-run/` | gate order, state-file lifecycle | no — costs an agent |
| `.claude/tests/blender-fbx-probe/` | a binary asset after a real Unity import | yes |
| **this harness** | **the generated project compiles** | **yes** |

Still covered by nothing: PlayMode, scene wiring, prefab authoring, Step 5d MCP setup.

## Why it exists

`/setup-project` emits `.asmdef` and `.cs` files as fenced blocks inside a markdown command file.
Until 2026-09-02 nothing had ever compiled them, and three compile errors had shipped in the
generated framework code — found by reading, not by any test.

`validate-generated-asmdefs.py` was written first because it is cheap and catches that whole class.
It is not a substitute: it cannot see a typo, a missing type, or a wrong signature, and it says so
in its own output. This harness is the real answer.

**It paid for itself on its first run.** With the validator already green, the probe failed:

```
Assets/_Framework/Events/EventBus.cs(3,7): error CS0246:
  The type or namespace name 'VContainer' could not be found
```

`FrameworkEvents` carried `references: []` while `EventBus.cs` did `using VContainer.Unity` — a
defect that predates the save/load work and had never been caught. The validator had waved it
through because it treated every package namespace as external and therefore unchecked. Both were
fixed: the asmdef gained the reference, and the validator gained a package map so the same class of
error is now caught in 0.1s instead of needing a Unity run.

A second thing was measured rather than guessed while fixing it: the reference alone was enough.
`noEngineReferences: true` stayed on `FrameworkEvents`, because `EventBus.cs` genuinely touches no
engine type. Two changes had been made at once; re-running the probe with one reverted said which
one mattered.

## How to run

```bash
.claude/tests/setup-compile-probe/run-probe.sh                 # exit 0 = compiles
.claude/tests/setup-compile-probe/run-probe.sh --keep          # leave the temp project on disk
.claude/tests/setup-compile-probe/run-probe.sh --unity /path/to/Unity
.claude/tests/setup-compile-probe/run-probe.sh --help
```

Exit codes: `0` compiled clean · `2` compile errors (listed, log path printed, project kept) ·
`1` the harness could not run — no Unity, extraction failed, or Unity exited non-zero with **no**
compile errors in the log, which is a licence or package-resolution problem and must never be
reported as green.

Run it after editing any Step 3 or Step 4 block. ~20s warm, minutes cold. It is not a hook and must
never become one.

## What it does

1. Extracts every Step 3 / Step 4 block via `validate-generated-asmdefs.py --extract`. Shared parser
   on purpose — the probe must compile exactly the files the validator reasons about, and two
   parsers would eventually disagree in a way that reads as a green probe over an unchecked file.
2. Writes `Packages/manifest.json`: `com.unity.inputsystem`, `com.unity.nuget.newtonsoft-json`, plus
   VContainer and UniTask from the OpenUPM scoped registry.
3. `Unity -batchmode -nographics -quit`.
4. Greps the log for `error CS####`.

## Deliberate exclusions

`Games/Ecs/` needs `Unity.Entities` and ECS is disabled in the template's default feature set;
`Scripts/Tests/` needs an NSubstitute DLL no clone has (Gate B). Neither exclusion says those paths
are fine — they are simply not what this probe measures.

## Prerequisites

A licensed Unity Editor (pinned to `6000.2.6f2`; falls back to the newest installed and says so) and
network access for OpenUPM. Verified 2026-09-02: VContainer 1.16.9, UniTask 2.5.10, InputSystem
1.14.2, Newtonsoft 3.2.1 all resolve, and `FrameworkEvents`, `FrameworkLogging`,
`FrameworkSaveLoadSystems` and `<Name>Games` all produce DLLs in `Library/ScriptAssemblies`.

`FrameworkEditor` and `<Name>Editor` produce no DLL — they are asmdefs with no source files yet.
That is expected, not a failure.
