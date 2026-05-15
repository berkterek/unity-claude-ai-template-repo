---
name: code-simplification
description: Chesterton's Fence discipline for /clean-slop. Understand why code was written before removing it. Reduces complexity while preserving behavior.
model-tier: normal
---

# Code Simplification (Unity)

## Overview

Reduce complexity while fully preserving behavior. The goal is not fewer lines — it's code that is easier to read, understand, change, and debug. Every simplification should pass a simple test: "Would a new team member understand this faster than the original?"

## When to Use

- When `/clean-slop` is invoked
- When a feature is working and tests are green, but the implementation feels heavier than it needs to be
- When a code review flags readability or complexity issues
- When refactoring code written under time pressure

**When NOT to Use:**
- Code that is already clean and readable — don't simplify for the sake of simplifying
- Code you don't yet understand — understand it first, then simplify
- Code you are about to rewrite entirely — simplifying code that will be deleted wastes time

## Five Principles

### 1. Preserve Behavior Completely

Don't change what the code does — only how it expresses it. All inputs, outputs, side effects, error behaviors, and edge cases must remain the same. If you're not sure a simplification preserves behavior, don't do it.

```
ASK BEFORE EVERY CHANGE:
→ Does this produce the same output for every input?
→ Does this preserve the same error behavior?
→ Does this preserve the same side effects and ordering?
→ Do all existing tests pass without modification?
```

### 2. Follow Project Rules

Simplification means making code more consistent with the codebase — not imposing external preferences. Before simplifying:

```
1. Read CLAUDE.md and .claude/rules/ files
2. Examine how neighboring code handles similar patterns
3. Follow the project's style:
   - #region structure
   - VContainer registration pattern
   - Event subscribe/unsubscribe lifecycle
   - UniTask usage pattern
   - Null check rules (Unity == null, not is null)
```

A simplification that breaks project consistency is not a simplification — it's noise.

### 3. Be Explicit, Not Clever

If compact code requires a mental pause to parse, explicit code is better.

```csharp
// NOT EXPLICIT: Dense ternary chain
var label = isNew ? "New" : isUpdated ? "Updated" : isArchived ? "Archived" : "Active";

// EXPLICIT: Readable mapping
private string GetStatusLabel(EnemyState state)
{
    if (state.IsNew) return "New";
    if (state.IsUpdated) return "Updated";
    if (state.IsArchived) return "Archived";
    return "Active";
}
```

### 4. Maintain Balance

Simplification has a failure mode: over-simplification:

- Overly aggressive inlining — removing a helper that gives a concept a name makes the call site harder to read
- Merging unrelated logic — combining two simple methods into one complex method is not simpler
- Removing "unnecessary" abstractions — some abstractions exist for extensibility or testability
- Optimizing for line count — fewer lines is not a goal

### 5. Focus on What Changed

Default to simplifying recently modified code. Avoid refactoring out-of-scope code — it creates noise in the diff and introduces regression risk in code you weren't planning to change.

## Simplification Process

### Step 1: Understand Before Touching (Chesterton's Fence)

Before changing or deleting anything, understand why it is there. This is Chesterton's Fence: if you can't explain why the fence is in the road, don't tear it down. Understand the reason first, then decide if the reason is still valid.

```
ANSWER BEFORE SIMPLIFYING:
- What is this code responsible for?
- Who calls it? What does it call?
- What are the edge cases and error paths?
- Are there tests that define this behavior?
- Why might it have been written this way? (Performance? Platform constraint? Unity lifecycle?)
- git blame: what was the original context of this code?
```

If you can't answer these, you are not ready to simplify. Read more context first.

**Unity-specific Chesterton Fences:**

```csharp
// This null check may look "paranoid" — but it's necessary in Unity
if (_target == null) return;  // Removing this: checks for destroyed objects

// This #if block may look unnecessary — but it breaks the build
#if UNITY_EDITOR
using UnityEditor;
#endif

// This ?.Forget() may look "bloated" — but it swallows exceptions intentionally
InitAsync(ct).Forget();  // not async void; intentional exception handling

// This cache may look like "premature optimization" — but it's required in Update
private Camera _mainCamera;  // Camera.main calls FindObjectOfType on every access
```

### Step 2: Find Simplification Opportunities

Scan for these patterns:

