# PLAN — Unity Claude AI Template Improvements

> **Version:** v2 — 2026-06-03 — Applied grill-me decisions: T6 cancelled, T7 clarified, T11 unblocked
> **Previous Version:** v1 — 2026-06-03
> **Status:** Active
> **Scope:** `.claude/CLAUDE.md`, `.claude/hooks/`, `.claude/rules/`, `.claude/skills/`, `.claude-plugin/`, `.github/workflows/`, repo root (`install.sh`, `.claudeignore`)

## Context

The Unity Claude AI Template is mature (41 hooks, 72 skills, 15 rule files, 59 commands, 38 agents) but a competitor analysis plus internal audit surfaced 12 concrete gaps that increase token usage, leak state across sessions, slow new-project bootstrap, and limit distribution reach. None of these gaps require C# code changes — every fix lives in bash hooks, markdown rules, JSON manifests, or shell scripts.

The current `.claude/CLAUDE.md` is 202 lines and pulls in 14 `@`-referenced docs at session start, costing roughly 8K tokens before the agent has done anything. Rules are written in prose, which competitor projects (Superpowers, claude-md-management) have shown is measurably less effective at preventing AI mistakes than a structured **WHEN / WRONG / RIGHT / GOTCHA** card format. The repo also has no `.claudeignore`, no `install.sh`, no `plugin.json` manifest, no GitHub Actions workflow, and the `gate-cleared` state file persists across sessions (it is in `.gitignore` but not auto-deleted).

This plan groups 12 improvements into 6 phases ordered by foundational impact. Phase 1 captures five quick wins that need no other work, Phase 2 shrinks CLAUDE.md and upgrades the 5 most-read rules to the WHEN/WRONG/RIGHT/GOTCHA card format, Phase 3 ships an `install.sh` bootstrapper, Phase 4 wires hook profiles through every hook (lib already supports it), Phase 5 adds distribution (`plugin.json`) and CI (GitHub Actions), and Phase 6 adds self-tests for hooks.

## Goals

