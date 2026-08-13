# PLAN — Ponytail Adoption: Reuse-First Rules, Agent Step 0 Duplicate Check, and `check-duplicate-symbol.sh`

> **Version:** v1 — 2026-08-13
> **Status:** Active
> **Scope:** `.claude/` tooling layer only — `.claude/rules/csharp-unity.md`, `.claude/rules/performance.md`, code-writing agents in `.claude/agents/`, a new hook `.claude/hooks/check-duplicate-symbol.sh` + its bats test, and `.claude/settings.json` registration. No Unity runtime code (`Games/`, `_Framework/`) is touched.

**Complexity: 0.55 — Moderate.**
The standard rubric's scoring signals (new module folder, `IEventBus` event types, ECS/Addressables surface) are Unity-code-oriented and do not apply to a tooling-layer change; scoring is therefore on actual risk: ~16 files touched (11 agent markdown files + 2 rules files + hook + test + settings), a **blocking** PreToolUse hook that can produce false positives on every `Write` of a `.cs` file, and a `.claude/settings.json` mutation that can corrupt the harness config if the JSON write is not atomic/validated. Score ≥ 0.4, so a `## Chosen Approach` section is included.

## Context

The "ponytail" project is a ruleset aimed at agent laziness — its central useful insight is that agents reach for hand-rolled code and duplicate symbols instead of using what already exists. Three of its ideas transfer cleanly to this repo: (1) *prefer a built-in or already-installed package over hand-rolling*, (2) *before creating a new file, check whether the symbol already exists*, and (3) *enforce (2) mechanically rather than by exhortation*. This repo already has the substrate for all three — a Cards-based rules file, a per-agent `Step 0` preamble, a knowledge graph at `.claude/graph/graph.json`, and a mature `PreToolUse` hook library in `.claude/hooks/_lib.sh`.

**Explicit rejection — do not extend this adoption.** The rest of ponytail is deliberately NOT adopted. Its YAGNI rung, its "one-liner / smallest possible diff" rung, and its "no unrequested abstraction" rung directly contradict this repo's architecture, which is interface-first (`I*Service` in `Games/Abstracts/`, implementation in `Games/Concretes/`), 4-tier, and intentionally ceremonial at module boundaries (VContainer registration, `.asmdef` per module, `#region` discipline, an abstraction even when there is currently one implementer). Those rungs would read as "delete the interface, inline the module, skip the DI registration" — precisely the code this repo's other rules and hooks exist to prevent. A future reader who finds this plan and thinks "we adopted three ponytail rungs, we should finish the job" should stop here: the remaining rungs were evaluated and rejected on architectural grounds, not on schedule.

Current state, verified against the working tree:

- `csharp-unity.md` has a `## Cards` H2 with Cards 1, 1.1, 2, 3, 4, 5 ending at line 150, followed by `## Naming Summary` at line 151.
- `performance.md` has **no** Cards section (restructuring it is out of scope) but line 87 contains `- Pool frequently instantiated objects — \`ObjectPool<T>\` or custom pool`, whose "or custom pool" clause will contradict the new card and must be tightened.
- **`.claude/graph/graph.json` exists and is tracked by git.** It is not gitignored (only `.last-build` and `cache/file-hashes.json` are). Its committed content has `"generated_at": "2026-07-06T06:40:48Z"` and **both `.codebase.classes` and `.codebase.interfaces` are empty arrays** — this repo is a template, so the shipped graph carries no symbols.

That last point is the single most important fact driving the hook design. On a fresh clone the hook is inert for **two independent reasons**: the emptiness gate fires (both symbol arrays are length 0), and the staleness gate fires (the committed `generated_at` is over a month old relative to any realistic clone date). Either alone yields exit 0. A blocking hook that fired wrongly on a fresh clone would be strictly worse than no hook, so both gates are mandatory, not belt-and-braces. Note also that because `graph.json` is a **tracked** file, no test may mutate it in place — fixtures go through the `UNITY_GRAPH_FILE` env override (see Chosen Approach).

## Goals

- [ ] `csharp-unity.md` gains `### Card 6` teaching "prefer built-in / already-installed package over hand-rolling", with the five Unity mappings.
- [ ] `performance.md`'s "or custom pool" line is tightened so the two rules files do not disagree.
- [ ] Every code-writing agent (those with `Write`/`Edit` in `tools:`) gains a mandatory pre-write duplicate-symbol check inside its existing `Step 0`.
- [ ] New hook `.claude/hooks/check-duplicate-symbol.sh` blocks creation of a NEW `.cs` file under `Games/Abstracts/` or `Games/Concretes/` when a class/interface of the same name already exists in the graph.
- [ ] The hook degrades **silently** (exit 0) on every "we can't be sure" condition: `graph` feature off, graph file missing, empty symbol arrays, stale graph.
- [ ] `check-duplicate-symbol.bats` covers block, allow, `minimal` profile, `warn` mode, and all four degrade cases.
- [ ] The hook is registered in `.claude/settings.json` under `PreToolUse` with `"matcher": "Write"`.
- [ ] The temporary python script used to edit `settings.json` is deleted.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Add Card 6 to `csharp-unity.md` | ✅ Done | 1 |
| 1 | Task 2 — Tighten `performance.md` pooling line | ✅ Done | 1 |
| 1 | Task 3 — Re-grep authoritative agent list | ✅ Done — **20 agents, not 11** | 1 |
| 1 | Task 5 — Write `check-duplicate-symbol.sh` | ✅ Done | 1 |
| 2 | Task 4 — Add Step 0 duplicate check to each agent | ✅ Done — 20/20 | 2 |
| 2 | Task 6 — Write `check-duplicate-symbol.bats` | ✅ Done — 19 tests green | 2 |
| 3 | Task 7 — Register hook in `settings.json` (temp python script) | ✅ Done | 3 |
| 3 | Task 8 — Optional CLAUDE.md rules-table summary tweak | ✅ Done — applied (`reuse-first`) | 3 |
| 4 | Task 9 — End-to-end verification | ✅ Done — 262/262 suite green | 4 |

