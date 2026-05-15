---
name: documentation-and-adrs
description: Record architectural decisions as ADRs (Architecture Decision Records). Triggered by the /adr command. Writes decisions such as why VContainer, why struct events, why UniTask to docs/decisions/.
model-tier: normal
---

# Documentation and ADRs (Unity)

## Overview

Document decisions, not code. The most valuable documentation answers *why* — the context, constraints, and trade-offs that produced a decision. Code shows *what* was built; an ADR explains *why it was done this way* and *which alternatives were considered*.

## When to Use

- When making a significant architectural decision (VContainer vs Zenject, UniTask vs Coroutine, ECS vs MonoBehaviour)
- When choosing between competing approaches
- Before adding a new module, system, or package
- To prevent "why was this done this way?" questions when a new developer (or a new Claude session) starts on the project
- When you find yourself explaining the same thing repeatedly

**When NOT to Use:** Documenting obvious code. Writing comments that just restate what the code does. Opening an ADR for temporary prototype code.

## Architecture Decision Records (ADRs)

ADRs capture the rationale behind significant technical decisions. They are the most valuable form of documentation you can write.

### When to Write an ADR

- Framework, library, or major dependency selection (VContainer, UniTask, Addressables, DOTS)
- Render pipeline decision (Built-in → URP, URP → HDRP)
- Architectural pattern selection (ECS vs MonoBehaviour, event bus vs direct call)
- Package version decisions (why stay on this version, why upgrade)
- Any decision that would be expensive to reverse

### ADR Template

Save ADRs to `docs/decisions/` with sequential numbering:

```markdown
# ADR-001: VContainer over Zenject

## Status
Accepted | Superseded by ADR-XXX | Deprecated

## Date
2025-01-15

## Context
A dependency injection framework is needed across the project. Core requirements:
- Unity 6 compatibility
- Compile-time safety (over runtime reflection)
- Options considered: VContainer, Zenject, Manual DI

## Decision
Use VContainer.

## Alternatives Considered

### Zenject
- Pros: Large ecosystem, many examples
- Cons: Slow maintenance for Unity 6, heavier API
- Rejected: VContainer is superior in performance and actively maintained

### Manual DI (Factory + Constructor)
- Pros: Zero dependency, full control
- Cons: Scope management manual, Dispose lifecycle manual
- Rejected: Scope and lifecycle management becomes complex as the project grows

## Consequences
- AppScope → MenuScope → GameScope hierarchy is mandatory
- All services registered via interface
- Singleton pattern removed entirely
```

### ADR Lifecycle

```
PROPOSED → ACCEPTED → (SUPERSEDED or DEPRECATED)
```

- **Never delete old ADRs.** They capture historical context.
- When a decision changes, write a new ADR that references the old one.

## /adr Command

When the user wants to record an architectural decision:

```
/adr Decision not to use Zenject in favor of VContainer
/adr Why UniTask was chosen over Coroutines
/adr Addressables vs Resources.Load comparison
/adr When to prefer ECS DOTS over MonoBehaviour
```

### Command Flow

1. Scan `docs/decisions/` — find current ADR count (for next number)
2. Ask the user for context: why is this decision being made now?
3. Evaluate at least 2 alternatives
4. Write the ADR file as `docs/decisions/NNN-topic.md`
5. Add a reference to the relevant section in CLAUDE.md (if needed)

## Example ADRs for a Unity Project

Recommended ADRs to create at the start of a template project:

| ADR | Topic |
|-----|-------|
| ADR-001 | VContainer selection |
| ADR-002 | UniTask and CancellationToken strategy |
| ADR-003 | IEventBus struct event pattern |
| ADR-004 | Addressables — Resources.Load ban |
| ADR-005 | New Input System and InputView architecture |
| ADR-006 | URP render pipeline selection |
| ADR-007 | NSubstitute + AAA test strategy |

## Inline Code Documentation

### When to Write a Comment

Write *why*, not *what*:

```csharp
// WRONG: Repeats the code
// increment counter
_retryCount++;

// RIGHT: Explains non-obvious intent
// VContainer Dispose() order is non-deterministic — unsubscribe first,
// then null the reference. Otherwise destroyed object callback fires.
_eventBus?.Unsubscribe<LevelStartedEvent>(OnLevelStarted);
_eventBus = null;
```

### When NOT to Write a Comment

```csharp
// Don't comment code with explanatory names
public void TakeDamage(int amount) => _health -= amount;

// Don't leave TODO comments — either do it now or write an ADR
// TODO: add null check  ← Do it now

// Don't leave commented-out code — git history exists
// private IEnumerator OldCoroutine() { ... }  ← Delete it
```

### Document Known Pitfalls

```csharp
// IMPORTANT: This method must be called inside AppScope.Configure(),
// before RegisterBuildCallback. Called after it, EventBusAccessor
// gives a null reference on the first ECS System update.
// See: ADR-003
public static void Initialize(IEventBus bus) => _instance = bus;
```

## CLAUDE.md and Rules Files

Special attention for AI agent context:

- **CLAUDE.md** — Project rules must be kept current; the agent reads this at every session start
- **`.claude/rules/`** — Architectural decisions should be reflected here as rules
- **ADRs** — Let the agent understand the *why* behind past decisions, preventing it from relitigating them
- **Inline gotchas** — Prevent the agent from falling into known pitfalls

## Common Rationalizations

| Rationalization | Reality |
|-----------------|---------|
| "The code is self-documenting" | Code shows the what, not the why. It doesn't explain alternatives considered or constraints that applied. |
| "We'll write it when the API stabilizes" | Writing the ADR accelerates design. The ADR is the first test of the design. |
| "Nobody reads documentation" | Agents do. Future developers do. You will, six months from now. |
| "ADRs are extra work" | A 10-minute ADR prevents a 2-hour debate about the same topic six months later. |

## Verification Checklist

- [ ] Significant architectural decisions have an ADR
- [ ] Each ADR evaluates at least 2 alternatives
- [ ] ADR numbering is sequential (`docs/decisions/`)
- [ ] Known pitfalls are documented inline
- [ ] No commented-out code
- [ ] CLAUDE.md and rules files are current
- [ ] Unity-specific decisions (ECS, URP, Input System) are justified in an ADR
