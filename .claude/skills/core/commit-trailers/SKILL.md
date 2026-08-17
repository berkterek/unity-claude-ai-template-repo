---
name: commit-trailers
description: "Structured commit trailers — Scope-risk and Confidence on every commit, plus Constraint, Rejected, and Not-tested when they apply. Captures architectural decisions and known gaps in git history."
alwaysApply: true
---

# Structured Commit Trailers

When creating git commit messages, append structured trailers that capture decision context. This metadata makes architectural decisions searchable in git history and helps future developers understand why changes were made the way they were.

## Trailers

> **This file is the only definition of these trailers.** `.claude/agents/committer.md` used to carry a second, conflicting copy — it inverted which trailers were required and added a `Confidence` field that was never defined here. It now points at this file instead. If you change a trailer, change it here; do not restate the list elsewhere.

### Required (every commit)

**Scope-risk:** — How much of the project does this change affect? A level, an em dash, then what is actually affected:

```
Scope-risk: high — every .cs write under Games/Abstracts|Concretes/
Scope-risk: low — docs only; no runtime path reads these
```

- `low` — isolated change, single file or tightly scoped feature
- `medium` — touches multiple systems or changes shared interfaces
- `high` — modifies shared infrastructure, serialization format, or build pipeline

The level is what makes the field greppable (`git log --grep '^Scope-risk: high'`); the clause after it is what makes the hit worth reading. Earlier commits carry one half or the other because two definitions disagreed on the type — a bare level is still valid history, but write both from here on.

**Confidence:** — `high` | `medium` | `low`. How sure are you the change is correct and complete? Drop to `medium` or `low` when the change is unverified, was made under time pressure, or rests on an assumption you could not check — and say which in the body. A commit you cannot honestly mark `high` is the one a reviewer most needs to find.

### Conditional (include when applicable)

**Constraint:** — Architectural constraints that were respected during this change. Reference the rule or convention by name.

**Rejected:** — Alternatives that were considered and rejected, with brief reason. Helps future developers avoid re-exploring dead ends.

**Not-tested:** — Known gaps in test coverage or scenarios that weren't verified. Use `none` if everything is covered.

## Format Rules

- Trailers go after a blank line at the end of the commit message body
- One trailer per line
- Keep each trailer under 100 characters
- `Scope-risk` and `Confidence` are always present
- Never fabricate a trailer to fill a slot — a conditional trailer with nothing real to say is omitted, not invented
- Omit `Constraint` if no specific constraints were relevant
- Omit `Rejected` if no alternatives were considered
- Omit `Not-tested` for trivial changes; include it for anything non-trivial

## Examples

### Simple feature addition
```
Add object pooling for projectiles

Replaces Instantiate/Destroy cycle with a pre-warmed pool of 32.
Pool size is configurable via SerializeField on SpawnSystem.

Scope-risk: low — one spawn system; pool is private to it
Confidence: high
Constraint: no-alloc-in-update — pool grows only in Awake
Rejected: addressables-pool — overkill for single prefab type
Not-tested: pool exhaustion when max size exceeded during boss fight
```

### Bug fix
```
Fix enemy health not resetting on respawn

EnemyModel.Health was not reset in ObjectPool.OnGet callback.
Added explicit reset in EnemySystem.OnSpawn().

Scope-risk: low — single method; callers unchanged
Confidence: high
Not-tested: none
```

### Cross-system refactor
```
Migrate score tracking from static class to VContainer

ScoreManager was a static singleton — replaced with ScoreSystem
registered in GameLifetimeScope. All 4 consumers updated to
use constructor injection.

Scope-risk: high — every system that reads score; DI graph changes
Confidence: medium
Constraint: no-singletons — VContainer is the only DI mechanism
Rejected: SO-based-score-channel — adds complexity for simple int tracking
Not-tested: score persistence across scene transitions
```

### Serialization change
```
Rename _speed to _moveSpeed on PlayerView

Added FormerlySerializedAs to preserve prefab overrides.
All 3 prefab variants verified in inspector.

Scope-risk: medium — all prefabs and scenes carrying the renamed field
Confidence: high
Constraint: formerly-serialized-as — mandatory on all serialized field renames
```
