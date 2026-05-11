# /adr — Architecture Decision Record

Record a significant architectural decision to `docs/decisions/`.

## Usage

```
/adr <decision topic>
```

Examples:
```
/adr VContainer over Zenject for dependency injection
/adr UniTask instead of coroutines
/adr struct events for IEventBus
/adr URP over Built-in render pipeline
/adr Addressables instead of Resources.Load
```

## Pipeline

1. Read `documentation-and-adrs` skill from `.claude/skills/core/`
2. Scan `docs/decisions/` for existing ADRs → determine next number
3. Ask user for context if the topic needs clarification (one question)
4. Write `docs/decisions/NNN-topic.md` using the ADR template
5. Offer to add a reference in CLAUDE.md or the relevant rules file if applicable
6. Commit (ask user first)

## ADR Template

```markdown
# ADR-NNN: [Title]

## Status
Accepted

## Date
YYYY-MM-DD

## Context
[What situation forced this decision? Requirements, constraints, alternatives pressure.]

## Decision
[What was decided.]

## Alternatives Considered

### [Alternative 1]
- Pros: ...
- Cons: ...
- Rejected because: ...

### [Alternative 2]
- Pros: ...
- Cons: ...
- Rejected because: ...

## Consequences
[What becomes easier or harder as a result. What rules or patterns follow from this decision.]
```

## Notes

- Do NOT delete old ADRs. Use "Superseded by ADR-NNN" status instead.
- ADR numbers are sequential — never reuse a number.
- Keep ADRs short. Context + decision + 2 alternatives + consequences fits on one page.
