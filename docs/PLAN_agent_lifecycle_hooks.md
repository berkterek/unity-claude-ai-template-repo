# PLAN — Agent Lifecycle Hooks (SubagentStart / SubagentStop / TaskCompleted)

> **Version:** v1 — 2026-06-03
> **Status:** Active
> **Scope:** `.claude/hooks/` (3 new files), `.claude/settings.json` (manual), `.claude/hooks/session-save.sh`, `.claude/docs/hooks-warning.md`

## Context

The hook system currently covers PreToolUse, PostToolUse, SessionStart, Stop, UserPromptSubmit, Notification, and PreCompact event types. Multi-agent pipelines (`/implement`, `/orchestrate`, `/fix-deep`) spawn several subagents in sequence, but there is no automated record of which agents were spawned, when they started, or when they finished. This creates a blind spot: if a subagent silently stalls or produces no output, there is no session artifact capturing when it ran.

Three new Claude Code hook event types — `SubagentStart`, `SubagentStop`, and `TaskCompleted` — close this gap. `SubagentStart` fires when an agent is spawned; `SubagentStop` fires when it exits; `TaskCompleted` fires when a top-level task resolves. Together they produce two append-only JSONL audit files (`subagent-log.jsonl`, `task-log.jsonl`) that survive session end and are incorporated into `session.json` as a `subagent_summary` counter block.

**Payload reality constraints that shape this design:**

- `SubagentStart` and `SubagentStop` payloads carry `agent_type`, `agent_id`, `session_id`, `transcript_path`, `cwd`, and `hook_event_name`. They do NOT carry `exit_code`, `duration_ms`, or `last_assistant_message`.
- `SubagentStart` is advisory only — exit 2 is not honoured by Claude Code on this event.
- `SubagentStop` CAN block with exit 2, but since no `exit_code` field exists in the payload, there is no quality gate signal to act on. The hook is therefore pure audit trail.
- `TaskCompleted` fires only on successful task completion. There is no `status` field — the event itself is the success signal.
- `transcript_path` in both subagent payloads refers to the parent session's `.jsonl` conversation file, not the subagent's own transcript.

Because no `exit_code` or `status` field exists in any of these payloads, all three hooks are pure audit trail: log fields from the payload, append to JSONL, exit 0. No sentinel file is created.

Duration tracking is approximated by comparing the `started_at` timestamp of the most recent matching `agent_id` SubagentStart entry with the current wall clock time at SubagentStop.

## Goals

- [ ] Create `agent-start-log.sh` — SubagentStart hook; appends spawn record to `subagent-log.jsonl`
- [ ] Create `agent-stop-log.sh` — SubagentStop hook; appends stop record with approximate duration to `subagent-log.jsonl`
- [ ] Create `task-completed-log.sh` — TaskCompleted hook; appends task record to `task-log.jsonl`
- [ ] Register all three hooks in `settings.json` — MANUAL ONLY (check-config-protection.sh blocks agents)
- [ ] Update `session-save.sh` to embed a `subagent_summary` block into `session.json` via `jq -s`
- [ ] Update `.claude/docs/hooks-warning.md` to document all three new hooks

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Create `agent-start-log.sh` | ⏳ Pending | A |
| 1 | Create `agent-stop-log.sh` | ⏳ Pending | A |
| 1 | Create `task-completed-log.sh` | ⏳ Pending | A |
| 2 | Register hooks in `settings.json` | ⏳ Pending | B |
| 2 | Update `session-save.sh` | ⏳ Pending | B |
| 3 | Update `docs/hooks-warning.md` | ⏳ Pending | C |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/hooks/agent-start-log.sh` | Add | SubagentStart hook; JSONL append to `subagent-log.jsonl` |
| `.claude/hooks/agent-stop-log.sh` | Add | SubagentStop hook; JSONL append with approx duration to `subagent-log.jsonl` |
| `.claude/hooks/task-completed-log.sh` | Add | TaskCompleted hook; JSONL append to `task-log.jsonl` |
| `.claude/settings.json` | Modify | **Developer must apply manually in a text editor** |
| `.claude/hooks/session-save.sh` | Modify | Add `subagent_summary` block using `jq -s` |
| `.claude/docs/hooks-warning.md` | Modify | Append three rows + `## Subagent Audit Trail` section |

---

## Task 1 — Create `agent-start-log.sh`

**Files:**
- `.claude/hooks/agent-start-log.sh`

