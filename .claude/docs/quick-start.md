# Quick Start

1. Copy the `.claude/` folder into your Unity project root
2. Run `/setup-project` — it detects existing state, asks about optional features (Addressables / Testing / ECS), generates folder structure, .asmdef files, and base classes, then writes `.claude/project-features.json`
3. Complete the **Manual Setup Checklist** — see `.claude/docs/setup-checklist.md`

For an existing project with legacy code, see **Adding to an Existing Project** below.

## Adding to an Existing Project

Copy `.claude/` into the project root. Most hooks warn only — four will **block** existing code:

| Hook | What it blocks | Migration path |
|------|---------------|----------------|
| `check-input-system.sh` | `Input.GetKey`, `Input.GetAxis` | Create `PlayerControls.inputactions`, wrap in `InputView` |
| `check-vcontainer-singleton.sh` | Static singletons | Replace with VContainer registration in scope |
| `guard-editor-runtime.sh` | Bare `using UnityEditor` in runtime | Wrap with `#if UNITY_EDITOR` |
| `check-pure-csharp.sh` | `using UnityEngine` in `_Framework/` | Move Unity calls to a Provider in `Games/Concretes/` |

**Recommended migration order:**
1. Run `/setup-project` to scaffold the folder structure
2. Move existing scripts into the new structure without changing logic
3. Fix blocking hook violations one module at a time
4. Run `/migrate` for systematic pattern replacements (e.g. coroutine→UniTask)
5. Run `/validate` after each phase to confirm green state

---

## Troubleshooting

### NSubstitute is not found / `using NSubstitute;` fails to resolve

NSubstitute is **not** distributed via the Package Manager — `/setup-project` cannot install it automatically. Manual steps:

1. Download `NSubstitute.dll` and `Castle.Core.dll` from the NSubstitute releases page (or via NuGet → extract `lib/netstandard2.0/`).
2. Place both DLLs under `Assets/Plugins/NSubstitute/` (create the folder if missing).
3. In the Unity Inspector, restrict the DLLs to **Editor** platform only to avoid build errors.
4. Reference them from your test `.asmdef` via *Assembly Definition References*.

### Claude refuses to edit `.claude/settings.json`

This is intentional. `check-config-protection.sh` (PreToolUse) blocks every `Write`/`Edit` targeting `settings.json` to prevent accidental loss of the hook pipeline. To add or modify hook entries:

1. Open `.claude/settings.json` in a **non-Claude** editor (VS Code, vim, etc.).
2. Edit the `PostToolUse` / `PreToolUse` / `Stop` array directly.
3. Validate with `jq . .claude/settings.json > /dev/null` before saving.
4. Restart Claude Code so the new hook configuration is picked up.

### I created a new hook but it doesn't run

After dropping a script into `.claude/hooks/`, you must:

1. `chmod +x .claude/hooks/<your-hook>.sh` — the harness only executes executable files.
2. Add a matching entry to `.claude/settings.json` manually (see previous item).
3. Restart Claude Code.

### `/setup-project` did not generate test folders

Check `.claude/project-features.json`: `"testing"` must be `true`. The default ships as `true` (since 2026-05-26). If you opted out, flip the flag and re-run the scaffold steps from `/setup-project`.

### The knowledge graph isn't updating after edits

Confirm: (1) `.claude/project-features.json` has `"graph": true`; (2) `.claude/settings.json` includes a PostToolUse entry for `.claude/hooks/graph-auto-update.sh` (add manually if missing); (3) `.claude/graph/graph-builder.py` exists (it is invoked via `python3`, so its exec bit does not matter). After an edit, check `.claude/state/graph-updates.log` for a new line — that line proves the hook fired, not that a rebuild ran: rebuilds are serialised by a lock, so a write landing while one is in flight is logged and skipped. If a rebuild ran and something in it failed, `.claude/state/graph-rebuild.err` holds that run's stderr.

### Subagent edits aren't being verified at write time

This is by design. `PostToolUse` hooks only fire in the session that owns the tool call — so `verify-after-write.sh` never sees writes performed by a subagent spawned by `/orchestrate`, `/implement`, `/fix`, etc. Instead, every successful Write/Edit is appended to `.claude/state/session-edits.txt` (the accumulator), and the `stop-verify.sh` Stop hook drains that accumulator at session end running `bash -n` / `jq .` / `dotnet build` per file extension. If you don't see a `[stop-verify] verified=N warnings=M` line at session end, confirm `stop-verify.sh` is in the `"Stop"` array of `settings.json` (see the hook-wiring item above) and is executable.
