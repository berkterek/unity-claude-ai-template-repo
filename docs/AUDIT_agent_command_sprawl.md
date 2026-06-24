# Agent & Command Sprawl Audit

**Scope:** `.claude/agents/*.md` (34) and `.claude/commands/*.md` (55) in this Unity Claude Code template.
**Mode:** Analysis only. Nothing was deleted, moved, or edited. All recommendations are advisory.
**Date:** 2026-06-25

---

## 1. Summary

| Metric | Count |
|--------|-------|
| Agents | **34** |
| Commands | **55** |
| Dead-candidate agents (0 spawn references; catalog-only) | **9** |
| Orphan-candidate commands (0 refs) | **0** (lowest is 2) |
| Documentation gaps (command file absent from `commands.md`) | **2** |
| Overlap clusters | **6** |

**Headline findings:**
- **No truly dead agent and no truly orphan command exists.** Every agent appears at minimum in the `agents-index.md` catalog; every command is referenced ≥ 2 times.
- **9 agents are spawned by *zero* commands** — they exist only in the `agents-index.md` catalog (and sometimes `CLAUDE.md`). Per the repo's own framing, `.claude/agents/*.md` are FleetView prompt overlays, so these are **user-invoke-only** agents, not dead code. They are listed below as "dynamic-only".
- **2 command files (`/build-knowledge-graph`, `/knowledge-graph`) are missing from `docs/commands.md`**, which the project treats as the canonical command list. This is a documentation gap, not an orphan.
- **Dangling reference:** `unity-critic` and `unity-verifier` descriptions both cite a `/unity-workflow` command that **does not exist** (no `unity-workflow.md` in `.claude/commands/`). Stale reference.
- **Task-prompt mismatch:** the audit brief mentioned a `code-review` command and a `Plan`/`Explore`/`code-review` set — there is **no `code-review.md`** (only `review-code.md`); `Plan` and `Explore` are built-in FleetView agent types, not files in this repo.

### Method note on reference counts
Commands in this repo spawn agents via **bolded prose** ("spawn a **unity-coder** subagent"), not only via a `subagent_type:` YAML key. Counts below use whole-word grep (`-w`) across `.claude/commands/*.md`, `.claude/docs/*.md`, `.claude/CLAUDE.md`, and other `.claude/agents/*.md`, excluding each agent's own file. Because `-w` treats `-` as a word boundary, the bare name `coder` also matches inside `unity-coder`; this inflates the *bare-name* counts for `coder`/`reviewer`/`tester`/`migrator`/`setup` but does **not** change their verdict (all are heavily used). It is irrelevant to the dead-candidate set, whose names are unique.

---

## 2. Dead-candidate agents

"Referenced" = number of **files other than the agent's own** that mention the identifier. `agents-index.md` is the catalog (every agent is listed there once); a verdict of **dynamic-only** means *no command pipeline spawns it* — it appears only in the catalog (± `CLAUDE.md`).

