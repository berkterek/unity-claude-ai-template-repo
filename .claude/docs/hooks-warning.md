# Warning Hooks (exit 0 — logs to stderr, does not block)

| Hook | Warns |
|------|-------|
| `check-architecture-doc.sh` | A `.cs` file written into a `Concretes/<Domain>/` that has no `ARCHITECTURE.md` — no domain is exempt, `Infrastructure/` included. Same script also has a **blocking** branch for malformed docs, see `hooks-blocking.md` |
| `check-mono-justification.sh` | **PostToolUse.** Two checks on `_GameFolders/Scripts/Games/` MonoBehaviours: (1) Card 0 — no own `[SerializeField]` and no Unity lifecycle callback → the class probably should be pure C# (`ITickable` if it needs a frame tick); (2) shell over 150 lines → extract logic to a Handler. This is the hook `solid-oop.md` promises as "warns at 150 lines". Both checks can fire on one file. Disable: `DISABLE_HOOK_CHECK_MONO_JUSTIFICATION=1` |
| `check-no-linq-hotpath.sh` | LINQ in Update/FixedUpdate/LateUpdate |
| `check-no-hotpath-expensive-calls.sh` | `GetComponent`, `Camera.main`, `FindObjectOfType`, bare `transform.`, `tag ==`, `SendMessage` inside Update/FixedUpdate/LateUpdate/Tick/FixedTick/LateTick — suppressed if `_transform` field is cached |
| `check-getcomponent-in-awake.sh` | `GetComponent`/`GetComponentInChildren` in `Awake` — prefer `[SerializeField]` Inspector assignment for all components including `Transform`; only acceptable when component is added dynamically at runtime |
| `check-no-runtime-instantiate.sh` | `new GameObject()` — **blocked** outside Pool/Factory/Spawner and Editor files; `Destroy()` — warning only (`Instantiate(prefab)` is allowed) |
| `warn-serialization.sh` | Renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `check-ecs-structural-changes.sh` | `EntityManager.AddComponent/RemoveComponent/DestroyEntity` inside ECS system (use ECB) — skipped if `ecs=false` in `project-features.json` |
| `check-async-void.sh` | `async void` outside Unity lifecycle methods (swallows exceptions) |
| `check-unitask-cancellation.sh` | `async UniTask` methods without `CancellationToken` parameter |
| `check-null-propagation.sh` | `?.` or `is null` on Unity objects (bypasses destroyed-object detection) |
| `track-read.sh` (PostToolUse Read) | Records every `Read` tool call into `gateguard-reads.txt` so `gateguard.sh`'s Stage 1 (`unity_was_read()`) check passes on the next Edit/Write. Without this hook, `gateguard-reads.txt` is never populated and every edit is blocked even after the file is read. |
| `track-codex-review.sh` (PostToolUse) | Creates `${UNITY_HOOK_STATE_DIR}/codex-reviewed` — the absolute path `guard-reviewer-order.sh` reads, never a relative `.claude/state`, since a hook's cwd is the tool call's cwd — when `codex:codex-rescue` agent completes — enables `unity-reviewer` as fallback in reviewer-order enforcement |
| `instinct-capture.sh` (PostToolUse) | Captures tool-use observations for later distillation into instincts |
| `cost-tracker.sh` (PostToolUse) | Logs every tool call with timestamp for cost auditing |
| `instinct-distill.sh` (Stop) | Distills captured observations into confidence-scored instincts |
| `session-restore.sh` (SessionStart) | Restores session state from `.claude/state/` on session start |
| `session-save.sh` (Stop) | Saves current session state to `.claude/state/` on stop. Auto-expires ephemeral gate files (`gate-cleared`, `sparc-approved`, `codex-reviewed`, `graph-empty-warned`, etc.) so they never leak into the next session. |
| `stop-verify.sh` (Stop) | Drains the edit accumulator (`session-edits.txt`) at session end and runs batch verifiers — shell syntax check for `.sh`, JSON validity for `.json`, one `dotnet build` for all accumulated `.cs` files. Must be listed **after** `session-save.sh` in the Stop array. Implements the ECC pattern: catches subagent writes whose PostToolUse hooks never fired in the main session. |
| `notify.sh` (Notification) | OS-level notification when Claude finishes — macOS via `osascript`, Linux via `notify-send`. Silent fallback on other platforms. Persists last notification to `.claude/state/last-notify.json`. |
| `pre-compact.sh` (PreCompact) | Snapshots branch, last 5 commits, edited files, and workflow phase to `.claude/state/precompact-state.md` before `/compact` discards history. Consumed by `session-restore.sh` and `/catch-up`. |
| `graph-auto-update.sh` (PostToolUse Write\|Edit) | Triggers incremental graph rebuild in background — never blocks. Respects `project-features.json.graph` flag. Warns once per session when `scanned_files == 0` (empty graph). **Serialised:** this hook fires once per written file, so a burst would otherwise launch N concurrent wholesale rewrites of one `graph.json`; a `mkdir` lock (`${UNITY_HOOK_STATE_DIR}/graph-rebuild.lock`, reclaimed after 10 min) lets one run at a time and **skips** rather than queues — the next write in the burst triggers another, so the final write always gets a rebuild. The rebuild's stderr goes to `${UNITY_HOOK_STATE_DIR}/graph-rebuild.err` (truncated per run), never `/dev/null`: `graph-builder.py` reports a failing post-pass as non-fatal on stderr, and discarding it is what let a graph missing `communities[]`/`analysis{}` look healthy. |
| UserPromptSubmit inline hook | Injects skill-check reminder into every user prompt — enforces `using-superpowers` skill invocation before any action |
| `enforce-skill-for-keywords.sh` (UserPromptSubmit) | Detects third-party package keywords in the user's prompt (cinemachine, vcam, dotween, primetween, dreamteck, feel, odin, textmeshpro…). If the relevant skill has not been invoked yet this session, injects a blocking `additionalContext` message demanding `Skill` tool invocation before any code, advice, or MCP operation. Pairs with `track-skill-invocations.sh`. |
| `track-skill-invocations.sh` (PostToolUse Skill) | Records every `Skill` tool invocation to `${UNITY_HOOK_STATE_DIR}/skills-invoked.txt` — one skill name per line. Required by `enforce-skill-for-keywords.sh` to know which skills were already loaded so the enforcement message does not fire again for the same skill. Also injects `additionalContext` after every Skill invocation to force Claude to read and follow the skill content before proceeding. |
| `agent-start-log.sh` (**PreToolUse** matcher `Agent`) | Logs agent spawn (`agent_type`, `agent_id`, `session_id`) to `subagent-log.jsonl` with `"event": "SubagentStart"` as the record label. Registered on `PreToolUse`/`Agent`, **not** the native `SubagentStart` event — that event does not fire consistently in Claude Code (see the script header). Advisory only. |
| `agent-stop-log.sh` (**PostToolUse** matcher `Agent`) | Logs agent stop with approximate duration to `subagent-log.jsonl` with `"event": "SubagentStop"` as the record label. Registered on `PostToolUse`/`Agent` for the same reason. No `exit_code` in payload — pure audit trail, no blocking. |
| `task-completed-log.sh` (TaskCompleted) | Logs successful task completion (`task_id`, `task_title`, `task_subject`) to `task-log.jsonl`. Event fires on success only — no `status` field. |

