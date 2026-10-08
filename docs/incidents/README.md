# Incidents

Dated root-cause narratives moved out of `.claude/CLAUDE.md` on 2026-10-08 so they stop loading into every
session. CLAUDE.md keeps the short rule each one supports and links here. Nothing was deleted.

| File | Covers |
|---|---|
| `test-layers.md` | What bats, reviewer-fixtures, pipeline-dry-run, the asmdef validator, the Blender/compile probes, the graph harness and the rule-awareness probe can and cannot prove |
| `pretooluse-effective-content.md` | Why a `PreToolUse` content hook must judge the effective post-edit content, and keep its `Write` branch reachable |
| `plan-time-gates.md` | Plan-time path and fact validation; plan coverage of the deny-then-allow gates; the cwd and rename false-positive bugs |
| `ui-toolkit-status.md` | UI Toolkit version gate and adoption status / open blockers |
| `mcp-and-framework.md` | Frozen MCP tool lists, the SerializedOps applier, the framework package, the Unity official plugin's precedence |
| `knowledge-graph.md` | Graph partitions, extraction vs schema version, record semantics (events, installers, scope parents, registrations) |
| `model-tiers.md` | Aliases vs pinned IDs, fallbacks, cost notes |
| `subagent-depth.md` | Subagent lifecycle hooks and every known `subagent-depth` leak |
| `gate-markers.md` | `sparc-approved` / `codex-reviewed` TTLs, compaction keeping gates, gate-cleared ≠ pipeline-executed |
| `skills-loading.md` | How reference skills reach the main session and subagents; keyword enforcement |
