# PLAN — Template Consolidation & Portability

> **Version:** v2 — 2026-06-11 — review feedback applied: End State added, T2 agent decisions made, T3 flag mechanism defined, T6 corrected (gateguard.sh is the fact-forcing hook, not director gates), T8 fixture location fixed, T13 license blocker resolved, T1→T5 cross-phase dependency made explicit
> **Previous Version:** v1 — 2026-06-11
> **Status:** Draft — not started
> **Scope:** `.claude/commands/`, `.claude/agents/`, `.claude/docs/`, `.claude/hooks/`, `.claude/rules/`, `.claude/skills/`, `install.sh`, `update.sh` (new), `.github/workflows/`, `docs/SETUP.md`
> **Out of scope:** Graph module changes (PreToolUse consult hook, Obsidian export) — explicitly excluded by decision 2026-06-11.

## Context

The template is mature (57 commands, 36 agents, 49 hooks, 16 rules, ~74 skill files) but an external review surfaced structural problems that hurt its core promise — "drop into any Unity project, AI is integrated":

1. **Command/agent sprawl.** 4 fix variants (`/fix`, `/fix-lite`, `/fix-deep`, `/fix-codex`), 2 implement variants, and 5+ overlapping coder agents (`unity-coder`, `unity-coder-lite`, `coder`, `unity-developer`, `unity-prototyper`). Variants should be flags + model-tier routing, not separate files. Every duplicate is a maintenance liability and decision-fatigue source.
2. **No update path.** `install.sh` copies once. There is no version stamp in the target project, no `update.sh`, no 3-way merge. After installing into 3 projects, template improvements cannot be propagated — the single most critical gap for a template.
3. **Hard-coded stack.** Hooks block singletons and legacy input unconditionally, but real projects (e.g. GoodsPuzzle: SystemLocator + LeanTouch + Unity 2022.3) use different stacks. The result today is manual forking and config drift. `project-features.json` covers addressables/testing/ecs/graph but not DI or input choice.
4. **No Windows support.** All hooks and `install.sh` are bash with GNU-isms. Most Unity developers are on Windows.
5. **No Unity CI.** `claude-pr-review.yml` only runs Claude review. The testing feature is enabled but nothing runs the tests in CI.
6. **Blocking hooks under-tested.** Only 10/49 hooks have bats tests. A false-positive blocking hook halts every pipeline.
7. **Content duplication.** `bootstrap-pattern`, `scene-hierarchy`, event patterns exist in both `.claude/rules/` and `.claude/skills/core/` — drift is guaranteed.

## End State

When all phases are complete: a developer on macOS **or** Windows (Git Bash) clones the template, runs `./check-env.sh` (pass/fail table of dependencies), then `./install.sh /path/to/UnityProject`. Install writes a version manifest into the target. `/setup-project` asks 6 questions (addressables, testing, ecs, graph, **di**, **input**) and the hook/rule set adapts — a SystemLocator + LeanTouch project gets no false blocks. The developer sees ≤ 30 commands and ≤ 22 agents, each with one unambiguous role; depth variants are flags (`/fix --deep`). Months later, after the template improves, they run `./update.sh /path/to/UnityProject --dry-run`, review the action table, then run it for real — their customizations survive, conflicts surface as `.template-new` files. Every PR on their project runs Unity tests via game-ci (if testing enabled) and every PR on the template runs bats tests covering 100% of blocking hooks. In `minimal` hook profile, only COMMIT_GATE interrupts the flow.

## Goals

- [ ] G1 — Reduce commands from 57 to ≤ 30 and agents from 36 to ≤ 22 with zero capability loss (variants become flags / model tiers).
- [ ] G2 — Single source of truth for every rule: `rules/` holds the content, `skills/` holds an `@`-reference stub, never a copy.
- [ ] G3 — Ship `update.sh` with a hash-manifest 3-way merge so installed projects can pull template updates safely.
- [ ] G4 — Extend `project-features.json` with `di` and `input` keys; all stack-specific hooks and rules honor them.
- [ ] G5 — Windows compatibility: platform detection in `_lib.sh`, portable replacements for GNU-only constructs, documented Git Bash requirements, `check-env.sh` preflight.
- [ ] G6 — Add game-ci GitHub Actions workflow (EditMode + PlayMode test runner) gated on the `testing` feature.
- [ ] G7 — bats coverage for 100% of blocking (exit-2) hooks; bats job added to CI.
- [ ] G8 — Director Gates become profile-aware: `minimal` profile keeps only COMMIT_GATE; `standard` keeps SCOPE + COMMIT; `strict` keeps all 7.