## Subagent Audit Trail

Three hooks produce two persistent JSONL audit files in `.claude/state/`:

| File | Written by | Hook event it is registered on | `event` field value in the record |
|------|-----------|-------------------------------|----------------------------------|
| `subagent-log.jsonl` | `agent-start-log.sh`, `agent-stop-log.sh` | `PreToolUse` / `PostToolUse`, matcher `Agent` | `SubagentStart`, `SubagentStop` |
| `task-log.jsonl` | `task-completed-log.sh` | `TaskCompleted` | `TaskCompleted` |

> The two columns differ on purpose for `subagent-log.jsonl`: the native `SubagentStart`/`SubagentStop` events fire unreliably in Claude Code, so the hooks watch the `Agent` tool instead while keeping the original names as record labels. Every `jq` query below filters on the **field value**, so they are unaffected.

**Fields — SubagentStart entry:**
```json
{"event":"SubagentStart","agent_type":"unity-coder","agent_id":"abc123","session_id":"xyz","started_at":"2026-06-04T10:00:00Z","logged_at":"2026-06-04T10:00:00Z"}
```

**Fields — SubagentStop entry:**
```json
{"event":"SubagentStop","agent_type":"unity-coder","agent_id":"abc123","session_id":"xyz","duration_approx_s":47,"stopped_at":"2026-06-04T10:00:47Z","logged_at":"2026-06-04T10:00:47Z"}
```
`duration_approx_s` is `-1` when no matching SubagentStart entry exists.

**Fields — TaskCompleted entry:**
```json
{"event":"TaskCompleted","task_id":"t1","task_title":"Add AudioService","task_subject":"audio","session_id":"xyz","team_name":"","logged_at":"2026-06-04T10:01:00Z"}
```

**Persistence:** Both JSONL files accumulate across sessions (project-level state dir). They are NOT auto-expired by `session-save.sh`. `session.json` captures all-time totals in `subagent_summary`:
```json
"subagent_summary": {"spawned": 12, "stopped": 11, "tasks_completed": 5}
```

**Payload limitations:**
- SubagentStart/SubagentStop carry: `agent_type`, `agent_id`, `session_id`, `transcript_path`, `cwd` — no `exit_code`, no `duration_ms`
- TaskCompleted carries: `task_id`, `task_title`, `task_subject`, `team_name`, `session_id` — no `status` field (event fires = task succeeded)

**Useful jq queries:**
```bash
# Count agents spawned today
jq -s '[.[] | select(.event=="SubagentStart")] | length' .claude/state/subagent-log.jsonl

# List all agent types that ran
jq -rs '[.[] | select(.event=="SubagentStart") | .agent_type] | unique[]' .claude/state/subagent-log.jsonl

# Find slow agents (> 120s)
jq -s '[.[] | select(.event=="SubagentStop" and .duration_approx_s > 120)]' .claude/state/subagent-log.jsonl

# List completed tasks
jq -rs '[.[] | "\(.task_title) [\(.task_subject)]"] | .[]' .claude/state/task-log.jsonl
```

## verify-after-write.sh

| Property | Value |
|----------|-------|
| Hook type | PostToolUse |
| Matcher | `Write\|Edit` |
| File filter | `.cs` files only — filtering done **in-script** (hook matchers do not support file extension filtering) |
| Exit semantics | Always exit 0 — warning mode, never blocks pipeline |
| Compile backend | `dotnet build -v q` (MCP tools are not callable from bash hook scripts) |
| `--no-restore` | Omitted — false negatives from missing restore are worse than slower builds |
| No-sln fallback | Prints skip message to stderr, exits 0 |
| Loop risk | None — hook calls no Write/Edit tools |
