# Plan: Template Slimming — Remove Commands and Agents That Never Ran

**Status:** PLANNED, not started. Picked up only after the uncommitted working tree is committed (Step 0).
**Affected repos:** `unity-claude-ai-template-repo` (source of truth); sync to downstream projects afterwards.
**Origin:** 2026-11-06 session — the template carries 56 commands and 37 agents; usage was measured from real
session transcripts before deciding anything.

---

## Evidence — what was measured

Source: `~/.claude/projects/<project>/*.jsonl` (main sessions) and `*/subagents/*.meta.json` (agent spawns).
Counted: `<command-name>` in user turns (typed slash commands), `Skill` tool calls (model-invoked commands),
`agentType` in subagent meta files (spawns + summed token usage).

| Project | Sessions | Date range |
|---|---|---|
| block-canvas (repo + 02/05/08/10 clones) | 901 | 2026-11-02 → 11-06 |
| nile_bounce_legion | 877 | 2026-10-19 → 11-06 |
| nile_hole_sphere (older) | 136 | 2026-10-08 → 10-29 |
| all other projects (cross-check) | — | — |

**Caveat:** transcripts are retained ~30 days; usage older than that is invisible. The measurement script lived in
the session scratchpad — re-create it from the description above if the numbers need refreshing.

### Commands in active use (block + nile, typed + Skill)

| Command | block | nile | hole-sphere |
|---|---|---|---|
| `/orchestrate` | 20 | 30 | 16 |
| `/plan-module` | 20 | 25 | 15 |
| `/update-plan` | 29 | 5 | 7 |
| `/smart-commit` | 8 | 31 | 64 |
| `/fix` | 4 | 5 | 7 |
| `/search` | 4 | 1 | 4 |
| `/roadmap` | 3 | 2 | 1 |
| `/build-knowledge-graph` | 4 | 0 | 4 |

Lifecycle commands (run once per project, low count is expected — KEEP): `/setup-project`, `/game-idea`,
`/refine-gdd`, `/refine-tdd`, `/architect`, `/catch-up`, `/continue`, `/validate`.

All 34 `/update-plan` runs in block + nile targeted an existing module plan (`module 07`, `12`, "drift check") —
small work was **not** routed through `/create-plan`; it went through `/fix`, `/update-plan` or the main session.

### Never ran in any project (0 calls)

**35 commands:** `adr`, `audio-clip-setup`, `caveman`, `check-portability`, `checkpoint`, `clean-slop`,
`context-prime`, `create-changelog`, `create-prefab-scene`, `create-test`, `debate`, `debug-session`, `discover`,
`dry-run`, `dump`, `five`, `fix-codex`, `fix-deep`, `generate-tests`, `graphics-setup`, `grill-me`, `instincts`,
`learn`, `mermaid`, `migrate`, `new-module`, `qa`, `ralph`, `review-code`, `scene-setup`, `silent-failure-hunt`,
`smart-commit-selected`, `unity-scene-update`, `update-claude-md`, `update-scene-hierarchy`.

**14 agents:** `debate-critic`, `debate-moderator`, `debate-proposer`, `graphics-setup-agent`, `migrator`,
`unity-migrator`, `package-analyzer`, `unity-build-runner`, `unity-git-master`, `unity-network-dev`,
`unity-prototyper`, `unity-scene-builder`, `unity-security-reviewer`, `unity-test-builder`.

Dependency check: **no used command references any of these 35.** Hooks/scripts that mention them by name (must be
cleaned in Step 1): `hooks/_lib.sh`, `check-architecture-doc.sh`, `check-test-scene-exists.sh`,
`guard-gate-cleared.sh`, `guard-main-unity-tests.sh`, `instinct-distill.sh`, `session-restore.sh`,
`hooks/tests/{check-test-scene-exists,inject-rule-pointers,rule-read-audit}.bats`, `scripts/codex-review.sh`.

### Rarely used — kept for now (decision deferred)