- [ ] G1 — Add `.claudeignore` at repo root excluding Unity build artifacts.
- [ ] G2 — Auto-expire `.claude/state/gate-cleared` in `session-save.sh`.
- [ ] G3 — Warn from `graph-auto-update.sh` when graph is empty (`scanned_files == 0`).
- [ ] G4 — Add `block-projectsettings.sh` PreToolUse hook for `ProjectSettings/`.
- [ ] G5 — Add `notify.sh` (Notification hook) and `pre-compact.sh` (PreCompact hook).
- [ ] G6 — ~~Reduce `.claude/CLAUDE.md` to ~150 lines by moving inline tables to `@`-referenced docs.~~ **CANCELLED** — @-includes do not reduce token cost.
- [ ] G7 — Convert the 5 most-read rules to WHEN/WRONG/RIGHT/GOTCHA card format.
- [ ] G8 — Add `install.sh` one-command bootstrap script.
- [ ] G9 — Roll out hook profiles (minimal | standard | strict) across every hook.
- [ ] G10 — Add `.claude-plugin/plugin.json` for marketplace distribution.
- [ ] G11 — Add `.github/workflows/claude-pr-review.yml` for GitHub Actions PR review.
- [ ] G12 — Add `bats` self-tests for the top 10 critical hooks.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | T1 — `.claudeignore` at repo root | Pending | P1 |
| 1 | T2 — gate-cleared auto-expiry in `session-save.sh` | Pending | P1 |
| 1 | T3 — graph empty warning in `graph-auto-update.sh` | Pending | P1 |
| 1 | T4 — `block-projectsettings.sh` PreToolUse hook **[MANUAL: settings.json]** | Pending | P1 |
| 1 | T5 — `notify.sh` + `pre-compact.sh` **[MANUAL: settings.json]** | Pending | P1 |
| 2 | T6 — `.claude/CLAUDE.md` token reduction to ~150 lines | **CANCELLED** | — |
| 2 | T7 — WHEN/WRONG/RIGHT/GOTCHA cards for top-5 rules | Pending | P2 |
| 3 | T8 — `install.sh` bootstrap script | Pending | — |
| 4 | T9 — Hook profile rollout across all 41 hooks | Pending | — |
| 5 | T10 — `.claude-plugin/plugin.json` manifest | Pending | P5 |
| 5 | T11 — GitHub Actions `claude-pr-review.yml` | Pending | P5 |
| 6 | T12 — bats self-tests for top-10 hooks | Pending | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claudeignore` | Create | T1 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/session-save.sh` | Edit | T2 — add `rm -f gate-cleared` |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/graph-auto-update.sh` | Edit | T3 — warn when `scanned_files == 0` |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/block-projectsettings.sh` | Create | T4 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/notify.sh` | Create | T5 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/pre-compact.sh` | Create | T5 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/CLAUDE.md` | ~~Edit~~ | ~~T6 — strip inline tables~~ — CANCELLED |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/project-features.md` | ~~Create~~ | ~~T6 — receives moved table~~ — CANCELLED |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/required-stack.md` | ~~Create~~ | ~~T6 — receives moved table~~ — CANCELLED |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/architecture.md` | Edit | T7 — card format |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/csharp-unity.md` | Edit | T7 — card format |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/unity-prefabs.md` | Edit | T7 — card format |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/event-patterns.md` | Edit | T7 — card format |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/unity-async.md` | Edit | T7 — card format |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/install.sh` | Create | T8 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/*.sh` | Edit (bulk) | T9 — add `HOOK_PROFILE_LEVEL` |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude-plugin/plugin.json` | Create | T10 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.github/workflows/claude-pr-review.yml` | Create | T11 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/*.bats` | Create | T12 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/run-tests.sh` | Create | T12 |
| `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/Docs/PLAN_template_improvements.md` | Create | This plan |

---

## Phase 1 — Low-Hanging Fruit

## Task T1 — Add `.claudeignore` at Repo Root

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claudeignore`

**parallel_group:** P1

**Steps:**
1. [ ] Create `.claudeignore` at the repo root (sibling of `.gitignore`).
2. [ ] Populate with Unity build artifacts, IDE temp files, large generated assets, and Claude state that should never leak into context.
3. [ ] Confirm `.gitignore` does **not** ignore `.claudeignore` (it must be committed so every clone gets it).
4. [ ] Run a quick `claude /context` (manual check by user) and confirm Library/, Temp/, Logs/ no longer appear in any tool scans.

**Test Type:** NoTest

**Code Skeleton:**
```gitignore
# .claudeignore — files Claude Code should never read or include in context.
# Mirrors .gitignore for Unity-generated trees that waste tokens.

# Unity generated
Library/
Temp/
Logs/
obj/
Build/
Builds/
MemoryCaptures/
UserSettings/

# IDE
.vs/
.idea/
*.csproj
*.sln
*.suo
*.user
*.userosscache
*.unityproj

# OS
.DS_Store
Thumbs.db

# Claude state (large, ephemeral)
.claude/state/session-cost.jsonl
.claude/state/instincts/observations.jsonl
.claude/state/gateguard-reads.txt
.claude/state/gateguard-facts-passed.txt
.claude/state/gateguard-facts-denied.txt
.claude/state/skills-invoked.txt
.claude/state/session-edits.txt
.claude/state/session-warnings.txt
.claude/state/stop-verify-batch.txt
.claude/state/graph-updates.log

# Knowledge graph raw outputs (use slash commands to query instead)
.claude/graph/*.tmp
.claude/graph/build/

# Large assets
*.fbx
*.psd
*.tif
*.tga
*.wav
*.mp3
*.ogg
*.mov
*.mp4
*.exr
*.hdr
```

**Acceptance Criteria:**
- File exists at exactly `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claudeignore`.
- Tracked by git (`git status` shows it as a new file).
- File starts with `# .claudeignore` comment header.
- Contains at minimum: `Library/`, `Temp/`, `Logs/`, `obj/`, `Build/`, `.DS_Store`, `*.fbx`.

---

## Task T2 — Auto-Expire `gate-cleared` in `session-save.sh`

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/session-save.sh`

**parallel_group:** P1

**Steps:**
1. [ ] Open `session-save.sh` and locate the final `exit 0` (line 111).
2. [ ] Immediately before the final `exit 0`, insert a cleanup block that removes ephemeral pipeline gate files.
3. [ ] The cleanup must use `rm -f` (silent on missing) so the hook never fails when the file is absent.
4. [ ] Log a one-line stderr message when the file existed and was removed.

**Test Type:** NoTest (bash hook — covered by T12 bats self-tests).

**Code Skeleton:**
```bash
# (inside session-save.sh — insert before final `exit 0`)

# --- Auto-expire ephemeral pipeline gate state ---
# These files are written by pipeline commands during a single session and
# MUST NOT persist across sessions. Stop hook is the canonical cleanup point.
for _gate in gate-cleared graph-empty-warned sparc-approved codex-reviewed plan-state.json verify-state.json agent-context.json; do
    _path="${UNITY_HOOK_STATE_DIR}/${_gate}"
    if [ -e "$_path" ]; then
        rm -f "$_path"
        echo "  Expired: ${_gate}" >&2
    fi
done
```

**Acceptance Criteria:**
- `session-save.sh` contains the literal string `Auto-expire ephemeral pipeline gate state`.
- After a manual run of `bash .claude/hooks/session-save.sh < /dev/null` with `.claude/state/gate-cleared` pre-created, the file is gone.
- `session-save.sh` still exits 0 in all cases.
- No other files in `.claude/state/` are touched (only the 7 listed).

---

## Task T3 — Graph Empty Warning in `graph-auto-update.sh`

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/graph-auto-update.sh`

**parallel_group:** P1

**Steps:**
1. [ ] Open `graph-auto-update.sh`.
2. [ ] Between the feature-flag check (line 44) and the builder existence check (line 47), insert a graph-freshness probe.
3. [ ] If `.claude/graph/graph.json` exists and `.codebase.scanned_files == 0`, write a one-time warning per session to `$UNITY_WARNINGS_FILE` and stderr.
4. [ ] Use a sentinel file `.claude/state/graph-empty-warned` so the warning fires once per session (cleared by T2 on Stop).

**Test Type:** NoTest

**Code Skeleton:**
```bash
# (inside graph-auto-update.sh — insert after the GRAPH_ENABLED check)

# --- Graph empty-state warning (once per session) ---
GRAPH_JSON=".claude/graph/graph.json"
WARN_SENTINEL=".claude/state/graph-empty-warned"
if [[ -f "$GRAPH_JSON" && ! -f "$WARN_SENTINEL" ]]; then
    SCANNED=$(python3 -c "
import json
try:
    d = json.load(open('$GRAPH_JSON'))
    print(d.get('codebase', {}).get('scanned_files', 0))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

    if [[ "$SCANNED" = "0" ]]; then
        mkdir -p .claude/state
        touch "$WARN_SENTINEL"
        echo "WARNING (graph-auto-update): graph.json reports scanned_files=0 — graph is empty." >&2
        echo "  Run: /build-knowledge-graph to populate it, or disable the 'graph' feature in .claude/project-features.json." >&2
        echo "graph-auto-update: empty graph (scanned_files=0)" >> .claude/state/session-warnings.txt
    fi
fi
```

Also add `graph-empty-warned` to the T2 cleanup loop so the warning recurs in the next session if still unresolved.

**Acceptance Criteria:**
- `graph-auto-update.sh` contains the literal string `Graph empty-state warning`.
- With `scanned_files: 0` in `graph.json` and no sentinel, running the hook writes `WARNING (graph-auto-update)` to stderr.
- With the sentinel present, the warning does NOT repeat.
- T2's expiry loop also clears `graph-empty-warned` (update the `_gate` list in T2 to include it).
- Hook still exits 0.

---

## Task T4 — `block-projectsettings.sh` PreToolUse Hook **[MANUAL: settings.json]**

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/block-projectsettings.sh`

**parallel_group:** P1

**Steps:**
1. [ ] Create `block-projectsettings.sh`. Must be executable (`chmod +x`).
2. [ ] Parse the tool input JSON from stdin, extract `tool_input.file_path`.
3. [ ] Block any Write/Edit targeting `ProjectSettings/*.asset`, `Packages/manifest.json`, `Packages/packages-lock.json`.
4. [ ] Use `unity_hook_block` from `_lib.sh` so `UNITY_HOOK_MODE=warn` correctly downgrades to warning.
5. [ ] **[MANUAL: settings.json]** Append a `PreToolUse` entry with `matcher: "Edit|Write"` pointing at the new hook. Claude cannot edit `settings.json` directly — surface this as a user-action step at the end of the task.

**Test Type:** NoTest

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# ============================================================================
# block-projectsettings.sh — PRE-TOOL-USE HOOK
# Blocks edits to Unity project configuration files that must be changed
# through the Unity Editor (Project Settings, Package Manager) rather than
# raw text edits. Wrong-format edits here can corrupt the project.
# ============================================================================
# Trigger: PreToolUse (Edit|Write)
# Exit: 0 if not a protected file, 2 if blocked
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # critical safety — runs in all profiles
source "${SCRIPT_DIR}/_lib.sh"

TOOL_INPUT=$(cat)
FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', d).get('file_path', ''))
except Exception:
    print('')
")

[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
    */ProjectSettings/*.asset|ProjectSettings/*.asset)
        unity_hook_block "Direct edits to ProjectSettings/*.asset are forbidden. Use the Unity Editor (Edit > Project Settings) or MCP 'manage_editor' / 'manage_build' tools. File: $FILE_PATH" ;;
    */Packages/manifest.json|Packages/manifest.json)
        unity_hook_block "Direct edits to Packages/manifest.json are forbidden. Use the Unity Package Manager UI or MCP 'manage_shell' (openupm add ...) instead. File: $FILE_PATH" ;;
    */Packages/packages-lock.json|Packages/packages-lock.json)
        unity_hook_block "Packages/packages-lock.json is generated — never edit by hand. Let Unity regenerate it. File: $FILE_PATH" ;;