**Steps:**
1. [ ] Add shebang and header comment: trigger = SubagentStart, exit = 0 always (advisory — exit 2 not honoured), profile = standard
2. [ ] Set `HOOK_PROFILE_LEVEL="standard"`, source `_lib.sh`
3. [ ] Read stdin: `INPUT=$(cat)`
4. [ ] Extract `AGENT_TYPE` (`.agent_type // "unknown"`), `AGENT_ID` (`.agent_id // "unknown"`), `SESSION_ID` (`.session_id // "unknown"`)
5. [ ] Define `SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"`
6. [ ] Append one JSONL line via `jq -nc`: `{event, agent_type, agent_id, session_id, started_at, logged_at}`
7. [ ] `exit 0`

**Test Type:** NoTest

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# agent-start-log.sh — SubagentStart hook
# Trigger: SubagentStart | Exit: 0 always (advisory — exit 2 not honoured) | Profile: standard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type  // "unknown"')
AGENT_ID=$(echo "$INPUT"   | jq -r '.agent_id    // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id  // "unknown"')

SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"

jq -nc \
    --arg event      "SubagentStart" \
    --arg agent_type "$AGENT_TYPE" \
    --arg agent_id   "$AGENT_ID" \
    --arg session_id "$SESSION_ID" \
    --arg started_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg logged_at  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, agent_type:$agent_type, agent_id:$agent_id, session_id:$session_id, started_at:$started_at, logged_at:$logged_at}' \
    >> "$SUBAGENT_LOG"

exit 0
```

**Acceptance Criteria:**
- Running with a valid SubagentStart JSON payload appends exactly one valid JSON line to `subagent-log.jsonl`
- All six fields present; missing payload fields fall back to `"unknown"` without error
- `subagent-log.jsonl` is NOT in the auto-expire list in `session-save.sh`

---

## Task 2 — Create `agent-stop-log.sh`

**Files:**
- `.claude/hooks/agent-stop-log.sh`

**Note:** Named `agent-stop-log.sh` (not `agent-stop-verify.sh`) because no quality gate is possible — SubagentStop payload carries no `exit_code`. Duration is approximated by reading the last matching `agent_id` SubagentStart line from `subagent-log.jsonl` and comparing timestamps.

**Steps:**
1. [ ] Add shebang and header comment: trigger = SubagentStop, exit = 0 always, profile = standard
2. [ ] Set `HOOK_PROFILE_LEVEL="standard"`, source `_lib.sh`
3. [ ] Read stdin, extract `AGENT_TYPE`, `AGENT_ID`, `SESSION_ID`
4. [ ] Set `STOPPED_EPOCH=$(date +%s)` and `STOPPED_AT` timestamp
5. [ ] Compute `DURATION_APPROX_S`: read last matching `agent_id` SubagentStart line from `subagent-log.jsonl` with `jq -rs`, parse `started_at` epoch, subtract; default to -1 on any failure
6. [ ] Append JSONL: `{event, agent_type, agent_id, session_id, duration_approx_s, stopped_at, logged_at}`
7. [ ] `exit 0`

**Test Type:** NoTest

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# agent-stop-log.sh — SubagentStop hook
# Trigger: SubagentStop | Exit: 0 always (no exit_code in payload) | Profile: standard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
AGENT_ID=$(echo "$INPUT"   | jq -r '.agent_id   // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

STOPPED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
STOPPED_EPOCH=$(date +%s)
SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"

DURATION_APPROX_S=-1
if [ -f "$SUBAGENT_LOG" ]; then
    START_TS=$(jq -rs --arg id "$AGENT_ID" \
        '[.[] | select(.event=="SubagentStart" and .agent_id==$id)] | last | .started_at // empty' \
        "$SUBAGENT_LOG" 2>/dev/null || true)
    if [ -n "$START_TS" ]; then
        START_EPOCH=$(date -u -d "$START_TS" +%s 2>/dev/null \
            || date -u -jf '%Y-%m-%dT%H:%M:%SZ' "$START_TS" +%s 2>/dev/null \
            || echo 0)
        if [ "$START_EPOCH" -gt 0 ] 2>/dev/null; then
            DURATION_APPROX_S=$(( STOPPED_EPOCH - START_EPOCH ))
        fi
    fi
fi

jq -nc \
    --arg  event         "SubagentStop" \
    --arg  agent_type    "$AGENT_TYPE" \
    --arg  agent_id      "$AGENT_ID" \
    --arg  session_id    "$SESSION_ID" \
    --argjson duration   "$DURATION_APPROX_S" \
    --arg  stopped_at    "$STOPPED_AT" \
    --arg  logged_at     "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, agent_type:$agent_type, agent_id:$agent_id, session_id:$session_id, duration_approx_s:$duration, stopped_at:$stopped_at, logged_at:$logged_at}' \
    >> "$SUBAGENT_LOG"

exit 0
```

