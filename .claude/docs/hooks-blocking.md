## Blocking Hooks (exit 2 — stops the write)

| Hook | Blocks |
|------|--------|
| `block-git-push.sh` | `git push` — Claude cannot push; user always pushes manually |
| `block-scene-edit.sh` | Direct editing of `.unity`, `.prefab`, `.asset` files |
| `guard-editor-runtime.sh` | `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `check-no-monobehaviour-in-services.sh` | `class FooService : MonoBehaviour` or `: ScriptableObject` in `_Framework/` / `Games/Abstracts/` / `Games/Concretes/` — `using UnityEngine` is allowed (math types); only inheritance is blocked |
| `check-input-system.sh` | Legacy `Input.GetKey` / `Input.GetAxis` API |
| `check-vcontainer-singleton.sh` | Static singleton patterns outside of `EventBusAccessor` |
| `check-unity-event.sh` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` |
| `check-time-scale.sh` | `Time.timeScale =` assignment — use IEventBus + PauseService instead |
| `check-enum-byte-base.sh` | `enum` without `: byte` base in ECS component or IEvent files — use `ushort` if 255+ values needed |
| `guard-critical-files.sh` | Edits to `AppScope`, `InputView`, `*Installer`, `IEventBus`, `.asmdef` without investigation — **exception: files under `TestScopes/`, `EditModeTest/`, or `PlayModeTest/` paths** |
| `check-config-protection.sh` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` — **exception: test assemblies (`EditModeTest`, `PlayModeTest`)** |
| `gateguard.sh` (PreToolUse) | Edit/Write on any C# file that has not been read in the current session |
| `guard-gate-cleared.sh` (PreToolUse) | Agent spawn blocked if `.claude/state/gate-cleared` is missing — Director Gate must be shown and `go` received before spawning any coder/fixer/committer agent |
| `guard-reviewer-order.sh` | Codex installed and no `.claude/state/codex-reviewed` marker → blocks `unity-reviewer` agent spawn; Codex review required first. |
| `guard-sparc-approved.sh` (PreToolUse) | Coder agent spawn blocked if `.claude/state/sparc-approved` is missing — SPARC gate must fire and `go` received before spawning `coder`, `unity-coder`, or `unity-coder-lite` |
| `block-projectsettings.sh` (PreToolUse Edit\|Write) | Direct edits to `ProjectSettings/*.asset`, `Packages/manifest.json`, `Packages/packages-lock.json` — use the Unity Editor or Package Manager instead. **[MANUAL: add to settings.json]** |
| `check-ls-grep.sh` (PreToolUse Bash) | `ls \| grep` / `ls \| awk` / `ls \| sed` patterns — use `tree` for directory listings instead |

@.claude/docs/hook-profiles.md