esac

exit 0
```

**[MANUAL: settings.json] — user must add this entry to `.claude/settings.json` under `hooks.PreToolUse`:**
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": ".claude/hooks/block-projectsettings.sh",
      "timeout": 3000,
      "statusMessage": "Checking ProjectSettings protection..."
    }
  ]
}
```

**Acceptance Criteria:**
- File exists, executable bit set.
- `bash .claude/hooks/block-projectsettings.sh <<<'{"tool_input":{"file_path":"ProjectSettings/EditorSettings.asset"}}'` exits with code 2 and prints `BLOCKED`.
- Same call with `Assets/Game/Foo.cs` exits 0 silently.
- `UNITY_HOOK_MODE=warn bash .claude/hooks/block-projectsettings.sh <<<'{"tool_input":{"file_path":"ProjectSettings/EditorSettings.asset"}}'` exits 0 with `WARNING (downgraded from BLOCKED)` on stderr.
- Plan output explicitly tells the user "**[MANUAL: settings.json]** add this entry…" — implementer must surface it before marking task complete.

---

## Task T5 — `notify.sh` + `pre-compact.sh` **[MANUAL: settings.json]**

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/notify.sh`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/pre-compact.sh`

**parallel_group:** P1

**Steps:**
1. [ ] Verify `_lib.sh` exports `CLAUDE_PROJECT_DIR` or use `$PWD` as fallback. The `notify.sh` skeleton defines `LAST_NOTIFY` locally rather than referencing an undefined env var.
2. [ ] Create `notify.sh`. On macOS use `osascript -e 'display notification'`. On Linux use `notify-send` if present. Silent fallback on other platforms.
3. [ ] Create `pre-compact.sh`. Save current branch, last 5 commits, modified file list, and the last UserPromptSubmit text into `.claude/state/precompact-state.md` (session-save already reads this path).
4. [ ] Both hooks exit 0 always — they are advisory.
5. [ ] **[MANUAL: settings.json]** Add `Notification` and `PreCompact` event entries.

**Test Type:** NoTest

**Code Skeleton — `notify.sh`:**
```bash
#!/usr/bin/env bash
# ============================================================================
# notify.sh — NOTIFICATION HOOK
# Surfaces OS-level notifications when Claude finishes a task or needs input.
# Reads the notification payload from stdin.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

# Define last-notify state file locally — do not assume a global env var exists.
LAST_NOTIFY="${CLAUDE_PROJECT_DIR:-.}/.claude/state/last-notify.json"

INPUT=$(cat)
MESSAGE=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(d.get('message', 'Claude Code: task complete'))
except Exception:
    print('Claude Code')
" "$INPUT" 2>/dev/null || echo "Claude Code")

case "$(uname -s)" in
    Darwin)
        osascript -e "display notification \"${MESSAGE//\"/}\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null || true ;;
    Linux)
        command -v notify-send >/dev/null 2>&1 && notify-send "Claude Code" "$MESSAGE" || true ;;
esac

# Persist last-notify for /catch-up
mkdir -p "$(dirname "$LAST_NOTIFY")"
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"message\":$(printf '%s' "$MESSAGE" | jq -Rs .)}" > "$LAST_NOTIFY"
exit 0
```

**Code Skeleton — `pre-compact.sh`:**
```bash
#!/usr/bin/env bash
# ============================================================================
# pre-compact.sh — PRE-COMPACT HOOK
# Snapshots session state before /compact discards conversation history.
# session-save.sh and session-restore.sh both consume precompact-state.md.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

OUT="${UNITY_HOOK_STATE_DIR}/precompact-state.md"
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
COMMITS=$(git log --oneline -5 2>/dev/null || echo "(no commits)")
MODIFIED="(none)"
if [ -f "$UNITY_EDITS_FILE" ]; then
    MODIFIED=$(sort -u "$UNITY_EDITS_FILE" | head -20)
fi

cat > "$OUT" <<EOF
# Pre-Compact Snapshot

> Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
> Branch: $BRANCH

## Recent commits
\`\`\`
$COMMITS
\`\`\`

## Files edited this session
\`\`\`
$MODIFIED
\`\`\`

## Workflow phase
$(unity_state_read workflow_phase 2>/dev/null || echo "unknown")

## Resume hint
Run /catch-up or read this file at the start of the next turn to restore context.
EOF

echo "Pre-compact snapshot written to $OUT" >&2
exit 0
```

