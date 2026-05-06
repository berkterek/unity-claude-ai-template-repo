# Director Gates — Centralized Review Prompts

Named review gates used across pipeline commands. Reference by ID to avoid prompt drift.

---

## TD-ARCHITECTURE

**Trigger:** After any implementation — verify structural integrity.
**Context to pass:** Task description, files changed, relevant architecture rules.

**Verdict:** `PASS` — architecture is sound. `FAIL: [file:line] issue` — specific violation.

Checks:
- VContainer DI: no singletons, no static mutable state, no service locators
- Interface-driven: consumers depend on interfaces, not concrete types
- IEventBus: cross-module communication only through events, not direct calls
- Provider pattern: UnityEngine API in Concretes/ only, services are pure C#
- Module boundaries: no concrete cross-module dependencies

---

## TD-UNITY-RISK

**Trigger:** Before writing any architecture decision or implementation touching Unity APIs.
**Context to pass:** Unity API names being used, Unity 6 version, `docs/engine-reference/unity/`.

**Verdict:** `CLEAR` — no post-cutoff risk. `RISK: [api] [risk-level] [mitigation]`

Checks:
- Read `docs/engine-reference/unity/deprecated-apis.md` — is any listed API used?
- Read `docs/engine-reference/unity/breaking-changes.md` — does the task touch any affected area?
- Read `docs/engine-reference/unity/current-best-practices.md` — are better alternatives available?

---

## TD-PERFORMANCE

**Trigger:** After implementation of any system with Update/FixedUpdate paths or ECS systems.
**Context to pass:** Files changed, hot path locations.

**Verdict:** `PASS` or `FAIL: [file:line] [allocation-type]`

Checks:
- Zero heap allocations in Update/FixedUpdate/LateUpdate (no `new`, no boxing, no LINQ, no string ops)
- `renderer.material` not used (clones material) — use `sharedMaterial` or `MaterialPropertyBlock`
- ECS structural changes use ECB, not direct `EntityManager` calls inside systems
- Addressables handles stored as fields and released in `Dispose()`
- `Camera.main`, `GetComponent<T>()` cached in Awake — not called per frame

---

## TD-COMPILE

**Trigger:** After every coder pass — mandatory before reviewer.
**Context to pass:** Files changed.

**Verdict:** `VALIDATED` — clean compile and all tests pass. `COMPILE FAILED: [errors]` or `TEST FAILED: [tests]`

Steps:
1. `mcp__UnityMCP__refresh_unity` — trigger recompile
2. Poll `editor_state` until `isCompiling` is false
3. `mcp__UnityMCP__read_console` with type `Error` — check for errors
4. If clean → `mcp__UnityMCP__run_tests` — run Edit Mode tests
5. Report VALIDATED or list failures

---

## CD-SCOPE

**Trigger:** Before starting any task — verify scope is well-defined.
**Context to pass:** Task description, affected files.

**Verdict:** `CLEAR` — scope is bounded. `BLOATED: [what's out of scope]`

Checks:
- Does the task touch files not mentioned in the original request? Flag them.
- Is the task trying to refactor unrelated code? Flag it.
- Are new abstractions being created that have no current callers? Flag it.
- YAGNI: is everything being implemented actually needed right now?

---

## How to Reference Gates

In pipeline commands, reference a gate by ID:

```
Spawn reviewer subagent with gate TD-ARCHITECTURE:
Pass: task description + files changed
Expect verdict: PASS or FAIL: [file:line] issue
```

In agent prompts:
```
Apply gate TD-PERFORMANCE from .claude/docs/director-gates.md.
Files to check: $CODER_OUTPUT
```
