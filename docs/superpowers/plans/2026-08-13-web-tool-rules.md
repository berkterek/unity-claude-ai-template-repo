# Web Authoring Tool Rules & Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision v2 — 2026-08-13.** Tasks 1–7 shipped. A live test was then run: a fresh agent was given only `web-tooling/SKILL.md` and the three `web-tool-*.md` rule files, forbidden from seeing `nile_hole_sphere_repo` (the project the rules were derived from), and asked to build a wave-table editor for an unrelated tower-defense game — a pure table editor with no visual preview. It produced a working, compliant tool (10/10 tests passing, opens from `file://`, no build step), which validates the core rule set as transferable rather than project-specific. It also reported five gaps, each since verified against the current files: no card governs list-item identity/ordering (F1); design-system Card 3's segmented-control row steers toward the expensive custom widget (F2); Cards 6 and 9 both claim the delete action with no resolution (F3); `SKILL.md`'s applicability note over-excludes design-system Card 5 (F4); architecture Card 2's data-flow carve-out is ambiguous about reading `e.target.value` in a delegated handler (F5). Separately the plan's own File Structure table and the `rg -c '^### Card '` assertions inside Tasks 2–5 now hold stale card counts. Tasks 8–13 close these. **Tasks 1–7 below are historical and must not be edited.**

**Goal:** Add three normative rule files and one router skill to `unity-claude-ai-template-repo` that govern browser-based authoring/editor tools, so the next level editor does not re-derive its standards.

**Architecture:** Rules-heavy, skill-thin. Three `web-tool-*.md` files under `.claude/rules/` carry the normative content in the repo's existing Cards idiom (WHEN / WRONG / RIGHT / GOTCHA). One `SKILL.md` under `.claude/skills/web-tooling/` acts as a router that tells an agent which rule to read in which order, plus a file skeleton. Content is grounded in web research, then translated into repo idiom — never pasted verbatim. Integration is two table rows plus one index row; no hooks, no slash command, no `auto-loaded-skills.md` entry.

**Tech Stack:** Markdown only. Verification via `grep`/`rg` and manual reading. No code is shipped by this plan.

## Global Constraints

- **Reference project (read-only):** `/Users/berkterek/Desktop/Github/nile_hole_sphere_repo/tools/web-level-editor/`. Never modify any file under it. It is the source of RIGHT examples and the target of the final bite test.
- **Rule file format:** every rule file opens with an H1, then a `## Scope` line, then `## Cards`, then reference prose. Each card is `### Card N: <Title>` with `**WHEN:**`, `**WRONG:**` (fenced code), `**RIGHT:**` (fenced code), `**GOTCHA:**`. This matches `.claude/rules/architecture.md` and `.claude/rules/solid-oop.md` exactly.
- **Language:** rule and skill files are written in **English**, matching every existing file under `.claude/rules/`.
- **Scope line, verbatim, in all three rule files:** `> **Scope:** Browser-based authoring/editor/config tools only. NOT runtime game UI (UGUI / UI Toolkit) — see rules/unity-prefabs.md and skills/core/unity-ugui.md for that.`
- **Opinion marking:** any rule not backed by a cited external source or by existing `web-level-editor` code is prefixed `> **Advisory:**` — matching the convention already used in `.claude/rules/architecture.md`.
- **No hooks, no slash command.** Do not touch `.claude/settings.json`. Do not touch `.claude/docs/auto-loaded-skills.md`.
- **Commits are held.** The user's standing rule is: no `git commit` without an explicit instruction. Every task below ends with a **staging** step (`git add`) and stops there. Do not run `git commit` unless the user says so in that session.
- **Filename prefix:** all three rule files use the `web-tool-` prefix so they sort together and never read as Unity rules.

---

## File Structure

| Path | Responsibility |
|---|---|
| `docs/superpowers/research/2026-08-13-web-tool-research.md` | Working notes from the three research queries. Source of citations for the rule files. Committed so future edits can trace a rule back to its origin. |
| `.claude/rules/web-tool-data-contract.md` | 6 cards. The contract between the tool's export and the consuming system. Read first — most expensive to get wrong. |
| `.claude/rules/web-tool-architecture.md` | 7 cards. Zero-build constraint, model/DOM separation, file limits, render contract, testing. |
| `.claude/rules/web-tool-design-system.md` | 8 cards. Tokens, spacing scale, control-type mapping, viewport primacy, units, destructive actions, keyboard access, state visibility. |
| `.claude/skills/web-tooling/SKILL.md` | Router + skeleton + 6-step new-tool checklist. No normative content of its own. |
| `.claude/CLAUDE.md` | 3 rows appended to the `## Rules (auto-loaded)` table. |
| `.claude/docs/skills-index.md` | 1 row for `web-tooling`. |
| `docs/superpowers/reports/2026-08-13-web-level-editor-violations.md` | Output of the bite test. Proves the rules constrain something. |

