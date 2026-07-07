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
| **normal** | `claude-sonnet-4-6` | `claude-normal` | Balanced work: `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/performance-audit`, `/new-module`, `/check-portability`, `/clean-slop`, `/catch-up`, `/learn`, `/search` |
| **heavy** | `claude-opus-4-8` | `claude-heavy` | Deep thinking: `/architect`, `/roadmap`, `/plan-module`, `/game-idea`, `/grill-me`, `/refine-gdd`, `/refine-tdd` |

Setup aliases once in your shell profile — see `.claude/aliases.sh`.

---

## Layer 2 — Subagent Model (Lead / Worker / Scanner)

Each agent's `model:` frontmatter follows **role level**, not domain. Orchestration lives in commands and the session — agents do not orchestrate each other.

| Level | Role | Model | Agents |
|-------|------|-------|--------|
| **Lead** | Decides, reviews, critiques, plans architecture | **Opus** | `unity-critic`, `debugger`, `unity-developer`, `reviewer`, `unity-reviewer` |
| **Worker** | Executes a defined task (write code/test, build, set up, migrate, fix, lean plan) | **Sonnet** | all others, incl. `coder`, `unity-coder`, `lean-planner`, `tester`, `migrator`, … |
| **Scanner** | Mechanical read-only scan (lint, locate files, pattern-match) | **Haiku** | `unity-scout`, `unity-linter` |

**Command spawn rule:** every agent spawned inside a command must carry an explicit `model` so it never silently inherits the session model. Pinned examples: `Plan` subagent → `opus`; `Explore` → `haiku`; `/search` action router → `haiku`. The `FORCE_HAIKU_TIER` / `FORCE_OPUS_TIER` flags in `/fix`, `/fix-deep`, `/implement`, `/orchestrate` override worker tier per run.

> Full design: `docs/superpowers/specs/2026-06-24-agent-model-tiers-design.md`. Source-of-truth agent list: `docs/agents-index.md → ## Model Tier`.
