# Context Prime

Brief Claude on project context at the start of a session.

## Steps

1. Read `.claude/CLAUDE.md` — architecture rules, hooks, slash commands overview
2. Read `.claude/rules/architecture.md` — VContainer, IEventBus, module structure
2.5. (opt-in) If `.claude/project-features.json` has `.graph == true` AND `.claude/graph/graph.json` exists:
   ```bash
   jq '{
     classes:    (.codebase.classes    | length),
     interfaces: (.codebase.interfaces | length),
     events:     (.codebase.events     | length),
     installers: (.codebase.vcontainer.installers | length),
     generated_at,
     errors:     (.validation.errors   | length),
     warnings:   (.validation.warnings | length)
   }' .claude/graph/graph.json
   ```
   Report the summary in the output block. If `generated_at` is older than 24 hours, suggest:
   "Graph is stale — run `/build-knowledge-graph` before starting work."
   Skip this step entirely if the feature is disabled or the file is missing.
3. If `docs/CATCH_UP.md` exists, read it — human-readable codebase guide
4. Read `production/session-state/active.md` — current task state (if any active work)
5. Report what was loaded and the current session status to the user

## Output

After loading, summarize:
- Project name and architecture style (VContainer DI, UniTask, New Input System, ECS DOTS optional)
- Active task from session state (if any)
- Any open questions from session state the user should be aware of
- Graph: N classes, M events, K installers — generated &lt;X&gt; ago (or "graph disabled / not built")

## Session State

After loading context, update `production/session-state/active.md`:
- Set **Task** to the current task being worked on (ask user if unclear)
- Set **Status** to `active`
- Set **Last Updated** to today's date
- Preserve any existing Progress checkboxes and Key Decisions

This keeps the state file current for crash recovery and session resume.