## Phases

| Phase | Task | Status | parallel_group | Risk |
|-------|------|--------|----------------|------|
| 1 | T1 — Reference audit: who spawns what | pending | P1 | low |
| 1 | T2 — Dedupe map + deprecation policy | pending | P1 | low |
| 2 | T3 — Merge command variants into flags | pending | — | **high** (breaks muscle memory + docs) |
| 2 | T4 — Merge agent variants via model-tier routing | pending | — | **high** (subagent_type strings referenced in commands, hooks, agents-index) |
| 2 | T5 — Rules/skills dedupe (single source) | pending | P2 | medium |
| 2 | T6 — Gate-profile binding | pending | P2 | low |
| 3 | T7 — Version stamp in install.sh | pending | — | low |
| 3 | T8 — update.sh with 3-way merge | pending | — | medium |
| 4 | T9 — Stack feature flags (di / input) | pending | — | medium |
| 4 | T10 — Hook + rule conditionalization | pending | — | medium |
| 5 | T11 — Windows portability pass | pending | P5 | medium |
| 5 | T12 — check-env.sh preflight | pending | P5 | low |
| 5 | T13 — game-ci workflow | pending | P5 | low |
| 5 | T14 — bats coverage for all blocking hooks + CI job | pending | P5 | low |

Phase order rationale: Phase 1–2 (pruning) first — everything later (update manifest, conditionalization, tests) gets cheaper when there are fewer files. Phase 3 (update path) before Phase 4 so the stack-flag changes are the first update that installed projects pull.

**Cross-phase dependencies (explicit):**
- T3, T4, T5 are all `blockedBy: T1 + T2 approval`. T2's dedupe map is a human approval point (BREAKING_REVISION_GATE semantics): if T1's reference scan contradicts the proposed merge table — e.g. an agent assumed mergeable turns out to be spawned by 6 commands with divergent prompts — the map is revised and re-approved **before** any Phase 2 file changes. This is the designed stall point; stalling here is cheap, stalling mid-T4 is not.
- T8 `blockedBy: T7` (manifest format), T14 partially `blockedBy: T6 + T8` (tests those outputs).
- Phase 4/5 tasks have no dependency on Phase 2 outcomes except final doc-table regeneration.

---

## Task Details

### Phase 1 — Audit (no file changes)

**T1 — Reference audit.**
Produce `docs/audit-references.md`:
- For every agent: which commands/docs/hooks reference its `subagent_type` string (`grep -rn "subagent_type" .claude/commands .claude/docs .claude/hooks` + `agents-index.md`).
- For every command: which agents it spawns, which gates it fires, which other commands reference it.
- For every skill in `skills/core/`: does an equivalent rule exist in `rules/`? List exact overlap pairs.
- Output: three tables (agents, commands, rule/skill overlaps). No judgment yet — raw data.

**T2 — Dedupe map.**
From T1, produce the merge decision table in `docs/audit-dedupe-map.md`. Proposed starting point (validate against T1 data):

| Keep | Absorb | Mechanism |
|------|--------|-----------|
| `/fix` | `/fix-lite`, `/fix-deep`, `/fix-codex` | `--lite` / `--deep` / `--codex` flags; complexity score already routes depth |
| `/implement` | `/implement-lite` | `--lite` flag |
| `unity-coder` | `unity-coder-lite`, `coder` | calling command passes `model` param on the Agent tool (haiku/sonnet for lite path) |
| `unity-fixer` | `unity-fixer-lite` | same |
| `unity-developer` | **KEEP — decided 2026-06-11.** Read-only reviewer/consultant (tools: Read, Glob, Grep, Bash — no Write/Edit). Role sentence passes the no-AND test: "reviews code and plans for Unity-specific concerns." Action: clarify its description frontmatter so the reviewer-not-implementer boundary is explicit; do NOT rename (reference churn not worth it) | — |
| `unity-prototyper` | **KEEP — decided 2026-06-11.** Overlaps unity-coder superficially (both write code + use MCP) but intent differs: prototyper = gate-free rapid throwaway prototype, coder = production feature under pipeline/gates. Action: add one line to each description stating this boundary | — |
| `/smart-commit` | `/smart-commit-selected` | `--select` flag |
| `/update-scene-hierarchy` | absorbed by `/unity-scene-update` | already a subset per CLAUDE.md description |