Task order follows dependency: research → the three rule files (data-contract first, since the skill's reading order mirrors it) → skill → integration → bite test.

---

### Task 1: Research and capture sources

**Files:**
- Create: `docs/superpowers/research/2026-08-13-web-tool-research.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a markdown file with three `## ` sections named exactly `## Visual language`, `## Vanilla architecture`, `## Data contract`. Each section contains a `### Findings` list where every bullet has the shape `- **<claim>** — <source name/URL>`. Tasks 2–4 cite these bullets. A claim with no source bullet must be marked `> **Advisory:**` in the rule file.

- [ ] **Step 1: Run the three research queries**

Use `WebSearch`, one call per topic, in a single message so they run concurrently:

1. `Refactoring UI spacing scale typography scale design tokens principles`
2. `WAI-ARIA Authoring Practices slider dialog listbox keyboard interaction pattern`
3. `zero-build vanilla javascript ES modules application architecture event delegation idempotent render`

Then a fourth and fifth, same treatment:

4. `consumer-driven contract testing JSON schema versioning practice`
5. `Blender Tiled level editor UI conventions viewport panel layout`

- [ ] **Step 2: Fetch the two highest-value hits per topic**

Use `WebFetch` on the two most authoritative results per topic (prefer primary sources: `w3.org/WAI/ARIA/apg`, `refactoringui.com`, official Radix/shadcn docs, `developer.mozilla.org`). Skip listicles and SEO blogspam.

- [ ] **Step 3: Write the research notes file**

Structure exactly:

```markdown
# Web Authoring Tool — Research Notes

**Date:** 2026-08-13
**Purpose:** Source material for `.claude/rules/web-tool-*.md`. Every card in those
files either cites a bullet here or is marked `> **Advisory:**`.

## Visual language

### Findings
- **Spacing scale should be a small fixed set, not arbitrary values** — Refactoring UI, <URL>
- **<claim>** — <source>

### Rejected
- **<claim we chose not to adopt>** — <why>

## Vanilla architecture

### Findings
- **<claim>** — <source>

### Rejected

## Data contract

### Findings
- **<claim>** — <source>

### Rejected
```

The `### Rejected` sections are not optional. Recording what was considered and dropped is what stops this being re-litigated in six months.

- [ ] **Step 4: Verify the file has real citations**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c 'https?://' docs/superpowers/research/2026-08-13-web-tool-research.md
```
Expected: a count of **6 or more**. Fewer means the research was too thin to ground three rule files — go back to Step 2.

Run:
```bash
rg '^## (Visual language|Vanilla architecture|Data contract)$' docs/superpowers/research/2026-08-13-web-tool-research.md
```
Expected: exactly 3 matching lines.

- [ ] **Step 5: Stage**

```bash
git add docs/superpowers/research/2026-08-13-web-tool-research.md
```

Do not commit. See Global Constraints.

---

### Task 2: `web-tool-data-contract.md`

**Files:**
- Create: `.claude/rules/web-tool-data-contract.md`
- Read (do not modify): `/Users/berkterek/Desktop/Github/nile_hole_sphere_repo/tools/web-level-editor/editor.js`, `preview-core.js`, `preview-core.test.js`, `preview-parity-fixture.json`, `sample-level.json`

**Interfaces:**
- Consumes: `## Data contract` findings from Task 1.
- Produces: a rule file with exactly 6 cards titled, in order:
  `Card 1: One Schema, One Place`, `Card 2: Enum Map in One Constant Block`,
  `Card 3: Every Export Carries a Version`, `Card 4: Units and Scale Are Written Down`,
  `Card 5: Replicated Logic Is Locked by a Parity Fixture`,
  `Card 6: Importer Errors on Missing Fields`.
  Tasks 3, 4 and 5 cross-reference these by exact title.

- [ ] **Step 1: Read the reference implementation**

Read all five files listed above. Extract, verbatim, for use as RIGHT examples:
- the `CATEGORY_OPTS` / `COLLECTABLE_OPTS` / `BLOCKER_OPTS` constant block from `editor.js` → Card 2 RIGHT
- the header comment in `editor.js` that states the fraction-of-terrain-size contract → Card 4 RIGHT
- the fixture-comparison assertion from `preview-core.test.js` → Card 5 RIGHT

- [ ] **Step 2: Write the file**

Skeleton (fill every card completely — no card ships without all four parts):

```markdown
# Web Tool — Data Contract Rules (NON-NEGOTIABLE)

> **Scope:** Browser-based authoring/editor/config tools only. NOT runtime game UI (UGUI / UI Toolkit) — see rules/unity-prefabs.md and skills/core/unity-ugui.md for that.

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: One Schema, One Place

**WHEN:** The tool exports data another system reads.

**WRONG:**
```js
// key names typed by hand on the writing side...
out.wallHeight = model.wallHeight;
out.wallThickness = model.wallThickness;
```
```csharp
// ...and again on the reading side. A rename on one side is a silent data loss on the other.
[SerializeField] private float wallHeigth;
```

**RIGHT:**
```js
/* One field table. Both the exporter and the importer's field list derive from it. */
const SCHEMA = [
  { key: "wallHeight",    type: "number", unit: "fraction-of-size" },
  { key: "wallThickness", type: "number", unit: "fraction-of-size" },
];
const exportModel = (m) => Object.fromEntries(SCHEMA.map(f => [f.key, m[f.key]]));
```

**GOTCHA:** <the concrete failure mode: a typo'd key deserializes to the C# default, the level loads, and nothing errors — it is just wrong>

### Card 2: Enum Map in One Constant Block
...
```

Every GOTCHA must name a **concrete observable failure**, not a restatement of the rule. "This is bad practice" is not a GOTCHA. "The importer sees `0`, treats it as `None`, and the collectable silently never spawns" is.

- [ ] **Step 3: Add the reference prose**

Below `## Cards`, add these H2 sections:
- `## Why the Contract Is the First Rule` — 1 paragraph
- `## Versioning Strategy` — the concrete rule: integer `version`, importer switch, unknown version is a hard error
- `## Parity Fixture Pattern` — the generalized form of `preview-parity-fixture.json` + `preview-core.test.js`: what goes in the fixture, when it is regenerated, why regenerating it to silence a failure defeats the purpose
- `## Common Mistakes` — a two-column table (Mistake | Solution), matching the style at the end of `.claude/rules/bootstrap-pattern.md`

- [ ] **Step 4: Verify structure**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-data-contract.md
```
Expected: `6`

Run:
```bash
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-data-contract.md
done
```
Expected: `6` for each of the four. Any number below 6 means a card is incomplete.

Run:
```bash
rg -q '^> \*\*Scope:\*\* Browser-based authoring' .claude/rules/web-tool-data-contract.md && echo SCOPE_OK || echo SCOPE_MISSING
```
Expected: `SCOPE_OK`

- [ ] **Step 5: Stage**

```bash
git add .claude/rules/web-tool-data-contract.md
```

---

### Task 3: `web-tool-architecture.md`

**Files:**
- Create: `.claude/rules/web-tool-architecture.md`
- Read (do not modify): `web-level-editor/editor.js`, `preview-core.js`, `preview-core.test.js`, `index.html`

**Interfaces:**
- Consumes: `## Vanilla architecture` findings from Task 1; may cross-reference `Card 5: Replicated Logic Is Locked by a Parity Fixture` from Task 2.
- Produces: a rule file with exactly 7 cards titled, in order:
  `Card 1: Zero Build, Runs from file://`, `Card 2: One Model, One Source of Truth`,
  `Card 3: Pure Core, DOM Shell`, `Card 4: File Line Limit ~400`,
  `Card 5: Event Delegation, Not Per-Row Listeners`, `Card 6: Render Is Idempotent`,
  `Card 7: The Pure Core Has Tests, With No Test Runner`.
  Task 5 cross-references Cards 1, 3 and 7 by exact title.

- [ ] **Step 1: Write Cards 1–3**

Card 3's WRONG example is the real one — cite it explicitly:

```markdown
**WRONG:**
`web-level-editor/editor.js` is 619 lines holding the model, the section-derivation
math, the 3D preview wiring, every DOM listener, and the export serializer. Nothing in
it can be tested without a browser, and the derivation math cannot be reused.

**RIGHT:**
```
<tool>-core.js    ← pure: model transforms, derivation, serialization. Zero DOM.
<tool>.js         ← shell: queries elements, binds events, calls core, writes DOM.
<tool>-core.test.js ← plain assertions over the pure core, runs under `node`.
```
`web-level-editor/preview-core.js` (138 lines, DOM-free, tested by
`preview-core.test.js`) is the correct shape — the rest of the tool has not caught up
to it yet.
```

**GOTCHA** for Card 3: naming the specific consequence — once preview math lives inside a DOM file, the parity fixture from data-contract Card 5 cannot be run at all, so the replication silently drifts.

- [ ] **Step 2: Write Cards 4–7**

Card 4's threshold is `~400` lines and is **advisory**, so it carries the marker:

```markdown
> **Advisory:** The 400-line figure is a judgment call, not a sourced standard. The
> enforceable part is the trigger it encodes: when one file holds two responsibilities
> you would describe with an "and", split it. Line count is just the cheapest smoke alarm.
```

Card 6's RIGHT example must show a real idempotent render (build a fragment, replace container contents) and its WRONG must show the append-without-clear bug that produces duplicated rows.

Card 7's RIGHT example is a runnable, dependency-free test — model it on `preview-core.test.js`:

```js
/* run: node <tool>-core.test.js  — exits non-zero on failure, no runner, no install */
import { deriveSections } from "./tool-core.js";
let failures = 0;
const eq = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.error(`FAIL ${label}\n  got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`); }
};
eq("empty input yields empty output", deriveSections([]), []);
process.exit(failures ? 1 : 0);
```

- [ ] **Step 3: Add the reference prose**

H2 sections: `## Why Zero Build`, `## The Model/DOM Boundary`, `## Testing Without a Runner`, `## Common Mistakes` (two-column table).

`## Why Zero Build` must state the actual reason in one sentence: the tool outlives the project, and a build pipeline is the part that rots first.

- [ ] **Step 4: Verify structure**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-architecture.md
```
Expected: `7`

Run:
```bash
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-architecture.md
done
```
Expected: `7` for each.

Run:
```bash
rg -q '^> \*\*Scope:\*\* Browser-based authoring' .claude/rules/web-tool-architecture.md && echo SCOPE_OK || echo SCOPE_MISSING
```
Expected: `SCOPE_OK`

- [ ] **Step 5: Stage**

```bash
git add .claude/rules/web-tool-architecture.md
```

---

### Task 4: `web-tool-design-system.md`

**Files:**
- Create: `.claude/rules/web-tool-design-system.md`
- Read (do not modify): `web-level-editor/styles.css`, `index.html`

**Interfaces:**
- Consumes: `## Visual language` findings from Task 1.
- Produces: a rule file with exactly 8 cards titled, in order:
  `Card 1: No Color Outside Tokens`, `Card 2: Fixed Spacing Scale`,
  `Card 3: Control Type Derives from Data Type`, `Card 4: The Viewport Is First-Class`,
  `Card 5: Every Numeric Field Shows Unit and Real Scale`,
  `Card 6: Destructive Actions Confirm; Actions Are Undoable`,
  `Card 7: Keyboard Access and Visible Focus`,
  `Card 8: State Must Be Visible`.
  Task 5 cross-references Cards 1 and 2 by exact title.

- [ ] **Step 1: Write Cards 1–2 with the concrete scale**

Card 1's RIGHT example is lifted from the real `:root` block in `styles.css` — it already complies, so quote it and say so.

Card 2 must publish the **actual numbers**, not the concept:

```markdown
**RIGHT:**
```css
:root {
  --space-1: 4px;  --space-2: 8px;  --space-3: 12px;
  --space-4: 16px; --space-6: 24px; --space-8: 32px;
}
.topbar { padding: var(--space-3) var(--space-6); }
```

**WRONG:**
```css
.topbar { padding: 14px 28px; }  /* web-level-editor/styles.css — off-scale, invented per rule */
```
```

Cite the Task 1 spacing-scale finding. If no source supports the exact 4/8/12/16/24/32 set, keep the set and mark it `> **Advisory:**`.

- [ ] **Step 2: Write Cards 3–5**

Card 3 needs a decision table, not prose:

| Data | Control |
|---|---|
| Bounded numeric (min and max known) | Range slider **paired with** a numeric readout |
| Unbounded numeric | Number input with unit suffix |
| Enum, ≤ 4 options | Segmented control |
| Enum, > 4 options | Select |
| Boolean | Toggle |
| Free text | Text input |

Card 5's RIGHT is the real `1.0× = true Unity scale` treatment from `index.html`.

- [ ] **Step 3: Write Cards 6–8**

These three are gaps in the reference tool — there is no RIGHT example to quote, so write runnable ones.

Card 7's WRONG must be `<div onclick=...>` and its RIGHT a real `<button>` with a `:focus-visible` rule; the GOTCHA names the consequence: `outline: none` with no replacement makes the tool unusable by keyboard and the breakage is invisible to a mouse user, so it ships.

Card 8's RIGHT shows three visible states — unsaved-changes indicator, inline field validation, and an empty-state message — as three short snippets.

- [ ] **Step 4: Add the reference prose**

H2 sections: `## Token Layers` (primitive → semantic), `## Accessibility Floor` (the non-negotiable minimum, citing WAI-ARIA APG from Task 1), `## Common Mistakes` (two-column table).

- [ ] **Step 5: Verify structure**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-design-system.md
```
Expected: `8`

Run:
```bash
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-design-system.md
done
```
Expected: `8` for each.

Run:
```bash
rg -q '^> \*\*Scope:\*\* Browser-based authoring' .claude/rules/web-tool-design-system.md && echo SCOPE_OK || echo SCOPE_MISSING
```
Expected: `SCOPE_OK`

- [ ] **Step 6: Stage**

```bash
git add .claude/rules/web-tool-design-system.md
```

---

### Task 5: `web-tooling/SKILL.md`

**Files:**
- Create: `.claude/skills/web-tooling/SKILL.md`
- Read (do not modify): `.claude/skills/core/scene-hierarchy.md` — copy its frontmatter shape and heading style

**Interfaces:**
- Consumes: the exact card titles produced by Tasks 2, 3 and 4.
- Produces: a skill named `web-tooling`, referenced by Task 6's `skills-index.md` row.

- [ ] **Step 1: Check the frontmatter convention in this repo**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
head -8 .claude/skills/core/scene-hierarchy.md .claude/skills/systems/physics/SKILL.md 2>/dev/null
```
Match whatever `name:` / `description:` / `model-tier:` shape is already in use. Do not invent new frontmatter keys.

- [ ] **Step 2: Write the skill**

```markdown
---
name: web-tooling
description: Use when building or modifying a browser-based authoring, editor, or config tool — a level editor, data authoring page, or any HTML tool a designer opens to produce data another system consumes. Routes to the three web-tool rule files and provides the file skeleton.
---

# Web Authoring Tool — Router

## When this applies

A tool that (a) runs in a browser, (b) a human uses to author data, and (c) exports
that data for another system to read. A level editor is the canonical case.

Does NOT apply to runtime game UI. That is UGUI — see `skills/core/unity-ugui.md`.

## Read in this order

1. `.claude/rules/web-tool-data-contract.md` — the contract with the consuming system.
   First, because it is the most expensive thing to get wrong: a wrong pixel is noticed
   in a second, a wrong enum int is noticed after a level ships.
2. `.claude/rules/web-tool-architecture.md` — how the code is arranged.
3. `.claude/rules/web-tool-design-system.md` — how it looks and feels. Last, because it
   is the cheapest to change later.

## File skeleton

```
tools/<tool-name>/
├── index.html            ← structure only; no inline style, no inline handlers
├── styles.css            ← :root token block first (design-system Card 1 + Card 2)
├── <tool>-core.js        ← pure: model, derivation, serialization. Zero DOM.
├── <tool>.js             ← shell: element queries, event delegation, render
├── <tool>-core.test.js   ← plain assertions, `node <tool>-core.test.js`, no runner
├── <tool>-fixture.json   ← parity fixture, if the tool replicates target-system logic
└── README.md             ← what it exports, where the consuming importer lives
```

## New tool checklist

1. Write down the export schema and the unit/scale contract **before** any UI —
   data-contract Card 1 and Card 4.
2. Create the `:root` token block and the spacing scale — design-system Card 1 and Card 2.
3. Build `<tool>-core.js` and its test first. It must run under `node` with nothing installed —
   architecture Card 3 and Card 7.
4. Build the shell: `index.html` + `<tool>.js`. Render idempotently — architecture Card 6.
5. If the tool previews or simulates target-system behaviour, add the parity fixture and
   its test — data-contract Card 5.
6. Write `README.md` naming the consuming importer by path, so the two sides stay findable.

## Confirm before shipping

- Opens from `file://` with no build step — architecture Card 1.
- `node <tool>-core.test.js` exits 0.
- No raw hex outside `:root`; no off-scale spacing values.
- Every interactive element is reachable and visibly focusable by keyboard —
  design-system Card 7.
```

- [ ] **Step 3: Verify every cross-reference resolves**

Every `Card N` title named in the skill must exist in the file it points at. Run:

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-data-contract.md .claude/rules/web-tool-architecture.md .claude/rules/web-tool-design-system.md
```
Expected: `6`, `7`, `8` respectively.

Then read `SKILL.md` and confirm by eye that each `Card N` reference points at a card number that exists in the named file. A reference to "design-system Card 9" is a bug — there are only 8.

- [ ] **Step 4: Stage**

```bash
git add .claude/skills/web-tooling/SKILL.md
```

---

### Task 6: Integration into CLAUDE.md and skills-index.md

**Files:**
- Modify: `.claude/CLAUDE.md` — the `## Rules (auto-loaded)` table
- Modify: `.claude/docs/skills-index.md`

**Interfaces:**
- Consumes: the four files from Tasks 2–5.
- Produces: nothing downstream. Task 7 is independent of this task.

- [ ] **Step 1: Locate the rules table**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n '^\| `solid-oop.md` \|' .claude/CLAUDE.md
```
The three new rows go immediately after the last existing row of that table.

- [ ] **Step 2: Append the three rows**

```markdown
| `web-tool-data-contract.md` | **Web authoring tools only** — export schema single-source, enum int map, version field, unit/scale contract, parity fixture lock, importer error-on-missing |
| `web-tool-architecture.md` | **Web authoring tools only** — zero-build `file://` constraint, single model source of truth, pure-core/DOM-shell split, ~400 line limit, event delegation, idempotent render, runner-less tests |
| `web-tool-design-system.md` | **Web authoring tools only** — design tokens, fixed spacing scale, control-type decision table, viewport primacy, unit display, destructive-action confirmation, keyboard access, visible state |
```

The `**Web authoring tools only**` prefix on all three is deliberate: this table is read in Unity sessions, and a reader skimming it must be able to skip these three in one glance.

- [ ] **Step 3: Do NOT add these to Session Start**

Confirm no edit was made to the `## Session Start` section:
```bash
git diff .claude/CLAUDE.md | rg '^\+' | rg -i 'session start' && echo 'LEAK - revert that edit' || echo 'OK - session start untouched'
```
Expected: `OK - session start untouched`

- [ ] **Step 4: Add the skills-index row**

Read `.claude/docs/skills-index.md` first to find the correct table and column shape, then add one row for `web-tooling` pointing at `.claude/skills/web-tooling/SKILL.md` with the description: `Browser-based authoring/editor tools — routes to the three web-tool rule files, file skeleton, new-tool checklist`.

- [ ] **Step 5: Confirm auto-load was not touched**

```bash
git status --porcelain .claude/docs/auto-loaded-skills.md .claude/settings.json
```
Expected: **empty output**. Any output means a Global Constraint was violated — revert those files.

- [ ] **Step 6: Stage**

```bash
git add .claude/CLAUDE.md .claude/docs/skills-index.md
```

---

### Task 7: Bite test — audit the reference tool against the new rules

**Files:**
- Create: `docs/superpowers/reports/2026-08-13-web-level-editor-violations.md`
- Read (do not modify): every file under `nile_hole_sphere_repo/tools/web-level-editor/`

**Interfaces:**
- Consumes: the three rule files from Tasks 2–4.
- Produces: the evidence that the rules constrain something real. This is the plan's acceptance test.

- [ ] **Step 1: Audit against each rule file**

Read all three rule files, then read all five source files in `web-level-editor/`. For every violation record: rule file, card number and title, the file and line, what is wrong, and what it should be.

- [ ] **Step 2: Write the report**

```markdown
# `web-level-editor` — Violations Against the New Rule Set

**Date:** 2026-08-13
**Audited:** `nile_hole_sphere_repo/tools/web-level-editor/` (read-only — nothing was changed)
**Purpose:** Bite test. If this list is empty, the rules are too loose to be worth having.

## Violations

| Rule | Card | File:Line | Problem | Fix |
|---|---|---|---|---|
| architecture | 4 | `editor.js` (619 lines) | Holds model, derivation math, preview wiring, DOM listeners and serializer | Extract derivation + serialization into `editor-core.js` |
| design-system | 2 | `styles.css:~50` | `padding: 14px 28px` — off-scale | `var(--space-3) var(--space-6)` |
| ... | | | | |

## Compliant — worth noting

| Rule | Card | Evidence |
|---|---|---|
| design-system | 1 | `styles.css` `:root` block already holds every color as a token |
| data-contract | 5 | `preview-parity-fixture.json` + `preview-core.test.js` are exactly the pattern Card 5 generalizes |

## Verdict

<PASS if the violation table has ≥ 2 rows including at least architecture Card 4 and
design-system Card 2 — the rules bite. FAIL otherwise — the rules are too loose and
Tasks 2–4 need tightening.>
```

- [ ] **Step 3: Check the verdict**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^\| (architecture|design-system|data-contract) \|' docs/superpowers/reports/2026-08-13-web-level-editor-violations.md
```
Expected: **2 or more**.

If the count is 0 or 1, the rules do not constrain anything — **stop and report to the user** that Tasks 2–4 need tightening rather than proceeding. Do not pad the report with invented violations to pass this check.

- [ ] **Step 4: Confirm the reference project was not modified**

```bash
cd /Users/berkterek/Desktop/Github/nile_hole_sphere_repo && git status --porcelain tools/web-level-editor/
```
Expected: **empty output**. Anything else means a read-only constraint was broken.

- [ ] **Step 5: Stage**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add docs/superpowers/reports/2026-08-13-web-level-editor-violations.md
```

---

## Done When

- Three rule files exist with 6 / 7 / 8 complete cards, each card carrying all four parts.
- `web-tooling/SKILL.md` exists and every card cross-reference in it resolves.
- `CLAUDE.md` has three new rows; `skills-index.md` has one; `auto-loaded-skills.md` and `settings.json` are untouched.
- The violation report lists at least two real violations, including architecture Card 4 and design-system Card 2.
- `nile_hole_sphere_repo` has no working-tree changes.
- Everything is staged, nothing is committed.

---

# v2 — Post-Live-Test Corrections (Tasks 8–13)

> **Applies to Tasks 8–13 only.** Everything above is shipped history and is not to be edited, including its now-stale inline card-count assertions — Task 9 records the errata instead of rewriting them.

**Baseline at the start of Task 8** (verified 2026-08-13): `web-tool-design-system.md` = **10** cards, `web-tool-data-contract.md` = **7** cards, `web-tool-architecture.md` = **7** cards. Tasks 1–7's stated counts (6 / 7 / 8) are historical and no longer true.

**Shared conventions every task below must honour** (these are the house rules the reviewer will check against):

- **Card structure:** every rule file opens with an H1, then a `## Scope` line, then `## Cards`, then reference prose. Each card is `### Card N: <Title>` with bold `**WHEN:**`, `**WRONG:**` (fenced code), `**RIGHT:**` (fenced code), `**GOTCHA:**`.
- **GOTCHA bar:** names a concrete observable failure, never a restatement of the rule. "This is bad practice" is a defect. "The importer sees `0`, treats it as `None`, and the collectable silently never spawns" is correct.
- **Advisory:** `> **Advisory:**` records **provenance, not confidence**. A card with no backing research bullet gets one even when it is grounded in working code, and it must state what specifically is unsourced and what the enforceable residue is.
- **Fenced-code exception:** WRONG/RIGHT must be fenced code EXCEPT where the claim is about a real file's shape or size rather than a code construct — then prose is correct and the card must say why. Never fabricate a shortened example to satisfy the fence.
- **Quote integrity:** never present a truncated or paraphrased quote as complete. Two Critical findings were raised during this project for exactly this.
- **Commits:** unlike Tasks 1–7 as written, for **this run commits ARE permitted locally** — matching how Tasks 1–7 were actually executed. Commit locally per task after staging. **Never push.**

**Task ordering rationale:** Task 8 adds a card (architecture 7 → 8), so it must land before Task 9, which writes the corrected counts into the plan's own File Structure table. Tasks 10–13 are content-only within existing cards and change no counts, so they may run in any order after Task 9.

---

### Task 8: New architecture card — list-item identity and ordering (F1)

> This card is **appended** as `### Card 8`, never inserted as Card 3 with a renumber. This project's established convention (see `.claude/rules/architecture.md`'s own history) is: do NOT renumber or edit any existing card; new cards append after the existing ones. Renumbering would break every live external reference to architecture Cards 1–7 for no gain but topical adjacency.

