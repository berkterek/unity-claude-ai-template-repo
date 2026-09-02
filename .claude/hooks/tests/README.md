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

Not every suite here covers a `.claude/hooks/*.sh`. `.claude/scripts/` validators are
tested in this same directory — one runner, one place to look. Known gap:
`validate-plan-paths.sh` has no suite, though it is the fail-closed sibling of
`validate-plan-facts.sh` and carries the same responsibility.


| File | Under test |
|------|------------|
| `block-git-push.bats` | `block-git-push.sh` |
| `block-scene-edit.bats` | `block-scene-edit.sh` |
| `block-projectsettings.bats` | `block-projectsettings.sh` |
| `check-config-protection.bats` | `check-config-protection.sh` |
| `check-pure-csharp.bats` | `check-pure-csharp.sh` |
| `check-vcontainer-singleton.bats` | `check-vcontainer-singleton.sh` |
| `check-unity-event.bats` | `check-unity-event.sh` |
| `check-legacy-input.bats` | `check-input-system.sh` |
| `check-domain-folder-structure.bats` | `check-domain-folder-structure.sh` |
| `check-architecture-doc.bats` | `check-architecture-doc.sh` |
| `check-no-throwaway-editor-script.bats` | `check-no-throwaway-editor-script.sh` |
| `check-mono-justification.bats` | `check-mono-justification.sh` |
| `check-test-scene-exists.bats` | `check-test-scene-exists.sh` — includes the `project-features.json` `testing:false` gate |
| `session-save.bats` | `session-save.sh` — gate expiry |
| `graph-auto-update.bats` | `graph-auto-update.sh` — empty graph warning |
| `hook-profile.bats` | `_lib.sh` — profile gating, `DISABLE_UNITY_HOOKS`, `UNITY_HOOK_MODE` |
| `guard-gate-cleared.bats` | `guard-gate-cleared.sh` |
| `validate-plan-facts.bats` | `.claude/scripts/validate-plan-facts.sh` — plan-time fact gate (`Callers:`/`Wiring:`), fence handling, `_templates/` skip |
| `check-duplicate-siblings.bats` | `.claude/scripts/check-duplicate-siblings.py` — Card 5 structural duplicate detector; pins the two false positives it originally shipped with |

## What each test covers

Every `.bats` file includes:
- **Happy path** — allowed operation exits 0
- **Blocking trigger** — forbidden operation exits 2 with `BLOCKED`
- **Profile skip** — `UNITY_HOOK_PROFILE=minimal` skips standard/strict hooks
- **Warn mode** — `UNITY_HOOK_MODE=warn` downgrades exit 2 to exit 0 (where applicable)

Tests use a temporary `UNITY_HOOK_STATE_DIR` (`mktemp -d`) so they never pollute real session state.

## Run the suite with a clean environment

`env -u CLAUDE_PROJECT_DIR -u UNITY_HOOK_STATE_DIR bats .claude/hooks/tests/*.bats`

An inherited `CLAUDE_PROJECT_DIR` or `UNITY_HOOK_STATE_DIR` — easily left behind by a shell
where you were exercising a hook by hand — points some tests at the real `.claude/state` and
the real `path-allowlist.txt` instead of their own fixtures. Measured 2026-09-02: it produced
two reproducible-looking failures (`blocks direct read of graph.json when hybrid_graph is
true`, `path-allowlist.txt entry turns a block into a pass`) that vanish with a clean
environment. Both were chased as regressions before the cause was found.

If a failure will not reproduce for someone else, check this before anything else.
