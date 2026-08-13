# Web Tool — Architecture Rules (NON-NEGOTIABLE)

> **Scope:** Browser-based authoring/editor/config tools only. NOT runtime game UI (UGUI / UI Toolkit) — see rules/unity-prefabs.md and skills/core/unity-ugui.md for that.

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: Zero Build, Runs from file://

**WHEN:** Starting any new browser-based authoring/editor tool for the project.

> **Advisory:** No supporting research bullet on this exact framing — this rule generalizes from how `web-level-editor/index.html` and `editor.js` are actually shipped (no bundler, no `npm install`, opened directly as a file).

**WRONG:**
```html
<!-- Requires `npm install && npm run build` before the tool can be opened at all -->
<script type="module" src="./dist/bundle.js"></script>
```

**RIGHT:**
```html
<!-- Opens directly from disk — no build step, no dev server, no node_modules -->
<script src="./editor-core.js"></script>
<script src="./editor.js"></script>
```

**GOTCHA:** A build-tool-dependent editor stops opening the day the project's Node version drifts, a bundler config bit-rots, or someone clones the repo two years later without the original `package-lock.json` toolchain resolving cleanly. A tool that is two `<script>` tags and a `file://` URL has no toolchain to rot.

---

### Card 2: One Model, One Source of Truth

**WHEN:** Any UI element (a slider, a `<select>`, a text field) needs to reflect or change tool state.

> **Advisory:** No supporting research bullet cites this exact rule by name — the underlying research bullet is `(secondary, unverified against a second source)` and, paraphrased rather than quoted here, says: application state should not be derived by reading it back from the DOM, with a narrow carve-out for locating an event-delegation target — render() should read from a single source of truth instead. That source's carve-out is scoped only to **locating** a delegation target; this card extends the carve-out to also cover **reading the value** that triggered the event, which the source itself does not say — that extension is this project's judgment, not the source's. The enforceable part, restated as time-and-direction rather than target-location: inside an event handler, reading `e.target.value` (or the target's `dataset`) to write into the model is the one legitimate DOM → model flow, because it is the only moment the DOM holds information the model does not yet have. Outside an event handler, any read of a DOM node's value as a source of truth is a violation, however innocuous it looks. The enforceable residue beyond the sourced part (event delegation, model-owns-state direction) is: no function outside an event handler may read a DOM node to answer a question the model can answer.

**WRONG:**
```js
// Reading current state back out of the DOM instead of the model
function getWallHeight() {
  return Number(document.getElementById("wallHeight").value); // DOM is now the source of truth
}
```

**RIGHT:**
```js
// model is the single source of truth; the DOM element only ever displays it
const model = { wallHeight: 0.30 };
$("wallHeight").addEventListener("input", (e) => {
  model.wallHeight = num(e.target.value); // write model, not just the input's own value
  redraw();
});
```

WRONG and RIGHT both call `.value` — the difference is not the API, it's the time and the role of the read. RIGHT's read happens once, at event time, inside the handler that just fired, and its result is written into the model immediately. WRONG's read happens at an arbitrary later time — whenever something calls `getWallHeight()` — and its result is used *instead of* the model, as if the DOM element, not `model.wallHeight`, were the source of truth. Same `.value` call, opposite role: one is the model catching up to an event that already happened, the other is the DOM standing in for state the model should already hold.

**GOTCHA:** Once two code paths both claim to know "the current wall height" — one reading `model.wallHeight`, another reading `input.value` — they inevitably desync the moment a value is set programmatically (e.g. on import, or by a "reset to default" button) without also touching the input. The export then serializes whichever one nobody remembered to update, and the mismatch is invisible until the exported file doesn't match what the screen showed.

---

### Card 3: Pure Core, DOM Shell

**WHEN:** Any calculation — model transforms, section-derivation math, serialization — runs inside the tool.

> **Advisory:** No supporting research bullet on this exact rule — it generalizes from reference-tool code, specifically the contrast between `web-level-editor/preview-core.js` (138 lines, DOM-free, tested) and `editor.js` (619 lines, everything interleaved). The enforceable residue is the split itself — pure calculation in one file, DOM in another — not any external authority for "pure core" as a named pattern.

**WRONG:**
This claim is about the shape and size of a real file, not a code construct, so it is
stated in prose rather than a fabricated code fence:
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