**Files:**
- Modify: `.claude/rules/web-tool-architecture.md` — append a new `### Card 8: Every List Row Has a Stable Identity` directly after the existing `### Card 7: The Pure Core Has Tests, With No Test Runner`. Cards 1–7 are not renumbered, retitled, or otherwise edited.
- Modify: `.claude/CLAUDE.md` — the `web-tool-architecture.md` description row (line ~134)
- Modify: `README.md` — the mirrored `web-tool-architecture.md` description row (line ~214)
- Read (do not modify): `docs/superpowers/research/2026-08-13-web-tool-research.md`

**Interfaces:**
- Consumes: the existing Card 2 (`One Model, One Source of Truth`) conceptually — the new card is a specialization of "the model is the one source of truth" applied to list rows, even though it is physically appended at the end of the card list rather than placed adjacent to Card 2.
- Produces: architecture card count **8**, asserted by Task 9's errata note and by Task 12's SKILL.md reference check.

**Blast radius, explicit:**
- **Counts change:** architecture 7 → **8**. data-contract stays 7. design-system stays 10.
- **No renumbering, no retitling, no editing of Cards 1–7.** Every existing `architecture Card N` reference in the repo — `.claude/skills/web-tooling/SKILL.md` (Cards 1, 3, 6, 7), `web-tool-data-contract.md`, `web-tool-design-system.md`, wherever any of them name an architecture card by number — continues to resolve to the same title it always did and needs no edit. Verified: only six live `architecture Card N` references exist repo-wide (`web-tool-design-system.md` lines 13, 282, 285; `SKILL.md` lines 49, 50, 58), resolving to Cards 1, 2, 3 and 6 — all untouched by an append.
- **Rows that do change:** `.claude/CLAUDE.md` line ~134 and `README.md` line ~214 — the per-file description rows enumerating architecture's topics — each gain the new topic. They must stay byte-identical to each other, as they are today.

