# Instruction Loading Restructure — Design

**Date:** 2026-10-08
**Status:** Implemented — verified 2026-10-08 (results: `2026-10-08-instruction-loading-spike.md`)
**Goal:** Raise rule adherence by loading only the instructions relevant to the current work, without losing
awareness of a rule at plan time. Silencing the startup size warning is a side effect, not the goal.

## 1. Problem

Claude Code warns at session start:

> 24 instruction files add up to 469.5k chars, over the 150.0k-char total limit · largest: .claude/CLAUDE.md
> (84.9k), .claude/rules/architecture.md (47.1k), .claude/rules/ui-toolkit-runtime.md (33.4k)

Measured 2026-10-08:

| Source | Chars | Loaded |
|---|---|---|
| `.claude/CLAUDE.md` (367 lines) | 85k | launch |
| `.claude/rules/*.md` — 22 files, **none** has `paths:` frontmatter | 388k | launch |
| 14 `@` imports in CLAUDE.md (`.claude/docs/*.md`) | 137k | launch (per docs) |
| 24 nested `@` imports in `.claude/docs/auto-loaded-skills.md` (skill files) | 241k | launch (per docs) — **not in the warning's count** |

Worst case ≈ 850k chars ≈ 210k tokens before any work starts. Irrelevant rules load in every session:
3 `web-tool-*` files (68k) in C#-only sessions; `ecs-dots` and `addressables` (20k) although both features are
DISABLED in `project-features.json`.

## 2. What the research established

Four research passes (official docs, CHANGELOG, anthropics/claude-code issues, and the source of
diet103/claude-code-infrastructure-showcase, obra/superpowers, affaan-m/everything-claude-code,
thedotmack/claude-mem).

**Loading mechanics (official docs, code.claude.com):**
- The warning is advisory — issue #96506 reports full content reaching the model past 150k (user report, no
  maintainer confirmation). The documented cost is adherence: *"Longer files consume more context and reduce
  adherence."* / *"Bloated CLAUDE.md files cause Claude to ignore your actual instructions."*
- Target: CLAUDE.md under 200 lines; part-of-codebase content → path-scoped rules; procedures and reference
  material → skills (only descriptions load at launch, 1,536-char cap).
- `@` imports do not reduce cost — *"imported files also load at launch"*, each counted as a separate file.
- `paths:` is the **only** frontmatter field a rule reads — there is no `description:`-requested rule type.
  Trigger: Read / Write / Edit of a matching file (Write/Edit since 2.1.288; issue #93248 reports new-file Write
  still not triggering), single-file `cat`/`head`/`tail`/`sed -n`/`grep` via Bash (2.1.293). Not Glob, not MCP.
- Compaction drops path-scoped rules until a matching file is touched again; root CLAUDE.md is re-read.
- `SessionStart` (matchers `startup|resume|clear|compact`) and `UserPromptSubmit` can return
  `additionalContext`. `InstructionsLoaded` is observability only.
