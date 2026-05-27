# PLAN — Pipeline Hooks & Lean-Planner Test (LEAN)

> Version: v1 — 2026-05-26
> Version: v2 — 2026-05-26
> Mode: lean
> Status: Active

## Tasks

| # | Task | Files | Notes |
|---|------|-------|-------|
| 1 | Verify Hook A skips non-.cs files (exit 0, no build) | `.claude/hooks/verify-after-write.sh` | `echo '{"path":"README.md"}' \| .claude/hooks/verify-after-write.sh` → exit 0, no dotnet output |
| 2 | Verify Hook A handles .cs with no .sln gracefully | `.claude/hooks/verify-after-write.sh` | `echo '{"path":"Test.cs"}' \| .claude/hooks/verify-after-write.sh` → exit 0, skip message |
| 3 | Verify Hook B blocks agent spawn without sparc-approved | `.claude/hooks/guard-sparc-approved.sh`, `.claude/state/sparc-approved` | `rm -f .claude/state/sparc-approved` + unity-coder pipe → exit 2 |
| 4 | Verify Hook B allows with sparc-approved; passes non-coder unconditionally | `.claude/hooks/guard-sparc-approved.sh`, `.claude/state/sparc-approved` | `touch .claude/state/sparc-approved` + unity-coder → exit 0. tester (no state file) → exit 0 |
| 5 | Verify lean-planner produces compact table-only output within 5 tasks | `.claude/agents/lean-planner.md` | Invoke with sample topic; confirm no code skeletons, no acceptance criteria, no parallel_group |
| 6 | Verify /update-plan --lean pipeline uses general-purpose agent + lean prompt, no auto-spawn, and preserves table-only output | `.claude/skills/update-plan.md`, `.claude/agents/lean-planner.md` | Run /update-plan --lean on this file; confirm subagent_type=general-purpose, lean-planner prompt inlined, output is table-only with version bump |

## Notes
- No implementer auto-spawn
- Task 5 bu planın kendisi — lean-planner çıktısı doğrulandı ✓
- Task 6 /update-plan --lean pipeline end-to-end doğrulaması