- [ ] **Step 1: Snapshot existing architecture card references as a baseline**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n 'architecture(\.md)? Card ([0-9]+)' .claude/rules .claude/skills .claude/CLAUDE.md README.md
```
Expected: a non-empty list, every match resolving to Cards 1–7 (Card 8 does not exist yet). Record the output — Step 4 re-runs the identical command and expects every line outside `.claude/CLAUDE.md`/`README.md` to be byte-for-byte unchanged, since appending Card 8 must not alter a single existing reference. The query is scoped to `.claude/rules .claude/skills .claude/CLAUDE.md README.md` rather than the whole repo — at repo root the widened `architecture(\.md)? Card N` pattern also matches unrelated Unity `architecture.md Card 2.1` hits under `.claude/hooks/` and `docs/PLAN_monobehaviour_hook_structural_detection.md`, which belong to a different rule file entirely and must not be swept into this task.

- [ ] **Step 2: Write the new card as `### Card 8: Every List Row Has a Stable Identity`**

Append it directly after Card 7. It must carry all four parts.

**The specific claim it makes:** a row in an editable collection is identified by a stable key generated at creation time and never reused, never by its array index or its position in the DOM. The model owns the key; the DOM carries it as a data attribute only so an event-delegation handler can map an event back to a row. Deleting a row removes it from the array and does not renumber, reassign, or reuse any other row's key. Duplicate keys are a bug, not a supported state — the tool must not be able to produce one.