### Execution deviations (v1 as-built, 2026-08-13)

Three things differed from the plan as written. All are recorded here rather than silently absorbed.

1. **Task 3 found 20 code-writing agents, not 11.** The research behind this plan undercounted. Per Task 3 step 4 ("the grep is authoritative, not this plan") all 20 received the Step 0 line. The extra nine are `audio-clip-agent`, `graphics-setup-agent`, `debugger`, `unity-optimizer`, `unity-particle-designer`, `unity-shader-dev`, `unity-test-builder`, `unity-test-runner`, `unity-verifier`. Several of these (import settings, URP assets, shaders) will never author an `I*Service`, so the line is inert there — accepted as harmless over-application, since the hook is the real enforcement and a missed agent is the costlier error.

2. **`csharp-unity.md` Card 5 had no trailing `---`.** The plan assumed one. Card 5 ran straight into `## Naming Summary`. Card 6 was inserted with a leading `---` and no trailing one, preserving the file's existing shape.

3. **The Step 0 line is an unnumbered bolded block, not "the last numbered item".** Three agents (`coder`, `tester`, `audio-clip-agent`) have no `## Step 0` section at all, and the remaining Step 0 lists differ in length. A numbered item would have produced a different string per file, breaking the "byte-identical across all files" acceptance criterion — which matters more, since it is what makes the instruction greppable and future edits scriptable. The block is appended at the end of the `## Step 0` section where one exists, and at the end of the file's first `## ` section otherwise. No agent gained a new top-level heading.

Sequencing rationale: Tasks 1, 2, 3, 5 touch disjoint files and have no cross-dependencies → group 1. Task 4 needs Task 3's authoritative agent list; Task 6 needs the hook script from Task 5 to exist before its bats suite can pass → group 2. Task 7 is only meaningful once the hook exists and its tests pass; Task 8 depends on Task 1's card landing → group 3. Task 9 verifies everything → group 4.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/rules/csharp-unity.md` | Edit | Insert `### Card 6` after Card 5 (ends line 150) and before `## Naming Summary` (line 151) |
| `.claude/rules/performance.md` | Edit | One line (87): drop "or custom pool" from the Object Lifecycle bullet |
| `.claude/agents/*.md` — **20 files** | Edit | Every agent whose frontmatter `tools:` contains `Write` or `Edit`. As-built list: `audio-clip-agent`, `coder`, `debugger`, `graphics-setup-agent`, `migrator`, `tester`, `unity-coder`, `unity-fixer`, `unity-migrator`, `unity-network-dev`, `unity-optimizer`, `unity-particle-designer`, `unity-prototyper`, `unity-setup`, `unity-shader-dev`, `unity-test-builder`, `unity-test-runner`, `unity-ui-builder`, `unity-ui-toolkit-builder`, `unity-verifier`. See Execution deviations #1 — the pre-execution estimate of 11 was wrong. |
| `.claude/agents/unity-scene-builder.md` | **No change** | Verified `tools: Read, Glob, Grep, mcp__unityMCP__*` — no Write/Edit → OUT of scope |
| `.claude/hooks/check-duplicate-symbol.sh` | **New** | PreToolUse, `HOOK_PROFILE_LEVEL="standard"`, mode 755 |
| `.claude/hooks/tests/check-duplicate-symbol.bats` | **New** | bats-core |
| `.claude/settings.json` | Edit (via Bash+python) | New `PreToolUse` entry, `"matcher": "Write"` |
| `CLAUDE.md` | Edit (optional) | One-line topic summary in `## Rules (auto-loaded)` |
| `<scratchpad>/patch_settings.py` | **New → deleted** | Scratchpad only; must not survive |

## Test Type mapping (read this before flagging a missing test)

The standard path-based Test Type matrix (EditMode / PlayMode-ECS / PlayMode-Scene) targets Unity C# under `Games/...` and `_Framework/`. **None** of the files in this plan are Unity runtime code — they are `.claude/` tooling: a bash hook, markdown rules, markdown agent definitions, and JSON harness config. Therefore:

- Markdown and JSON tasks → **`NoTest`**. This is correct, not an omission.
- The hook task → verification is its **bats suite** (`bash .claude/hooks/tests/run-tests.sh`), not a Unity test. It is still labelled `NoTest` in the Unity sense.

---

## Chosen Approach

**Block vs warn for the hook.** Chosen: **block**, via `unity_hook_block` at `HOOK_PROFILE_LEVEL="standard"`. A duplicate `I*Service` is a real architectural defect that is cheap to prevent and expensive to unwind once both files have implementers and VContainer registrations. The false-positive risk that would normally argue for `warn` is bounded by the four silent-degrade gates: the hook only ever fires when the graph is present, enabled, non-empty, and fresh — i.e. only in a real project with a recently built graph, never on a template clone. Users who disagree retain three escape hatches already in `_lib.sh`: `UNITY_HOOK_MODE=warn` downgrades the block, `UNITY_HOOK_PROFILE=minimal` skips the hook entirely, and `DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1` disables just this one.

**Accepted tradeoff — cross-domain basename collisions.** The hook derives the symbol name from the file basename, not by parsing the file. This is sound under the repo's "one type per file, filename matches class name" rule (`csharp-unity.md` → Types and File Rules), but that rule guarantees *filename ↔ class name* agreement, **not** global uniqueness of class names across domains. Two domains may legitimately land on the same name — `Games/Concretes/Enemies/SpawnConfig.cs` and `Games/Concretes/Waves/SpawnConfig.cs` are both valid under the domain-folder convention. The hook will block the second one. This is an **accepted false positive**, not an oversight: the collision is itself worth a human glance (two same-named types in one assembly is a readability hazard even when legal), and the operator's escape is the per-hook switch `DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1` or `UNITY_HOOK_MODE=warn`. The block message must therefore name the existing file's path so the agent can see immediately that it is a different domain and re-run with the switch. Namespace-aware matching (comparing the intended namespace against the graph entry's `.namespace`) is a deliberate **non-goal for v1** — it would require parsing `tool_input.content`, which no hook in this repo does today.

**Step 0 item vs a new Step 0.5.** Chosen: **an additional numbered item inside the existing `## Step 0`**. `unity-coder.md`'s Step 0 is already a numbered list ("1. Read `.claude/docs/auto-loaded-skills.md` … 2. From that list, read every skill …"), so appending item 3 costs no new heading and keeps the "before writing a single line of code" framing that already governs the section. A `Step 0.5` heading would need to be threaded into 11 files whose Step 0 bodies are not identical, and would read as optional. Apply the *same* wording and the *same* placement (last numbered item of Step 0) in every file. Note there is no shared include — Step 0 is duplicated markdown per agent, so this is 11 individual edits.

**How the bats fixture supplies a graph.json.** Chosen: **an env override for the graph path**, mirroring the existing `UNITY_FEATURES_FILE` and `UNITY_HOOK_STATE_DIR` overrides that tests already rely on. The hook resolves its graph as `UNITY_GRAPH_FILE="${UNITY_GRAPH_FILE:-$(git rev-parse --show-toplevel)/.claude/graph/graph.json}"`. The override is not a convenience — `.claude/graph/graph.json` is **tracked by git**, so a test that wrote fixture symbols into the real file would dirty the working tree and could be committed by accident. Rejected alternative: constructing a temp git repo per test — it fights the `cd "$BATS_TEST_DIRNAME/../../.."` convention every existing test uses, for no gain over two env vars.

**Caution for the implementer (`should_skip_path` semantics).** The patterns are `*/Editor/*`, `*/Plugins/*`, `*/ThirdParty/*`, `*_AssetFolders/*`, `*PackageCache/*`, `*EditModeTest/*`, `*PlayModeTest/*`, `*Tests/*`, `*Test/*`, `*Spec/*` — each requires a **path segment ending in that token, followed by a slash**. So `.../SmokeTest/Foo.cs` IS skipped, while a *file* named `TestBootstrap.cs` is NOT (no trailing slash). It is a segment-suffix match, not an arbitrary substring match. Test `file_path` values must still avoid any directory segment ending in `Test`/`Tests`/`Spec`/`Editor`/`Plugins`/`ThirdParty`, or the assertion will pass or fail for the wrong reason.

---

## Task 1 — Add `### Card 6` to `csharp-unity.md`

**Files:**
- `.claude/rules/csharp-unity.md`