**[MANUAL: settings.json] — add to `.claude/settings.json`:**
```json
"Notification": [
  { "hooks": [ { "type": "command", "command": ".claude/hooks/notify.sh", "timeout": 3000 } ] }
],
"PreCompact": [
  { "hooks": [ { "type": "command", "command": ".claude/hooks/pre-compact.sh", "timeout": 5000 } ] }
]
```

**Acceptance Criteria:**
- Both files exist and are executable.
- On macOS, `echo '{"message":"test"}' | bash .claude/hooks/notify.sh` produces a Notification Center popup.
- `bash .claude/hooks/pre-compact.sh < /dev/null` creates `.claude/state/precompact-state.md` with `# Pre-Compact Snapshot` header.
- Plan output surfaces the manual `settings.json` step.

---

## Phase 2 — CLAUDE.md & Skill Format

## ~~CANCELLED~~ Task T6 — CLAUDE.md Token Reduction to ~150 Lines

> **Cancelled:** @-includes do not reduce token cost — content is still loaded into context at session start. Splitting CLAUDE.md into multiple files referenced via `@.claude/docs/foo.md` makes the file shorter on disk but the resolver expands every `@`-include before the agent's first turn, so the effective token bill is identical (and sometimes slightly larger due to additional file headers and markdown framing). Real token reduction requires either (a) deleting content outright, (b) moving content to skills/rules that load on-demand only when triggered, or (c) tightening the prose. This task pursued the wrong lever and is therefore cancelled. Section retained below for historical reference.

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/CLAUDE.md` (Edit — shrink from 202 to ~150 lines)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/required-stack.md` (Create — receives `## Required Stack` table)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/optional-features.md` (Create — receives `## Optional Features` + `## Optional Plugins` tables)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/rules-index.md` (Create — receives the 17-row `## Rules (auto-loaded)` table)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/project-features.md` (Create — receives `## Project Features` table)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/director-gates-summary.md` (Create — receives the `## Director Gates` table; the prose `@.claude/docs/director-gates.md` already exists)

**Steps:**
1. [ ] Move `## Required Stack` table (lines 19–25) into `required-stack.md`. Replace in CLAUDE.md with one line: `@.claude/docs/required-stack.md`.
2. [ ] Move `## Optional Features` table (lines 27–37) into `optional-features.md`, plus `## Optional Plugins` (lines 39–50). Replace with one combined `@`-include pointing to `optional-features.md` — single file covers both Optional Features and Optional Plugins tables.
3. [ ] Move `## Rules (auto-loaded)` table (lines 85–105) into `rules-index.md`. Replace with `@.claude/docs/rules-index.md`.
4. [ ] Move `## Project Features` status table (lines 165–176) into `project-features.md`. Replace with `@.claude/docs/project-features.md`.
5. [ ] Move the `## Director Gates` 8-row table (lines 137–146) into `director-gates-summary.md`. Replace with `@.claude/docs/director-gates-summary.md`.
6. [ ] Keep at top level only: `## Important Constraints`, `## Knowledge Graph`, `## Quick Start`, `## Session Start`, `## NON-NEGOTIABLE: /orchestrate Rules`, `## NON-NEGOTIABLE: Director Gate Rules`.
7. [ ] Verify final line count: `wc -l .claude/CLAUDE.md` must report ≤ 160.
8. [ ] Verify no `@`-reference points to a missing file: `grep -E '^@' .claude/CLAUDE.md | sed 's/^@//' | xargs -I{} test -f {} && echo OK`.

**Test Type:** NoTest

**Code Skeleton — final CLAUDE.md shape (lines, not full content):**
```markdown
# Unity AI Template — Claude Code Configuration

<intro paragraph — 2 lines>

## Important Constraints
<existing 7 bullets — kept inline because they are runtime invariants>

## Knowledge Graph
@.claude/docs/knowledge-graph.md

## Required Stack
@.claude/docs/required-stack.md

## Optional Features & Plugins
@.claude/docs/optional-features.md

## Quick Start
@.claude/docs/quick-start.md

## Model Tiers
@.claude/docs/model-tiers.md

## Session Start
<existing prose — kept inline, ~15 lines>

## Rules (auto-loaded)
@.claude/docs/rules-index.md

## Hooks
@.claude/docs/hooks-blocking.md
@.claude/docs/hooks-warning.md

## Commands
@.claude/docs/commands.md

## Agents
@.claude/docs/agents-index.md

## Architecture Summary
@.claude/docs/architecture-summary.md

## Context Management
@.claude/docs/context-management.md

## Director Gates
@.claude/docs/director-gates-summary.md
@.claude/docs/director-gates.md

## Project Features
@.claude/docs/project-features.md

## NON-NEGOTIABLE: /orchestrate Rules
@.claude/docs/orchestrate-rules.md

## NON-NEGOTIABLE: Director Gate Rules
<existing 5 inline bullets — kept inline as last-line enforcement>

## Setup
@.claude/docs/setup-checklist.md

## Skills Library
@.claude/docs/skills-index.md
@.claude/docs/auto-loaded-skills.md
```

**Acceptance Criteria:**
- `wc -l .claude/CLAUDE.md` reports a value **between 130 and 160 inclusive**.
- All 5 newly created docs exist and contain the table content removed from CLAUDE.md (no content lost — only relocated).
- `grep -c '^@' .claude/CLAUDE.md` reports **≥ 17** (every relocated section is `@`-referenced).
- `grep -q '@.claude/docs/required-stack.md' .claude/CLAUDE.md && grep -q '@.claude/docs/optional-features.md' .claude/CLAUDE.md && echo OK` — must print `OK`.
- The literal strings `Director Gate Rules`, `Required Stack`, `Optional Features`, and `Project Features` still appear in `.claude/CLAUDE.md` as section headers (just shorter sections).
- Tokens-per-session reduction estimate: target ~30% reduction in initial CLAUDE.md payload (subjective verification via `claude /context`).