**WRONG (fenced JS):** a delete handler that does `model.rows.splice(Number(card.dataset.index), 1)` followed by a re-render that re-derives `dataset.index` from the new array positions — the exact shape used today by architecture Cards 5 and 6. Show that the index held by an already-open editor or an in-flight change event now points at a different row.

**RIGHT (fenced JS):** rows created as `{ id: nextId(), ... }` with a monotonic counter (or `crypto.randomUUID()`); the render writing `data-row-id`; the delegated handler resolving `model.rows.find(r => r.id === el.dataset.rowId)`; delete as `model.rows = model.rows.filter(r => r.id !== id)`; reorder as an array move that touches no `id`. Show that the undo snapshot from design-system Card 9 restores identical `id`s, so a redo after a delete is meaningful.

**GOTCHA — the observable failure, not a restatement:** the user deletes row 3 while row 5's number input still has focus; the re-render renumbers the remaining rows, the pending `change` event fires with `dataset.index === "4"`, and the value the user typed for the old row 5 is silently written into what is now a different row. Nothing throws, the table looks plausible, and the corruption is only found when the exported data is loaded by the consuming system.

**Advisory — required.** No research bullet in `docs/superpowers/research/2026-08-13-web-tool-research.md` covers list-item identity in any of its three sections. The card is grounded in working code and in the F1 live-test gap, not in a cited source, so it opens with `> **Advisory:**` stating exactly that: the stable-key requirement is a judgment call with no external citation; the enforceable residue is that array index must never be the only handle on a row that survives a re-render.

- [ ] **Step 3: Verify the append preserved Cards 1–7 unchanged**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n '^### Card ' .claude/rules/web-tool-architecture.md
```
Expected: exactly 8 lines, numbered 1–8 with no gaps and no duplicates, in the order: `Zero Build, Runs from file://`, `One Model, One Source of Truth`, `Pure Core, DOM Shell`, `File Line Limit ~400`, `Event Delegation, Not Per-Row Listeners`, `Render Is Idempotent`, `The Pure Core Has Tests, With No Test Runner`, `Every List Row Has a Stable Identity`. Cards 1–7 keep exactly their original numbers and titles — only `8` is new.

- [ ] **Step 4: Update the two live description rows; guard that nothing else needed a fix**

Update only `.claude/CLAUDE.md` line ~134 and `README.md` line ~214 — append `stable row identity (never array index)` to the existing topic list in **both**, keeping the two rows byte-identical to each other as they are today.

