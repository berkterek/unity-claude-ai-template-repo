# Agent Model Tiers — Lead / Worker / Scanner

**Date:** 2026-06-24
**Status:** Approved (design)
**Scope:** Re-tier the existing 34 agents by a single role-level rule, fix doc inconsistencies, and pin floating model spawns in commands. **No new agents.**

---

## Problem

Agent model assignment is inconsistent and partly undocumented:

1. **Role-level not encoded.** `unity-developer` (reviewer) is Opus while `coder` (writer) is Sonnet — looks contradictory because the *level* (lead vs worker) is hidden behind domain naming.
2. **Doc vs config drift.** `lean-planner` frontmatter is `model: opus`, but three docs (`README.md` ×2, `agents-index.md`) describe it as Sonnet and `--lean` as "faster for small tasks". The frontmatter is the bug — `lean-planner` is the cheap/fast planner; the full Opus planner is the `Plan` subagent.
3. **Floating models in commands.** `/search` spawns `Explore` and an "action router" with **no** `model`, so they inherit the session model (Opus on a `/heavy` session = expensive research/routing). `Explore` is unpinned in 6 commands.

### Three model layers (context)
Model selection happens at three independent layers. This spec touches only layer 2.
1. **Session model** — shell aliases (`claude-heavy`/`normal`/`light`); documented in `model-tiers.md` / README.
2. **Subagent model** — agent `.md` frontmatter (`model:`). ← **this spec**
3. **Skill model-tier** — skill frontmatter (`model-tier: light|normal|heavy`) + the `model-routing` skill. Out of scope here.

Reference studied: `Donchitos/Claude-Code-Game-Studios` — a 3-tier studio hierarchy (Directors=Opus, Leads=Sonnet, Specialists=Sonnet/Haiku) with vertical delegation *inside agents*. This project instead orchestrates **in commands**, so we adopt the tier→model **principle**, not the 49-agent agent-as-orchestrator structure.

---

## The Rule (single source of truth)

Model tier follows **role level**, never domain.

| Level | Role | Model | Rationale |
|-------|------|-------|-----------|
| **Lead** | Decides, reviews, critiques, plans architecture, resolves conflict | **Opus** | High judgment; wrong answer is expensive |
| **Worker** | Executes a defined task (write code/test, build, set up scene, migrate, fix) | **Sonnet** | Balanced execution |
| **Scanner** | Mechanical read-only scan (lint, locate files, pattern-match) | **Haiku** | Fast, cheap, no deep reasoning |

Delegation stays in commands and the session. Agents do not orchestrate each other; the command (and the session model the user picks via `/heavy` etc.) is the "director".

---

## Classification (all 34 agents)

### Tier 1 — Lead (Opus)
| Agent | Current | Target | Change |
|-------|---------|--------|--------|
| `unity-critic` | opus | opus | — |
| `debugger` | opus | opus | — |
| `unity-developer` | opus | opus | — (reviewer/consultant, not a writer) |
| `reviewer` | opus | opus | — |
| `unity-reviewer` | sonnet | **opus** | ⬆ upgrade (review = lead) |

### Tier 3 — Scanner (Haiku)
| Agent | Current | Target | Change |
|-------|---------|--------|--------|
| `unity-scout` | haiku | haiku | — |
| `unity-linter` | haiku | haiku | — |

### Tier 2 — Worker (Sonnet) — all remaining 27
`coder`, `unity-coder`, `tester`, `unity-test-runner`, `unity-test-builder`, `unity-verifier`,
`migrator`, `unity-migrator`, `unity-fixer`, `committer`, `unity-setup`, `unity-scene-builder`,
`unity-build-runner`, `unity-git-master`, `unity-network-dev`, `unity-prototyper`,
`unity-ui-builder`, `unity-ui-toolkit-builder`, `unity-shader-dev`, `unity-particle-designer`,
`unity-optimizer`, `graphics-setup-agent`, `audio-clip-agent`, `package-analyzer`,
`silent-failure-hunter`, `unity-security-reviewer` — all **sonnet** (no change).
`lean-planner` — opus → **sonnet** (⬇ matches docs + `--lean` "fast/cheap" intent; deep planning is the Opus `Plan` subagent).