**Steps:**
1. [ ] Read lines 122–155 to see Card 5's exact body and the `---` separator that precedes `## Naming Summary` (line 151).
2. [ ] Insert a new `### Card 6: Reuse Before You Hand-Roll` **after** Card 5's trailing `---` and **before** `## Naming Summary`. Do not renumber anything; Card 1.1 already establishes that numbering is not strictly sequential.
3. [ ] Follow the verbatim card format used by Cards 1–5: `### Card N: Title`, then `**WHEN:**`, `**WRONG:**` + fenced `csharp` block, `**RIGHT:**` + fenced `csharp` block, `**GOTCHA:**`, then a closing `---`.
4. [ ] Cover all five mappings. Because the format allows only one WRONG/RIGHT pair cleanly, put the most load-bearing one (`ObjectPool<T>` vs a hand-rolled `Queue<GameObject>`) in the WRONG/RIGHT blocks, and list the other four as a compact mapping table between the RIGHT block and the GOTCHA.
5. [ ] Mapping table rows (exactly these five): `Queue<GameObject>` pool → `UnityEngine.Pool.ObjectPool<T>`; manual timer field / `WaitForSeconds` coroutine → `UniTask.Delay`; hand-rolled JSON string parsing → `JsonUtility`; custom lerp/damping smoothing → `Mathf.SmoothDamp`; custom registry / service locator / static instance dictionary → **VContainer**.
6. [ ] GOTCHA text states the escape valve: hand-rolling is permitted only when the built-in demonstrably cannot meet a measured requirement, and that justification belongs in a code comment or an ADR — not in silence.
7. [ ] Verify no card index file needs updating (confirmed: none exists).

**Test Type:** NoTest

**Code Skeleton:**
```markdown
### Card 6: Reuse Before You Hand-Roll

**WHEN:** You are about to write a utility, pool, timer, parser, or registry.

**WRONG:**
(csharp fence) hand-rolled Queue<GameObject> pool: Get()/Return(), manual SetActive

**RIGHT:**
(csharp fence) UnityEngine.Pool.ObjectPool<T> with createFunc / actionOnGet / actionOnRelease

| Instead of hand-rolling | Use |
|---|---|
| `Queue<GameObject>` pool | `UnityEngine.Pool.ObjectPool<T>` |
| manual timer / `WaitForSeconds` | `UniTask.Delay` |
| string-splitting JSON | `JsonUtility` |
| custom lerp damping | `Mathf.SmoothDamp` |
| custom registry / locator | VContainer |

**GOTCHA:** ...

---
```

**Acceptance Criteria:**
- `grep -n "^### Card 6" .claude/rules/csharp-unity.md` returns exactly one line, and its line number is greater than Card 5's and less than `## Naming Summary`'s.
- All five mappings appear in the card.
- Card 5 and `## Naming Summary` are otherwise byte-identical to before.

---

## Task 2 — Tighten the pooling line in `performance.md`

**Files:**
- `.claude/rules/performance.md`

**Steps:**
1. [ ] `grep -n "custom pool" .claude/rules/performance.md` to confirm the line under `## Object Lifecycle` (expected: line 87).
2. [ ] Change `- Pool frequently instantiated objects — \`ObjectPool<T>\` or custom pool` so the "or custom pool" permission is removed and replaced with a pointer to Card 6 (e.g. `— use \`UnityEngine.Pool.ObjectPool<T>\`; see csharp-unity.md Card 6`).
3. [ ] Change **only** that line. Do not add a `## Cards` section to `performance.md` — restructuring it is explicitly out of scope.

**Test Type:** NoTest

**Code Skeleton:**
```bash
# before: - Pool frequently instantiated objects — `ObjectPool<T>` or custom pool
# after:  - Pool frequently instantiated objects — `UnityEngine.Pool.ObjectPool<T>` (see csharp-unity.md Card 6)
```

**Acceptance Criteria:**
- `grep -c "custom pool" .claude/rules/performance.md` returns 0.
- `git diff --stat .claude/rules/performance.md` shows 1 insertion, 1 deletion.

---

## Task 3 — Produce the authoritative code-writing agent list

**Files:**
- `.claude/agents/*.md` (read only)

**Steps:**
1. [ ] Re-grep rather than trusting any hardcoded list: inspect the `tools:` frontmatter line of every `.claude/agents/*.md` and select those whose `tools:` contains `Write` or `Edit`.
2. [ ] Note the trap: a naive `grep -l Write .claude/agents/*.md` matches the word "Write" anywhere in the body (it returns `committer.md`, `debugger.md`, `unity-verifier.md`, etc., which are not code-writing agents). Match on the frontmatter `tools:` line only.
3. [ ] Cross-check against the 11 verified names: `coder`, `tester`, `unity-fixer`, `unity-prototyper`, `unity-ui-builder`, `unity-ui-toolkit-builder`, `migrator`, `unity-migrator`, `unity-network-dev`, `unity-coder`, `unity-setup`. `unity-scene-builder.md` has `tools: Read, Glob, Grep, mcp__unityMCP__*` → **out of scope**.
4. [ ] If the grep surfaces any agent not in that list of 11, add it — the grep is authoritative, not this plan.

**Test Type:** NoTest

**Code Skeleton:**
```bash
grep -H "^tools:" .claude/agents/*.md | grep -E "Write|Edit"
```

**Acceptance Criteria:**
- A concrete list of file paths is produced and recorded before Task 4 begins.
- `unity-scene-builder.md` is absent from it.

---

## Task 4 — Add the Step 0 duplicate-symbol check to every code-writing agent

**Files:**
- Every file from Task 3's list (expected 11, incl. `unity-setup.md`)