`.claude/skills/web-tooling/SKILL.md` and the other two `.claude/rules/web-tool-*.md` files are LIVE call sites that name architecture cards by number, but under the append-only approach they need **no** change here — none referenced Card 8 (it didn't exist) and none of their existing Card 1–7 references shifted. This step's verification is therefore a no-op guard, not a rewrite. `docs/superpowers/plans/2026-08-13-web-tool-rules.md` Tasks 1–7, `docs/superpowers/reports/2026-08-13-web-level-editor-violations.md` and `docs/superpowers/specs/2026-08-13-web-tool-rules-design.md` are HISTORICAL and are never touched by this or any future card addition: editing shipped task text contradicts Task 9's own rule that shipped text is a record, not a live checklist, and editing the report or spec would falsify a historical record of what was audited or designed at the time.

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n 'architecture(\.md)? Card ([0-9]+)' .claude/rules .claude/skills .claude/CLAUDE.md README.md
```
Expected: identical to Step 1's recorded baseline for every line outside `.claude/CLAUDE.md` and `README.md`; those two files' own lines are the only ones that changed, gaining the new topic phrase — confirming the sweep is a no-op guard everywhere else.

Run:
```bash
diff <(rg -N '^\| `web-tool-architecture\.md` \|' .claude/CLAUDE.md) <(rg -N '^\| `web-tool-architecture\.md` \|' README.md) && echo ROWS_IDENTICAL || echo ROWS_DIVERGED
```
Expected: `ROWS_IDENTICAL`

Run:
```bash
rg -n 'stable row identity' .claude/CLAUDE.md README.md
```
Expected: exactly 2 lines, one per file.

- [ ] **Step 5: Verify the card is structurally complete and no reference dangles**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-architecture.md
done
```
Expected: `8` for each of the four.

Run:
```bash
rg -on 'architecture(\.md)? Card ([0-9]+)' -r '$2' .claude/rules .claude/skills .claude/CLAUDE.md README.md | awk -F: '$NF>8 {print; bad=1} END {exit bad?1:0}' && echo NO_DANGLING_REFS || echo DANGLING_REF_FOUND
```
Expected: `NO_DANGLING_REFS`. As in Step 1, the search is scoped to `.claude/rules .claude/skills .claude/CLAUDE.md README.md` — the widened pattern also matches unrelated Unity `architecture.md Card 2.1` hits at repo root under `.claude/hooks/` and `docs/PLAN_monobehaviour_hook_structural_detection.md`, which must stay out of scope.

Run:
```bash
rg -q '^> \*\*Advisory:\*\*' .claude/rules/web-tool-architecture.md && rg -A3 '^### Card 8: Every List Row Has a Stable Identity' .claude/rules/web-tool-architecture.md | rg -q 'Advisory' && echo ADVISORY_ON_CARD8 || echo ADVISORY_MISSING
```
Expected: `ADVISORY_ON_CARD8`

- [ ] **Step 6: Stage and commit**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add .claude/rules/web-tool-architecture.md .claude/CLAUDE.md README.md
git commit -m "rules(web-tool): append architecture Card 8 — stable list-row identity"
```

Commit locally only. Do not push.

---

### Task 9: Correct the plan's stale card counts and record the errata

**Files:**
- Modify: `docs/superpowers/plans/2026-08-13-web-tool-rules.md` — the `## File Structure` table (rows for the three rule files, around lines 29–31) and a new errata block
- Read (do not modify): all three `.claude/rules/web-tool-*.md`

**Interfaces:**
- Consumes: the post-Task-8 card counts.
- Produces: a plan that can be re-run or resumed without failing its own verification steps.

**Blast radius, explicit:** documentation-only, confined to this plan file. **No rule file, no `SKILL.md`, no `CLAUDE.md`, no `README.md`, no `skills-index.md` changes.** No card counts change here — this task only records them.

**Why a new task rather than an edit:** Tasks 2, 3, 4 and 5 contain inline `rg -c '^### Card '` assertions expecting `6`, `7`, `8`; the shipped `## Done When` line "Three rule files exist with 6 / 7 / 8 complete cards" (line 665) makes the same now-stale claim. Those numbers are now wrong, so the plan fails its own verification if resumed. The house rule forbids editing shipped task text, so the fix is a clearly-marked errata block that supersedes all of them, plus a correction to the File Structure table, which is descriptive rather than task text and is safe to correct in place.

- [ ] **Step 1: Read the true counts, do not assume them**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-data-contract.md .claude/rules/web-tool-architecture.md .claude/rules/web-tool-design-system.md
```
Expected after Task 8: `7`, `8`, `10` respectively. If any number differs, stop — Task 8 did not land cleanly and Steps 2–3 would enshrine another wrong number.

- [ ] **Step 2: Correct the File Structure table**

Rewrite only the leading card count and the topic list in the three rule-file rows, leaving every other row untouched:

- `web-tool-data-contract.md` → `7 cards.` and the topic list gains tool-side import validation.
- `web-tool-architecture.md` → `8 cards.` and the topic list gains stable row identity.
- `web-tool-design-system.md` → `10 cards.` and the topic list gains bounded undo/redo history and localStorage draft persistence.

- [ ] **Step 3: Add the errata block immediately below the File Structure table**

It must be visually unmissable and must name the superseded assertions precisely rather than gesturing at them:

```markdown
> **ERRATA (v2, 2026-08-13) — card counts in Tasks 2–5 are superseded.**
> Tasks 2, 3, 4 and 5 each contain an inline `rg -c '^### Card '` assertion expecting
> `6` (data-contract), `7` (architecture) and `8` (design-system). Those files have
> since grown. **Current, authoritative counts: data-contract 7, architecture 8,
> design-system 10.** Task 5 Step 3's combined check expecting `6`, `7`, `8` is
> likewise superseded and should be read as `7`, `8`, `10`. The shipped `## Done When`
> line "Three rule files exist with 6 / 7 / 8 complete cards" is superseded the same
> way and should be read as `7 / 8 / 10`. The task text itself is deliberately left
> unedited — it is a record of what shipped, not a live checklist. Architecture's new
> Card 8 was **appended**, not inserted — Cards 1–7 keep their original numbers and
> titles, so this note does not need (and must not add) any "architecture Card N means
> N+1" clause. When resuming this plan, use the counts in this note.
```

- [ ] **Step 4: Verify the errata is present and the table agrees with reality**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -q 'ERRATA \(v2, 2026-08-13\)' docs/superpowers/plans/2026-08-13-web-tool-rules.md && echo ERRATA_PRESENT || echo ERRATA_MISSING
```
Expected: `ERRATA_PRESENT`

Run:
```bash
rg -n '^\| `\.claude/rules/web-tool-(data-contract|architecture|design-system)\.md` \| [0-9]+ cards\.' docs/superpowers/plans/2026-08-13-web-tool-rules.md
```
Expected: 3 lines reading `7 cards.`, `8 cards.`, `10 cards.` respectively — matching Step 1's output exactly.

- [ ] **Step 5: Confirm no shipped task text was edited**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git diff docs/superpowers/plans/2026-08-13-web-tool-rules.md | rg '^-' | rg -v '^---' | rg 'Expected: `[678]`' && echo 'VIOLATION - a shipped assertion was edited' || echo 'OK - shipped task text intact'
```
Expected: `OK - shipped task text intact`

- [ ] **Step 6: Stage and commit**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add docs/superpowers/plans/2026-08-13-web-tool-rules.md
git commit -m "docs(plan): correct web-tool card counts, add v2 errata note"
```

---

### Task 10: Resolve the delete/undo overlap between design-system Cards 6 and 9 (F3)

**Files:**
- Modify: `.claude/rules/web-tool-design-system.md` — `### Card 6: Destructive Actions Confirm` (WHEN at line ~174), `### Card 9: Authoring Work Is Recoverable` (WHEN ~265, Advisory ~267), and the `## Common Mistakes` rows at lines ~373 and ~377
- Read (do not modify): `docs/superpowers/research/2026-08-13-web-tool-research.md`

**Interfaces:**
- Consumes: architecture's new `Card 8: Every List Row Has a Stable Identity` (Task 8) — Card 9 gains a cross-reference to it.
- Produces: a single decision rule that an agent can apply without reading both cards and guessing.

**Blast radius, explicit:** **no count change** (design-system stays 10), **no renumbering, no title change.** Content-only inside two existing cards plus two Common Mistakes rows. **No change to `SKILL.md`, `CLAUDE.md`, `README.md`, or `skills-index.md`** — the description rows already say "destructive-action confirmation" and "bounded undo/redo history", and both remain accurate.

**The conflict, stated precisely.** Card 6's WHEN is unconditional: *"An action deletes data, replaces existing data wholesale, or cannot be trivially redone by re-entering the same input."* Card 9's WHEN covers *"a delete, a wholesale replace, a batch operation"*, and Card 9's Advisory says: *"An undo stack is the PRIMARY recovery mechanism; `confirm()` (Card 6) is the fallback for the narrow set of actions an undo stack cannot reach (e.g. a destructive action that also triggers an irreversible external side effect)."* Undefined: whether an ordinary in-model row delete — which undo **can** reach — still needs a `confirm()`. Card 6's WHEN was never amended to carve that out, and its WRONG/RIGHT show a plain `confirm()` on a row delete with no mention of undo. A literal reading of Card 6 alone still demands a confirm on every delete, which is why the live-test agent had to guess.

- [ ] **Step 1: Amend Card 6's WHEN with the carve-out**

The new WHEN must state the decision rule as a test the agent applies, in this shape: an action requires `confirm()` when it is destructive **and** at least one of — it is not covered by the undo stack; it escapes the model (writes a file, calls a network endpoint, clears persisted storage); or it discards more than a single row's worth of work in one gesture. An in-model single-row delete that the undo stack captures does **not** get a `confirm()` — it gets an undo entry and, if the tool has one, a transient "Deleted — Undo" affordance.

Keep Card 6's existing bold `**WRONG:**`/`**RIGHT:**` markers and their fenced examples exactly as they are (a plain `confirm()` on a destructive action) — do not add a second pair of bold markers. Instead add a second, contrasting fenced code block **underneath each existing marker**: under the existing `**WRONG:**` marker, a second fenced block showing `confirm("Delete this row?")` on an undoable single-row delete; under the existing `**RIGHT:**` marker, a second fenced block showing the same delete pushed onto the undo stack with no dialog. Both fenced JS. The bold marker count for the file must stay exactly one `**WRONG:**` and one `**RIGHT:**` per card — Task 9's design-system count of 10 depends on this.

Card 6's GOTCHA must be extended or replaced so it names an observable failure of over-confirming, not just of under-confirming: an author editing a 40-row table dismisses a modal on every single delete, learns to hit Enter reflexively, and then blows through the one dialog that guarded the irreversible "Clear all and re-import" — the dialog stopped carrying information the moment it fired on everything.

- [ ] **Step 2: State the rule operationally in Card 9, and add its cross-reference to architecture Card 8**

Card 9's Advisory already establishes the precedence. Add, adjacent to it, the same decision rule expressed from the undo side so a reader arriving at Card 9 first reaches the identical conclusion: every model mutation pushes a snapshot; `confirm()` is added **only** when the mutation fails the Card 6 test above. Cross-reference Card 6 by its exact title, `Card 6: Destructive Actions Confirm`.

Re-check the existing Card 9 → Card 6 cross-reference still reads correctly after Step 1's WHEN rewrite; it is currently phrased as a fallback relationship and must not now contradict Card 6's own text.

Also add, in this step, the one cross-reference this plan gives Card 9 to architecture's new `Card 8: Every List Row Has a Stable Identity` (Task 8) — this replaces the design-system-side edit Task 8 originally proposed and never landed, since Card 9 is the only design-system card that actually needs it. Add the sentence: *"An undo snapshot is only meaningful if it restores the same row identity it captured — see `web-tool-architecture.md Card 8: Every List Row Has a Stable Identity`."* State why row identity is load-bearing here: Card 9's undo stack stores snapshots to replay; if a row is identified by its position in the array rather than a stable key, a delete that shifts every later row's position means an undo snapshot taken before the delete no longer maps onto the same rows after a redo — it restores whatever row now happens to sit at that index, not the row the snapshot actually captured.

- [ ] **Step 3: Advisory treatment**

No research bullet in any of the three sections of the research notes bears on confirm-vs-undo precedence. The carve-out is therefore unsourced and must be marked. Card 6 gains a `> **Advisory:**` stating specifically that the *boundary* between confirm-worthy and undo-only actions is a judgment call with no external citation, and that the enforceable residue is: a destructive action is never silent — it is either undoable **or** confirmed, and the tool must be able to say which for every destructive action it offers.

- [ ] **Step 4: Reconcile the Common Mistakes rows**

Read lines ~373 and ~377 of `web-tool-design-system.md`. One row currently pairs with Card 6 and one with Card 9. Both must now be consistent with the decision rule — in particular, no row may state or imply "every delete confirms". If a row does, restate it as the failure the rule actually prevents.

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n -i 'confirm' .claude/rules/web-tool-design-system.md
```
Expected: every hit is either inside Card 6, inside Card 9's precedence text, or a Common Mistakes row that is consistent with the decision rule. Read each hit; a hit that says a delete always confirms is a defect this task must fix.

- [ ] **Step 5: Verify counts and structure are untouched**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-design-system.md
```
Expected: `10` — unchanged.

Run:
```bash
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-design-system.md
done
```
Expected: `10` for each.

Run:
```bash
rg -n '^### Card (6|9): ' .claude/rules/web-tool-design-system.md
```
Expected: exactly `### Card 6: Destructive Actions Confirm` and `### Card 9: Authoring Work Is Recoverable` — titles unchanged.

- [ ] **Step 6: Stage and commit**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add .claude/rules/web-tool-design-system.md
git commit -m "rules(web-tool): resolve Card 6 / Card 9 delete-confirm vs undo overlap"
```

---

### Task 11: Card 3 control-table wording pass, including the segmented-control row (F2)

**Files:**
- Modify: `.claude/rules/web-tool-design-system.md` — `### Card 3: Control Type Derives from Data Type`, its Advisory (line ~80) and its decision table (the `| Enum, ≤ 4 options | Segmented control |` row is line ~94)
- Read (do not modify): `.claude/rules/web-tool-design-system.md` `## Accessibility Floor` section (lines ~352–362), `docs/superpowers/research/2026-08-13-web-tool-research.md`

**Interfaces:**
- Consumes: the Accessibility Floor's listbox keyboard contract.
- Produces: a Card 3 whose table no longer steers a tool toward building a custom widget by default.

**Blast radius, explicit:** **no count change** (design-system stays 10), **no title change, no renumbering.** Content-only within Card 3. **No cross-reference updates required** in `SKILL.md`, `CLAUDE.md`, `README.md` or `skills-index.md` — "control-type decision table" remains an accurate description row entry in both `CLAUDE.md` line 135 and `README.md` line 215.

**Why this is a wording pass and not its own rule change.** The tension is real: a segmented control is a custom listbox-shaped widget with no native HTML equivalent, so recommending it triggers the Accessibility Floor obligation, which closes with *"The contracts above apply the moment a tool builds a **custom** version of any of these three widgets instead of using the native element."* `<select>` inherits that contract for free. But Card 3's own Advisory at line 80 **already** flags this exact row as one of five *"conventional UI judgment calls with no supporting research bullet"*, so the row is already non-binding — which is why this is folded in here rather than given its own task and its own review gate.

- [ ] **Step 1: Rewrite the segmented-control row to state its cost inline**

The row must no longer read as a bare recommendation. It must carry the price: a segmented control is a custom listbox and therefore owes the full Accessibility Floor keyboard contract — arrow-key roving focus, `role="listbox"`/`role="option"`, `aria-selected`, and a single tab stop for the group. `<select>` is the default and satisfies the contract with no work. Choose the segmented control only when the options must be visible simultaneously (a mode switch the author toggles constantly), and then implement the contract.

- [ ] **Step 2: Sweep the remaining rows for the same failure mode**

Read every row of the table and check each against the same question: does the recommended control require custom keyboard work that the card does not mention? The `Bounded numeric → Range slider paired with a numeric readout` row is the other candidate — a native `<input type="range">` is fine, a custom-drawn slider is not, and the Accessibility Floor names slider as one of its three widgets. State that distinction in the row rather than leaving it to the reader.

- [ ] **Step 3: Update Card 3's Advisory to keep provenance honest**

The Advisory at line ~80 currently names five judgment calls with no supporting research bullet. After Steps 1–2 the accessibility consequence **is** grounded — it derives from the Accessibility Floor, which cites WAI-ARIA APG. The Advisory must be reworded to keep the two apart: the *mapping* from data type to control remains an unsourced convention; the *keyboard contract owed by a custom widget* is sourced and is not advisory. Do not delete the Advisory — the mapping is still unsourced.

**Quote integrity check:** if the reworded Advisory quotes the Accessibility Floor's closing sentence, quote it in full — *"The contracts above apply the moment a tool builds a **custom** version of any of these three widgets instead of using the native element."* — or paraphrase without quotation marks. A truncated quote presented as complete has already drawn two Critical findings on this project.

- [ ] **Step 4: Verify**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n 'Segmented control' .claude/rules/web-tool-design-system.md
```
Expected: the row now mentions the keyboard contract or `<select>` as the default on the same line or the line immediately following. A bare `| Enum, ≤ 4 options | Segmented control |` with nothing else is a fail.

Run:
```bash
rg -c '^### Card ' .claude/rules/web-tool-design-system.md
```
Expected: `10` — unchanged.

Run:
```bash
rg -A2 '^### Card 3: Control Type Derives from Data Type' .claude/rules/web-tool-design-system.md | rg -q 'Advisory' && echo ADVISORY_RETAINED || echo ADVISORY_LOST
```
Expected: `ADVISORY_RETAINED`

- [ ] **Step 5: Stage and commit**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add .claude/rules/web-tool-design-system.md
git commit -m "rules(web-tool): Card 3 control-table wording pass — name the custom-widget cost"
```

---

### Task 12: Narrow SKILL.md's preview-applicability note (F4)

**Files:**
- Modify: `.claude/skills/web-tooling/SKILL.md` — the `## Applicability note — preview/simulation cards` section (the note is at line ~27)
- Modify: `.claude/rules/web-tool-design-system.md` — `### Card 5: Every Numeric Field Shows Unit and Real Scale` (WHEN at line ~149, Advisory ~151, RIGHT ~159–166, GOTCHA ~168)

**Interfaces:**
- Consumes: the card titles as they stand after Tasks 8, 10 and 11.
- Produces: a note that excludes only the genuinely preview-dependent half of Card 5.

**Blast radius, explicit:** **no count change**, **no renumbering, no title change.** `CLAUDE.md` and `README.md` description rows both already list "unit display" for design-system and need **no** update. `skills-index.md` needs none. Only `SKILL.md` and Card 5's own body change.

**The defect, quoted in full.** `SKILL.md` line 27 reads verbatim: *"Three cards assume the tool previews or simulates the data it edits: `web-tool-design-system.md Card 4: The Viewport Is First-Class`, `web-tool-design-system.md Card 5: Every Numeric Field Shows Unit and Real Scale`, and `web-tool-data-contract.md Card 5: Replicated Logic Is Locked by a Parity Fixture`. A pure data-authoring tool — a table or list editor with no visual preview — has nothing for these three to apply to and skips them."* But Card 5's WHEN says *"A numeric field **or** preview control…"*, and the card splits in two: the real-scale/exaggeration half (the RIGHT example at 159–166 and the GOTCHA at 168) is genuinely preview-specific, while the unit-suffix half applies to **any** numeric field with an implicit unit — Card 5's own Advisory at line 151 already says it *"covers the same concern at the **UI-surface level**, not the export schema."* The live-test agent added a `sec` suffix on its own judgment precisely because the note had told it to skip the whole card.

- [ ] **Step 1: Split the note's treatment of design-system Card 5**

The note must now say: two cards are fully skipped by a preview-less tool — `web-tool-design-system.md Card 4: The Viewport Is First-Class` and `web-tool-data-contract.md Card 5: Replicated Logic Is Locked by a Parity Fixture`. `web-tool-design-system.md Card 5` is **partially** skipped: its real-scale/exaggeration requirement needs a preview and does not apply, but its unit-suffix requirement applies to every numeric field in every tool, preview or not — a field holding seconds shows `sec`, a field holding a fraction shows `×` or `%`. Name the halves explicitly so an agent can act on the note without opening the card.

- [ ] **Step 2: Make Card 5 self-describing so it survives the note being wrong again**

Amend Card 5's WHEN to state its own two-part structure rather than relying on `SKILL.md` to split it: the unit-suffix requirement is unconditional for any numeric field whose unit is not in its label; the real-scale requirement applies only when the tool renders a preview of the value. Leave the existing bold `**RIGHT:**` marker at 159–166 and the existing `**GOTCHA:**` at 168 in place exactly as they are — they are the real-scale half and are correct — and add the unit-suffix half as a second fenced code block placed directly underneath the existing `**RIGHT:**` marker — not as a new bold marker: a number input with a unit suffix element and a label that does not repeat the unit. The file's marker count must stay exactly one `**RIGHT:**` per card — Task 9's design-system count of 10 depends on this.

Card 5's GOTCHA already names a real-scale failure. Add or extend so the unit half has one too, naming an observable failure: the author types `500` into a duration field believing it is milliseconds, the tool stores seconds, the exported wave takes eight minutes to spawn, and nothing in the tool or the importer flags it because `500` is a valid number in both units.

- [ ] **Step 3: Add the missing verification — nobody checks the note's accuracy**

Task 5 Step 3 only checks that referenced cards **exist**; nothing checks that the applicability note's claims about them are true. Add this check to the tool's shipping routine in `SKILL.md`'s `## Confirm before shipping` list, phrased as a reviewer instruction: *if the tool has no preview, confirm the note's exclusions were applied at the half-card granularity — a preview-less tool still shows units.*

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n 'Card 5' .claude/skills/web-tooling/SKILL.md
```
Expected: the design-system Card 5 mention is qualified as partial; the data-contract Card 5 mention remains a full exclusion. Two distinct treatments, both visible.

Run:
```bash
rg -q 'partially|partial' .claude/skills/web-tooling/SKILL.md && echo NOTE_SPLIT || echo NOTE_STILL_BINARY
```
Expected: `NOTE_SPLIT`

- [ ] **Step 4: Verify every card reference in SKILL.md still resolves after Task 8's append**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -c '^### Card ' .claude/rules/web-tool-data-contract.md .claude/rules/web-tool-architecture.md .claude/rules/web-tool-design-system.md
```
Expected: `7`, `8`, `10`.

Then read `SKILL.md` in full and confirm by eye that every `Card N` reference points at a card number that exists in the named file, and that every reference quoting a card **title** quotes the current title exactly — Task 8 appended architecture Card 8 without renumbering Cards 1–7, and Task 10 may have adjusted Card 6's surrounding text. A reference to "architecture Card 3: Pure Core, DOM Shell" is still correct — Card 8's append left Card 3 untouched. The only reference that would be a bug here is one naming a card above 8, or one quoting a title that no longer matches the card it points at.

Run:
```bash
rg -c '^### Card ' .claude/rules/web-tool-design-system.md
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-design-system.md
done
```
Expected: `10` cards, and `10` for each of the four markers.

The marker loop is not redundant with Task 10 Step 5. Step 2 of this task adds a second fenced block under Card 5's existing `**RIGHT:**` marker — the exact edit whose failure mode is an extra marker — and Tasks 10–13 may run in any order after Task 9. If Task 10 ran first, its marker assertion cannot catch a botched edit made here. Each task that touches a card body asserts the marker counts itself.

- [ ] **Step 5: Stage and commit**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add .claude/skills/web-tooling/SKILL.md .claude/rules/web-tool-design-system.md
git commit -m "skill(web-tooling): narrow preview-applicability note; split design-system Card 5"
```

---

### Task 13: Disambiguate architecture Card 2's data-flow carve-out (F5)

**Files:**
- Modify: `.claude/rules/web-tool-architecture.md` — `### Card 2: One Model, One Source of Truth`, its Advisory (line ~36), WRONG (~38–44) and RIGHT (~46–54)
- Read (do not modify): `docs/superpowers/research/2026-08-13-web-tool-research.md` — the `## Vanilla architecture` section, bullet at line ~43

**Interfaces:**
- Consumes: the research bullet that the current wording was derived from.
- Produces: a Card 2 whose stated rule matches its own RIGHT example.

**Blast radius, explicit:** **no count change** (architecture stays 8 after Task 8), **no renumbering, no title change.** Lowest blast radius of the v2 tasks. `CLAUDE.md` line 134 and `README.md` line 214 already say "single model source of truth" and need **no** update. No `SKILL.md` change.

**The defect, precisely.** Card 2's Advisory at line ~36 states the rule as *"the direction of data flow: model → render, never DOM → model **except to locate an event-delegation target**"* — a carve-out phrased around **locating a target**, not around **reading the value** that triggered the event. Yet Card 2's own RIGHT example at lines 46–54 does `model.wallHeight = num(e.target.value)`, which is reading a value, not locating a target. Its WRONG at 38–44 is a `getWallHeight()` that reads `document.getElementById(...).value` at an arbitrary later time. So the card's stated rule forbids what its own RIGHT example does. The real distinction is: **an event-time read that writes into the model is correct; reading state back out of the DOM independently of an event, as if the DOM were the source, is the violation.**

- [ ] **Step 1: Rewrite the Advisory's carve-out to match the RIGHT example**

State the distinction as time-and-direction, not as target-location: inside an event handler, reading `e.target.value` (or the target's `dataset`) to write into the model is the one legitimate DOM → model flow, because it is the only moment the DOM holds information the model does not yet have. Outside an event handler, any read of a DOM node's value as a source of truth is a violation, however innocuous it looks.

- [ ] **Step 2: Add one clarifying sentence tying WRONG and RIGHT together**

The card must explicitly say why its WRONG and RIGHT are not the same operation, since both read `.value`. The RIGHT read happens once, at event time, and its result is immediately written into the model; the WRONG read happens at an arbitrary later time and its result is used *instead of* the model. Same API call, opposite role.

- [ ] **Step 3: Keep the Advisory honest about provenance**

The research bullet in `## Vanilla architecture` (line ~43) carries the **identical narrow carve-out** — phrased around locating a delegation target. Extending it to cover event-time value reads is this project's judgment, not the source's. The Advisory must say so specifically: the sourced part is event delegation and the model-owns-state direction; the event-time-value-read carve-out is an extension made here, and the enforceable residue is that no function outside an event handler may read a DOM node to answer a question the model can answer.

Do not restate the research bullet as though the source made this distinction. Quote it in full or paraphrase it unquoted.

- [ ] **Step 4: Verify**

Run:
```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
rg -n -A20 '^### Card 2: One Model, One Source of Truth' .claude/rules/web-tool-architecture.md
```
Expected: the Advisory no longer says "except to locate an event-delegation target" as its only carve-out; it names the event-time read explicitly, and it flags the extension as unsourced.

Run:
```bash
rg -q 'except to locate an event-delegation target' .claude/rules/web-tool-architecture.md && echo OLD_WORDING_REMAINS || echo OLD_WORDING_REPLACED
```
Expected: `OLD_WORDING_REPLACED`

Run:
```bash
rg -c '^### Card ' .claude/rules/web-tool-architecture.md
```
Expected: `8` — unchanged.

Run:
```bash
for p in 'WHEN:' 'WRONG:' 'RIGHT:' 'GOTCHA:'; do
  printf '%s => ' "$p"; rg -c "\*\*$p\*\*" .claude/rules/web-tool-architecture.md
done
```
Expected: `8` for each.

- [ ] **Step 5: Stage and commit**

```bash
cd /Users/berkterek/Desktop/Github/unity-claude-ai-template-repo
git add .claude/rules/web-tool-architecture.md
git commit -m "rules(web-tool): clarify architecture Card 2 event-time DOM read carve-out"
```

---

## Done When — v2 (Tasks 8–13)

- `web-tool-architecture.md` has **8** cards, the new **`Card 8: Every List Row Has a Stable Identity`** carries all four parts plus an `> **Advisory:**`, and no reference anywhere in the repo points at an architecture card number above 8.
- The plan's own File Structure table reads `7` / `8` / `10` cards, and the v2 ERRATA block names Tasks 2–5's superseded assertions explicitly. No shipped task text was edited.
- Design-system Cards 6 and 9 state one decision rule for confirm-vs-undo, reachable from either card, and no line in the file says a delete always confirms.
- Design-system Card 3's control table names the accessibility cost of each custom widget it recommends, and its Advisory separates the unsourced mapping from the sourced keyboard contract.
- `SKILL.md`'s applicability note excludes design-system Card 5 only in half, and Card 5's WHEN states its own two-part structure so it survives the note drifting again.
- Architecture Card 2's stated rule matches its own RIGHT example, and its Advisory marks the event-time-read carve-out as an extension beyond the research bullet.
- Every rule file still has `**WHEN:** / **WRONG:** / **RIGHT:** / **GOTCHA:**` counts equal to its card count: 7 / 8 / 10.
- `.claude/CLAUDE.md` and `README.md` carry byte-identical `web-tool-architecture.md` description rows, both including stable row identity.
- `auto-loaded-skills.md` and `settings.json` are untouched; `nile_hole_sphere_repo` has no working-tree changes.
- All six tasks are committed locally. **Nothing is pushed.**