---

## Task T7 — WHEN/WRONG/RIGHT/GOTCHA Cards for Top-5 Rules

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/architecture.md`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/csharp-unity.md`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/unity-prefabs.md`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/event-patterns.md`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/unity-async.md`

**parallel_group:** P2

**Steps (per rule file):**
1. [ ] At the top of the file, insert a `## Cards` section containing 3–8 atomic rules in the WHEN/WRONG/RIGHT/GOTCHA format.
2. [ ] Each card must fit on roughly 10 lines and reference one and only one decision.
3. [ ] Preserve all existing prose content **below** the cards section — cards are an additive index, not a replacement.
4. [ ] Cards sit above existing prose. Do NOT delete or modify any existing prose content below the `## Cards` section.
5. [ ] Add a one-line summary at the very top: `> Read the **Cards** section first. The prose below is reference detail.`

**Test Type:** NoTest

**Code Skeleton (template card — to be repeated):**
```markdown
## Cards

### Card 1: No Singletons

**WHEN:** Writing or refactoring any service that needs to be accessed from multiple call sites.

**WRONG:**
```csharp
public class AudioService : MonoBehaviour
{
    public static AudioService Instance { get; private set; }
    private void Awake() => Instance = this;
}
```

**RIGHT:**
```csharp
public interface IAudioService { UniTask PlayAsync(AudioId id, CancellationToken ct); }

public sealed class AudioService : IAudioService, IStartable { /* ... */ }

// AudioInstaller.cs
public override void Install(IContainerBuilder b) =>
    b.Register<IAudioService, AudioService>(Lifetime.Singleton).AsSelf();
```

**GOTCHA:** `MonoBehaviour.FindObjectOfType<AudioService>()` is also a singleton in disguise — equally forbidden. Resolve through constructor injection only.

---
```

**Per-file card budgets (atomic rules to extract):**

`architecture.md` → 6 cards:
1. No singletons (VContainer only).
2. Provider pattern for scene-instanced views.
3. Module → Service → Installer → Scope chain.
4. EventBus crosses modules; Action stays inside the method; C# event stays inside the class.
5. One-caller overfitting rule.
6. GameScope vs ModuleInstaller wiring boundary.

`csharp-unity.md` → 5 cards:
1. Naming conventions (`Game.Concretes.<Domain>`).
2. Null check on Unity objects (no `?.` on UnityEngine.Object).
3. UniTask, never `Task` returning to Unity.
4. `#region` discipline.
5. Namespace collision with UnityEngine types.

`unity-prefabs.md` → 4 cards:
1. `new GameObject()` forbidden — use Instantiate with a prefab reference.
2. `Destroy()` on a prefab asset is forbidden.
3. BaseCanvas pattern for UI prefabs.
4. Prefab Variants — Base vs Variant decision table.

`event-patterns.md` → 4 cards:
1. UnityEvent forbidden (hook-enforced).
2. IEventBus for cross-module.
3. System.Action for one-time callback.
4. C# event for internal-module notification.

`unity-async.md` → 4 cards:
1. No coroutines — UniTask only.
2. Always pass CancellationToken.
3. Naked `.Forget()` swallows exceptions.
4. `async void` is forbidden — use `UniTaskVoid` or `.Forget()` with exception handler.

**Acceptance Criteria:**
- All 5 files start with `> Read the **Cards** section first.` summary line.
- Each file contains a `## Cards` section with the exact card count above (6/5/4/4/4 = 23 cards total).
- Every card contains all four labels: `**WHEN:**`, `**WRONG:**`, `**RIGHT:**`, `**GOTCHA:**`.
- Prose content below cards is unchanged (verified via `git diff` showing only additions, not deletions, in the prose sections).
- `grep -c '^### Card ' .claude/rules/architecture.md` returns 6; analogous counts for the other 4 files.

---

## Phase 3 — Install Bootstrap

## Task T8 — `install.sh` One-Command Bootstrap

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/install.sh`

**Steps:**
1. [ ] Create `install.sh` at repo root, executable.
2. [ ] Script accepts one positional argument: target Unity project directory (defaults to `$PWD`). Use a single argument-parsing loop to accept `--force` in any position and reject unknown `-*` flags.
3. [ ] Copy `.claude/`, `.claudeignore`, and `.claude-plugin/` (created in T10) into the target.
4. [ ] `chmod +x` every `.sh` under `.claude/hooks/`.
5. [ ] If the target has no `.git`, abort with an error (`/setup-project` later requires a repo).
6. [ ] Print clearly labelled NEXT STEPS so the user knows the manual actions: open Claude Code, run `/setup-project`, register hooks in `settings.json`.
7. [ ] Refuse to overwrite an existing `.claude/` without `--force`.

**Test Type:** NoTest (manual end-to-end run by the user)

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# ============================================================================
# install.sh — Bootstrap a Unity project with this Claude Code template.
#
# Usage:
#   ./install.sh /path/to/UnityProject           # install into target
#   ./install.sh                                  # install into $PWD
#   ./install.sh /path/to/UnityProject --force    # overwrite existing .claude/
#   ./install.sh --force /path/to/UnityProject    # --force in any position
#
# Argument parsing is centralized in the loop below — a single pass accepts the
# positional target dir AND the --force flag in any order, and rejects unknown
# flags with a non-zero exit so typos don't silently install to $PWD.
# ============================================================================
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -*) echo "Unknown flag: $arg"; exit 1 ;;
    *) TARGET="$arg" ;;
  esac
done
TARGET="${TARGET:-$PWD}"

echo "Unity AI Template installer"
echo "  source : $SOURCE_DIR"
echo "  target : $TARGET"
echo

# --- Preflight ---
if [ ! -d "$TARGET" ]; then
    echo "ERROR: target directory does not exist: $TARGET" >&2
    exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
    echo "ERROR: $TARGET is not a git repo. Run 'git init' there first." >&2
    exit 1
fi

if [ -d "$TARGET/.claude" ] && [ "$FORCE" != "true" ]; then
    echo "ERROR: $TARGET/.claude already exists. Re-run with --force to overwrite." >&2
    exit 1
fi

# --- Copy ---
echo "Copying .claude/ ..."
cp -R "$SOURCE_DIR/.claude" "$TARGET/.claude"

echo "Copying .claudeignore ..."
cp "$SOURCE_DIR/.claudeignore" "$TARGET/.claudeignore"

if [ -d "$SOURCE_DIR/.claude-plugin" ]; then
    echo "Copying .claude-plugin/ ..."
    cp -R "$SOURCE_DIR/.claude-plugin" "$TARGET/.claude-plugin"
fi

# --- chmod hooks ---
echo "Setting hook permissions ..."
find "$TARGET/.claude/hooks" -name "*.sh" -print0 | xargs -0 chmod +x

# --- Clear ephemeral state (don't carry source-project state into target) ---
rm -f "$TARGET/.claude/state/session.json" \
      "$TARGET/.claude/state/session-cost.jsonl" \
      "$TARGET/.claude/state/gate-cleared" \
      "$TARGET/.claude/state/sparc-approved" \
      "$TARGET/.claude/state/codex-reviewed" 2>/dev/null || true

cat <<'EOF'

────────────────────────────────────────────────────────────────────────────
SUCCESS — template installed.

NEXT STEPS (manual):

1. Open the project in Claude Code:
       cd "$TARGET" && claude

2. Inside Claude Code, run:
       /setup-project

   This will:
     - configure .claude/project-features.json (Addressables / ECS / Testing / Graph)
     - delete rules and hooks for disabled features
     - generate the initial skills index

3. Manually register optional hooks in .claude/settings.json if you added any
   (Claude cannot edit settings.json — that file is protected). Specifically:
     - block-projectsettings.sh   → PreToolUse / Edit|Write
     - notify.sh                  → Notification
     - pre-compact.sh             → PreCompact

4. (Optional) Build the initial knowledge graph:
       /build-knowledge-graph

5. (Optional) Enable the GitHub PR review workflow by adding your
   ANTHROPIC_API_KEY secret to the repo (Settings > Secrets > Actions).
────────────────────────────────────────────────────────────────────────────
EOF
```