**Steps:**
1. [ ] For each agent, locate its `## Step 0` section. `unity-coder.md` has the canonical `## Step 0 — Load Project Skills & Context` with a numbered list ending at item 2.
2. [ ] Append the duplicate-symbol check as the **last numbered item** of the existing Step 0 list (per the Chosen Approach — not a new `Step 0.5`).
3. [ ] Use identical wording in all files so the instruction is greppable and future edits can be scripted.
4. [ ] The instruction must name the trigger precisely: creating a **NEW** file whose type is `I*Service`, `I*Handler`, or `*Module`.
5. [ ] Point the agent at real query surfaces only: the `/knowledge-graph` skill's subcommands, or a direct `jq` over `.claude/graph/graph.json` (`.codebase.classes[] | select(.name=="X")` / `.codebase.interfaces[]`). **Do not** reference a symbol-lookup command on `graph-traversal.py` — it exposes only `impact`, `callers`, `path`, `god_nodes`, `finalize_calls` and has no name-lookup entry point.
6. [ ] The required action on a hit: **extend the existing symbol**, do not create a duplicate. If extension is genuinely wrong (different domain, same name), say why in the response before proceeding.
7. [ ] For any agent whose Step 0 is not a numbered list (check each — the bodies are not identical), adapt to that file's local structure while keeping the same sentence.
8. [ ] Note there is no shared include file; all 11 edits are independent and manual.

**Test Type:** NoTest

**Code Skeleton:**
```markdown
3. **Before creating a NEW `I*Service`, `I*Handler`, or `*Module` file**, query the
   knowledge graph for that exact symbol name (via `/knowledge-graph`, or
   `jq '.codebase.interfaces[], .codebase.classes[] | select(.name=="IFooService")'
   .claude/graph/graph.json`). If a match exists, **extend the existing symbol at
   its reported `.file`** instead of creating a duplicate.
```

**Acceptance Criteria:**
- `grep -l "Before creating a NEW" .claude/agents/*.md | wc -l` equals the count from Task 3.
- The added text is byte-identical across all files (`grep -h` output collapses to one unique line via `sort -u`).
- No agent gained a new top-level `##` heading.

---

## Task 5 — Write `.claude/hooks/check-duplicate-symbol.sh`

**Files:**
- `.claude/hooks/check-duplicate-symbol.sh` (new)

**Steps:**
1. [ ] Start from the verbatim boilerplate of `check-domain-folder-structure.sh`: shebang, `SCRIPT_DIR`, `HOOK_PROFILE_LEVEL="standard"` **as a plain shell var set BEFORE** `source "${SCRIPT_DIR}/_lib.sh"` (`_lib.sh` self-exits 0 if the level exceeds the active `UNITY_HOOK_PROFILE`).
2. [ ] **Copy the `# --- Hook Audit Logging ---` `_hook_log` function and its `trap '_hook_log $?' EXIT` verbatim from an existing hook.** Do not reinvent it — it writes a JSON line to `~/.claude/hook-audit.log` and trims to 500 lines.
3. [ ] Read stdin: `INPUT=$(cat)`; `FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')`; `[ -z "$FILE_PATH" ] && exit 0`. Do **not** read `.tool_input.content` — no existing hook does, and this hook needs only the path (for the symbol name) and the graph.
4. [ ] Gate on extension: `case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac`.
5. [ ] Call `should_skip_path "$FILE_PATH" && exit 0` (mandatory — covers Editor/Plugins/ThirdParty/Tests/etc.).
6. [ ] Gate on domain: proceed only if the path contains `Games/Abstracts/` or `Games/Concretes/`; otherwise exit 0.
7. [ ] **New-file gate — read carefully:** `[ ! -f "$FILE_PATH" ] || exit 0`. At PreToolUse time the Write has not landed, so a genuinely NEW file does **not** exist on disk; an existing file means this Write is an overwrite of a file whose symbol is already in the graph legitimately — not our concern. This is the **exact opposite** of `check-new-service.sh`'s `[ ! -f ... ] && exit 0` bail, which wants the on-disk file. Add an inline comment saying so verbatim, so nobody "fixes" it later.
8. [ ] Feature gate: `UNITY_FEATURES_FILE="${UNITY_FEATURES_FILE:-$(git rev-parse --show-toplevel 2>/dev/null)/.claude/project-features.json}"` then `[ "$(jq -r '.graph // false' "$UNITY_FEATURES_FILE" 2>/dev/null)" = "true" ] || exit 0`. The `// false` matters (missing key disables) and the env override matters for tests.
9. [ ] Graph gate: `UNITY_GRAPH_FILE="${UNITY_GRAPH_FILE:-$(git rev-parse --show-toplevel 2>/dev/null)/.claude/graph/graph.json}"`; `[ -f "$UNITY_GRAPH_FILE" ] || exit 0`. In this repo the file **does** exist and is tracked — this gate covers projects that removed it, not the template case.
10. [ ] Emptiness gate: if `(.codebase.classes // []) | length` **and** `(.codebase.interfaces // []) | length` are both 0, exit 0. **This is the gate that makes the shipped template safe** — both arrays are empty in the committed `graph.json`.
11. [ ] Staleness gate: read top-level `.generated_at` (ISO-8601 UTC, e.g. `"2026-07-06T06:40:48Z"`). There is **no** `metadata` object — do not look for one. If it is absent, unparseable, or older than 24h, exit 0. Use a portable epoch conversion (BSD `date -j -f "%Y-%m-%dT%H:%M:%SZ"` vs GNU `date -d`); guard both and exit 0 if neither works. This is the **second** independent reason the template clone is safe (committed timestamp is 2026-07-06).
12. [ ] Derive the symbol name from the basename minus `.cs`. See Chosen Approach for the accepted cross-domain collision tradeoff — the block message must include the existing file path so a legitimate collision is diagnosable at a glance.
13. [ ] Look it up with raw `jq` over the **inline** arrays — `.codebase.classes` / `.codebase.interfaces` are plain arrays; only `scenes`/`prefabs` use `{"$partition": ...}` refs, so no partition resolution is needed. Emit the matching entry's `.file`.
14. [ ] On a hit, call `unity_hook_block "..."` with a message naming the symbol, the existing `.file`, and the `DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1` escape for a legitimate cross-domain collision. **Never a raw `exit 2`** — `unity_hook_block` is what honours `UNITY_HOOK_MODE=warn`.
15. [ ] End with `exit 0`.
16. [ ] Ensure the file is executable (mode 755) to match sibling hooks — a missing exec bit makes the hook a silent no-op (exit 126).
17. [ ] Note `block-graph-direct-read.sh` is irrelevant here: it registers only on matcher `Read` and only when `.hybrid_graph == true`; this hook's own `jq` on graph.json is unaffected.