| Agent | Ref files | Where referenced | Verdict |
|-------|-----------|------------------|---------|
| `unity-build-runner` | 1 | `agents-index.md` only | **dynamic-only** — no command spawns it; user-invokable for CI/builds |
| `unity-network-dev` | 1 | `agents-index.md` only | **dynamic-only** — no command; multiplayer is a niche on-demand agent |
| `unity-optimizer` | 1 | `agents-index.md` only | **dynamic-only** — overlaps `/performance-audit` (see cluster 6) but not spawned by it |
| `unity-prototyper` | 1 | `agents-index.md` only | **dynamic-only** — the "star agent" per its own description, but no command wires it; user-invoked |
| `unity-scene-builder` | 1 | `agents-index.md` only | **dynamic-only** — overlaps `unity-setup`/`unity-scene-update` (cluster 5); not spawned |
| `unity-security-reviewer` | 1 | `agents-index.md` only | **dynamic-only** — backs no command; `/qa` does not call it |
| `unity-test-runner` | 1 | `agents-index.md` only | **dynamic-only** — overlaps `tester` + `unity-test-builder` (cluster 3); not spawned |
| `unity-ui-builder` | 1 (+1 cross-ref) | `agents-index.md`, mentioned in `unity-ui-toolkit-builder.md` | **dynamic-only** — runtime UGUI agent; no command spawns it |
| `unity-ui-toolkit-builder` | 2 | `agents-index.md`, `unity-ui-builder.md` | **dynamic-only** — Editor UI agent; no command spawns it |
| `unity-shader-dev` | 2 | `agents-index.md`, `CLAUDE.md` (performance rule routes shader work here) | **keep** — referenced by an architecture rule as the routing target |
| `unity-particle-designer` | 2 | `agents-index.md`, `CLAUDE.md` (perf rule routes VFX here) | **keep** — referenced by an architecture rule |
| `unity-git-master` | 2 | `agents-index.md`, `CLAUDE.md` (git-skill loading note) | **keep** — referenced by CLAUDE.md skill-loading rule |
| `audio-clip-agent` | 2 | `agents-index.md`, `/audio-clip-setup` | **keep** — backs a command |
| `graphics-setup-agent` | 2 | `agents-index.md`, `/graphics-setup` | **keep** — backs a command |
| `package-analyzer` | 2 | `agents-index.md`, `/discover` | **keep** — backs a command |
| `unity-critic` | 4 | `/architect`, `agents-index.md`, `commands.md`, `model-tiers.md` | **keep** — but its description cites non-existent `/unity-workflow` (fix the description) |
| `unity-linter` | 4 | `/qa`, `/orchestrate`, `agents-index.md`, `model-tiers.md` | **keep** — backs two commands |
| `silent-failure-hunter` | 4 | `/fix`, `/implement`, `/fix-deep`, `agents-index.md` | **keep** — backs three commands |
| `unity-verifier` | 11 | many commands | **keep** — but description cites non-existent `/unity-workflow` (fix the description) |

**No agent has 0 references.** The 9 "dynamic-only" agents are the closest to dead, but the repo explicitly documents that agents are user-invokable FleetView overlays, so 0 command-spawns ≠ unused. **None can be proven removable.**

All other agents (coder, unity-coder, reviewer, unity-reviewer, unity-developer, debugger, tester, committer, migrator, unity-migrator, unity-fixer, lean-planner, unity-scout, unity-setup) are heavily referenced (files 4–33) and unambiguously live.

---

## 3. Orphan-candidate commands

Every command file is referenced ≥ 2 times. Commands are user-invoked via slash, so this section reports **documentation coverage** (presence in `docs/commands.md`, the canonical list) rather than usage.

| Command | In `commands.md`? | Ref files | Verdict |
|---------|-------------------|-----------|---------|
| `/build-knowledge-graph` | **NO** | 8 | **DOCUMENT** — well-used (referenced by 8 files incl. CLAUDE.md graph workflow) but missing from the canonical command list |
| `/knowledge-graph` | **NO** | 5 | **DOCUMENT** — same; referenced by CLAUDE.md graph cheatsheet but not in `commands.md` |
| All other 53 commands | Yes | 2–17 | keep |

**Lowest-referenced commands** (still documented, still valid — listed for completeness): `/status` (2), `/silent-failure-hunt` (2), `/audio-clip-setup` (2), `/graphics-setup` (2), `/game-plan` (2), `/update-claude-md` (2), `/unity-scene-update` (3? listed 3), `/update-scene-hierarchy` (2). All appear in `commands.md` and are user-invokable. **No orphans.**

**Documented names with no file** (these are NOT missing commands — they are state files / built-in commands referenced in prose): `/clear`, `/normal` (built-ins), `/plan-summary`, `/project-features`, `/decisions`, `/logs`, `/state`, `/skills`, `/third-party`, `/learned`, `/manifest`, `/large`, `/removing`, `/search-findings`. These are paths or built-ins, not slash-command files — no action.

---

## 4. Overlap clusters