**Structural complexity:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| 3+ levels of nesting | Hard to follow control flow | Extract to guard clauses or helper methods |
| 50+ line method | Multiple responsibilities | Split into focused methods |
| Nested ternary | Requires mental stack | if/else chain or switch |
| Boolean flag parameters | `DoThing(true, false, true)` | Options object or separate methods |
| Repeated conditions | Same if-check in multiple places | Extract to a well-named predicate method |

**Naming and readability:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| Generic names | `data`, `result`, `temp`, `val` | Describe the content: `enemyStats`, `validationErrors` |
| Abbreviated names | `btn`, `evt`, `cfg` | Use full words (except universal abbreviations like `id`, `url`) |
| "What" comments | `// increment counter` above `_count++` | Delete the comment — code is self-explanatory |
| "Why" comments | `// VContainer Dispose order is non-deterministic` | Keep these — they are intentional context |

**Redundancy:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| Repeated logic | Same 5+ lines in multiple places | Extract to a shared method |
| Dead code | Unreachable branch, unused variable | Verify it's truly dead, then delete |
| Unnecessary abstraction | Wrapper that adds no value | Inline the wrapper |
| Over-engineering | Factory-of-factory, single-strategy Strategy | Replace with simple direct approach |

### Step 3: Apply Changes Incrementally

Make one simplification at a time. Run tests after each change.

```
FOR EACH SIMPLIFICATION:
1. Make the change
2. Run the test suite (Unity Test Runner or dotnet test)
3. Tests pass → continue
4. Tests fail → revert and reconsider
```

Do not combine multiple simplifications without testing in between. If something breaks, you need to know which one caused it.

### Step 4: Verify the Result

After all simplifications:

```
COMPARE BEFORE AND AFTER:
- Is the simplified version genuinely easier to understand?
- Did you introduce new patterns inconsistent with the codebase?
- Is the diff clean and reviewable?
- Would a team member approve this change as a clear improvement?
```

If the "simplified" version is harder to understand or review, revert it. Not every simplification attempt succeeds.

## Unity-Specific Guidance

```csharp
// SIMPLIFY: Unnecessary async wrapper
// Before
public async UniTask<Enemy> GetEnemyAsync(CancellationToken ct)
{
    return await _spawner.SpawnAsync(ct);
}
// After
public UniTask<Enemy> GetEnemyAsync(CancellationToken ct)
    => _spawner.SpawnAsync(ct);

// SIMPLIFY: Unnecessary else branch
// Before
public void TakeDamage(int amount)
{
    if (_health > 0)
    {
        _health -= amount;
    }
    else
    {
        return;
    }
}
// After
public void TakeDamage(int amount)
{
    if (_health <= 0) return;
    _health -= amount;
}

// SIMPLIFY: Repeated event subscribe pattern
// Before
_eventBus.Subscribe<LevelStartedEvent>(OnLevelStarted);
_eventBus.Subscribe<LevelEndedEvent>(OnLevelEnded);
_eventBus.Subscribe<PlayerDiedEvent>(OnPlayerDied);
// Each unsubscribed separately...
// After: use a project-wide SubscriptionList helper pattern if available
```

## Common Rationalizations

| Rationalization | Reality |
|-----------------|---------|
| "It works, don't touch it" | Working code that's hard to read will also be hard to fix when it breaks. |
| "Fewer lines is always simpler" | A 1-line nested ternary is not simpler than a 5-line if/else. |
| "I'll quickly simplify this unrelated code too" | Out-of-scope simplification creates noise in the diff and unintentional regression risk. |
| "The original author had a reason" | Maybe. git blame — apply Chesterton's Fence. But most accumulated complexity has no reason. |
| "I'll refactor while adding this feature" | Separate refactoring from feature work. Mixed changes are harder to review, revert, and understand in history. |

## Red Flags

- A simplification that requires modifying tests to pass (you changed behavior)
- "Simplified" code that is longer and harder to understand than the original
- Removing a Unity-specific null check or lifecycle guard
- Simplifying code you don't fully understand yet
- Bundling many simplifications into one large, hard-to-review commit

## Verification Checklist

- [ ] All existing tests pass without modification
- [ ] Unity compiles without errors
- [ ] Each simplification is an incremental, reviewable change
- [ ] Diff is clean — no unrelated changes mixed in
- [ ] Simplified code follows project rules (checked against CLAUDE.md)
- [ ] No error handling removed or weakened
- [ ] Unity null checks (`== null`) preserved (not replaced with `is null`)
- [ ] `#if UNITY_EDITOR` guards preserved
- [ ] A team member or review agent would approve this as a clear improvement
