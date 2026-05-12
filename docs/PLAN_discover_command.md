# PLAN — /discover Command for Unity Package Analysis

> **Version:** v2 — 2026-05-12
> **Revision:** v2 — Added prefab-from-package duplication convention (Task 6, Task 1/2 addenda, JSON schema extension, cross-references).
> **Status:** Active
> **Scope:** `.claude/commands/`, `.claude/agents/`, `.claude/CLAUDE.md`, `README.md`, `.claude/skills/plugins/` (output target only), `.claude/rules/unity-specifics.md`

### Revision Notes

**v2 — 2026-05-12**
- Added the "prefab duplication from third-party packages" convention as a project-wide non-negotiable rule (Task 6).
- Annotated Task 1 with a prefab-detection addendum: `package-analyzer` must inventory `*.prefab` files inside each resolved package, map them to suggested `_GameFolders/Prefabs/<Category>/` destinations, include an 8th `## Prefabs (if any)` section in the skill template, and extend its JSON output with a `"prefabs"` array.
- Annotated Task 2 with a prefab-summary addendum: the `/discover` dry-run output must include a `package | prefab_name | suggested_destination` table, and `--write` must NOT auto-duplicate prefabs — it only records duplication instructions inside the generated skill file.
- Updated Status table to include Task 6 in parallel_group B (alongside Tasks 3 and 4).

**v1 — 2026-05-12**
- Initial plan. `/discover` slash command + `package-analyzer` subagent + CLAUDE.md / README.md updates + smoke test.

---

**Complexity: 0.5 — Medium** (unchanged; v2 additions are bounded read-only scans + one rule doc edit)

Scoring breakdown:
- **Surface area (0.2):** 1 new agent, 1 new command, 3 doc edits, 1 new skills subtree — bounded.
- **Unknowns (0.1):** Package manifest shape is well-defined; only unknown is per-package summarization quality.
- **Integration (0.1):** Touches slash-command registry, agents directory, CLAUDE.md, README.md, unity-specifics.md, and `skills/plugins/` tree.
- **Risk (0.1):** Writes new skill drafts into a versioned tree; needs an overwrite prompt and a dry-run.

## Context

The repo already ships a rich set of "core / gameplay / genre / platform / systems / third-party / plugins" skills under `.claude/skills/`. The `plugins/` subtree is the documented home for per-third-party-package guidance, but today it must be populated by hand. When a new Unity project pulls in a package such as PrimeTween, R3, or UniTask via UPM, Claude has no automatic way to learn that the package is present, what its idiomatic API looks like, or where its samples live.

`/learn` already extracts patterns from completed work and writes new skills under `.claude/skills/learned/`. `/discover` is its analogue for installed packages: read `Packages/manifest.json` plus `Packages/packages-lock.json`, walk each package directory for `package.json`, `README.md`, `CHANGELOG.md`, and `Samples~/`, and synthesize a short SKILL.md per package. The command runs in two modes: **dry-run** (preview the skills that would be created) and **write** (commit the drafts to disk after an overwrite-aware prompt).

Because plugin skill drafts are read every time the matching package is touched, quality matters. The `package-analyzer` subagent therefore reads `.claude/skills/core/unity-mcp-patterns/SKILL.md` for the MCP tool patterns it should reference when describing Editor-time integrations. It does not invent MCP tool names; it references documented patterns by name and lets the runtime resolve the actual tool identifiers.

## Goals

- [ ] Add a `package-analyzer` subagent that reads `Packages/manifest.json` + per-package files and produces one SKILL.md draft per discovered package.
- [ ] Add a `/discover` slash command that orchestrates the subagent, supports `--dry-run` and `--write`, and prompts before overwriting an existing `.claude/skills/plugins/<package>/SKILL.md`.
- [ ] Register `/discover` under **Quality** in `.claude/CLAUDE.md` (alongside `/learn`), and register the `package-analyzer` row in the Agents table.
- [ ] Register `/discover` in the Quality table of `README.md`.
- [ ] Smoke-test the full pipeline against a real package (PrimeTween) and against two error paths (missing path, second-run overwrite).
- [ ] **(v2)** Document the "prefab duplication from third-party packages" convention in `.claude/rules/unity-specifics.md` so the rule is enforced repo-wide, not only inside generated skill files.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Create `package-analyzer` subagent | ⏳ Pending | A |
| 1 | Task 2 — Create `/discover` slash command | ⏳ Pending | A |
| 2 | Task 3 — Update `.claude/CLAUDE.md` | ⏳ Pending | B |
| 2 | Task 4 — Update `README.md` | ⏳ Pending | B |
| 2 | Task 6 — Add Prefab Duplication rule to `.claude/rules/unity-specifics.md` | ⏳ Pending | B |
| 3 | Task 5 — Manual verification (smoke test) | ⏳ Pending | — |