**Acceptance Criteria:**
- Appends exactly one valid JSON line with event `"SubagentStop"`
- `duration_approx_s` is -1 when no matching SubagentStart exists; a positive integer when it does
- No sentinel file created; no blocking
- Handles missing `subagent-log.jsonl` without error

---

## Task 3 — Create `task-completed-log.sh`

**Files:**
- `.claude/hooks/task-completed-log.sh`

**Note:** `TaskCompleted` fires only on success — no `status` field in payload. Event fires = task succeeded.

**Steps:**
1. [ ] Add shebang and header comment: trigger = TaskCompleted, exit = 0 always, profile = standard
2. [ ] Set `HOOK_PROFILE_LEVEL="standard"`, source `_lib.sh`
3. [ ] Read stdin, extract `TASK_ID`, `TASK_TITLE`, `TASK_SUBJECT`, `SESSION_ID`, `TEAM_NAME` (default `""`)
4. [ ] Define `TASK_LOG="${UNITY_HOOK_STATE_DIR}/task-log.jsonl"`
5. [ ] Append JSONL: `{event, task_id, task_title, task_subject, session_id, team_name, logged_at}`
6. [ ] `exit 0`

**Test Type:** NoTest

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# task-completed-log.sh — TaskCompleted hook
# Trigger: TaskCompleted (success only — no status field) | Exit: 0 always | Profile: standard
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
TASK_ID=$(echo "$INPUT"      | jq -r '.task_id      // "unknown"')
TASK_TITLE=$(echo "$INPUT"   | jq -r '.task_title   // "unknown"')
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')
SESSION_ID=$(echo "$INPUT"   | jq -r '.session_id   // "unknown"')
TEAM_NAME=$(echo "$INPUT"    | jq -r '.team_name    // ""')

TASK_LOG="${UNITY_HOOK_STATE_DIR}/task-log.jsonl"

jq -nc \
    --arg event        "TaskCompleted" \
    --arg task_id      "$TASK_ID" \
    --arg task_title   "$TASK_TITLE" \
    --arg task_subject "$TASK_SUBJECT" \
    --arg session_id   "$SESSION_ID" \
    --arg team_name    "$TEAM_NAME" \
    --arg logged_at    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{event:$event, task_id:$task_id, task_title:$task_title, task_subject:$task_subject, session_id:$session_id, team_name:$team_name, logged_at:$logged_at}' \
    >> "$TASK_LOG"

exit 0
```

**Acceptance Criteria:**
- Appends exactly one valid JSON line to `task-log.jsonl`
- `team_name` is empty string when absent (not null, not "unknown")
- No sentinel, no warning, no blocking
- `task-log.jsonl` is NOT auto-expired at Stop

---

## Task 4 — Register Hooks in `settings.json`

**Files:**
- `.claude/settings.json`

> ⚠️ **MANUAL TASK — agent cannot perform this step.**

`check-config-protection.sh` blocks `Edit|Write` on `settings.json`. Bash redirects would technically bypass the hook but should be avoided for auditability — settings.json is the authoritative hook registry and changes must be visible and deliberate.

**Developer must open `.claude/settings.json` in a text editor and make the following change:**

Locate the closing `]` of the `"PreCompact"` array (last entry before the `"hooks"` closing brace). Add a comma after it, then insert:

```json
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/agent-start-log.sh",
            "timeout": 2000,
            "statusMessage": "Logging agent spawn..."
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/agent-stop-log.sh",
            "timeout": 3000,
            "statusMessage": "Logging agent stop..."
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/task-completed-log.sh",
            "timeout": 2000,
            "statusMessage": "Logging task completion..."
          }
        ]
      }
    ]
```

**Steps:**
1. [ ] Open `.claude/settings.json` in a text editor
2. [ ] Add comma after closing `]` of `"PreCompact"` array
3. [ ] Paste the three JSON blocks above
4. [ ] Save and validate: `jq . .claude/settings.json > /dev/null`

**Test Type:** NoTest

**Acceptance Criteria:**
- `jq . .claude/settings.json` exits 0
- Three new keys exist under `"hooks"`: `SubagentStart`, `SubagentStop`, `TaskCompleted`
- No existing entries disturbed

---

## Task 5 — Update `session-save.sh`

**Files:**
- `.claude/hooks/session-save.sh`

**Steps:**
1. [ ] After the `AGENT_CONTEXT` variable block, add:

```bash
SUBAGENT_LOG="${UNITY_HOOK_STATE_DIR}/subagent-log.jsonl"
TASK_LOG="${UNITY_HOOK_STATE_DIR}/task-log.jsonl"

