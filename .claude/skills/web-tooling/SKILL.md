---
name: web-tooling
description: Use when building or modifying a browser-based authoring, editor, or config tool — a level editor, data authoring page, or any HTML tool a designer opens to produce data another system consumes. Routes to the three web-tool rule files and provides the file skeleton.
model-tier: normal
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
├── <tool>-core.test.js   ← node:test/node:assert, `node --test <tool>-core.test.js`, no install
├── <tool>-fixture.json   ← parity fixture, if the tool replicates target-system logic
└── README.md             ← what it exports, where the consuming importer lives
```

## New tool checklist

1. Write down the export schema and the unit/scale contract **before** any UI —
   data-contract Card 1: One Schema, One Place and Card 4: Units and Scale Are Written Down.
2. Create the `:root` token block and the spacing scale — design-system Card 1: No Color
   Outside Tokens and Card 2: Fixed Spacing Scale.
3. Build `<tool>-core.js` and its test first. It must run under `node` with nothing installed —
   architecture Card 3: Pure Core, DOM Shell and Card 7: The Pure Core Has Tests, With No Test Runner.
4. Build the shell: `index.html` + `<tool>.js`. Render idempotently — architecture Card 6:
   Render Is Idempotent.
5. If the tool previews or simulates target-system behaviour, add the parity fixture and
   its test — data-contract Card 5: Replicated Logic Is Locked by a Parity Fixture.
6. Write `README.md` naming the consuming importer by path, so the two sides stay findable.

## Confirm before shipping

- Opens from `file://` with no build step — architecture Card 1: Zero Build, Runs from file://.
- `node --test <tool>-core.test.js` exits 0.
- No raw hex outside `:root`; no off-scale spacing values.
- Every interactive element is reachable and visibly focusable by keyboard —
  design-system Card 7: Keyboard Access and Visible Focus.