Tasks 1 and 2 share `parallel_group: A` — the command file references the agent by name only, so the two files can be drafted simultaneously. Tasks 3, 4, and 6 share `parallel_group: B` — all three are documentation edits that depend on Tasks 1 and 2 landing first but not on each other. Task 5 is sequential and gates completion.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/agents/package-analyzer.md` | Create | New subagent spec; mirrors style of `learner` / `unity-scout`. |
| `.claude/commands/discover.md` | Create | New slash-command spec; mirrors style of `learn.md`. |
| `.claude/skills/plugins/` | Create children at runtime | Subagent writes `<package>/SKILL.md` here; no template files committed. |
| `.claude/CLAUDE.md` | Edit | Add `/discover` bullet under **Quality**; add `package-analyzer` row to Agents table. |
| `README.md` | Edit | Add `/discover` row to the **Quality** table in the Slash Commands section. |
| `.claude/rules/unity-specifics.md` | Edit (v2) | Append "Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)" subsection after the existing "Prefab Rules" section. |

---

## Task 1 — Create package-analyzer Subagent

**Files:**
- Create: `.claude/agents/package-analyzer.md`

**Steps:**

1. [ ] Read `.claude/agents/learner.md` and `.claude/agents/unity-scout.md` to copy the front-matter style (name, description, tools, model tier) and the "Inputs / Process / Outputs / Failure Modes" body convention.

2. [ ] Create `.claude/agents/package-analyzer.md` with these sections:
   - **Role:** "Read-only analyst that walks `Packages/manifest.json`, `Packages/packages-lock.json`, and each resolved package directory, then emits one skill draft per package."
   - **Tools:** `Read`, `Bash` (restricted to `ls`, `find`, `cat`, `head`, `tail`, `grep`), `Glob`. No write tools — drafts are returned as structured output for the orchestrator.
   - **Model tier:** `normal` (sonnet) — summarization-heavy, not reasoning-heavy.
   - **Inputs:** project root path (required), `--include-assets-plugins` flag (optional, off by default), `--only <package-name>` filter (optional, repeatable).

3. [ ] Write the **Process** section (ordered):
   1. **Read `.claude/skills/core/unity-mcp-patterns/SKILL.md` at start of MCP mode and use tool patterns documented there.** When a package exposes Editor-time integrations, reference patterns by name from that skill rather than hardcoding tool identifiers.
   2. Parse `Packages/manifest.json` for the `dependencies` map; ignore entries whose value begins with `com.unity.` unless `--include-unity-builtins` is set (default off — Unity's own packages already have skills under `skills/core/`).
   3. For each remaining dependency, resolve the on-disk path: prefer `Library/PackageCache/<name>@<version>/`, fall back to `Packages/<name>/` (embedded), fall back to a `file:`-prefixed local path from the manifest.
   3a. **Prefab inventory.** Scan for `*.prefab` files under the resolved path (cap: 200 per package). For each prefab, infer a Category from path/name heuristics (`UI`, `VFX`, `Enemies`, `Environment`, `Audio`, `Tools`; default: `ThirdParty`). Map each prefab to a suggested destination: `_GameFolders/Prefabs/<Category>/<PackageSlug>/<OriginalName>.prefab`. Reject any source path containing `..` segments.
   4. For each resolved path, read at most: `package.json` (name, displayName, version, description, samples list), `README.md` (first 200 lines), `CHANGELOG.md` (first 80 lines), and the file list of `Samples~/` if present.
   5. Synthesize a `SKILL.md` draft with these **eight** fixed sections (in order): `# <displayName>`, `## When to use`, `## Key APIs`, `## Idiomatic patterns`, `## Editor integration (if any)`, `## Samples`, `## Prefabs (if any)`, `## References`. Each section is 2–6 lines; the whole draft must stay under 150 lines. Omit `## Prefabs (if any)` only if zero prefabs were detected — do not emit an empty section.

4. [ ] Write the **Outputs** section — a JSON array on stdout where each element is:
   ```json
   {
     "package": "<name>",
     "version": "<ver>",
     "target_path": ".claude/skills/plugins/<slug>/SKILL.md",
     "exists": <bool>,
     "draft": "<full markdown body>",
     "prefabs": [
       {
         "original_path": "<relative-path-from-package-root>",
         "category": "<inferred-category>",
         "suggested_dest": "_GameFolders/Prefabs/<Category>/<slug>/<OriginalName>.prefab"
       }
     ]
   }
   ```
   `prefabs` is an empty array `[]` when no prefabs were detected. The orchestrator parses this and handles writes / overwrite prompts / the Prefab Summary table.

