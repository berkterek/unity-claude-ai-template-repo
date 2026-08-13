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

> **Advisory:** No supporting research bullet cites this exact rule by name — the underlying research bullet ("state should be the single source of truth that render() reads from, not derived by reading back from the DOM") is `(secondary, unverified against a second source)`. The enforceable part is the direction of data flow: model → render, never DOM → model except to locate an event-delegation target.

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

**GOTCHA:** Once two code paths both claim to know "the current wall height" — one reading `model.wallHeight`, another reading `input.value` — they inevitably desync the moment a value is set programmatically (e.g. on import, or by a "reset to default" button) without also touching the input. The export then serializes whichever one nobody remembered to update, and the mismatch is invisible until the exported file doesn't match what the screen showed.

---

### Card 3: Pure Core, DOM Shell

**WHEN:** Any calculation — model transforms, section-derivation math, serialization — runs inside the tool.

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

**GOTCHA:** Once preview math lives inside a DOM file, the parity fixture from `web-tool-data-contract.md Card 5: Replicated Logic Is Locked by a Parity Fixture` cannot be run at all — a Node test cannot `require()` a file that touches `document`/`window` at load time — so the replication between the JS preview and the C# runtime it mirrors silently drifts with nothing to catch it.

---

### Card 4: File Line Limit ~400

**WHEN:** A single `.js` file in the tool keeps growing.

> **Advisory:** The 400-line figure is a judgment call, not a sourced standard. The
> enforceable part is the trigger it encodes: when one file holds two responsibilities
> you would describe with an "and", split it. Line count is just the cheapest smoke alarm.

**WRONG:**
`web-level-editor/editor.js` (619 lines) holds the model, the section-derivation math,
the 3D preview camera/canvas wiring, every DOM event listener, and the JSON export/import
serializer — five responsibilities in one file, none of it separable without a rewrite.

**RIGHT:**
Split along the responsibility boundary the moment a second "and" appears in the file's
description: model+derivation into `<tool>-core.js` (see Card 3), 3D preview wiring into
its own module, DOM binding into the shell. `web-level-editor/preview-core.js` (138 lines)
stayed under the line by staying to one responsibility — the preview math — not because
138 was a deliberately chosen target.

**GOTCHA:** `editor.js` crossing 400 lines happened gradually, one `addEventListener` and
one new field at a time, with no single commit that looks alarming in review. By the time
it reached 619 lines, section-derivation math and DOM wiring were interleaved enough that
extracting the pure core became a multi-hour untangling job instead of a five-minute file
split — the cost of ignoring the smoke alarm compounds, it doesn't stay flat.

---

### Card 5: Event Delegation, Not Per-Row Listeners

**WHEN:** Rendering a dynamic list of rows/cards (course segments, spawn points) where each row has its own inputs and buttons.

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

**WRONG:**
```js
// tool-core.js has real math, but the only place it's exercised is by opening the browser
// and clicking through the UI — no assertion anywhere pins the actual output values.
```

**RIGHT:**
```js
/* run: node tool-core.test.js  — exits non-zero on failure, no runner, no install */
import { deriveSections } from "./tool-core.js";
let failures = 0;
const eq = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.error(`FAIL ${label}\n  got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`); }
};
eq("empty input yields empty output", deriveSections([]), []);
process.exit(failures ? 1 : 0);
```
Modeled on `web-level-editor/preview-core.test.js`, which asserts `preview-core.js`'s
output against a frozen fixture with `node --test`, no `npm install`, no framework —
see `web-tool-data-contract.md Card 5: Replicated Logic Is Locked by a Parity Fixture`
for the fixture pattern this test file also implements.

**GOTCHA:** Because Card 3 already separates the core from the DOM, the core has no
technical excuse left for being untested — "it needs a browser" stopped being true the
moment the math moved out of `editor.js`. A core left untested anyway means a refactor
of the derivation math has zero automated signal that it still produces the same
numbers, and the first person to notice a regression is a designer looking at a hill
that used to be smooth and now has a visible seam.

---

## Why Zero Build

The tool outlives the project — it gets opened again eighteen months from now by someone who does not have the original `node_modules` — and a build pipeline is the part that rots first: dependency versions drift, the bundler config stops resolving, and the tool that "just needs `npm run build`" becomes the tool nobody can open. Two `<script>` tags and a `file://` URL have no toolchain to rot.

## The Model/DOM Boundary

The boundary is the one Card 3 draws: `<tool>-core.js` holds every transform, derivation, and serialization step and imports nothing DOM-related — it is loadable and testable under plain `node` with zero setup. `<tool>.js` is the shell: it queries elements, binds listeners (Card 5), reads/writes the model (Card 2), calls into the core for any computation, and writes the result back to the DOM (Card 6). The model itself lives in the shell or in the core depending on who owns its lifecycle, but the *rule* that both files must respect is the same: DOM code never reimplements a calculation the core already owns, and core code never touches `document` or `window`. `web-level-editor/preview-core.js` versus `editor.js` is the concrete before/after of this split — one side already made it, the other has not.

## Testing Without a Runner

There is no framework, no `npm test`, no CI runner assumed for these tools — the test file is a plain script that imports the core, runs assertions with hand-rolled `if`/`console.error` checks (or Node's built-in `node:test`/`node:assert`, which ships with the runtime and needs no install), and exits non-zero on any failure. `node <tool>-core.test.js` (or `node --test <tool>-core.test.js`) is the entire contract — anyone who can run `node` can verify the core still behaves, without ever installing a test framework the tool doesn't otherwise depend on.

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