**Acceptance Criteria:**
- File exists at repo root, executable bit set.
- Running `./install.sh /tmp/fake-target` on a non-existent dir exits 1 with `ERROR: target directory does not exist`.
- Running against a dir without `.git` exits 1 with `ERROR: ... is not a git repo`.
- Running against a fresh dir with `.git` copies `.claude/`, `.claudeignore`, sets hook permissions, prints `SUCCESS — template installed.` and the NEXT STEPS block.
- Re-running on a target with existing `.claude/` and no `--force` exits 1; with `--force` it overwrites.
- Running `./install.sh --bogus` exits 1 with `Unknown flag: --bogus`.
- After install, `find <target>/.claude/hooks -name '*.sh' ! -perm -u+x` returns no rows.

---

## Phase 4 — Hook Profiles

## Task T9 — Hook Profile Rollout Across All Hooks

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/*.sh` (all 41 hooks)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/docs/hook-profiles.md` (Create — user-facing doc)

**Steps:**
1. [ ] Audit every hook in `.claude/hooks/` and decide its profile level using the matrix below.
2. [ ] Each hook must source `_lib.sh` with `HOOK_PROFILE_LEVEL=<level>` set immediately before sourcing. `_lib.sh` already implements the gating logic — just declare the level.
3. [ ] Hooks that already declare a level (e.g., `session-save.sh` declares `standard`) — verify the level matches the matrix and update if not.
4. [ ] Create `.claude/docs/hook-profiles.md` documenting the three profiles and which hooks run at each level.
5. [ ] Reference the new doc from `@.claude/docs/hooks-blocking.md` and `@.claude/docs/hooks-warning.md`.

**Profile Matrix:**

| Profile | Active hooks |
|---------|--------------|
| **minimal** | `block-git-push`, `block-scene-edit`, `block-projectsettings` (T4), `check-config-protection`, `guard-critical-files` — only safety/corruption preventers. |
| **standard** (default) | All `minimal` + every `check-*` and `warn-*` hook + `guard-editor-runtime`, `guard-gate-cleared`, `guard-reviewer-order`, `guard-sparc-approved`, `auto-load-skills`, `track-read`, `track-skill-invocations`, `verify-after-write`, `session-save`, `session-restore`, `notify`, `pre-compact`, `graph-auto-update`. |
| **strict** | All `standard` + `gateguard`, `enforce-skill-for-keywords`, `cost-tracker`, `hook-logger`, `instinct-capture`, `instinct-distill`, `stop-verify`, `track-codex-review`, `install-git-hooks`. |

**Test Type:** NoTest (verify via T12 bats tests)

**Code Skeleton (the 3-line declaration to insert into each hook):**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # one of: minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"
```

**Code Skeleton — `.claude/docs/hook-profiles.md`:**
```markdown
# Hook Profiles

Hook execution is gated by the `UNITY_HOOK_PROFILE` environment variable. Set it
in `.claude/settings.json` under `env`. The default is `standard`.

```json
{ "env": { "UNITY_HOOK_PROFILE": "standard" } }
```

## Levels

| Profile | When to use | Tradeoff |
|---------|-------------|----------|
| `minimal` | Brand-new project, exploring, or running an external tool that triggers many false positives. | Only corruption-preventing hooks fire. Code quality is unenforced. |
| `standard` | Default. Day-to-day work. | All quality checks fire; gateguard and instinct capture skipped. |
| `strict`  | Pipelines (`/implement`, `/orchestrate`, `/fix`) where every safeguard matters. | All hooks fire, including those that may add 1–3 s per Write/Edit. |

## Which hooks run at each level
<rendered table from the Profile Matrix>

## Per-hook override
Disable a single hook regardless of profile:
```bash
DISABLE_HOOK_CHECK_PURE_CSHARP=1 claude
```

## Downgrade blocking → warning
```bash
UNITY_HOOK_MODE=warn claude
```
```

**Acceptance Criteria:**
- `grep -L 'HOOK_PROFILE_LEVEL' .claude/hooks/*.sh` returns no rows (every hook declares a level).
- `grep -c 'HOOK_PROFILE_LEVEL="minimal"' .claude/hooks/*.sh | grep -v ':0$' | wc -l` ≥ 5 (matches the 5 minimal hooks) — (requires T4 to be complete).
- `grep -c 'HOOK_PROFILE_LEVEL="strict"' .claude/hooks/*.sh | grep -v ':0$' | wc -l` ≥ 9.
- `UNITY_HOOK_PROFILE=minimal bash .claude/hooks/check-pure-csharp.sh < /dev/null` exits 0 immediately (skipped).
- `.claude/docs/hook-profiles.md` exists and is `@`-referenced from `hooks-blocking.md`.

---

## Phase 5 — Distribution & CI

## Task T10 — `.claude-plugin/plugin.json` Manifest

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude-plugin/plugin.json`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude-plugin/README.md`

**parallel_group:** P5

**Steps:**
1. [ ] Create the `.claude-plugin/` directory.
2. [ ] Author `plugin.json` declaring the template as a Claude Code plugin: name, version, description, author, homepage, and explicit pointers to the existing `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`, `.claude/rules/` directories.
3. [ ] Use semver — start at `1.0.0`.
4. [ ] Create a short `.claude-plugin/README.md` describing installation via `claude plugin install`.
5. [ ] Verify there are no broken paths in `plugin.json` (every referenced dir exists in the repo).

**Test Type:** NoTest

**Code Skeleton — `.claude-plugin/plugin.json`:**
```json
{
  "name": "unity-claude-ai-template",
  "version": "1.0.0",
  "description": "Opinionated Unity 6 + VContainer + UniTask Claude Code configuration. Hook-enforced architecture, 72 skills, 38 agents, 59 slash commands, Unity Knowledge Graph.",
  "author": {
    "name": "Berk Terek",
    "email": "b.terek@luduarts.com"
  },
  "homepage": "https://github.com/berkterek/unity-claude-ai-template-repo",
  "license": "MIT",
  "keywords": ["unity", "unity6", "vcontainer", "unitask", "claude-code", "template", "gamedev"],
  "engines": {
    "claude-code": ">=0.5.0"
  },
  "skills": ".claude/skills/",
  "agents": ".claude/agents/",
  "commands": ".claude/commands/",
  "hooks": ".claude/hooks/",
  "rules": ".claude/rules/",
  "docs": ".claude/docs/",
  "settings": ".claude/settings.json",
  "claudemd": ".claude/CLAUDE.md",
  "post_install": {
    "message": "Template installed. Run /setup-project inside Claude Code to configure feature flags. See .claude/docs/quick-start.md."
  },
  "requires": [
    {
      "tool": "git",
      "min_version": "2.0"
    },
    {
      "tool": "jq",
      "min_version": "1.6"
    },
    {
      "tool": "python3",
      "min_version": "3.8"
    }
  ],
  "optional_dependencies": {
    "unity-mcp-server": "https://github.com/CoderGamester/mcp-unity",
    "openupm-cli": "Used by /discover and install.sh for openupm package resolution"
  }
}
```

**Code Skeleton — `.claude-plugin/README.md`:**
```markdown
# unity-claude-ai-template — Claude Code Plugin

Install:
```bash
claude plugin install github:berkterek/unity-claude-ai-template-repo
```

Or copy the repo and run `./install.sh /path/to/UnityProject`.

After install:
```
/setup-project
/build-knowledge-graph
```

See `.claude/docs/quick-start.md` for the full tour.
```

**Acceptance Criteria:**
- `.claude-plugin/plugin.json` exists, parses with `jq . .claude-plugin/plugin.json` (no errors).
- Every path referenced by `plugin.json` (`.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`, `.claude/rules/`, `.claude/docs/`, `.claude/settings.json`, `.claude/CLAUDE.md`) exists in the repo.
- `name`, `version`, `description`, `engines.claude-code` are non-empty.
- README references `claude plugin install` and `/setup-project`.

---

## Task T11 — GitHub Actions PR Review Workflow

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.github/workflows/claude-pr-review.yml`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.github/workflows/README.md`

**parallel_group:** P5

**Steps:**
1. [ ] Confirmed: `anthropics/claude-code-action@v1` does NOT support `mode: review` or `extra_args` parameters. The correct approach is `prompt:` input only, which the skeleton already uses. This step is now documentation-only.
2. [ ] Create `.github/workflows/`.
3. [ ] Author `claude-pr-review.yml` using the official `anthropics/claude-code-action@v1` action. Trigger on `pull_request` (opened, synchronize, reopened).
4. [ ] Use `-p` non-interactive mode so the action runs once per PR event without hanging.
5. [ ] Reference the project's review skill (`code-review:code-review`) so Claude follows the same conventions as local reviews.
6. [ ] Run only on PRs touching `Assets/**`, `Packages/**`, `.claude/**`, `Docs/**`, `*.cs`, `*.md`.
7. [ ] Add a one-line README in `.github/workflows/` explaining the required secret.

**Test Type:** NoTest (manual smoke test by opening a PR after merge)

**Code Skeleton — `claude-pr-review.yml`:**
```yaml
name: Claude PR Review

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - 'Assets/**'
      - 'Packages/**'
      - '.claude/**'
      - 'Docs/**'
      - '**/*.cs'
      - '**/*.md'