**Test Type:** NoTest (verified by the bats suite in Task 6)

**Code Skeleton:**
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"
# --- Hook Audit Logging ---  (copy verbatim from check-new-service.sh)
trap '_hook_log $?' EXIT

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac
should_skip_path "$FILE_PATH" && exit 0
case "$FILE_PATH" in */Games/Abstracts/*|*/Games/Concretes/*) ;; *) exit 0 ;; esac

# NOTE: inverted vs check-new-service.sh ON PURPOSE. PreToolUse fires BEFORE the
# Write lands, so a NEW file is absent from disk. An existing file = overwrite = skip.
[ ! -f "$FILE_PATH" ] || exit 0

UNITY_FEATURES_FILE="${UNITY_FEATURES_FILE:-$(git rev-parse --show-toplevel 2>/dev/null)/.claude/project-features.json}"
[ "$(jq -r '.graph // false' "$UNITY_FEATURES_FILE" 2>/dev/null)" = "true" ] || exit 0

UNITY_GRAPH_FILE="${UNITY_GRAPH_FILE:-$(git rev-parse --show-toplevel 2>/dev/null)/.claude/graph/graph.json}"
[ -f "$UNITY_GRAPH_FILE" ] || exit 0
# emptiness gate (both arrays length 0) -> exit 0   [makes the template safe]
# staleness gate on top-level .generated_at (>24h)  -> exit 0   [second template guard]

SYMBOL="$(basename "$FILE_PATH" .cs)"
EXISTING=$(jq -r --arg n "$SYMBOL" \
  '[(.codebase.classes // [])[], (.codebase.interfaces // [])[]]
   | map(select(.name == $n)) | .[0].file // empty' "$UNITY_GRAPH_FILE")
[ -n "$EXISTING" ] && unity_hook_block "Duplicate symbol '$SYMBOL' already exists at $EXISTING. Extend it instead of creating a new file. If this is a legitimate different-domain type with the same name, re-run with DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1."
exit 0
```

**Acceptance Criteria:**
- `bash -n .claude/hooks/check-duplicate-symbol.sh` passes.
- File is executable.
- No raw `exit 2` appears anywhere in the file.
- `should_skip_path`, `unity_hook_block`, and the `_hook_log` trap are all present.
- The block message contains the existing file path and the disable-switch hint.

---

## Task 6 — Write `.claude/hooks/tests/check-duplicate-symbol.bats`

**Files:**
- `.claude/hooks/tests/check-duplicate-symbol.bats` (new)

**Steps:**
1. [ ] Copy the setup/teardown skeleton verbatim from a sibling test: `export UNITY_HOOK_STATE_DIR="$(mktemp -d)"`, `HOOK=".claude/hooks/check-duplicate-symbol.sh"`, `cd "$BATS_TEST_DIRNAME/../../.."`, and `rm -rf "$UNITY_HOOK_STATE_DIR"` in teardown.
2. [ ] In setup, additionally build fixtures inside `$UNITY_HOOK_STATE_DIR`: a `features.json` with `{"graph": true}` and a `graph.json` with a **fresh** top-level `generated_at` plus one entry in `.codebase.interfaces` named `IPlayerService` with `"file": "Games/Abstracts/Players/IPlayerService.cs"`. Export `UNITY_FEATURES_FILE` and `UNITY_GRAPH_FILE` to point at them. **Never write fixtures into the real `.claude/graph/graph.json` — it is tracked by git.**
3. [ ] Choose test `file_path` values that avoid `should_skip_path` — no path *segment* ending in `Test`/`Tests`/`Spec`/`Editor`/`Plugins`/`ThirdParty`. Use e.g. `Games/Abstracts/Players/IPlayerService.cs` (duplicate) and `Games/Abstracts/Players/IInventoryService.cs` (novel).
4. [ ] Test: **blocks** on a duplicate → `status -eq 2`.
5. [ ] Test: **allows** a novel symbol → `status -eq 0`.
6. [ ] Test: **allows** an existing on-disk file (the inverted new-file gate) → `status -eq 0`.
7. [ ] Test: `UNITY_HOOK_PROFILE=minimal` → `status -eq 0` even on a duplicate.
8. [ ] Test: `UNITY_HOOK_MODE=warn` → `status -eq 0` on a duplicate, with a warning on stderr.
9. [ ] Degrade tests, each asserting `status -eq 0` on an otherwise-blocking input: graph feature `false`; `UNITY_GRAPH_FILE` pointing at a nonexistent path; graph with both arrays empty (**the shipped-template case**); graph with `generated_at` set >24h in the past (**the second shipped-template guard**).
10. [ ] Test: a path outside `Games/Abstracts|Concretes` → `status -eq 0`.
11. [ ] Test: a non-`.cs` path → `status -eq 0`.
12. [ ] Test: `DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1` on a duplicate → `status -eq 0`.
13. [ ] Run `bash .claude/hooks/tests/run-tests.sh` and confirm the new file is picked up and green.

**Test Type:** NoTest (this *is* the test)

**Code Skeleton:**
```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-duplicate-symbol.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    export UNITY_FEATURES_FILE="$UNITY_HOOK_STATE_DIR/features.json"
    export UNITY_GRAPH_FILE="$UNITY_HOOK_STATE_DIR/graph.json"
    # write {"graph":true} and a FRESH graph containing IPlayerService
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

@test "blocks duplicate interface symbol" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Games/Abstracts/Players/IPlayerService.cs\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
```

**Acceptance Criteria:**
- All cases from steps 4–12 exist as distinct `@test` blocks (12+ tests).
- `bash .claude/hooks/tests/run-tests.sh` is fully green.
- Temp fixtures are removed by teardown; `git status` shows no stray files and **`.claude/graph/graph.json` is unmodified**.

---

## Task 7 — Register the hook in `.claude/settings.json`

**Files:**
- `.claude/settings.json`
- a temporary python script in the scratchpad (created, run, then **deleted**)

**Steps:**
1. [ ] Back up the current file first: `cp .claude/settings.json <scratchpad>/settings.json.bak`, and record `jq -e . .claude/settings.json >/dev/null` passing beforehand.
2. [ ] Write a **temporary** python script into the scratchpad directory that loads `.claude/settings.json`, appends the new entry to `hooks.PreToolUse`, and writes it back with `indent=2` and a trailing newline. Use `json.load`/`json.dump` — never a regex or string splice. Python's `json` preserves insertion order, so appending to the array and dumping with the same indent should leave every other key byte-identical; step 8 verifies this rather than assuming it.
3. [ ] Rationale for the python-via-Bash route: `check-config-protection.sh` blocks `.claude/settings.json` with a **hardcoded `exit 2`** (line 88), not `unity_hook_block`, so `UNITY_HOOK_MODE=warn` does not help. It only intercepts the Write/Edit tool path, so a Bash-run script is unaffected. The user explicitly approved this bypass for this task only.
4. [ ] Run the script via Bash.
5. [ ] The new entry uses `"matcher": "Write"` — **not** `Edit|Write`, because this is new-file-creation only. Shape it exactly like the existing `check-domain-folder-structure.sh` entry: `command` = `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-duplicate-symbol.sh"`, `"type": "command"`, `"timeout": 5000`, `"statusMessage": "Checking for duplicate symbols..."`. Appending to the end of the `PreToolUse` array is fine. **This rests on an assumption, not a verified harness guarantee:** this hook reads only `tool_input.file_path` and two data files, and depends on no other hook's side effects, so wherever it sits in the array it evaluates the same input and returns the same result. Neither this repo's docs nor `settings.json` state whether PreToolUse hooks run in parallel or sequentially with a short-circuit on the first `exit 2`. If they do short-circuit, an earlier blocking hook could prevent this one from running at all on a given call — that is a "did not get a chance to run" risk, symmetric with every hook already in the array, not an ordering-breaks-correctness risk.
6. [ ] Verify the JSON parses: `jq -e . .claude/settings.json`.
7. [ ] Verify the entry landed: `jq '.hooks.PreToolUse[] | select(.hooks[].command | test("check-duplicate-symbol"))' .claude/settings.json` returns exactly one object with `matcher == "Write"`.
8. [ ] Verify nothing else changed: `git diff .claude/settings.json` shows only the added block (no reindentation of unrelated keys, no key reordering — if python's dump reindents, restore the backup and adjust the dump params before retrying).
9. [ ] **Delete the temporary python script.** This is a required step, not cleanup hygiene.
10. [ ] Delete the backup only after step 8 passes.

**Test Type:** NoTest

**Code Skeleton:**
```python
# <scratchpad>/patch_settings.py  — TEMPORARY, delete after running
import json, pathlib
p = pathlib.Path(".claude/settings.json")
d = json.loads(p.read_text())
d["hooks"]["PreToolUse"].append({
    "matcher": "Write",
    "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-duplicate-symbol.sh",
        "timeout": 5000,
        "statusMessage": "Checking for duplicate symbols..."
    }]
})
p.write_text(json.dumps(d, indent=2) + "\n")
```

**Acceptance Criteria:**
- `jq -e . .claude/settings.json` exits 0.
- Exactly one `check-duplicate-symbol` PreToolUse entry exists, with `matcher: "Write"`.
- `git diff` on settings.json is confined to the added block.
- The temp python script no longer exists on disk.

---

## Task 8 — Extend the CLAUDE.md rules-table summary *(optional)* **[BLOCKED — needs investigation]**

**Files:**
- `CLAUDE.md`

**Steps:**
1. [ ] Inspect the `## Rules (auto-loaded)` table row for `csharp-unity.md` and read its one-line topic summary.
2. [ ] Decide whether "reuse before hand-rolling" is a distinct enough topic to warrant appending to that summary, or whether the existing wording already subsumes it. **This is the uncertain part:** the table is a terse topic index, and padding every row on every card addition would erode it.
3. [ ] If yes, append the shortest possible phrase (e.g. `, reuse-first`). If no, record the decision and skip — skipping is an acceptable outcome for this task.
4. [ ] Do not touch any other CLAUDE.md row or section.

**Test Type:** NoTest

**Code Skeleton:**
```markdown
| `csharp-unity.md` | ...existing topics..., reuse-first |
```

**Acceptance Criteria:**
- Either the row gained ≤ 4 words, or the task is explicitly marked "skipped, by decision" in the Status table.
- No other CLAUDE.md line changed.

---

## Task 9 — End-to-end verification

**Files:**
- All of the above (read/execute only)

**Steps:**
1. [ ] Run the full suite: `bash .claude/hooks/tests/run-tests.sh`. It must be green **in full** — not just the new file. A new PreToolUse entry can perturb `hook-profile.bats` or `check-config-protection.bats` expectations.
2. [ ] Confirm the hook fires on a **synthetic duplicate**: with `UNITY_GRAPH_FILE` pointed at a temp fixture graph containing `IPlayerService` (fresh `generated_at`), pipe `{"tool_input":{"file_path":"Games/Abstracts/Players/IPlayerService.cs"}}` into the hook and assert exit 2 and a `BLOCKED:` message naming the existing `.file`.
3. [ ] **Template-clone regression guard.** Pipe the same duplicate payload with **no** env overrides, against this repo as it actually stands, and assert exit 0. The reason is *not* that `graph.json` is missing — it exists and is tracked. It is that the committed graph has **empty `classes`/`interfaces` arrays** (emptiness gate) **and** a `generated_at` of `2026-07-06T06:40:48Z`, far more than 24h old (staleness gate). Either gate alone suffices; assert both fire by temporarily testing a fixture that is empty-but-fresh and one that is populated-but-stale.
4. [ ] Confirm `DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1` and `DISABLE_UNITY_HOOKS=1` both yield exit 0 on the duplicate payload.
5. [ ] `jq -e . .claude/settings.json` and re-verify the registered entry.
6. [ ] `grep -c "^### Card 6" .claude/rules/csharp-unity.md` → 1; `grep -c "custom pool" .claude/rules/performance.md` → 0.
7. [ ] `grep -l "Before creating a NEW" .claude/agents/*.md | wc -l` matches Task 3's count, and `unity-scene-builder.md` is not among them.
8. [ ] `git status --porcelain` shows only the intended files — no temp python script, no `.bak`, no fixture leftovers, and **`.claude/graph/graph.json` unmodified**.
9. [ ] Review the final `git diff` in full and confirm nothing from ponytail's rejected rungs (YAGNI, one-liner, no-unrequested-abstraction) crept into any rules or agent text.

**Test Type:** NoTest (bats suite is the verification vehicle)

**Code Skeleton:**
```bash
bash .claude/hooks/tests/run-tests.sh
echo '{"tool_input":{"file_path":"Games/Abstracts/Players/IPlayerService.cs"}}' \
  | bash .claude/hooks/check-duplicate-symbol.sh; echo "exit=$?"   # expect 0 (empty + stale graph)
jq -e '.hooks.PreToolUse[] | select(.hooks[].command | test("check-duplicate-symbol"))' .claude/settings.json
git status --porcelain
```

**Acceptance Criteria:**
- Full bats suite green.
- Synthetic duplicate blocks (exit 2); this repo as it stands does not block (exit 0), for the emptiness + staleness reasons above.
- Both disable switches work.
- settings.json valid and correctly registered.
- Working tree contains only intended changes; tracked `graph.json` untouched.