### Resolved borderline decisions
- `silent-failure-hunter` → **Sonnet** (accuracy over cost: detecting swallowed exceptions needs control-flow reasoning, not pure pattern match).
- `unity-security-reviewer` → **Sonnet** (security scan is mostly pattern-based; not deep architectural judgment).
- `package-analyzer` → **Sonnet** (generates Adapter-pattern drafts; produces output, not a pure scan).

**Net frontmatter changes: two — `unity-reviewer` sonnet → opus, `lean-planner` opus → sonnet.** All other agents already match the rule.

---

## Mechanism fixes

### 1. Command spawn pinning (the real runtime bug)
Every **built-in** agent spawned in a command (`Explore`, `Plan`, `general-purpose`, `claude`, action router) must carry an explicit `model` so it never inherits the session model. Named agents (`unity-coder`, `reviewer`, …) auto-use their `.md` frontmatter and need no pin.

Pinned by role tier:
- **`Explore`** → `haiku` — `create-plan`, `game-plan`, `search`, `update-plan` (Scanner: locates code, no synthesis). (`architect`/`scene-setup` only use the verb "explore" via brainstorming — no spawn.)
- **action router** (`search`) → `general-purpose` + `haiku` (tiny routing decision).
- **`general-purpose` plan-review fallback** (Codex unavailable) → `opus` — `create-plan`, `update-plan` (review = lead).
- **`general-purpose` implementer** (per-task + single) → `sonnet` — `create-plan`, `update-plan` (worker).
- **`general-purpose` package-analyzer host** → `sonnet` — `discover` (matches package-analyzer worker tier).
- **`general-purpose` validate** → `sonnet` — `orchestrate`, `qa`.
- **`claude` isolated Test Writer** → `sonnet` — `fix`, `implement`, `migrate`, `orchestrate` (tester = worker; `subagent_type: "claude"` kept for clean-context isolation).
- Already correct, left as-is: `Plan` subagent (`opus`); `FORCE_HAIKU_TIER` / `FORCE_OPUS_TIER` escape hatches in `fix`, `fix-deep`, `implement`, `orchestrate`.

Audit invariant: `grep` for each built-in spawn type across `commands/*.md` returns zero lines lacking an explicit `model`.

### 2. Documentation
With the `lean-planner` flip, README ×2 and `agents-index.md` "(Sonnet)" descriptions are **already correct** — no text fix needed there. Remaining doc work:
- **`agents-index.md`**: add a `Model` column reflecting the final classification (esp. `unity-reviewer` = Opus).
- **`model-tiers.md`**: currently covers *session* model only. Add a separated section for the **agent-level** Lead/Worker/Scanner → model rule, and state the **three layers** (session / subagent / skill). Add `/search` to session guidance (research → normal/sonnet).
- **`README.md`**: in the Model Tiers section, add `/search` and a short note distinguishing the three layers; ensure the agents table (≈L756+) reflects `unity-reviewer` as an Opus reviewer. (lean-planner lines already say Sonnet — leave.)
- **`.claude/CLAUDE.md`**: `@`-references `model-tiers.md` so the rule propagates automatically; add one pointer line under `## Model Tiers` noting the agent-level Lead/Worker/Scanner rule lives in `model-tiers.md`. No table duplicated inline.

---

## Non-goals (YAGNI)
- No new director/lead orchestrator agents.
- No change to how commands delegate (no vertical agent-to-agent delegation).
- No 49-agent studio port.

## Acceptance
- Each `.claude/agents/*.md` frontmatter matches the classification table.
- No command spawns an agent without an explicit `model`.
- `agents-index.md` and `model-tiers.md` agree with the frontmatter (no drift).