Deprecation policy: deleted command files are replaced for one release by a 5-line stub that prints "moved to /fix --lite" and exits — then removed. Agent files cannot stub (subagent_type lookup), so T4 must update **every** reference atomically in one commit.

### Phase 2 — Consolidation

**T3 — Command merges.** Apply T2 map.

*Flag mechanism (decided 2026-06-11):* flags are literal tokens typed by the user (`/fix --lite <bug>`) and arrive inside `$ARGUMENTS` as plain text. There is no parser — the command markdown itself resolves the mode. Every merged command starts with a mandatory `## Mode Resolution` section:

```
## Mode Resolution
Inspect $ARGUMENTS for these exact tokens, then strip them from the task text:
- contains "--lite"  → LITE mode (skip steps marked [FULL], spawn agents with model: haiku)
- contains "--deep"  → DEEP mode (evidence-first pipeline below)
- contains "--codex" → CODEX mode
- multiple flags     → precedence: --deep > --codex > --lite; warn the user which one won
- no flag            → default: complexity score routes depth (existing behavior)
```

Pipeline steps in the body are tagged `[FULL]` / `[DEEP-only]` etc. This is the same LLM-interpreted-but-deterministic instruction style the commands already use for `$ARGUMENTS`; no new infrastructure.

Each merged command:
1. Add `## Mode Resolution` header; move variant-specific pipeline steps behind mode tags.
2. Update `commands.md`, `quick-start.md`, `CLAUDE.md` command table.
3. Add stub files per deprecation policy.
Acceptance: `ls .claude/commands | wc -l` ≤ 30 (stubs excluded); every flag documented in the command's own Mode Resolution section; `/fix --lite` dry-run visibly skips `[FULL]` steps.

**T4 — Agent merges.** Apply T2 map. For each absorbed agent:
1. `grep -rn "<agent-name>"` across `.claude/` — update every spawn site, `agents-index.md`, `guard-reviewer-order.sh`, `guard-gate-cleared.sh` (both hooks match agent names).
2. Model tier is selected by the *calling command* via the Agent tool `model` param — not by duplicating the agent file.
Acceptance: `ls .claude/agents | wc -l` ≤ 22; `grep -rn "unity-coder-lite" .claude/` returns nothing; one full `/implement` dry-run passes.

**T5 — Rules/skills dedupe.** For each overlap pair from T1: `rules/<x>.md` keeps the content; `skills/core/<x>.md` becomes a ≤ 5-line stub with an `@.claude/rules/<x>.md` reference plus skill-specific trigger metadata only. Update `skills-index.md`.
Acceptance: no rule content exists in two places (verify by diffing section headers).

**T6 — Gate-profile binding.**

*Correction (2026-06-11):* `gateguard.sh` exists but is the **fact-forcing hook** for C# edits (DENY→FORCE→ALLOW) — unrelated to Director Gates. It is NOT touched by this task. Director Gates live in two places: (a) prompt-level gate sections inside the pipeline command files, (b) enforcement in `guard-gate-cleared.sh` via the `state/gate-cleared` file.

Implementation:
1. `guard-gate-cleared.sh` reads `UNITY_HOOK_PROFILE` and only enforces the gates required for the active profile:
   - `minimal` → only COMMIT_GATE
   - `standard` (default) → SCOPE_GATE + COMMIT_GATE
   - `strict` → all 7 gates
