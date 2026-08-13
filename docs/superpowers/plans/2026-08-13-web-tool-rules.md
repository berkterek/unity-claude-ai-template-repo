# Web Authoring Tool Rules & Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

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
