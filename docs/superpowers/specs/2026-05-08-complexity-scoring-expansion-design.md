# Complexity Scoring Expansion Design

**Date:** 2026-05-08  
**Status:** Approved

---

## Purpose

Extend the complexity scoring system from `fix` and `implement` to 4 more pipeline commands: `orchestrate`, `scene-setup`, `migrate`, `add-feature`.

Each command adjusts agent selection and pipeline depth based on the complexity score. Agent selection also depends on the target code type: pure C# → `coder`, Unity/Mixed → `unity-coder`.

---

## Out of Scope

- `fix-deep` — always runs max evidence pipeline; scoring adds no value
- `create-prefab-scene` — fixed legacy migration flow; scoring adds no value

---

## Shared Scoring Block

Added to all 4 commands as `## Step 0 — Complexity Scoring`. Same format as `fix.md` / `implement.md`:

```markdown
## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing).

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — coder → committer only |
| `lean` | Standard pipeline |
| `full` | unity-developer always active |

Before spawning any agents, score the task complexity on a 0.0–1.0 scale:

| Score | Label | Signals |
|-------|-------|---------|
| 0.0–0.3 | Simple | Single file, no new interfaces, no events |
| 0.4–0.6 | Medium | 2–4 files, new interface or event bus change |
| 0.7–1.0 | Complex | New module, ECS, Addressables, cross-system events |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
Complexity: [score] — [Label]
Rationale: [one sentence]
Pipeline: [which variant]
```

---

## Agent Routing Rule (All Commands)

Each command makes this decision before spawning a coder:

| Target | Agent (Simple) | Agent (Medium/Complex) |
|--------|----------------|------------------------|
| `_Framework/`, `Abstracts/`, pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring, Unity lifecycle | **unity-coder-lite** | **unity-coder** |
| Mixed (both) | **unity-coder-lite** | **unity-coder** |

---

## Per-Command Pipeline Changes

### `orchestrate`

| Score | Coder | Post-task Review |
|-------|-------|-----------------|
| Simple | coder / unity-coder-lite | unity-reviewer |
| Medium | coder / unity-coder | unity-reviewer |
| Complex | coder / unity-coder | unity-reviewer → unity-developer |

In `full` mode, unity-developer is always active regardless of score.

### `scene-setup`

Scene setup always targets Unity/Mixed — pure C# agent is never used.

| Score | Coder | Review |
|-------|-------|--------|
| Simple | unity-coder-lite | unity-reviewer |
| Medium | unity-coder | unity-reviewer |
| Complex | unity-coder | unity-reviewer → unity-developer |

### `migrate`

| Score | Pipeline |
|-------|----------|
| Simple | migrator/unity-migrator → reviewer |
| Medium | test guard → migrator/unity-migrator → reviewer |
| Complex | test guard → migrator/unity-migrator → unity-reviewer → unity-developer |

**Migrator routing:**
- Pure C# pattern migration → `migrator`
- Unity-specific migration (coroutine→UniTask, singleton→VContainer, legacy input) → `unity-migrator`

### `add-feature`

| Score | Interview | Coder | Review |
|-------|-----------|-------|--------|
| Simple | 3 targeted questions | coder / unity-coder-lite | unity-reviewer |
| Medium | full deep-interview | coder / unity-coder | unity-reviewer |
| Complex | full deep-interview | coder / unity-coder | unity-reviewer → unity-developer |

In `full` mode, unity-developer is always active.

---

## Implementation Points

The scoring block is added at the start of each command's pipeline (`## Step 0`). Existing step numbers shift up by 1.

| Command | Previous first step | New first step |
|---------|---------------------|----------------|
| `orchestrate` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
| `scene-setup` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
| `migrate` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
| `add-feature` | Step 1 | Step 1 → Step 2 (scoring Step 0) |
