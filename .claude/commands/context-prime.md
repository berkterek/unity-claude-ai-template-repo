# Context Prime

Brief Claude on project context at the start of a session.

## Steps

1. Read `.claude/CLAUDE.md` — architecture rules, hooks, slash commands overview
2. Read `.claude/rules/architecture.md` — VContainer, IEventBus, module structure
3. If `docs/CATCH_UP.md` exists, read it — human-readable codebase guide
4. Read `production/session-state/active.md` — current task state (if any active work)
5. Report what was loaded and the current session status to the user

## Output

After loading, summarize:
- Project name and architecture style (VContainer DI, UniTask, New Input System, ECS DOTS optional)
- Active task from session state (if any)
- Any open questions from session state the user should be aware of

## Session State

After loading context, update `production/session-state/active.md`:
- Set **Task** to the current task being worked on (ask user if unclear)
- Set **Status** to `active`
- Set **Last Updated** to today's date
- Preserve any existing Progress checkboxes and Key Decisions

This keeps the state file current for crash recovery and session resume.