- Path-scoping has a bug history (#16299 open; #33581, #16853 fixed) — verify, do not assume.

**Prior art — no system fully solves plan-time awareness:**
- diet103: `skill-rules.json` + UserPromptSubmit regex/keyword matcher; optional LLM classifier over-triggers on
  ~1/3 of off-topic prompts (its own benchmark comment) so it is off by default. Misses prompts without keywords.
  No compaction/subagent handling.
- obra/superpowers: SessionStart with `startup|clear|compact` injects a bootstrap; survives compaction; relies on
  model compliance.
- Secondary measurement (scottspence.com, 50 runs, Haiku 4.5): plain "consider skills" instruction 20%, forced
  "state which apply" hook 84%.
- No repo injects into subagents automatically.

**Consequence:** a single mechanism leaves a gap; the best-proven combination stacks three independent nets —
an always-on index (survives compaction), prompt-keyword injection (plan time), and path triggers (edit time).

## 3. Design

### 3.1 Layers

| Layer | When loaded | Files |
|---|---|---|
| **Core** (unscoped) | launch | `CLAUDE.md` (≤200 lines), `architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern` |
| **C#** | touching `.cs` | `event-patterns`, `unity-async`, `serialization`, `unity-lifecycle`, `logging`, `save-load`, `unity-input`, `performance` |
| **Domain** | touching domain files | `testing`, `ui-toolkit-runtime`, `web-tool-*` ×3, `unity-prefabs`, `scene-hierarchy`, `ecs-dots`, `addressables`, `roadmap-milestones` |

Core stays unscoped: it decides plan-time questions (module shape, tier, folder) and must survive compaction.
Scoped rules that also drive plan-time decisions — `testing` (test-type tree), `ui-toolkit-runtime` (Card 1
UGUI vs UI Toolkit), `save-load`, `roadmap-milestones` — are covered at plan time by 3.4, not by moving them
into core (that would put core back over budget).

### 3.2 Glob mapping (draft — finalized in the plan)

All globs quoted and `**/`-prefixed so they hold when `unity_project_folder` is a subfolder.

| Rule | `paths:` |
|---|---|
| C# layer (8 files) | `"**/*.cs"` (+ `unity-input`: `"**/*.inputactions"`; `performance`: `"**/Arts/**"`, `"**/*.{mat,shader,shadergraph}"`) |
| `testing` | `"**/Tests/**"`, `"**/*Tests.cs"` |
| `ui-toolkit-runtime` | `"**/*.{uxml,uss,tss}"`, `"**/UI/**"` |
| `web-tool-*` ×3 | `"tools/**"` |
| `unity-prefabs`, `scene-hierarchy` | `"**/*.{prefab,unity}"`, `"**/Prefabs/**"` |
| `ecs-dots` | `"**/Ecs/**"` |
| `addressables` | `"**/AddressableAssetsData/**"`, `"**/*Addressable*.cs"` |
| `roadmap-milestones` | `"docs/GDD*.md"`, `"docs/TDD*.md"`, `"docs/ROADMAP.md"`, `"docs/modules/**"` |

### 3.3 CLAUDE.md → index (≤200 lines)

- The 18 dated finding narratives move **verbatim** to `docs/incidents/<topic>.md`; CLAUDE.md keeps a 1–3 line
  rule per finding plus a link. Nothing is deleted.
- `@` imports become plain backtick references (read on demand), except `orchestrate-rules.md` (2.3k,
  NON-NEGOTIABLE).
- The "Rules" table becomes the **rule index**: one line per scoped rule — file, trigger glob, the decision it
  governs ("before choosing UGUI vs UI Toolkit → `rules/ui-toolkit-runtime.md`"). This is the same text 3.4
  injects, kept in one place.

### 3.4 Three awareness nets (adopted prior art, existing hooks only)

| Net | Prior art | Implementation | New registration? |
|---|---|---|---|
| **1. Always-on index** | superpowers SessionStart `startup\|clear\|compact` | `session-restore.sh` emits the rule index as `additionalContext` on every SessionStart, including `source=compact`. Index text lives in one file (e.g. `.claude/docs/rule-index.md`) that CLAUDE.md also references. | No — the SessionStart entry has no matcher, so it already fires on every source |
| **2. Plan-time keyword injection** | diet103 `skill-rules.json` (regex only, no LLM classifier) | New hook `inject-rule-pointers.sh` at profile level `standard` (save/persist → `save-load`; UI/screen/menu/popup → `ui-toolkit-runtime`; test → `testing`; milestone/roadmap/module → `roadmap-milestones`; prefab/scene → `unity-prefabs`, `scene-hierarchy`). Injected text is forced-eval and **short**: "Before planning, Read `rules/X.md` and state which cards apply." Never the rule body. **Not** folded into `enforce-skill-for-keywords.sh`: that hook declares `HOOK_PROFILE_LEVEL="strict"`, so under the default `standard` profile `_lib.sh` exits it before any matching runs — net 2 would be dead in the default configuration. | **Yes — one UserPromptSubmit entry, added by the developer** (`check-config-protection.sh` blocks Claude from `settings.json`) |
| **3. Edit-time trigger** | `paths:` frontmatter | Built-in (3.2) | No |

Subagents (no prior art injects automatically): agents keep explicit Step 0 reads of the rule files they depend
on; the audit covers the 11 agents and 19 commands that already reference rule files by name, plus MCP-driven
agents (`unity-setup`, `unity-scene-builder`) whose tools never fire `paths:`.

Injected text stays at index/headline size. Injecting rule bodies would recreate the bloat this design removes.

### 3.5 Auto-loaded skills

`auto-loaded-skills.md` stops `@`-importing skill files and becomes a described list
(``- `path` — <frontmatter description>``). Most of the 24 files are nested (`third-party/unitask/SKILL.md`) and
are **not** discoverable as skills, so the `@` import is their only route into the main session today; removing
it without a replacement would drop them. The replacement: `session-restore.sh` injects this list together with
the rule index (net 1), and agents' Step 0 keeps reading it. `auto-load-skills.sh` writes described entries. **Coupled change, required:** `enforce-skill-for-keywords.sh`
(line ~138) currently treats a skill listed in `auto-loaded-skills.md` as "already in context" and skips
enforcement — after this change that assumption is false and enforcement would silently switch off. The skip
must be removed or keyed on actual Skill invocation (`track-skill-invocations.sh`) only.

### 3.6 Core shrink — `architecture.md` dedup

AppModules / AppScope / GameScope code and the EntryPoint section are duplicated in `bootstrap-pattern.md` and
`solid-oop.md`. Keep one copy at the owner, replace the others with a reference. Target ~47k → ~35k
(duplicated reference-prose sections below the cards: Code-First Static Module, AppScope, EntryPoint, GameScope,
IEvent code samples, Provider Pattern, No Singletons). Core after: ~20k + 35k + 29.6k + 27.3k + 26.9k ≈ 139k.

### 3.7 Behaviour from the developer's side

The developer does nothing differently and never names a rule or skill — selection is automatic.

Example prompt: *"Build a settings screen; persist sound on/off."*
1. On submit, net 2 matches "screen" and "persist" and injects: "Before planning, Read `rules/ui-toolkit-runtime.md`
   and `rules/save-load.md` and state which cards apply."
2. The plan follows them (Unity 6+ → UI Toolkit per Card 1; `SettingsSaveData` with `int Version`).
3. The first `.cs` / `.uxml` touched loads the C# and UI layers via `paths:`.
4. After `/compact`, net 1 re-injects the index.

A prompt with no keyword ("tweak this a bit") skips net 2; nets 1 and 3 still apply. Residual risk, measured in
Phase 7.

## 4. Constraints

- **Rule file names and Card numbers do not change.** 30+ files reference them by name and card number.
- Content hooks are unaffected — they reference rule files only in message strings.
- Exactly one `settings.json` change: the UserPromptSubmit entry for `inject-rule-pointers.sh`, added by a
  Python script the developer explicitly authorized on 2026-10-08 (this entry only). Net 1 needs none: the SessionStart entry
  for `session-restore.sh` has no matcher and already fires on every source.
- `architecture.md` headings referenced from other files stay: Scripts/ Folder Rules, Domain Folder Convention,
  Adding a Top-Level Folder, NO GameContext / Service Locator, Handler Factory, EventBusAccessor, one-caller.
  `reviewer-fixtures/README.md` cites `architecture.md:28` (Card 1) — dedup touches only lines below the cards.

### Measurement

`reviewer-fixtures` does **not** measure this change: it hands the reviewer its criteria in the prompt, so it is
independent of which rules load. The primary measure is a new **rule-awareness probe**
(`.claude/tests/rule-awareness-probe/`): headless `claude -p --permission-mode plan` planning prompts with a
marker answer key (e.g. a settings-persistence prompt must produce `SaveData` + `Version` + `ISaveLoadService`).
Non-deterministic like the other prompt probes — run ≥3 times per prompt, before and after.

## 5. Phases

| # | Phase | Exit criterion |
|---|---|---|
| 0 | **Spike** — `paths:` on Read/Write/Edit and new-file Write (#93248); inside a subagent's own Read; after `/compact`; whether scoped rules and nested `@` imports count toward the startup total; whether `@` imports are expanded at all in this harness; whether `session-restore.sh` `additionalContext` reaches the model on `compact` | Written findings; design revised if any assumption fails |
| 1 | **Baseline** — build the rule-awareness probe, run it ≥3× per prompt, record `/context` memory totals | Numbers recorded |
| 2 | CLAUDE.md → index; incidents → `docs/incidents/`; rule-index file | ≤200 lines; every moved narrative linked |
| 3 | Imports → plain refs; `auto-loaded-skills` + `auto-load-skills.sh` + the 3.5 skip-logic fix | bats green, incl. new `enforce-skill-for-keywords.bats` |
| 4 | Awareness nets 1 and 2 (3.4) | bats: index emitted on `compact`; each keyword injects its rule path |
| 5 | `paths:` frontmatter + agent/command explicit-read audit | Each scoped rule shown loading on a matching Read |
| 6 | `architecture.md` dedup | Card numbers unchanged; references intact |
| 7 | **Verify** — `/context`, reviewer-fixtures vs baseline, compaction + subagent + plan-time prompt re-test | Warning gone; fixtures not worse than baseline |

## 6. Success criteria

1. No startup size warning; launch-loaded instruction chars < 150k, measured with `/context`.
2. Rule-awareness probe marker score not worse than the Phase 1 baseline.
3. A plan-time prompt naming save/UI/test/milestone work, with no file touched, receives the matching rule
   pointer; after `/compact` the index is present again.
4. Every scoped rule loads on its trigger; every audited command/agent reads its rule explicitly.
5. Hook bats suite green.

## 7. Out of scope

- Splitting concern-based rule files into narrower per-directory files (breaks card references).
- Renaming files or renumbering cards.
- An LLM-based intent classifier (prior art shows ~1/3 false triggers).
- Hook registrations beyond the one UserPromptSubmit entry for `inject-rule-pointers.sh`.
- Changing `enforce-skill-for-keywords.sh`'s profile level (a separate decision with its own blast radius).

## 8. Risks

| Risk | Mitigation |
|---|---|
| Scoped rule silently not loading (bug history, #93248) | Phase 0 spike + Phase 5 per-rule verification |
| Plan-time prompt without a keyword misses a rule | Net 1 (always-on index) still names it; residual risk accepted |
| Model ignores injected pointer | Forced-eval phrasing; content hooks remain the hard enforcement; measured in Phase 7 |
| Skill enforcement silently disabled by 3.5 | Coupled skip-logic fix + new bats test |
| Keyword list goes stale | Lives in one `KEYWORD_MAP`; same maintenance as today |
| Trimming changes agent behaviour with all tests green | Rule-awareness probe baseline vs after |