5. [ ] Write the **Failure modes** section:
   - Missing project root → exit non-zero with `ERR_NO_PROJECT_ROOT`
   - Unreadable manifest → `ERR_MANIFEST_PARSE`
   - Zero dependencies after filtering → exit 0 with empty array (not an error)

6. [ ] Write a **Quality bar** section: no invented API names, no version numbers in prose (they go in front-matter only), no copy-paste of upstream README beyond a 2-line attribution, no suggested destinations outside `_GameFolders/Prefabs/`.

**Acceptance Criteria:**
- `.claude/agents/package-analyzer.md` exists, has valid front-matter, and lists `Read`, `Bash`, `Glob` as its tool surface.
- The Process section begins with the instruction to read `.claude/skills/core/unity-mcp-patterns/SKILL.md` before referencing any MCP tool.
- The Process section includes step "3a. Prefab inventory" with the 200-file cap and `..` rejection rule.
- The Outputs section specifies the full JSON shape above, including the `"prefabs"` array with `original_path`, `category`, and `suggested_dest` fields.
- The skill template lists `## Prefabs (if any)` as the 8th section, positioned immediately before `## References`.

### Addendum — ## Prefabs section content (v2)

The `## Prefabs (if any)` section in the generated SKILL.md must include:
- A bullet list of each detected prefab: `- <original_path> → <suggested_dest>`
- The following verbatim rule line: `NEVER use the package prefab directly in scenes. Duplicate into the suggested \`_GameFolders/Prefabs/<Category>/\` destination and customize the copy. The Logic vs Visual Separation rule (root = logic components, Body child = visual/renderer components) applies to the duplicated prefab.`
- A cross-reference: `See \`.claude/rules/unity-specifics.md\` → "Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)" and "Prefab Rules (NON-NEGOTIABLE)" for folder structure and separation rules.`

---

## Task 2 — Create /discover Slash Command

**Files:**
- Create: `.claude/commands/discover.md`

**Steps:**

1. [ ] Read `.claude/commands/learn.md` end-to-end to inherit the command-file style: YAML front-matter (`description`, `argument-hint`), the "Usage / Flow / Output" body shape, and the convention for sequencing subagent calls.

2. [ ] Create `.claude/commands/discover.md` with:
   - **Front-matter:** `description: Discover installed Unity packages and emit per-package skill drafts under .claude/skills/plugins/`. `argument-hint: [--dry-run] [--write] [--only <pkg>] [--include-assets-plugins]`.
   - **Usage examples:**
     ```
     /discover                                          ← dry-run by default
     /discover --write
     /discover --only com.kybernetik.primetween --write
     /discover --include-assets-plugins --dry-run
     ```

3. [ ] Write the **Flow** section:
   1. Resolve the project root from the current working directory; fail fast with `ERR_NO_PROJECT_ROOT` if `Packages/manifest.json` is missing.
   2. Invoke `package-analyzer` with the parsed flags. Capture its JSON output.
   3. Pretty-print a table: `package | version | target_path | exists`. Then immediately print the **Prefab Summary** table: `package | prefab_name | suggested_destination` (built from the `prefabs` field of the JSON). If all packages have `prefabs: []`, print `Prefab Summary: (none detected)`.
   4. Print: `Note: --write only documents prefab duplication targets inside skill files. It does not duplicate any prefab.`
   5. If `--dry-run` (default), stop here.
   6. If `--write`, iterate the array:
      - Reject any element whose `suggested_dest` escapes `_GameFolders/Prefabs/` — surface `ERR_PREFAB_DEST_OUT_OF_ROOT` and skip that package.
      - If `exists == false`, create the target directory and write the draft.
      - If `exists == true`, show a 10-line diff against the current file and ask the user to choose `overwrite | skip | edit`. The prompt fires per-package — no bulk yes/no.
   7. After all writes, print a summary: `<N> created`, `<M> overwritten`, `<K> skipped`.

4. [ ] Add an **Output contract** section: every write goes through the standard Write tool so the gateguard / read-before-edit hooks apply; no shell redirects. `--write` does NOT create, copy, or move any `.prefab` file — it only writes SKILL.md files containing duplication documentation.

5. [ ] Add an **Error surfaces** section:
   - Missing manifest → `ERR_NO_PROJECT_ROOT`
   - Malformed JSON from subagent → `ERR_SUBAGENT_OUTPUT`
   - Write permission denied → `ERR_WRITE_DENIED`
   - Target path traversal (crafted `name` field with `..`) → reject before any write
   - Prefab suggested destination outside `_GameFolders/Prefabs/` → `ERR_PREFAB_DEST_OUT_OF_ROOT`