### Cluster 1 — Reviewers (4 agents + 1 command)
| Member | One-line role | 
|--------|---------------|
| `reviewer` (opus, +MCP) | "Principal-level code reviewer… triggers Unity compilation + Play mode validation via MCP." |
| `unity-reviewer` (opus, no MCP) | "Reviews Unity C# for correctness, perf, serialization, lifecycle, GC, CompareTag, leaks." |
| `unity-developer` (opus) | "Unity 6 specialist — reviews code AND plans; hot paths, draw calls, ECS, Addressables, prefab structure; second reviewer for score ≥ 0.7." |
| `unity-critic` (opus) | "Challenges *plans* before execution — risks, edge cases, over-engineering." |
| `/review-code` (cmd) | "Manual code review on specific files via **unity-reviewer**." |

**What genuinely differs:** `reviewer` has MCP/Bash tools (can compile + run Play mode); `unity-reviewer` is read-only (no MCP) and is the static Unity-pitfall pass; `unity-developer` reviews *plans + code* and is layered as the **second** reviewer only at complexity ≥ 0.7; `unity-critic` reviews **plans, not code** (pre-implementation adversary). `/review-code` is just a thin file-scoped entry point to `unity-reviewer`.

**Recommendation: KEEP-distinct, but DOCUMENT-BOUNDARY.** The four agents have non-trivial tool/phase differences, but `reviewer` vs `unity-reviewer` is the murkiest pair — both are opus code reviewers; the only hard difference is MCP access. Add a one-line decision note ("MCP runtime validation → `reviewer`; static read-only Unity review → `unity-reviewer`") to `agents-index.md`. Not a merge candidate without behavioral verification.

### Cluster 2 — Fixers / debuggers (5 commands + 2 agents)
| Member | One-line role |
|--------|---------------|
| `/fix` | "Debugger → Test Writer → Coder → Reviewer → Committer" — stack trace clearly points to cause. |
| `/fix-deep` | "Evidence-first pipeline; refuses to fix unless root cause is *proven*." |
| `/fix-codex` | "Codex-driven fix pipeline — for legacy/large files or when stuck after `/fix`/`/fix-deep`." |
| `/debug-session` | "Structured root-cause analysis; routes to **unity-fixer** after cause found." |
| `/five` | "5 Whys root-cause drill-down." |
| `unity-fixer` (agent) | "Diagnoses + fixes Unity bugs via MCP console reads." |
| `debugger` (agent) | "Root cause analysis specialist: reproduce → isolate → identify → fix → verify." |

**What genuinely differs:** These are deliberately tiered by *evidence threshold and cost*: `/five` (analysis only, no fix) < `/debug-session` (structured analysis → routes to fixer) < `/fix` (fast, trusts the stack trace) < `/fix-deep` (won't fix without proof) < `/fix-codex` (escalation to Codex for hard/large cases). The agents `debugger` (opus, planning) and `unity-fixer` (sonnet, executes via MCP) are the diagnosis vs. execution split.

**Recommendation: KEEP-all-with-decision-table.** This is the strongest case of *intentional* tiering, and `commands.md` already documents when to use each. The redundancy is real-but-justified. Action: ensure the existing decision rows stay visible; no merge.

### Cluster 3 — Test builders / runners (3 agents + 2 commands)
| Member | One-line role |
|--------|---------------|
| `tester` (agent) | "Writes NUnit tests per the test-type decision tree; NSubstitute; AAA." |
| `unity-test-builder` (agent) | "Builds Play Mode **test scenes** via MCP — TestBootstrap prefab, TestScope, TestInstaller, stub." |
| `unity-test-runner` (agent) | "Writes EditMode/PlayMode tests AND **executes** them via MCP `run_tests`." |
| `/create-test` | "Unified test generator — routes to EditMode / ECS / Programmatic / Scene; builds full infra." |
| `/generate-tests` | "Write missing tests for an existing class." |

**What genuinely differs:** `tester` = pure C# test authoring (no MCP); `unity-test-builder` = scene + bootstrap scaffolding via MCP (the heavy PlayMode-Scene path); `unity-test-runner` = authoring **plus execution**. `/create-test` is the router that picks the test type and builds infra; `/generate-tests` is a simpler "fill in missing tests for one class" entry.

**Recommendation: KEEP `tester`, `unity-test-builder`, `/create-test`; flag `unity-test-runner` for DOCUMENT-BOUNDARY.** `unity-test-runner` overlaps `tester` (both write tests) and `unity-test-builder` (both use MCP) and is **spawned by no command** (dynamic-only). Its unique value is *executing* tests — but `/create-test` does not use it, and `unity-verifier` already runs tests via MCP. This is the cluster's weakest member. Do **not** remove (it's a valid user-invokable agent), but document its niche or consider folding test-execution into `unity-verifier`. Similarly, `/generate-tests` vs `/create-test` overlap; `/create-test` is the superset — consider documenting `/generate-tests` as the lightweight subset.

