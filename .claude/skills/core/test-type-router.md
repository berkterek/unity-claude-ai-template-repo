---
name: test-type-router
description: Determines test type (EditMode / PlayMode-ECS / PlayMode-Scene / NoTest) from a class name, file path, or task description. Used by /implement, /generate-tests, /create-test-scene, and /create-plan before any test writing begins.
model-tier: light
---

# Test Type Router

Given a class name, file path, or task description, emit one of four test type decisions. This is the single source of truth — all pipelines that write or create tests must call this first.

---

## Decision Matrix

### 1 — Path-based (fastest, most reliable)

If the target file path is known:

| Path contains | Decision |
|---------------|----------|
| `Games/Abstracts/` | **EditMode** |
| `Games/Concretes/` | **EditMode** |
| `Games/Ecs/Systems/` | **PlayMode-ECS** |
| `Games/Ecs/Components/` | **NoTest** — data struct |
| `Games/Ecs/Authorings/` | **NoTest** — bake-time only |
| `_Framework/` | **EditMode** — pure C# |
| `Editor/` | **NoTest** — editor tooling |

### 2 — Class type fallback (when path is unknown)

If the path is not known, inspect the class definition or task description:

| Class type | Decision |
|------------|----------|
| Extends `LifetimeScope` (Scope) | **NoTest** — DI wiring, tested via integration |
| Extends `MonoBehaviour` with no logic | **NoTest** — thin view/provider adapter |
| Extends `MonoBehaviour` WITH logic | **PlayMode-Scene** — lifecycle matters |
| `ISystem` or `SystemBase` | **PlayMode-ECS** — isolated World |
| `IComponentData` struct | **NoTest** — data only |
| `Baker<T>` inner class | **NoTest** — bake-time |
| Pure C# class (service, model, util) | **EditMode** |
| `ScriptableObject` config | **NoTest** — data container |

### 3 — Keyword fallback (last resort)

If neither path nor class type is available, scan the task description:

| Keywords in description | Decision |
|------------------------|----------|
| "ECS", "System", "ISystem", "World" | **PlayMode-ECS** |
| "MonoBehaviour", "scene", "prefab", "lifecycle", "VContainer wiring" | **PlayMode-Scene** |
| "service", "interface", "pure C#", "logic", "event", "model" | **EditMode** |
| "config", "SO", "ScriptableObject", "data struct", "authoring", "baker" | **NoTest** |

---

## Output Format

Always emit a single-line decision block before any test writing:

```
TEST TYPE DECISION
  Target:   [class name or file path]
  Decision: [EditMode | PlayMode-ECS | PlayMode-Scene | NoTest]
  Reason:   [one sentence — which rule matched]
```

**If decision is NoTest**, stop and report:
```
TEST TYPE DECISION
  Target:   [class name or file path]
  Decision: NoTest
  Reason:   [one sentence]

No test file will be created for this target.
```

**If decision is PlayMode-Scene**, also emit:
```
→ Use /create-test-scene [FeatureName] to scaffold the scene and TestBootstrap.
```

**If decision is PlayMode-ECS**, also emit:
```
→ Write an isolated World test in [ProjectName]PlayModeTest assembly.
   Do NOT use /create-test-scene — no scene needed for ECS system tests.
```

---

## How to Apply (per pipeline)

### /implement

Run this router in Step 0c (after complexity scoring). Extract the target class/path from `$TASK_DESCRIPTION`. Add the decision to the test-writer prompt as a hard constraint:

```
## Test Type (MANDATORY — do not override)
Decision: [EditMode | PlayMode-ECS | PlayMode-Scene | NoTest]
Reason: [from router output]
```

If **NoTest** → skip Step 1 (Test Writer) entirely.
If **PlayMode-Scene** → note that `/create-test-scene` should be run separately for the scene; test-writer writes the test stub only.

### /generate-tests

Run router first. If NoTest → stop with explanation. Otherwise proceed with correct assembly and test pattern.

### /create-test-scene

Run router in Step 2 pre-check. If decision is not PlayMode-Scene → stop:
```
⚠ This target does not require a Play Mode scene test.
  Decision: [EditMode | PlayMode-ECS | NoTest]
  Reason:   [one sentence]

Use /generate-tests instead.
```

### /create-plan

For each task in the plan, append a `test_type` field to the Task block:

```markdown
**Test Type:** EditMode | PlayMode-ECS | PlayMode-Scene | NoTest
```

Planner runs the router logic per task based on the file map entry for that task.
