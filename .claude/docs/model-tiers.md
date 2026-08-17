# Model Tiers

Model selection happens at **three independent layers**. Don't confuse them:

| Layer | Where set | Controls |
|-------|-----------|----------|
| **1. Session model** | Shell alias (`claude-heavy` etc.) at launch | The model running the slash command / main loop |
| **2. Subagent model** | Agent `.md` frontmatter `model:` | The model a spawned subagent runs on (see Layer 2 rule below) |
| **3. Skill model-tier** | Skill frontmatter `model-tier:` + `model-routing` skill | Suggested tier for a skill's work |

---

## Layer 1 — Session Model

Start your session with the right model for the task:

| Tier | Model | Alias | When to use |
|------|-------|-------|-------------|
| **light** | `claude-haiku-4-5` | `claude-light` | Quick tasks: `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | `claude-sonnet-5` | `claude-normal` | Balanced work: `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/performance-audit`, `/new-module`, `/check-portability`, `/clean-slop`, `/catch-up`, `/learn`, `/search` |
| **heavy** | `claude-opus-5` | `claude-heavy` | Deep thinking: `/architect`, `/roadmap`, `/plan-module`, `/game-idea`, `/grill-me`, `/refine-gdd`, `/refine-tdd` |

Setup aliases once in your shell profile — see `.claude/aliases.sh`.

### When the Current Model Is Unavailable

There is **no automatic model fallback** in Claude Code, and the API's `fallbacks` parameter does not provide one either — it fires only on safety refusals, and overloads, rate limits, and server errors are returned as-is. Falling back is a manual decision.

| Tier | Primary | Fallback | Last resort |
|------|---------|----------|-------------|
| **heavy** | `claude-opus-5` | `claude-opus-4-7` | `claude-opus-4-6` |
| **normal** | `claude-sonnet-5` | `claude-sonnet-4-6` | — |
| **light** | `claude-haiku-4-5` | — | — |

**Prefer `/model <id>` inside the running session** over restarting with a fallback alias — it keeps your context, your open plan, and any gate state. Restart only if the session itself is unusable.

Two things that make this actually work:

- **Opus 5 and Sonnet 5 have rate-limit buckets separate from the 4.x pool.** Dropping a generation gives you genuinely fresh headroom; it is not the same quota under a different name.
- **A model switch invalidates the prompt cache** (caches are model-scoped). The first request after switching pays full price for the whole prefix. Switch because you're blocked, not to shave cost.

Match the failure to the fix before reaching for a fallback:

| Symptom | Fallback helps? | Actual fix |
|---|---|---|
| `529 overloaded_error`, sustained | **Yes** | Switch tier, or retry with backoff |
| `429 rate_limit_error` | **Yes** — separate bucket | Wait out `retry-after`, or switch |
| `stop_reason: "refusal"` | Sometimes | A different model has different classifiers; retry there |
| Context window exhausted | No | `/compact`, or `/checkpoint` and start fresh |
| CLI crash / hang | No | Not a model problem — check hooks and MCP connections |

### Why not Claude Fable 5

`claude-fable-5` is Anthropic's most capable widely released model, but it is **deliberately not a tier here**. It costs 2× Opus 5 ($10/$50 vs $5/$25 per MTok), thinking is always on (the `thinking` parameter is rejected), single requests on hard tasks can run for many minutes, and it requires 30-day data retention. Its advantage is long-horizon *autonomous* execution — overnight refactors, one-shot whole-system builds, no human in the loop.

This project's pipelines are the opposite shape: every command stops at a Director Gate (`SCOPE_GATE` → `SPARC_GATE` → `QUALITY_GATE` → `COMMIT_GATE`) every few minutes, and every subagent is a narrow, single-task worker. The autonomy Fable is priced for never gets used, and minute-long turns fight the gate rhythm.

If you want it for a one-off architecture session, add the alias manually and launch with it — do not add it to this table, or agents will start inheriting it:

```sh
alias claude-frontier='claude --model claude-fable-5'
```

---

## Layer 2 — Subagent Model (Lead / Worker / Scanner)

Each agent's `model:` frontmatter follows **role level**, not domain. Orchestration lives in commands and the session — agents do not orchestrate each other.

| Level | Role | Model | Agents |
|-------|------|-------|--------|
| **Lead** | Decides, reviews, critiques, plans architecture | **Opus** | `unity-critic`, `debugger`, `unity-developer`, `reviewer`, `unity-reviewer`, `debate-proposer`, `debate-critic`, `debate-moderator` |
| **Worker** | Executes a defined task (write code/test, build, set up, migrate, fix, lean plan) | **Sonnet** | all others, incl. `coder`, `unity-coder`, `lean-planner`, `tester`, `migrator`, … |
| **Scanner** | Mechanical read-only scan (lint, locate files, pattern-match) | **Haiku** | `unity-scout`, `unity-linter` |

**Command spawn rule:** every agent spawned inside a command must carry an explicit `model` so it never silently inherits the session model. Pinned examples: `Plan` subagent → `opus`; `Explore` → `haiku`; `/search` action router → `haiku`. The `FORCE_HAIKU_TIER` / `FORCE_OPUS_TIER` flags in `/fix`, `/fix-deep`, `/implement`, `/orchestrate` override worker tier per run.

> Full design: `docs/superpowers/specs/2026-06-24-agent-model-tiers-design.md`. Source-of-truth agent list: `docs/agents-index.md → ## Model Tier`.

Agent frontmatter uses the aliases `opus` / `sonnet` / `haiku`, never a pinned model ID — so Layer 2 tracks whatever those resolve to and needs no edit when Layer 1 moves.

---

## After a Layer 1 Model Bump

Two things to re-check when the aliases point at a newer model — both are prompt-side, not config:

1. **Re-tune `effort` per command.** Effort defaults carried over from a prior model rarely transfer. On Opus 5, `low` and `medium` are unusually strong; sweep down from the `high` default rather than assuming the old setting still fits.
2. **Delete verification scaffolding.** Opus 5 verifies its own work unprompted. Instructions like *"double-check your answer"* or *"add a final verification step"* in agent prompts now cause over-verification with no capability gain — removing them is a delete, not a rewrite. Note this inverts the usual "ask Claude to self-check" advice.