### Cluster 4 — Planners (3 commands + 1 agent + built-in `Plan`)
| Member | One-line role |
|--------|---------------|
| `/create-plan` | "Researcher → planner (opus) → reviewer → save → optional implementer." |
| `/update-plan` | "Analyzer → planner → reviewer → save — modify an existing plan." |
| `/plan-workflow` | "Workflow Planner Agent — produces WORKFLOW.md for `/orchestrate`." |
| `lean-planner` (agent) | "Compact 3-5 task plan; used by `/create-plan --lean`; no skeletons/criteria." |
| `Plan` (FleetView built-in) | Architect agent for implementation strategy — not a repo file. |

**What genuinely differs:** `/create-plan` (new plan) vs `/update-plan` (revise plan) is a clean create/edit split. `/plan-workflow` outputs a different artifact (WORKFLOW.md for orchestration), not a task plan. `lean-planner` is a *mode* of `/create-plan`/`/update-plan` (the `--lean` flag), not a standalone command.

**Recommendation: KEEP-all-distinct.** Each produces a different artifact or lifecycle stage. No redundancy.

### Cluster 5 — Scene setup / hierarchy (2 commands-pair + several agents)
| Member | One-line role |
|--------|---------------|
| `/scene-setup` | "Coder + unity-setup → verifier → reviewer → committer — build a scene from a description." |
| `/update-scene-hierarchy` | "Reorganize containers only; does NOT convert bare GOs to prefabs." |
| `/unity-scene-update` | "Full audit: reorganize containers AND convert bare GOs to prefabs." |
| `/create-prefab-scene` | "Legacy migration: scan scenes for bare GOs, build prefab inventory, create prefabs." |
| `unity-setup` (agent) | "Scene + prefab config via MCP — 6-container hierarchy, logic/visual split." |
| `unity-scene-builder` (agent) | "Scene composition via MCP — hierarchy, lighting, camera, volumes." |

**What genuinely differs:** `/update-scene-hierarchy` (containers only) vs `/unity-scene-update` (containers + prefab conversion) is an explicit superset/subset documented in `commands.md`. `/create-prefab-scene` targets *legacy* scenes specifically. `/scene-setup` builds *new* scenes. Agent-wise, `unity-setup` (full setup incl. prefabs, ScriptableObjects, Input wiring) overlaps `unity-scene-builder` (scene composition only), and **`unity-scene-builder` is spawned by no command (dynamic-only).**

**Recommendation: KEEP commands distinct; DOCUMENT-BOUNDARY for `unity-scene-builder` vs `unity-setup`.** The commands are a coherent build/reorganize/migrate matrix. The agent overlap (`unity-scene-builder` ⊂ `unity-setup`) is the weak point — `unity-scene-builder` has no MCP-less unique capability that `unity-setup` lacks, and nothing spawns it. Document its niche or note it as redundant-but-user-invokable.