**GOTCHA:** Once preview math lives inside a DOM file, the parity fixture from `web-tool-data-contract.md Card 5: Replicated Logic Is Locked by a Parity Fixture` cannot be run at all — a Node test cannot `require()` a file that touches `document`/`window` at load time — so the replication between the JS preview and the C# runtime it mirrors silently drifts with nothing to catch it.

---

### Card 4: File Line Limit ~400

**WHEN:** A single `.js` file in the tool keeps growing.

> **Advisory:** The 400-line figure is a judgment call, not a sourced standard. The
> enforceable part is the trigger it encodes: when one file holds two responsibilities
> you would describe with an "and", split it. Line count is just the cheapest smoke alarm.

**WRONG:**
```js
/* editor.js — one file, five responsibilities, 619 lines:
 *   - the model (segments, spawns, wall settings)
 *   - section-derivation math (partition, chain start heights)
 *   - 3D preview camera/canvas wiring
 *   - every DOM event listener (inputs, buttons, drag, import/export UI)
 *   - the JSON export/import serializer
 * None of this is separable without a rewrite — everything reads/writes shared closures.
 */
```

**RIGHT:**
```
<tool>-core.js       ← model transforms + section-derivation math. Zero DOM.
<tool>-preview.js    ← 3D preview camera/canvas wiring only.
<tool>.js            ← DOM shell: listeners, reads/writes model, calls core + preview.
<tool>-core.test.js  ← plain assertions over the pure core, runs under `node`.
```
Split along the responsibility boundary the moment a second "and" appears in the file's
description. `web-level-editor/preview-core.js` (138 lines) stayed under the line by
staying to one responsibility — the preview math — not because 138 was a deliberately
chosen target.

**GOTCHA:** `editor.js` crossing 400 lines happened gradually, one `addEventListener` and
one new field at a time, with no single commit that looks alarming in review. By the time
it reached 619 lines, section-derivation math and DOM wiring were interleaved enough that
extracting the pure core became a multi-hour untangling job instead of a five-minute file
split — the cost of ignoring the smoke alarm compounds, it doesn't stay flat.

---

### Card 5: Event Delegation, Not Per-Row Listeners

**WHEN:** Rendering a dynamic list of rows/cards (course segments, spawn points) where each row has its own inputs and buttons.

> Research: event delegation (one listener on a stable parent container) should be preferred over binding a listener to every dynamically-created row — dev.to/mackmoneymaker, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a (secondary), independently spot-checked against javascript.plainenglish.io, https://javascript.plainenglish.io/mastering-event-delegation-for-large-scale-javascript-applications-fd2b52c06afd (secondary).

**WRONG:**
```js
// editor.js renderSpawns() — a fresh listener bound per input, per row, on every re-render
model.spawns.forEach((sp, i) => {
  const card = document.createElement("div");
  card.innerHTML = `...`;
  card.querySelectorAll("[data-f]").forEach((el) => {
    const evt = el.tagName === "SELECT" ? "change" : "input";
    el.addEventListener(evt, () => { model.spawns[i][el.dataset.f] = num(el.value); }); // new closure every row, every render
  });
  host.appendChild(card);
});
```

**RIGHT:**
```js
// One listener on the stable parent container, bound once — never rebound on re-render
host.addEventListener("input", (e) => {
  const el = e.target.closest("[data-f]");
  if (!el) return;
  const card = el.closest("[data-index]");
  model.spawns[card.dataset.index][el.dataset.f] = num(el.value);
});
```

**GOTCHA:** Every call to `renderSpawns()` in the WRONG version re-runs `forEach` over the freshly-rebuilt DOM and attaches a brand-new closure to every input in every row — the old rows' listeners are garbage only because the old DOM nodes were discarded, not because anyone removed them. Add a "duplicate this row" or "sort rows" feature that re-renders in place without discarding all nodes, and the per-row listeners silently double up: one edit fires the update function twice, and a designer sees a value that increments by 2 instead of 1 with no error anywhere.

---

### Card 6: Render Is Idempotent

**WHEN:** Writing the function that rebuilds a list container's DOM from the model.

> **Advisory:** No supporting research bullet cites this exact rule by name — the underlying research bullet ("prefer an idempotent, full-rebuild render function... over incremental/manual DOM patching") is `(secondary, unverified against a second source)`. Being demonstrated in working reference-tool code does not exempt it. The enforceable part is "clear before rebuild, every time" — the general "render must be idempotent" framing rests on a single secondary source.

