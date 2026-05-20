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
