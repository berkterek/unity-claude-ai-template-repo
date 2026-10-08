# Instruction Loading — Spike Findings

**Date:** 2026-10-08 · Claude Code with `claude-opus-5-5` · Plan: `docs/superpowers/plans/2026-10-08-instruction-loading.md` Task 1

Probe: a throwaway `.claude/rules/zz-spike-probe.md` scoped to `**/*.spikeprobe`, carrying `SPIKE-MARKER-7731`.

| # | Question | How | Observed | Consequence |
|---|---|---|---|---|
| S2 | Is a scoped rule absent before any file is touched? | `claude -p`, no Read | `NONE` | As designed |
| S3 | Does Read of a matching file load it? | `claude -p`, Read `docs/spike/probe.spikeprobe` | `7731` | `paths:` works here — **decision gate passed** |
| S4 | Does Write of a **new** matching file load it? (issue #93248) | `claude -p --permission-mode acceptEdits` | `NONE` | #93248 reproduces. A rule for a file being created reaches the model only via net 1 (index) or net 2 (pointer) |
| S5 | Does a subagent's own Read load it? | subagent reads the probe file | loaded inside the subagent | Subagents get scoped rules; explicit Step 0 reads remain for MCP and plan-time work |
| S6 | Are `@` imports expanded? | marker in `quick-start.md` (direct) and `r3.md` (nested) | `NONE` for both; control phrase from CLAUDE.md body present | **No import in `.claude/CLAUDE.md` has ever loaded** |
| S6b | Why? | added `@docs/quick-start.md` | marker loaded | Imports resolve **relative to the importing file**. In `.claude/CLAUDE.md`, `@.claude/docs/x.md` → `.claude/.claude/docs/x.md` (missing). All 14 doc imports and the 24 nested skill imports were dead |
| S7a | Do scoped rules count toward the startup total? | `/context` (developer) | Warning still "24 files"; probe absent from Memory files | Path-scoped rules are **not** counted at launch |
| S7b | Where does a loaded scoped rule go? | Read probe, `/context` again | Memory files unchanged (185.2k); Messages 1.3k → 38.6k | Loaded into message history, as documented |
| S7c | Does `/compact` drop it? | `/compact` (developer) | Summary re-attached `Read .claude/rules/zz-spike-probe.md` | A **recently read** rule is re-attached after compaction; older ones are not guaranteed — net 1 still required |

## Baseline (`/context`, fresh interactive session, before any change)

- Memory files: **185.2k tokens** (18.5% of a 1M window) — `.claude/CLAUDE.md` 32.2k, `architecture` 18.6k, `ui-toolkit-runtime` 13.5k, `solid-oop` 11.6k, `csharp-unity` 11.1k, `web-tool-design-system` 10.9k, `bootstrap-pattern` 10.5k, …
- `/context` suggestion: "save ~55.6k".
- Startup warning: 24 files, 469.5k chars.

## Design consequences (rulings recorded in the plan ledger)

1. Task 5 is a **fix**, not a regression guard: the 24 reference skills never reached the main session; the injected index is the first route they get.
2. Task 6 converting imports to plain references loses no behaviour.
3. The one import kept (`orchestrate-rules.md`) is written file-relative: `@docs/orchestrate-rules.md`.