2. Each pipeline command's gate sections get a profile guard line: "Skip this gate if the active profile does not require it (see director-gates.md profile table)." Commands determine the profile via `bash -c 'echo "${UNITY_HOOK_PROFILE:-standard}"'`.
3. `director-gates.md` gets a Profile column; CLAUDE.md gate table updated.
Acceptance: bats test per profile asserting which gates `guard-gate-cleared.sh` enforces; manual `/implement` run under `minimal` reaches coder spawn with only COMMIT_GATE pending.

### Phase 3 — Update path

**T7 — Version stamp.** `install.sh` additionally writes `.claude/.template-meta.json` into the target:
```json
{
  "template_version": "<from plugin.json>",
  "template_commit": "<git rev-parse HEAD of template repo>",
  "installed_at": "<ISO date>",
  "files": { "<relpath>": "<sha256>", ... }
}
```
`files` covers everything install.sh copied. Excluded from manifest: `settings.json`, `project-features.json`, `state/`, `skills/learned/`, `skills/plugins/`.

**T8 — update.sh.** Usage: `./update.sh /path/to/UnityProject [--dry-run] [--force]`. Per file, classic 3-way:

| Local hash vs manifest | Template hash vs manifest | Action |
|---|---|---|
| unchanged | changed | overwrite (clean update) |
| changed | unchanged | keep local (user customization) |
| changed | changed | **conflict** — write `<file>.template-new` next to it, list at end |
| missing locally | any | copy (new file) |
| in manifest, removed in template | unchanged locally | delete; if changed locally → list as orphan, keep |

Never touches the exclusion list from T7. `--dry-run` prints the action table without writing. Rewrites the manifest at the end.

*Fixture (decided 2026-06-11):* no committed fixture tree. A committed generator script `.claude/hooks/tests/fixtures/make-update-fixture.sh` builds a minimal fake template (5 files — one per merge-table row) and a fake installed project with manifest into `$BATS_TEST_TMPDIR` from the bats `setup()` function. Deterministic, no repo clutter, regenerated per test run.
Acceptance: bats test exercises all 5 action-table rows against the generated fixture, plus one exclusion-list row (settings.json untouched even when changed in template).

### Phase 4 — Stack adaptation

**T9 — Feature flags.** Extend `project-features.json`:
```json
{ "di": "vcontainer | service-locator | none",
  "input": "new-input-system | leantouch | legacy" }
```
`/setup-project` asks both questions (defaults: `vcontainer`, `new-input-system` — current behavior unchanged for existing installs; missing keys = defaults). `_lib.sh` gets `feature_get <key>` helper reading the JSON once per hook run.

**T10 — Conditionalization.** Hooks:
- `check-vcontainer-singleton.sh` → exit 0 immediately when `di != vcontainer`
- `check-input-system.sh` → when `input == leantouch`, block legacy Input API but stop requiring New Input System; when `legacy`, downgrade to warn
Rules: `architecture.md`, `bootstrap-pattern.md`, `unity-input.md` get a one-line header: "Applies when `di: vcontainer`" / "Applies when `input: new-input-system`" and CLAUDE.md `## Project Features` table documents the skip, mirroring the existing addressables/ecs pattern. Do NOT write parallel rule sets for service-locator — out of scope; the flag only disables enforcement that would block such projects.
Acceptance: with `di: service-locator`, writing a `static Instance` produces no block; with defaults, behavior identical to today.

### Phase 5 — Platform & CI

**T11 — Windows portability.** Audit all 49 hooks + install.sh + update.sh for: `stat -c` (vs `stat -f` / portable `wc -c`), `sed -i` without suffix, `readlink -f`, `date -d`, process substitution requirements, hard-coded `/tmp`, `python3` (fallback `py -3`). Add `detect_platform()` to `_lib.sh` (`uname -s` → `msys*/cygwin*/mingw*` = windows). Fix or guard each occurrence. Document in `docs/SETUP.md`: Git Bash required, Python 3.10+ on PATH, optional WSL note.
Acceptance: `grep -rn "stat -c\|sed -i[^']\|readlink -f\|date -d\|/tmp/" .claude/hooks install.sh update.sh` returns nothing (all occurrences fixed or guarded); key hook scenarios (blocking a singleton write, gate enforcement) run without error on Git Bash 4.x.