permissions:
  contents: read
  pull-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Claude Code Review
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            You are reviewing a pull request on a Unity 6 + VContainer + UniTask project.
            Read .claude/CLAUDE.md first. Then invoke the code-review:code-review skill.
            Focus on:
              - VContainer / no-singleton compliance
              - UniTask / no-coroutine compliance
              - New Input System usage
              - IEventBus vs Action vs C# event decision
              - Test type correctness per .claude/rules/testing.md
            Post a single consolidated review comment.
```

**Code Skeleton — `.github/workflows/README.md`:**
```markdown
# Workflows

## claude-pr-review.yml

Runs `anthropics/claude-code-action` against every PR. Requires the repo secret:

- `ANTHROPIC_API_KEY` — your Anthropic API key. Add at Settings > Secrets and variables > Actions.

The workflow only runs on PRs that touch source, packages, docs, or .claude/.
It uses `-p` (non-interactive) so it never hangs waiting for input.
```

**Acceptance Criteria:**
- `.github/workflows/claude-pr-review.yml` parses as valid YAML.
- Workflow triggers on `pull_request` and is gated on the path filter list above.
- References `anthropics/claude-code-action@v1` (pinned major version, not floating).
- README explicitly names the `ANTHROPIC_API_KEY` secret.
- No hard-coded API key anywhere in the file (`grep -E 'sk-ant-' .github/workflows/claude-pr-review.yml` returns zero rows).

---

## Phase 6 — Self-Tests

## Task T12 — bats Self-Tests for Top-10 Hooks

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/run-tests.sh`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/block-git-push.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/block-scene-edit.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/block-projectsettings.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/check-pure-csharp.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/check-vcontainer-singleton.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/check-unity-event.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/check-legacy-input.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/session-save.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/graph-auto-update.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/hook-profile.bats`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/tests/README.md`