### Cluster 6 — Scouts / linters / explorers
| Member | One-line role |
|--------|---------------|
| `unity-scout` (haiku) | "Fast codebase exploration — structure, files, dependencies." |
| `unity-linter` (haiku) | "Quick rule-compliance validation pass — naming, regions, hooks." |
| `Explore` (FleetView built-in) | Read-only fan-out search agent — not a repo file. |

**What genuinely differs:** `unity-scout` = *find* things (exploration); `unity-linter` = *check* things (rule compliance). Different jobs despite both being haiku read-only scanners. `Explore` is a built-in, not a repo agent.

**Recommendation: KEEP-distinct.** Exploration vs linting are genuinely different mechanical passes.

**Bonus overlap — performance:** `unity-optimizer` (agent, dynamic-only) vs `/performance-audit` (command). The command exists for hot-path/allocation auditing; the agent does profiler-guided optimization via MCP. They overlap conceptually but `/performance-audit` does not spawn `unity-optimizer`. **DOCUMENT-BOUNDARY.**

---

## 5. Recommended actions (prioritized by confidence)

1. **[DOCUMENT-BOUNDARY] Add `/build-knowledge-graph` and `/knowledge-graph` to `docs/commands.md`.** *High confidence.* Both are real command files, heavily referenced (8 and 5 files incl. CLAUDE.md), but absent from the canonical command list. Pure documentation fix, zero risk.

2. **[DOCUMENT-BOUNDARY] Fix the stale `/unity-workflow` reference** in `unity-critic.md` and `unity-verifier.md` descriptions. *High confidence.* No `/unity-workflow` command exists (the loop command is `/ralph`). Update the descriptions to point at the real commands (`/architect` for `unity-critic`, `/ralph` + pipelines for `unity-verifier`).

3. **[DOCUMENT-BOUNDARY] Add a reviewer decision note to `agents-index.md`** distinguishing `reviewer` (MCP runtime validation) from `unity-reviewer` (static read-only). *Medium-high.* These two opus reviewers are the murkiest overlap; a one-line table prevents misuse. No removal.

4. **[DOCUMENT-BOUNDARY] Clarify the niche of the 9 dynamic-only agents** (`unity-build-runner`, `unity-network-dev`, `unity-optimizer`, `unity-prototyper`, `unity-scene-builder`, `unity-security-reviewer`, `unity-test-runner`, `unity-ui-builder`, `unity-ui-toolkit-builder`) in `agents-index.md` — explicitly mark them "user-invoked only; not spawned by any command." *Medium.* Prevents the false impression that they're wired into pipelines.

5. **[DOCUMENT-BOUNDARY] Note `unity-test-runner` and `unity-scene-builder` as overlapping subsets.** *Medium.* `unity-test-runner` ⊂ (`tester` + `unity-verifier`); `unity-scene-builder` ⊂ `unity-setup`. They are the two clearest redundancy candidates, but both are valid user-invokable agents — document, do not remove.

6. **[KEEP] The fixer cluster (`/fix`, `/fix-deep`, `/fix-codex`, `/debug-session`, `/five`).** *High confidence keep.* Intentional evidence/cost tiering, already documented. No action.

7. **[KEEP] The planner cluster and scene-command matrix.** *High confidence keep.* Each produces a distinct artifact or targets a distinct lifecycle stage (create/update/workflow; new/reorganize/migrate).

8. **[KEEP] Everything not flagged above.** All core pipeline agents (coder, unity-coder, reviewer, debugger, tester, committer, etc.) are heavily referenced and live.

**No [SAFE-REMOVE] actions are recommended.** Nothing in this repo can be *proven* unreferenced: every agent appears in the catalog and every command is referenced ≥ 2 times. The repo's FleetView-overlay model means a command-spawn count of 0 does not imply an agent is unused.

---

> **Advisory note:** This audit is read-only and descriptive. No agent, command, hook, doc, or config file was created, deleted, moved, or edited (except this report at `docs/AUDIT_agent_command_sprawl.md`). "0 references found" is data; every "recommendation" above is judgment. Verify behavioral overlap by reading full agent bodies before acting on any DOCUMENT-BOUNDARY suggestion.