**WRONG:**
```js
// Called once per model change — but nothing clears the previous render first
function renderSpawns() {
  model.spawns.forEach((sp, i) => {
    const card = document.createElement("div");
    card.innerHTML = `<div>Spawn ${i}</div>`;
    host.appendChild(card); // appends on top of whatever is already there
  });
}
```

**RIGHT:**
```js
// web-level-editor/editor.js renderSpawns() — clear the container, then rebuild in full
function renderSpawns() {
  const host = $("spawns");
  host.innerHTML = ""; // idempotent: calling this twice in a row produces the same DOM both times
  model.spawns.forEach((sp, i) => {
    const card = document.createElement("div");
    card.innerHTML = `...`;
    host.appendChild(card);
  });
}
```

**GOTCHA:** Call the WRONG version twice in a row — once from an `input` handler and once from a follow-up `redraw()` a frame later, which is exactly the kind of double-trigger Card 5's stale-listener bug produces — and the spawn list silently doubles: every spawn point now appears twice in the DOM (and, if a listener also reads row index from DOM position, values start writing to the wrong array index). The bug reproduces only when render is called more than once for the same state, which makes it invisible in a manual click-through that always renders from a clean slate.

---

### Card 7: The Pure Core Has Tests, With No Test Runner

**WHEN:** The pure core module (Card 3) has any logic worth trusting — derivation math, serialization, partitioning.

> **Advisory:** No supporting research bullet on this exact rule — it generalizes from reference-tool code, specifically `preview-core.js` + `preview-core.test.js` (a real pure-core module that is actually tested, run via `node --test`, zero framework). The enforceable residue is "untested pure-core logic has no technical excuse once Card 3 is applied" — not any external authority for testing-without-a-runner as a named practice.

**WRONG:**
```js
// tool-core.js has real math, but the only place it's exercised is by opening the browser
// and clicking through the UI — no assertion anywhere pins the actual output values.
```

**RIGHT:**
```js
/* run: node --test tool-core.test.js — exits non-zero on any failing assertion,
 * no runner install, ships with the Node >= 18 runtime.
 * CommonJS (require/module.exports), not ESM `import` — plain .js with top-level
 * `import` fails on Node without `.mjs` or `"type": "module"`. CommonJS runs
 * unmodified on any Node >= 18 with zero package.json, matching preview-core.js. */
const test = require("node:test");
const assert = require("node:assert");
const { deriveSections } = require("./tool-core.js");

test("empty input yields empty output", () => {
  assert.deepStrictEqual(deriveSections([]), []);
});
```
Modeled directly on `web-level-editor/preview-core.test.js`, which asserts
`preview-core.js`'s output against a frozen fixture using `node:test`/`node:assert`,
invoked with `node --test`, no `npm install`, no framework — see
`web-tool-data-contract.md Card 5: Replicated Logic Is Locked by a Parity Fixture`
for the fixture pattern this test file also implements. `node --test` is preferred
over a hand-rolled `process.exit(failures?1:0)` runner: it is the exact invocation the
reference tool uses, and a hand-rolled runner can report success (exit 0) even when an
assertion inside it silently fails to execute — `node --test` cannot pass unless every
registered test actually ran and asserted true.

**GOTCHA:** Because Card 3 already separates the core from the DOM, the core has no
technical excuse left for being untested — "it needs a browser" stopped being true the
moment the math moved out of `editor.js`. A core left untested anyway means a refactor
of the derivation math has zero automated signal that it still produces the same
numbers, and the first person to notice a regression is a designer looking at a hill
that used to be smooth and now has a visible seam.

---

### Card 8: Every List Row Has a Stable Identity

**WHEN:** Rendering, deleting, or reordering rows in an editable collection (course segments, spawn points, any list a user adds to and removes from).

> **Advisory:** No research bullet in `docs/superpowers/research/2026-08-13-web-tool-research.md` covers list-item identity in any of its three sections. This card is grounded in working code and in a live-test gap (an agent given only these rule files still produced an index-based delete), not in a cited source. The enforceable residue is narrow: an array index must never be the only handle on a row that survives a re-render.

**WRONG:**
```js
// Delete handler resolves the row by its current array index...
deleteBtn.addEventListener("click", (e) => {
  const card = e.target.closest("[data-index]");
  model.rows.splice(Number(card.dataset.index), 1);
  renderRows(); // ...which re-derives every remaining card's data-index from its NEW array position
});
```