**Acceptance Criteria:**
- `.claude/commands/discover.md` exists, has front-matter with `description` and `argument-hint`, and lists all four flags in the usage examples.
- The Flow section documents both dry-run and write modes, the Prefab Summary table, and the per-package overwrite prompt.
- `ERR_PREFAB_DEST_OUT_OF_ROOT` appears in the Error surfaces section.
- The Output contract section explicitly states `--write` does NOT duplicate any `.prefab` file.

---

## Task 3 — Update .claude/CLAUDE.md

**Files:**
- Modify: `.claude/CLAUDE.md`

**Steps:**

1. [ ] **Read `.claude/CLAUDE.md` in full before editing** — `gateguard.sh` blocks writes on unread files. Confirm the Quality section location (around line 153) and the Agents table location (around line 192).

2. [ ] In the `### Quality` subsection, locate the `/learn` bullet and insert the new `/discover` bullet immediately after it:
   ```markdown
   - `/discover [--dry-run|--write] [--only <pkg>]` — Walk `Packages/manifest.json`, summarize each Unity package, and emit per-package skill drafts to `.claude/skills/plugins/<pkg>/SKILL.md`. Detects package prefabs and suggests `_GameFolders/Prefabs/<Category>/` duplication destinations in the generated skill. Supports `--dry-run` (default), `--write`, `--only <pkg>`, `--include-assets-plugins`.
   ```

3. [ ] In the **Agents** table, insert a `package-analyzer` row:
   ```markdown
   | `package-analyzer` | Read-only analyst — walks `Packages/manifest.json` + each package directory, detects prefabs and APIs, and returns skill drafts as JSON for `/discover` to write. |
   ```

4. [ ] Do NOT touch the "Building a Game from Scratch" phase table or the model-tier table.

**Acceptance Criteria:**
- `grep -n "/discover" .claude/CLAUDE.md` returns exactly one line inside the Quality block.
- `grep -n "package-analyzer" .claude/CLAUDE.md` returns exactly one line inside the Agents table.
- No existing rows or commands were removed or reordered destructively.

---

## Task 4 — Update README.md

**Files:**
- Modify: `README.md`

**Steps:**

1. [ ] **Read `README.md` before editing** — find the Quality command table location (around lines 311–328).

2. [ ] Insert a new row immediately after the `/learn` row:
   ```markdown
   | `/discover [--dry-run\|--write] [--only <pkg>]` | Walk `Packages/manifest.json`, summarize each Unity package, and emit per-package skill drafts to `.claude/skills/plugins/<pkg>/SKILL.md`. Detects package prefabs, suggests `_GameFolders/Prefabs/<Category>/` duplication destinations. Supports `--dry-run` (default), `--write`, `--only <pkg>`, `--include-assets-plugins`. |
   ```

3. [ ] Do NOT add `/discover` to the "Phase 6 — Documentation & Learning" table — it is opt-in, not part of the standard flow.

**Acceptance Criteria:**
- `grep -n "/discover" README.md` returns exactly one line inside the Quality table.
- The new row mentions both `--dry-run` and `--write`.

---

## Task 5 — Manual Verification (smoke test)

**Files:**
- None modified. Read-only smoke test.

**Steps:**

1. [ ] **Dry-run against a real package.** Run `/discover --only com.kybernetik.primetween --dry-run`. Confirm: package name resolved, version present, target path correct, draft body contains all eight required sections (including `## Prefabs (if any)` or its absence when no prefabs found), Prefab Summary table printed.

2. [ ] **Missing-path error.** From a directory with no `Packages/manifest.json`, run `/discover --dry-run`. Confirm exit non-zero with `ERR_NO_PROJECT_ROOT`, no files created.

3. [ ] **Overwrite prompt.** Run `/discover --only com.kybernetik.primetween --write` once. Run again. Confirm per-package `overwrite | skip | edit` prompt. Answer `skip` — confirm file unchanged.

**Acceptance Criteria:**
- (a) Skill draft shown: non-empty `draft` field, all required sections present, target path matches slug, Prefab Summary table displayed.
- (b) Missing-path error: exit non-zero, `ERR_NO_PROJECT_ROOT` in output, no files created.
- (c) Overwrite prompt fires on second run; `skip` leaves file unchanged.

---

## Task 6 — Document Prefab Duplication Convention in unity-specifics.md (v2)

**Files:**
- Modify: `.claude/rules/unity-specifics.md`

**Context:**

