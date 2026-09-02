# PLAN — `/setup-project` compile probe (test layer B)

**Status:** DONE 2026-09-02 · **Built at:** `.claude/tests/setup-compile-probe/`

> Kept as the decision record. Live documentation is the harness README. What the first run found —
> `CS0246: VContainer`, a missing package reference in `FrameworkEvents` that the asmdef validator had
> waved through — is written up there, along with the follow-on fix to the validator's package map.
> Complication 2 below was predicted and confirmed: `/setup-project` still does not generate a
> `manifest.json`, the probe authors its own, and that manifest is very likely what Step 2 should emit.
> **That remains open.**

## The gap

`/setup-project` Step 3 and Step 4 emit `.asmdef` and `.cs` files as fenced blocks inside a markdown
command file. Nothing in this repo has ever compiled them.

`.claude/scripts/validate-generated-asmdefs.py` (layer A, landed 2026-09-02) closes one class: an
assembly boundary that no longer matches the code inside it. It is a text analysis and deliberately
says so in its own output — a clean run is not a compile. It cannot see a typo, a missing type, a
wrong signature, a namespace that does not resolve, or a package that fails to install.

That gap is not theoretical. Layer A exists because three real compile errors shipped in the
generated framework code on 2026-09-02 and were found by hand, not by any test.

## What to build

`.claude/tests/setup-compile-probe/run-probe.sh`, modelled on `.claude/tests/blender-fbx-probe/` —
the existing fourth layer, and the precedent for "drives a real Unity, no model in the loop, and is
therefore deterministic".

1. Create a throwaway Unity project in a temp dir.
2. Extract every Step 3 / Step 4 block from `.claude/commands/setup-project.md` and write it to the
   path its `#### \`path\`` header names. **Reuse the parser from
   `validate-generated-asmdefs.py`** — one extractor, so the probe and the validator can never
   disagree about what "the generated files" are.
3. Write `Packages/manifest.json` with the Gate A packages: `com.unity.inputsystem`,
   `com.unity.nuget.newtonsoft-json`, plus VContainer and UniTask via an openupm scoped registry.
4. `Unity -batchmode -quit -projectPath <tmp> -logFile <log>`.
5. Grep the log for compile errors; exit 2 with the offending lines, 0 if clean.
6. Clean up unless `--keep`.

Match the blender probe's interface: `--case`, `--keep`, `--help`, exit 0 = green.

## What it proves, and what it still will not

**Proves:** the generated project compiles — every type resolves, every assembly reference is
sufficient, every package installs.

**Does not prove:** that anything *runs*. PlayMode, scene wiring, prefab authoring and MCP-driven
setup (Step 5d) stay uncovered. Do not let a green probe be read as "setup works" — it means
"setup compiles".

## Known complications, in the order they will bite

1. **Package resolution needs network and an openupm scoped registry.** VContainer and UniTask are
   not on the Unity registry. This is the bulk of the work; the C# side is trivial by comparison.
2. **`/setup-project` does not generate `manifest.json` today.** Gate A only *checks* that packages
   are present and stops if they are not — nothing installs them. The probe has to author a manifest
   to run at all, and once it has one, that manifest is very likely the thing Step 2 should have
   been emitting all along. Expect this probe to produce a `/setup-project` change as a side effect,
   the way the blender probe disproved a claim in the skill it tested on its first run.
3. **Unity version.** Pin the probe to one installed Editor and say which; a version bump is a
   deliberate edit, not an ambient one.
4. **Runtime.** A cold `-batchmode` import is minutes, not seconds. This is not a per-write hook and
   must never become one — it runs on demand, and after any edit to the Step 3 / Step 4 blocks.

## Where it goes in the test-layer table

`.claude/CLAUDE.md` documents four layers. This is the fifth, and the second deterministic one:

| Layer | Measures | Deterministic |
|---|---|---|
| `.claude/hooks/tests/` | a hook's exit code | yes |
| `.claude/tests/reviewer-fixtures/` | which criteria a reviewer fires | no — costs an agent |
| `.claude/tests/pipeline-dry-run/` | gate order, state-file lifecycle | no — costs an agent |
| `.claude/tests/blender-fbx-probe/` | a binary asset after a real Unity import | yes |
| **`.claude/tests/setup-compile-probe/`** | **that the generated project compiles** | **yes** |

Update that table in `CLAUDE.md` when this lands.