**RIGHT:**
```js
// Rows carry a stable id, assigned once at creation and never reused or reassigned.
let _nextId = 1;
const nextId = () => _nextId++; // or crypto.randomUUID() if collision-proof ids matter more than readability

function addRow(fields) {
  model.rows.push({ id: nextId(), ...fields });
  renderRows();
}

function renderRows() {
  host.innerHTML = "";
  model.rows.forEach((row) => {
    const card = document.createElement("div");
    card.dataset.rowId = row.id; // DOM carries the id only to map an event back to a row
    host.appendChild(card);
  });
}

host.addEventListener("click", (e) => {
  const card = e.target.closest("[data-row-id]");
  if (!card) return;
  const id = Number(card.dataset.rowId);
  model.rows = model.rows.filter((r) => r.id !== id); // filtered by id, not spliced by index
  renderRows();
});
```
An undo snapshot taken before the delete (`web-tool-design-system.md Card 9: Authoring Work Is Recoverable`) restores rows with these same `id`s intact, so a redo after a delete lands on the identical rows it started from — not on whatever happens to occupy those array slots afterward.

**GOTCHA:** The user deletes row 3 while row 5's number input still has focus. The re-render renumbers every remaining row's `data-index`, the pending `change` event on that still-focused input fires a beat later with `dataset.index === "4"`, and the value the user typed for the old row 5 is silently written into what is now a different row. Nothing throws, the table still looks plausible on screen, and the corruption is only discovered when the exported data is loaded by the consuming system and a value shows up on the wrong entity.

---

## Why Zero Build

The tool outlives the project — it gets opened again eighteen months from now by someone who does not have the original `node_modules` — and a build pipeline is the part that rots first: dependency versions drift, the bundler config stops resolving, and the tool that "just needs `npm run build`" becomes the tool nobody can open. Two `<script>` tags and a `file://` URL have no toolchain to rot.

## The Model/DOM Boundary

The boundary is the one Card 3 draws: `<tool>-core.js` holds every transform, derivation, and serialization step and imports nothing DOM-related — it is loadable and testable under plain `node` with zero setup. `<tool>.js` is the shell: it queries elements, binds listeners (Card 5), reads/writes the model (Card 2), calls into the core for any computation, and writes the result back to the DOM (Card 6). The model itself lives in the shell or in the core depending on who owns its lifecycle, but the *rule* that both files must respect is the same: DOM code never reimplements a calculation the core already owns, and core code never touches `document` or `window`. `web-level-editor/preview-core.js` versus `editor.js` is the concrete before/after of this split — one side already made it, the other has not.

## Testing Without a Runner

There is no framework, no `npm test`, no CI runner assumed for these tools — the test file imports the core and asserts against it using Node's built-in `node:test`/`node:assert`, which ships with the runtime and needs no install. `node --test <tool>-core.test.js` is the entire contract — anyone who can run `node` can verify the core still behaves, without ever installing a test framework the tool doesn't otherwise depend on. Prefer `node --test` over a hand-rolled `if`/`console.error`/`process.exit` runner: it matches the reference tool's actual invocation, and a hand-rolled runner can silently report success when an assertion inside it never actually executes.

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| Requiring `npm install`/`npm run build` before the tool opens | Ship as plain `<script>` tags that run from `file://` (Card 1) |
| Reading current state back out of an input's `.value` instead of the model | Model is the single source of truth; DOM only displays it (Card 2) |
| Model transforms, DOM wiring, and serialization interleaved in one file | Split into `<tool>-core.js` (pure) and `<tool>.js` (shell) (Card 3) |
| Letting one file accumulate multiple responsibilities past ~400 lines | Split at the first "and" in the file's one-sentence description (Card 4) |
| Binding a fresh listener to every row on every re-render | One delegated listener on the stable parent container (Card 5) |
| Appending newly rendered rows without clearing the previous render first | Clear the container, then rebuild in full, every time (Card 6) |
| Leaving the pure core untested because "the tool needs a browser to test" | The core has no DOM dependency after Card 3 — test it with plain `node` (Card 7) |
| Identifying a list row by its array index or its DOM position instead of a stable key | Give every row an `id` at creation time; delete/reorder by `id`, never by index (Card 8) |