SUBAGENT_SPAWNED=$(jq -s '[.[] | select(.event=="SubagentStart")] | length' "$SUBAGENT_LOG" 2>/dev/null || echo 0)
SUBAGENT_STOPPED=$(jq -s '[.[] | select(.event=="SubagentStop")]  | length' "$SUBAGENT_LOG" 2>/dev/null || echo 0)
TASKS_COMPLETED=$(jq -s  '[.[] | select(.event=="TaskCompleted")] | length' "$TASK_LOG"     2>/dev/null || echo 0)
```

2. [ ] Add `--arg` params to the existing `jq -n` invocation:
```bash
    --arg subagent_spawned "$SUBAGENT_SPAWNED" \
    --arg subagent_stopped "$SUBAGENT_STOPPED" \
    --arg tasks_completed  "$TASKS_COMPLETED" \
```

3. [ ] Add `subagent_summary` to the JSON output object:
```json
subagent_summary: {
    spawned:         ($subagent_spawned  | tonumber),
    stopped:         ($subagent_stopped  | tonumber),
    tasks_completed: ($tasks_completed   | tonumber)
}
```

4. [ ] Confirm `subagent-log.jsonl` and `task-log.jsonl` are NOT in the auto-expire loop

**Note — All-time counts:** `UNITY_HOOK_STATE_DIR` resolves to `.claude/state/` (project-level, not session-scoped). The JSONL files accumulate across sessions by design — they are a persistent audit trail. `subagent_summary` in `session.json` therefore reflects all-time totals, not just the current session. This is intentional: the `session.json` snapshot captures project-lifetime activity at the moment of Stop. Per-session filtering (by `session_id`) can be added later if needed.

**Test Type:** NoTest

**Acceptance Criteria:**
- `session.json` contains `subagent_summary` with `spawned`, `stopped`, `tasks_completed` as integers
- Counts are all-time totals from `subagent-log.jsonl` / `task-log.jsonl` (project-level state dir — by design)
- With no JSONL files present, all counts default to 0 without error
- Both JSONL files survive Stop unchanged

---

## Task 6 — Update `docs/hooks-warning.md`

**Files:**
- `.claude/docs/hooks-warning.md`

**Steps:**
1. [ ] Append three rows to the hook table:

| Hook | Warns |
|------|-------|
| `agent-start-log.sh` (SubagentStart) | Logs agent spawn (`agent_type`, `agent_id`, `session_id`) to `subagent-log.jsonl`. Advisory only — exit 2 not honoured on this event. |
| `agent-stop-log.sh` (SubagentStop) | Logs agent stop with approximate duration to `subagent-log.jsonl`. No `exit_code` in payload — pure audit trail. |
| `task-completed-log.sh` (TaskCompleted) | Logs successful task completion (`task_id`, `task_title`, `task_subject`) to `task-log.jsonl`. Event fires on success only — no `status` field. |

2. [ ] Add `## Subagent Audit Trail` section documenting:
   - `subagent-log.jsonl` and `task-log.jsonl` fields and persistence
   - `subagent_summary` in `session.json`
   - Payload limitations (no `exit_code`, no `status`)
   - Example `jq` queries

**Test Type:** NoTest

**Acceptance Criteria:**
- Three new rows in hook table with correct event names
- `## Subagent Audit Trail` section present with jq query examples
- Valid Markdown

---

## Implementation Notes

**No sentinel file:** The original design proposed a `subagent-warn` sentinel on non-zero exit code. Removed — SubagentStop payload carries no `exit_code`.

**`jq -s` over `grep -c`:** Avoids false positives from string matches in non-`event` fields.

**macOS/Linux `date` compatibility:** `agent-stop-log.sh` tries GNU `date -d` first, then BSD `date -jf`. Defaults to -1 on parse failure.

**`transcript_path` not logged:** Points to parent session transcript, not the subagent's — not useful for per-agent audit trail and would bloat JSONL lines.

**settings.json manual only:** Both `Edit`/`Write` (hook-blocked) and Bash redirect (bypasses hook, not auditable) should be avoided. Text editor only.
