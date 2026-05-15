## Commands (slash commands)

### Pipelines (multi-agent)
- `/implement <task>` — **complexity score** → test writer → **unity-coder** → **unity-verifier** (compile + tests via MCP) → reviewer priority: **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → **silent failure audit** (changed files) → committer
- `/fix <bug>` — **complexity score** → Step 1: **unity-fixer** + **unity-scout** simultaneously (complexity ≥ 0.4) → test writer → **unity-coder** → **unity-verifier** (compile + tests via MCP) → reviewer priority: **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → **silent failure audit** (changed files) → committer
- `/fix-deep <bug>` — **complexity score** → **evidence-first pipeline**: log intake (file / text / MCP) → hypothesis → debug injection → Step 3: **unity-fixer** + **unity-scout** simultaneously (complexity ≥ 0.4) → **evidence gate** (proven / refuted / inconclusive) → fix only if proven → validator → reviewer → **silent failure audit** (changed files) → committer; refuses to fix if root cause cannot be proven
  - Use for: logic bugs, "sometimes happens" issues, wrong values at runtime, NullRef with unclear source
  - Use `/fix` when: stack trace clearly points to root cause
- `/scene-setup <description>` — **complexity score** → **unity-coder-lite** (Simple) / **unity-coder** (Medium/Complex) + unity-setup → **unity-verifier** → **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → committer
- `/migrate <pattern> in <scope>` — **complexity score** → [test guard if Medium/Complex] → **migrator** / **unity-migrator** → reviewer → [unity-developer if score ≥ 0.7] → committer
- `/create-plan <file> <what>` — researcher → **complexity-aware planner** (opus, assigns `parallel_group` to independent tasks) → reviewer → save → optional implementer (parallel spawn for grouped tasks if complexity ≥ 0.4)
- `/update-plan <file> <change>` — analyzer → planner (opus, updates `parallel_group` annotations) → reviewer → save → optional implementer (parallel spawn for grouped tasks if complexity ≥ 0.4)
- `/smart-commit` — analyze dirty working tree → group into logical commits → commit
- `/orchestrate` — **complexity score** → read WORKFLOW.md → check `parallel_group` annotations → per-task: **coder** (pure C#) / **unity-coder-lite** (Simple Unity) / **unity-coder** (Medium/Complex Unity) → **unity-verifier** → **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → committer; tasks with same `parallel_group` run simultaneously (complexity ≥ 0.4); phase gate runs **ralph → silent-failure-hunt → validate** automatically before asking to proceed; emits `VERIFICATION_PASSED` event on success

> Reviewer priority: Codex → unity-reviewer (falls back to unity-reviewer if Codex is unavailable).

### Project Setup
- `/setup-project` — **Step 0:** detect existing state, compare against `project-features.json` (if any), offer sync-only mode on conflict. **Step 1:** ask feature questions (Addressables / Testing / ECS) + package gates. Generates folder structure, .asmdef files, base framework classes, and manual checklist. Writes `.claude/project-features.json`, removes disabled hooks from `settings.json`, adds `## Project Features` header to `CLAUDE.md`.
- `/create-prefab-scene` — **Legacy migration:** scan existing scenes for bare GameObjects, build a prefab inventory, create proper prefabs via MCP, review, commit. Use for scenes built before the prefab rules were in place.

### Design & Architecture
- `/game-idea` — Refine a raw game idea into a GDD (includes assumption surfacing + "Not Doing" list)
- `/architect` — Create a Technical Design Document from a GDD (auto-runs Phase 7 self-critique → **unity-critic** adversarial challenge → developer review)
- `/grill-me [plan or file]` — Stress-test a plan or design decision — asks one pointed question at a time, offers a recommended answer, resolves every branch; ends with a Decision Record
- `/refine-gdd` — Iterate on an existing GDD
- `/refine-tdd` — Iterate on an existing TDD

### Development
- `/plan-workflow` — Create a phased execution plan from a TDD — assigns integer `parallel_group` numbers (1, 2, `—`) compatible with `/orchestrate`; compile-time type dependencies force sequential even across different files
- `/new-module` — Generate the 5-file module structure (Interface, Service, Config, Installer, Events)

### Quality
- `/review-code` — Code review on specific files via **unity-reviewer**
- `/validate` — Validate a completed phase; **unity-verifier** via MCP tried first, dotnet CLI fallback
- `/check-portability` — Audit a module for copy-paste portability
- `/clean-slop` — Remove AI-generated bloat (dead code, useless abstractions)
- `/learn` — Extract project-specific patterns into `.claude/skills/learned/` + generates `PROMPTS.md` documenting the workflow
- `/discover [--dry-run|--write] [--only <pkg>]` — Walk `Packages/manifest.json`, summarize each Unity package, and emit per-package skill drafts to `.claude/skills/third-party/<pkg>/`. Small packages produce a single `SKILL.md`; large packages (50+ prefabs) produce a multi-file folder (`SKILL.md`, `api.md`, `prefabs.md`, `integration.md`, `test-strategy.md`, `samples.md`). Supports `--dry-run` (default), `--write`, `--only <pkg>`, `--include-assets-plugins`.
- `/generate-tests` — Write missing tests for an existing class
- `/create-test <FeatureName>` — Unified test generator: runs test-type-router to determine EditMode / PlayMode-ECS / PlayMode-Programmatic / PlayMode-Scene, then generates the full test infrastructure for the chosen type. EditMode → NSubstitute unit test. PlayMode-ECS → isolated World test. PlayMode-Programmatic → `new GameObject().AddComponent<>()` lifecycle test, no scene. PlayMode-Scene → TestScope + TestInstaller + test stub + scene via MCP.
- `/graphics-setup <mobile|pc>` — Show tier plan (Low/Medium/High), await approval, create URP Pipeline Assets + Renderer Data + URPQualityConfiguration via MCP, wire into Quality Settings, commit option
- `/audio-clip-setup [path]` — Scan AudioClip assets, categorize (Music/SFX/UI/Voice), apply optimized import settings via temp Editor script + MCP; reports per-clip changes + summary + commit option
- `/performance-audit` — Audit files for allocations and hot-path violations
- `/debug-session` — Structured root cause analysis; routes to **unity-fixer** (complex) or **unity-fixer-lite** (scoped) after root cause; **learner** skill runs on completion
- `/silent-failure-hunt` — Audit files for swallowed exceptions and silent error patterns
- `/ralph` — Relentless verify-fix loop (max 10 outer iterations) — refuses to stop until compile and tests are green or stuck is detected
- `/qa` — Full quality pipeline: **ralph** (compile + tests) → **silent-failure-hunt** → **validate** — run after any implementation, accepts `--phase N` and `--files <path>`

### Session & Context
- `/caveman` — Ultra-compressed communication mode (~75% fewer tokens). Drops filler, keeps technical accuracy. Exit with `/normal`.
- `/checkpoint` — Save current conversation summary to `.claude/state/checkpoint.md`, then run `/clear` to free context; next session auto-reads the checkpoint and resumes
- `/context-prime` — Brief Claude on project context at the start of a session
- `/search <query>` — **complexity score** → Phase 1: **Explore** + **unity-scout** simultaneously (complexity ≥ 0.4) → write findings to `.claude/state/search-findings.md` → Phase 2: reviewer validates **completeness** (COMPLETE / INCOMPLETE / REJECT, max 5 iter) → Phase 3: present findings to user → Phase 4: **action router** recommends next command (`/fix`, `/fix-deep`, `/implement`, `/create-plan`, `/update-plan`, or no action) — never executes automatically
- `/dump` — Save current session notes to `.claude/logs/` as markdown
- `/five` — 5 Whys root cause analysis for a bug or architectural problem
- `/continue` — Resume an interrupted orchestration run from the event journal (picks up where it left off)
- `/status` — Report current pipeline stage: GDD → TDD → WORKFLOW progress summary
- `/dry-run` — Preview the orchestration plan for a WORKFLOW.md without executing any tasks
- `/instincts` — Manage instinct library: status, list, evolve, promote, export, import

### Changelog
- `/create-changelog` — Create or update `CHANGELOG.md` with recent changes

### Diagrams
- `/mermaid` — Generate a Mermaid architecture diagram for a module or system

### Documentation
- `/catch-up` — Generate a human-readable codebase guide (`docs/CATCH_UP.md`)
- `/adr <decision>` — Record an Architecture Decision (e.g. `/adr why VContainer over Zenject`); writes to `docs/decisions/NNN-topic.md`
- `/update-claude-md [--section hooks|rules|commands|agents]` — Sync CLAUDE.md tables with actual project state (settings.json hooks, rules/ files, commands/ files, agents/ files). Shows diff, waits for confirmation before writing.