The existing "Prefab Rules (NON-NEGOTIABLE)" subsection covers prefab placement, variants, folder structure, and logic/visual separation for project-owned prefabs, but says nothing about prefabs that arrive via third-party UPM packages or Asset Store imports. Without an explicit rule, developers drag package prefabs directly into scenes, creating hard dependencies on `Library/PackageCache/<name>@<version>/...` paths that break the moment the package is upgraded or re-resolved.

**Steps:**

1. [ ] **Read `.claude/rules/unity-specifics.md` in full before editing** — `gateguard.sh` blocks writes on unread files. Confirm the end of the "Prefab Rules (NON-NEGOTIABLE)" section and the start of the "## .meta Files" section.

2. [ ] Insert a new subsection titled `## Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)` immediately after the existing "Prefab Rules (NON-NEGOTIABLE)" section and before "## .meta Files".

3. [ ] The new subsection must contain in this order:
   - **Opening paragraph:** Prefabs that ship inside a third-party UPM package (under `Library/PackageCache/<name>@<version>/`) or an Asset Store package (under `Assets/Plugins/<vendor>/`) must NEVER be referenced directly from a scene, a Resources reference, an Addressables entry, or another prefab.
   - **Why paragraph:** Package contents are immutable from the project's perspective — UPM rewrites `Library/PackageCache/` on every resolve, and Asset Store updates overwrite `Assets/Plugins/`. Any in-scene reference to a package GUID breaks with a "missing prefab" error on version bump; any in-package edit is silently lost.
   - **Procedure** (numbered, 5 steps):
     1. Identify the source prefab inside the package directory.
     2. Choose a category folder under `_GameFolders/Prefabs/<Category>/` matching the existing domain folders (Enemies, UI, VFX, Environment, …). Use a `<Category>/<PackageSlug>/` subfolder when the package contributes more than one prefab.
     3. Duplicate the prefab into that destination using **Project window → right-click → Duplicate**. Do NOT copy `.meta` files from the package — Unity will mint a fresh GUID on duplication.
     4. Replace any in-scene/in-prefab reference to the package GUID with the new GUID from the duplicate.
     5. Apply the Logic vs Visual Separation rule to the duplicate: logic components on the root GameObject, visual/renderer components on a `Body` child. See "Prefab Rules (NON-NEGOTIABLE)" for the full separation convention.
   - **Rules table** (5 rows):

     | Rule | Why |
     |------|-----|
     | Never drag a `Library/PackageCache/...` prefab into a scene | Reference breaks on package upgrade |
     | Always duplicate into `_GameFolders/Prefabs/<Category>/` first | Project owns the GUID and the asset lifecycle |
     | Never edit a package prefab in place | UPM resolve overwrites it; Asset Store update overwrites it |
     | Never copy `.meta` files from the package source | Forces Unity to assign a fresh GUID; old references stay scoped to the package |
     | Place duplicates by category, not by package | Keeps the project-side prefab tree organized by domain, not by vendor |

   - **Cross-reference lines:**
     ```
     See also: "Prefab Rules (NON-NEGOTIABLE)" in this file for folder structure, Prefab Variants, and Logic vs Visual Separation rules that apply after duplication.
     See also: `/discover` writes the per-package duplication plan into `.claude/skills/plugins/<package>/SKILL.md` under the `## Prefabs` section.
     ```

4. [ ] Do NOT modify the existing "Prefab Rules (NON-NEGOTIABLE)" subsection, the Input System section, or any other unrelated content. This is an append-only edit.

5. [ ] Verify the section heading uses the exact spelling **"Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)"**.

**Acceptance Criteria:**
- `grep -n "Prefab Duplication from Third-Party Packages" .claude/rules/unity-specifics.md` returns exactly one line.
- The new section appears between "Prefab Rules (NON-NEGOTIABLE)" and "## .meta Files" — verifiable by `grep -n "^## " .claude/rules/unity-specifics.md` showing correct ordering.
- The Procedure subsection contains exactly 5 numbered steps, including the Logic vs Visual Separation reference as step 5.
- The Rules table contains exactly 5 rows in the listed order.
- Both cross-reference lines (to "Prefab Rules" and to `/discover`) are present at the end of the subsection.
- `git diff .claude/rules/unity-specifics.md` shows only additions — no existing content removed or modified.

---

### Critical Files for Implementation
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/Docs/PLAN_discover_command.md`
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/agents/package-analyzer.md` (create)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/discover.md` (create)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/rules/unity-specifics.md` (edit — Task 6)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/CLAUDE.md` (edit — Task 3)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/README.md` (edit — Task 4)
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/skills/plugins/primetween.md` (reference only — do not modify)
