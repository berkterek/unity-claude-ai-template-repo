# Web Authoring Tool Rules & Skill — Design

**Date:** 2026-08-13
**Status:** Approved (design), not yet implemented
**Repo:** `unity-claude-ai-template-repo`

---

## Problem

`nile_hole_sphere_repo/tools/web-level-editor/` is a browser-based level editor
(vanilla JS, zero build, `file://`, ~1250 lines across 5 files). It was built with no
written standard. The next project will need a similar authoring tool, and without a
captured standard the same problems recur:

- Visual language re-invented per tool; spacing and color drift.
- Logic and DOM wiring collapse into one file (`editor.js` is already 619 lines).
- The data contract with Unity (JSON keys mirroring C# `[SerializeField]` names,
  enums as ints, a preview that replicates a C# generator) is the most fragile
  surface and is held together only by convention.

Goal: capture the standard in the template repo so it is reused, not re-derived.

---

## Scope

**In scope:** normative rules and one router skill governing **browser-based
authoring/editor/config tools** — tools a designer opens in a browser to produce data
consumed by another system.

**Out of scope:**
- Runtime game UI (UGUI / UI Toolkit) — governed by existing Unity rules.
- Refactoring the existing `web-level-editor` to conform. Separate task.
- Enforcement hooks and slash commands. Deliberately excluded (see Decisions).

Every rule file carries a `## Scope` line stating this boundary explicitly.

---

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Coverage | Visual design **and** code architecture, in separate files | Mixing them produces a file no one navigates |
| Sourcing | Research external references, then translate to repo idiom | Grounds rules in established practice rather than one project's habits |
| Enforcement | Rules + skill only; **no hooks, no slash command** | Zero false-positive risk, zero maintenance burden. Accepted weakness: instruction-only, no mechanical block |
| Stack constraint | Zero-build vanilla mandated | Authoring tools outlive the project that spawned them; `npm install` will not work in two years |
| Data contract | Own rule file (third file) | Highest-cost failure class in this domain |
| Packaging | Rules-heavy, one thin skill | Matches existing repo idiom: `rules/` = normative standard, `skills/` = how-to. Keeps `skills-index.md` from bloating |

---

## Deliverables

```
.claude/rules/
├── web-tool-design-system.md
├── web-tool-architecture.md
└── web-tool-data-contract.md

.claude/skills/web-tooling/
└── SKILL.md
```

Format follows the existing repo convention: a `## Cards` section at the top
(WHEN / WRONG / RIGHT / GOTCHA per card), reference prose below it.

### Integration

| File | Change |
|---|---|
| `.claude/CLAUDE.md` | Three rows added to the `## Rules (auto-loaded)` table |
| `.claude/CLAUDE.md` | **Not** added to `## Session Start` — irrelevant load in a Unity session |
| `.claude/docs/skills-index.md` | One row for `web-tooling` |
| `auto-loaded-skills.md` | **Untouched** — `web-tooling` loads on demand |

`rules/` bodies are referenced by name, not `@`-included, so these three files do not
inflate Unity-session context.

---

## Rule File Contents

### `web-tool-design-system.md`

| # | Card | Origin |
|---|---|---|
| 1 | No color outside tokens. Every color/shadow/radius is a `:root` variable; raw hex appears only inside `:root` | Existing `styles.css` already complies — codified |
| 2 | Fixed spacing scale (4/8/12/16/24/32). No intermediate values | Currently arbitrary (`14px 28px`) — requires correction |
| 3 | Control type derives from data type: bounded numeric → slider + numeric pair; enum → select; boolean → toggle. No free choice | `exag` slider + `exagVal` pair is the correct pattern |
| 4 | Viewport is first-class. The tool's primary surface is the viewport, not the form; panels never crowd it out | `preview-hero` sticky layout |
| 5 | Every numeric field shows its unit and real-scale equivalent | `1.0× = true Unity scale` note — correct reflex, promoted to rule |
| 6 | Destructive actions confirm; every action is undoable or warns | Gap — not present today |
| 7 | Keyboard access and `:focus-visible` required. Every clickable is a `<button>`; `<div onclick>` forbidden | Gap |
| 8 | State must be visible: unsaved changes, validation errors, empty states. Silent failure forbidden | Gap |

### `web-tool-architecture.md`

| # | Card |
|---|---|
| 1 | Zero build, runs from `file://`. No build step, no npm dependency, no transpile. ES modules permitted |
| 2 | One model, one source of truth. State is never read back from the DOM. Derived data is always derived, never hand-maintained |
| 3 | Pure core / DOM shell split. Computation and transformation live in a DOM-free `*-core.js`; the DOM file is wiring only |
| 4 | File line limit ~400. Past that, split responsibilities |
| 5 | Event delegation — no per-row listener binding |
| 6 | Render is idempotent — the same model rendered twice yields the same DOM |
| 7 | The pure core must have tests, with no external test runner (plain assertions runnable under `node`) |

`editor.js` at 619 lines violates Cards 3 and 4; it will appear as the WRONG example.

### `web-tool-data-contract.md`

| # | Card |
|---|---|
| 1 | The schema is defined in one place; both writer and reader reference it. Key names are never hand-typed twice |
| 2 | The enum→int map lives in one constant block, never scattered across call sites |
| 3 | Every export carries a `version` field; the importer does not silently proceed on an unknown version |
| 4 | The unit/scale contract is written down (e.g. "all spatial magnitudes are fractions of terrain size") at the head of both sides |
| 5 | If preview logic replicates a target system, it is locked by a parity fixture test. The fixture is committed; the test breaks when the replication drifts |
| 6 | The importer errors on null/missing fields rather than falling back to defaults and silently producing a wrong level |

Card 5 generalizes the existing `preview-parity-fixture.json` + `preview-core.test.js`
pair — the most valuable pattern in the current tool.

---

## Skill: `web-tooling/SKILL.md`

A router, not a tutorial:

- **Trigger:** authoring/editor/config tool that runs in a browser.
- **Reading order:** data-contract → architecture → design-system. Contract first
  because it is the most expensive to get wrong; visual language last because it is
  the cheapest to change.
- **Skeleton:** `index.html` / `styles.css` (token block pre-filled) /
  `<tool>-core.js` (pure) / `<tool>.js` (DOM) / `<tool>-core.test.js` / `README.md`.
- **A six-step checklist** for standing up a new tool.

---

## Research Plan

Executed before rule authoring; three independent queries.

| Topic | Sources | Extract |
|---|---|---|
| Visual language | Refactoring UI principles; Radix/shadcn token architecture; WAI-ARIA Authoring Practices (dialog, slider, listbox); Tiled and Blender UI conventions | Concrete numeric scales (spacing, type), control patterns, accessibility floor |
| Vanilla architecture | Zero-build ES-module tool examples; "you might not need a framework" patterns; event delegation and idempotent render approaches | File-split thresholds, state→render contract |
| Data contract | Consumer-driven contract testing; schema versioning practice; JSON schema approaches in game editors | Validation of the versioning and fixture strategy |

Findings are translated into the repo's Cards idiom, never pasted verbatim. Any rule
that is opinion rather than sourced practice is marked `> Advisory`, matching the
existing convention in `architecture.md`.

---

## Verification

Work is complete when:

1. Three rule files and one skill exist; every card has WRONG and RIGHT examples.
2. Every RIGHT example is either quoted from `web-level-editor` or is runnable code.
3. `CLAUDE.md` and `skills-index.md` are updated.
4. **Bite test:** the existing `web-level-editor` is read against the new rule set and
   a violation list is produced. An empty list means the rules are too loose — at
   minimum `editor.js` size (architecture Card 4) and the spacing scale (design Card 2)
   must appear. This is the evidence that the rules actually constrain something.

---

## Risks

| Risk | Mitigation |
|---|---|
| Instruction-only enforcement is ignored | Accepted by decision. The skill router raises the chance the rules are read at the right moment |
| Rules leak into Unity UI work | Explicit `## Scope` line in each file; `web-tool-` filename prefix; separate CLAUDE.md rows |
| Rules become stale relative to the tool they describe | Cards describe shape and constraint, not file names or symbols — the same rationale used for `ARCHITECTURE.md` intent contracts |