| Item | Uses (all projects) | Note |
|---|---|---|
| `/create-plan` | 19 (0 in block/nile, 3 in hole-sphere) | superseded by `/plan-module`; bypasses roadmap/milestone check |
| `/implement` | 13 (0 in block/nile, 2 in hole-sphere) | superseded by `/orchestrate` |
| `/status`, `/performance-audit`, `/knowledge-graph` | 1–2 each | |
| `lean-planner`, `unity-optimizer`, `audio-clip-agent`, `unity-particle-designer` | 1–2 each | |
| `unity-test-runner` (12), `unity-shader-dev` (9) | real work done | KEEP |

---

## Decisions

1. **Delete only the zero-use set (35 commands + 14 agents).** Evidence is measured, no used command depends on
   them, everything is recoverable from git. Low risk.
2. **Do not touch the rarely-used set yet.** Deleting it was proposed, but the user judged the overall change too
   large with a high error margin right now. Revisit with fresh numbers.
3. **`/plan-module --lean` is shelved.** Idea: one planning entry point with a complexity flag so every new feature
   passes the roadmap/milestone check (`rules/roadmap-milestones.md` Card 2), replacing `/create-plan` +
   `/implement`. Shelved because:
   - It touches the `/plan-module` ↔ `validate-plan-facts.sh` ↔ `/orchestrate` contract; a break surfaces only
     during a real module plan.
   - Need is unproven — small work is already handled by `/fix` and `/update-plan`.
   - If revived: lean may cut **cost** (Sonnet planner, ≤3 tasks, no skeletons, one review round) but never the
     **format** — ACs, `Callers:`/`Wiring:` lines and the milestone check stay, or `validate-plan-facts.sh` and
     `/orchestrate` break (`plan-module.md` explains why `lean-planner` is not used). Mode is an explicit `--lean`
     flag, auto-escalating to full if the plan exceeds 3 tasks — never an agent's own "this is small" judgment.
   - Routing if revived: bug → `/fix` (not roadmap); change to an existing module → `/update-plan`; small new
     feature → `/plan-module --lean` (gets a ROADMAP row).
   - Savings must be measured with `scripts/pipeline-breakdown.py` (full vs lean on one small module) before it
     counts as done.
4. **File count is not where the weight is.** Deleting files shrinks maintenance surface and the per-session
   command/agent listing; it does not move token cost. Measured agent consumption:

   | Agent | block | nile | hole-sphere |
   |---|---|---|---|
   | `unity-setup` | 314M | 4M | 271M |
   | `unity-coder` | 266M | 69M | 265M |
   | `general-purpose` | 183M | 350M | 229M |
   | `Plan` | 208M | 98M | 170M |

   `/compact` ran 72 (block), 50 (nile), 51 (hole-sphere) times — sessions hit the context limit constantly.
   This is a separate, larger investigation.

---

## Steps

### Step 0 — Clean baseline (user)
Commit the current uncommitted working tree (36+ modified files incl. `settings.json`) via `/smart-commit`.
Mixing deletions into it makes the change unreviewable.

### Step 1 — Delete the zero-use set (one commit)
- `git rm` the 35 `commands/*.md` and 14 `agents/*.md` listed above.
- Clean name references in the hooks/scripts/bats listed above; `instinct-distill.sh` belongs to the instincts
  system — decide whether the observation hooks go with `/instincts` or stay (they need `settings.json` changes,
  which only the user can make).
- Update `docs/commands.md`, `docs/agents-index.md`, `docs/skills-index.md`, `.claude/CLAUDE.md` (renamed-command
  line mentions `/create-test` and `unity-test-builder`), `README.md`.
- Grep the whole repo for each deleted name; zero hits outside git history.
- Run the hook bats suite; all green.
- Rollback: `git revert <commit>`.

### Step 2 — Re-measure (later)
After a few weeks of use, re-run the measurement. Decide the rarely-used set with the new numbers.

### Step 3 — Token cost investigation (separate plan)
Why `unity-setup`, `unity-coder`, `general-purpose` and `Plan` dominate, and why sessions compact this often.
