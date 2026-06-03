# Hook Self-Tests

Automated tests for the critical hooks in this template. Uses [bats-core](https://github.com/bats-core/bats-core).

## Run all tests

```bash
./.claude/hooks/tests/run-tests.sh
```

## Install bats

```bash
# macOS
brew install bats-core

# Linux
npm install -g bats
```

## Test files

| File | Hook under test |
|------|----------------|
| `block-git-push.bats` | `block-git-push.sh` |
| `block-scene-edit.bats` | `block-scene-edit.sh` |
| `block-projectsettings.bats` | `block-projectsettings.sh` |
| `check-config-protection.bats` | `check-config-protection.sh` |
| `check-pure-csharp.bats` | `check-pure-csharp.sh` |
| `check-vcontainer-singleton.bats` | `check-vcontainer-singleton.sh` |
| `check-unity-event.bats` | `check-unity-event.sh` |
| `check-legacy-input.bats` | `check-input-system.sh` |
| `session-save.bats` | `session-save.sh` — gate expiry |
| `graph-auto-update.bats` | `graph-auto-update.sh` — empty graph warning |
| `hook-profile.bats` | `_lib.sh` — profile gating, `DISABLE_UNITY_HOOKS`, `UNITY_HOOK_MODE` |
| `guard-gate-cleared.bats` | `guard-gate-cleared.sh` |

## What each test covers

Every `.bats` file includes:
- **Happy path** — allowed operation exits 0
- **Blocking trigger** — forbidden operation exits 2 with `BLOCKED`
- **Profile skip** — `UNITY_HOOK_PROFILE=minimal` skips standard/strict hooks
- **Warn mode** — `UNITY_HOOK_MODE=warn` downgrades exit 2 to exit 0 (where applicable)

Tests use a temporary `UNITY_HOOK_STATE_DIR` (`mktemp -d`) so they never pollute real session state.
