---
name: planning-and-task-breakdown
description: Task decomposition discipline for /create-plan and /plan-module. Vertical slice, per-task acceptance criteria, and checkpoints. Enhances existing planning pipelines.
model-tier: heavy
---

# Planning and Task Breakdown (Unity)

## Overview

Break work into small, verifiable tasks — each with clear acceptance criteria. Good task breakdown is the difference between an agent that produces reliable output and one that produces complex chaos. Every task should be sized so it can be implemented, tested, and verified in a single focused session.

## When to Use

- When `/create-plan` or `/plan-module` is invoked
- When a task looks too large or ambiguous to start
- When planning parallel agent work
- Before creating tasks.md

## Planning Process

### Step 1: Enter Plan Mode (Read-Only)

Before writing any code:

- Read the spec file and relevant codebase sections
- Identify existing patterns and rules (CLAUDE.md, architecture.md)
- Map dependencies between components
- Note risks and unknowns

**Do not write code during planning.** The output is a plan document, not an implementation.

### Step 2: Draw the Dependency Graph

Map what depends on what:

```
IEnemyService (interface)
    │
    ├── EnemyService (implementation)
    │       │
    │       ├── EnemyInstaller (VContainer registration)
    │       │
    │       └── EnemyTests (test)
    │
    └── EnemyProvider (MonoBehaviour — Unity API)
            │
            └── EnemyAuthoring (ECS baker, if applicable)
```

Implementation order follows the dependency graph bottom-up: foundations first.

### Step 3: Slice Vertically (Vertical Slice)

Instead of writing all interfaces, then all services, then all installers — build one feature path end to end:

**Bad (horizontal slicing):**
```
Task 1: Write all interfaces
Task 2: Write all services
Task 3: Write all installers
Task 4: Connect everything
```

**Good (vertical slicing):**
```
Task 1: Enemy spawns (IAudioService → AudioService → AudioInstaller → test)
Task 2: Enemy takes damage (IHealthService → HealthService → Installer → test)
Task 3: Enemy dies (IDeathService → DeathService + event → test)
Task 4: Enemy animation triggers (Provider + ECS bridge)
```

Each vertical slice delivers a working, testable piece of functionality.

### Step 4: Write the Tasks

Each task follows this structure:

```markdown
## Task [N]: [Short descriptive title]

**Description:** One paragraph explaining what this task accomplishes.

**Acceptance Criteria:**
- [ ] [Specific, testable condition]
- [ ] [Specific, testable condition]
- [ ] Tests green: `dotnet test --filter "ClassName"`
- [ ] Compiles without errors

**Dependencies:** [Task numbers this task depends on, or "None"]

**Files likely affected:**
- `_GameFolders/Scripts/Games/Abstracts/Audio/IAudioService.cs`
- `_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs`
- `_GameFolders/Scripts/Tests/AudioTests/AudioServiceTests.cs`

**Estimated scope:** [Small: 1-2 files | Medium: 3-5 files | Large: 5+ files]
```

### Step 5: Order and Add Checkpoints

Arrange tasks so that:

1. Dependencies are satisfied (foundations first)
2. Each task leaves the system in a working state
3. A validation checkpoint follows every 2-3 tasks
4. High-risk tasks come early (fail fast)

Checkpoints should be explicit:

```markdown
## Checkpoint: After Tasks 1-3
- [ ] All tests green
- [ ] Unity compiles without errors
- [ ] Core player flow works end to end
- [ ] Human approval before proceeding
```

## Task Size Guide

| Size | Files | Scope | Example |
|------|-------|-------|---------|
| **XS** | 1 | Single method or config | Add a validation rule |
| **S** | 1-2 | Single component or service | Write a new event struct |
| **M** | 3-5 | One feature slice | AudioService + Installer + test |
| **L** | 5-8 | Multi-component feature | Full spawn system |
| **XL** | 8+ | **Too large — split further** | — |

**Split a task if:**
- The task title contains "and" (sign of two tasks)
- Acceptance criteria has more than 3 items
- It touches two or more independent systems
- VContainer scope change + ECS change + UI change all at once

## tasks.md Template

```markdown
# Implementation Plan: [Feature/Project Name]

## Overview
[One paragraph summary of what we are building]

## Architectural Decisions
- [Key decision 1 and rationale — or ADR reference]
- [Key decision 2 and rationale]

## Task List

### Phase 1: Core Infrastructure
- [ ] Task 1: ...
- [ ] Task 2: ...

### Checkpoint: Core Infrastructure
- [ ] Tests green, compile clean

### Phase 2: Core Features
- [ ] Task 3: ...
- [ ] Task 4: ...

### Checkpoint: Core Features
- [ ] End-to-end flow working

### Phase 3: Integration
- [ ] Task 5: ...

### Checkpoint: Complete
- [ ] All acceptance criteria met
- [ ] Ready for review

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Scene reference lost during ECS migration | High | Test in test scene first |

## Open Questions
- [Question requiring human input]
```

## Parallelization Opportunities

When multiple agents or sessions are available:

- **Can parallelize:** Independent feature slices, tests for existing implementations, documentation
- **Must be sequential:** Database/schema migrations, shared state changes, dependency chains
- **Requires coordination:** Features sharing a common interface (lock the interface first, then parallelize)

Use `parallel_group` annotations in tasks.md — `/orchestrate` detects these automatically.

## Common Rationalizations

| Rationalization | Reality |
|-----------------|---------|
| "I'll figure it out as I go" | This is how complex, tangled code gets written and rewritten. 10 minutes of planning saves hours. |
| "The tasks are obvious" | Write them anyway. Explicit tasks surface hidden dependencies and forgotten edge cases. |
| "Planning is extra work" | Planning is the task. Without a plan, implementation is just typing. |
| "I can keep it all in my head" | The context window is finite. Written plans survive session boundaries. |

## Verification Checklist

Before starting implementation:

- [ ] Every task has acceptance criteria
- [ ] Every task has a verification step (test command or manual check)
- [ ] Task dependencies are identified and ordered
- [ ] No task touches more than ~5 files
- [ ] Checkpoints exist between major phases
- [ ] Tasks that can run in parallel are marked with `parallel_group`
- [ ] Human has approved the plan document