**Steps:**
1. [ ] Create `tests/` directory under `.claude/hooks/`.
2. [ ] Author a `run-tests.sh` entry point that detects whether `bats` is installed; if not, prints the install instructions for macOS (`brew install bats-core`) and Linux (`npm install -g bats`) and exits 1.
3. [ ] Write one `.bats` file per critical hook. Each file must include: a happy-path test, a blocking-trigger test, a profile-skip test (the hook is skipped at lower profile), and a warn-mode downgrade test (where applicable).
4. [ ] Tests must use a tmp `UNITY_HOOK_STATE_DIR` so they don't pollute real state.
5. [ ] Add a Makefile-style one-liner in `run-tests.sh`: pass = `exit 0`, fail = `exit 1`. This becomes the contract for a future CI job.
6. [ ] Add a one-line README documenting `./run-tests.sh`.

**Test Type:** NoTest (these *are* the tests)

**Code Skeleton — `tests/run-tests.sh`:**
```bash
#!/usr/bin/env bash
# Run all hook self-tests. Requires bats-core (brew install bats-core).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
    cat <<'EOF' >&2
ERROR: bats is not installed.

Install:
  macOS : brew install bats-core
  Linux : npm install -g bats
EOF
    exit 1
fi

cd "$SCRIPT_DIR"
bats *.bats
```

**Code Skeleton — `tests/block-projectsettings.bats`:**
```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/block-projectsettings.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks edits to ProjectSettings/EditorSettings.asset" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | $HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "allows edits to regular .cs files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Game/Foo.cs\"}}' | $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks edits to Packages/manifest.json" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Packages/manifest.json\"}}' | $HOOK"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades to warning" {
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING (downgraded from BLOCKED)"* ]]
}

@test "skipped on minimal profile when level is minimal" {
    # block-projectsettings declares HOOK_PROFILE_LEVEL=minimal, so it should
    # run on ALL profiles. Verify it still runs on minimal.
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | $HOOK"
    [ "$status" -eq 2 ]
}
```

**Code Skeleton — `tests/hook-profile.bats` (verifies _lib.sh profile gating):**
```bash
#!/usr/bin/env bats

@test "minimal profile skips a 'strict'-level hook" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_PROFILE=minimal run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="strict"
        source "$SCRIPT_DIR/_lib.sh"
        echo "should not reach here"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"should not reach here"* ]]
}

@test "strict profile runs a 'standard'-level hook body" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_PROFILE=strict run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="standard"
        source "$SCRIPT_DIR/_lib.sh"
        echo "reached"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached"* ]]
}

@test "DISABLE_UNITY_HOOKS=1 short-circuits the lib" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    DISABLE_UNITY_HOOKS=1 run bash -c '
        SCRIPT_DIR=".claude/hooks"
        source "$SCRIPT_DIR/_lib.sh"
        echo "should not reach"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"should not reach"* ]]
}
```

**Code Skeleton — `tests/session-save.bats`:**
```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

@test "session-save auto-expires gate-cleared" {
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/sparc-approved" ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/codex-reviewed" ]
}
```

**Acceptance Criteria:**
- `./.claude/hooks/tests/run-tests.sh` exits 0 on a clean checkout when bats is installed.
- Each of the 10 `.bats` files contains ≥ 3 `@test` cases.
- Running with bats absent prints the install instructions and exits 1.
- The `hook-profile.bats` test file exercises every documented env var: `UNITY_HOOK_PROFILE`, `DISABLE_UNITY_HOOKS`, `DISABLE_HOOK_*`, `UNITY_HOOK_MODE`.
- The `session-save.bats` test confirms T2's auto-expiry behaviour.
- README documents `./run-tests.sh`.

---

## Implementation Notes & Sequencing

- **Phase 1 tasks (T1–T5)** are fully independent and share `parallel_group: P1`. They can be picked up by a single coder in any order, or by five concurrent agents.
- **T2 and T3 are dependencies of T12** (the bats tests for session-save and graph-auto-update assert the new behaviour). Run T2/T3 before T12.
- **T6 is CANCELLED** — @-includes do not reduce token cost. Skip this task entirely; it is retained in the plan for historical context only.
- **T7 (rule cards)** is independent of T6 (which is cancelled). T7 can run in parallel with any other task — independent files.
- **T9 (profile rollout)** depends on T4 and T5 existing first (the new hooks must also declare their level). Order: T4, T5 → T9.
- **T11 (GitHub Actions)** is unblocked. Verification of `anthropics/claude-code-action@v1` parameters is complete: the action does NOT support `mode: review` or `extra_args` — the correct interface is `prompt:` only, which the skeleton in T11 already uses. T11 depends on T10 only at the doc level (README cross-reference). Otherwise independent.
- **[MANUAL: settings.json]** tasks (T4, T5) require the user to add hook registrations after the script files are created. Implementer should print the JSON snippet at end of task and explicitly ask the user to paste it into `.claude/settings.json`.
- **Today's date 2026-06-03** — every newly created file's header date stamp should use that date.

### Critical Files for Implementation
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/CLAUDE.md
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/_lib.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/session-save.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/hooks/graph-auto-update.sh
- /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/settings.json