**T12 — check-env.sh.** Preflight script run by install.sh and standalone: verifies bash ≥ 4, git, python3/py, jq (if used), grep -P availability; prints a pass/fail table; exit 1 on missing hard deps. Acceptance: runs clean on macOS and Git Bash.

**T13 — game-ci workflow.** `.github/workflows/unity-tests.yml`:

*License blocker — resolved (decided 2026-06-11):* the plan accepts the **Personal license** flow. game-ci supports Unity Personal via one-time manual activation: generate `.alf` with `game-ci/unity-request-activation-file`, upload at license.unity3d.com, store the resulting `.ulf` content as the `UNITY_LICENSE` repo secret. No Pro license required. Consequences baked into the design:
- Workflow ships with `workflow_dispatch` as the only trigger by default; PR/push triggers are a documented one-line uncomment **after** the secret exists. The template never ships a red-by-default CI.
- First job step checks `secrets.UNITY_LICENSE` is non-empty; if absent, exits 0 with a notice ("Unity CI not activated — see SETUP.md §License") instead of failing.
- SETUP.md gets the exact 5-step activation procedure (alf → ulf → secret), including the Personal-license caveat that the ulf is machine-independent for game-ci docker images.

Jobs: `game-ci/unity-test-runner@v4` with `testMode: EditMode` and `PlayMode`, `projectPath` from `unity_project_folder`, `Library/` cache keyed on `Packages/packages-lock.json`. Skipped entirely when `project-features.json` `testing == false` (read in a setup step).
Acceptance: actionlint passes; `workflow_dispatch` run without secret exits green with the notice; with secret, tests execute on a sample project.

**T14 — bats for all blocking hooks.** Inventory exit-2 hooks (block-*, guard-*, gateguard, check-config-protection, enforce-skill-for-keywords, check-no-runtime-instantiate, guard-editor-runtime, block-scene-edit, block-projectsettings, block-git-push, check-ls-grep). One bats file per hook: at minimum 1 blocking case + 1 passing case + 1 profile-downgrade case (`UNITY_HOOK_MODE=warn`). New `.github/workflows/hooks-test.yml` (ubuntu, bats-core) — also runs the T8 update.sh fixture test. Acceptance: every exit-2 hook has a test; CI green.

---

## File Map

| File | Change | Task |
|------|--------|------|
| `docs/audit-references.md` | Create | T1 |
| `docs/audit-dedupe-map.md` | Create | T2 |
| `.claude/commands/*` (≈30 files) | Merge/stub/delete | T3 |
| `.claude/agents/*` (≈14 files) | Merge/delete + reference updates | T4 |
| `.claude/skills/core/*` (overlap pairs) | Reduce to stubs | T5 |
| `.claude/hooks/guard-gate-cleared.sh`, pipeline command files, `.claude/docs/director-gates.md` | Edit | T6 |
| `install.sh` | Edit — write manifest | T7 |
| `update.sh` | Create | T8 |
| `.claude/commands/setup-project.md`, `.claude/hooks/_lib.sh` | Edit | T9 |
| `.claude/hooks/check-vcontainer-singleton.sh`, `check-input-system.sh`, 3 rule files, `.claude/CLAUDE.md` | Edit | T10 |
| `.claude/hooks/*` (portability fixes), `docs/SETUP.md` | Edit | T11 |
| `check-env.sh` | Create | T12 |
| `.github/workflows/unity-tests.yml` | Create | T13 |
| `.claude/hooks/tests/*.bats`, `.github/workflows/hooks-test.yml` | Create | T14 |

## Constraints & Reminders

- `settings.json` cannot be edited by Claude — any hook registration changes from T6/T10 are listed as **[MANUAL: settings.json]** steps at the end of each task.
- T4 is the highest-risk task: agent renames must land in a single commit with a full reference grep, and `guard-reviewer-order.sh` / `guard-gate-cleared.sh` agent-name lists must be updated in the same commit.
- After Phases 2–4, regenerate `commands.md`, `agents-index.md`, `skills-index.md`, and the CLAUDE.md tables — stale counts in `plugin.json` description too.
- Each phase = one branch, one PR, reviewed via `/review-code` before merge. Do not start Phase 3 while Phase 2 references are unmerged.
