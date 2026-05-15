## Context Management

### Context Getting Full? Use /checkpoint

When context reaches ~70-80%, use `/checkpoint` to save progress and fully reset:

```
/checkpoint  →  Claude writes summary to .claude/state/checkpoint.md
/clear       →  Context fully freed
Send: "read .claude/state/checkpoint.md"  →  Claude resumes from where you left off
```

The checkpoint file is at `.claude/state/checkpoint.md` and is deleted after it is read. This is the preferred approach over `/compact` when you need maximum token recovery.

**`/compact` vs `/checkpoint` + `/clear`:**
- `/compact` — shrinks context in-place, you continue immediately, some tokens remain
- `/checkpoint` + `/clear` — full reset, maximum token recovery, resumes via file on next message

### Session Resume

After a context reset or new session:
1. `session-restore.sh` runs automatically — shows checkpoint (if any) + prior session state
2. Read `.claude/CLAUDE.md` and `.claude/rules/architecture.md`
3. Read the source files for the module being worked on

### Session State Persistence (`.claude/state/`)

Structured state written and restored automatically by hooks across sessions:

| File | Contents |
|------|----------|
| `session.json` | Current branch, phase, modified files, active task, decisions |
| `learnings.jsonl` | Structured learning records accumulated across sessions |
| `instincts/` | Project-specific and global instinct library (confidence-scored patterns) |

- `session-restore.sh` (SessionStart hook) loads state at the start of every session
- `session-save.sh` (Stop hook) persists state when the session ends
- Use `/instincts` to view, evolve, promote, or export instincts

## Review Modes

Control pipeline depth by prefixing any pipeline command:

| Mode | Trigger | Pipeline |
|------|---------|---------|
| **solo** | `/solo /implement …` | unity-coder only — no reviewer, no committer |
| **lean** | `/lean /implement …` | unity-coder → unity-reviewer → committer |
| **full** | `/full /implement …` (default) | unity-coder → Codex → unity-reviewer → committer |

Use `solo` for exploratory spikes, `lean` for low-risk changes, `full` for production features.

## Hook Audit Log

Every hook execution is logged. Query logs to audit what was blocked or warned:

```bash
# All hook events from the current session
cat .claude/logs/hooks-$(date +%Y-%m-%d).log

# Only blocking events (exit code 2)
grep '"exit":2' .claude/logs/hooks-*.log

# Cost tracker summary
cat .claude/logs/cost-tracker.log | tail -50
```

Logs rotate daily and are stored in `.claude/logs/`.
