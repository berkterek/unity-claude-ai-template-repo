# Web Tool — Design System Rules (NON-NEGOTIABLE)

> **Scope:** Browser-based authoring/editor/config tools only. NOT runtime game UI (UGUI / UI Toolkit) — see rules/unity-prefabs.md and skills/core/unity-ugui.md for that.

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: No Color Outside Tokens

**WHEN:** Any element in the tool needs a color, border, shadow, or radius value.

> **Advisory:** No supporting research bullet on this exact rule — it generalizes from reference-tool code (`web-level-editor/styles.css`'s `:root` block already complying), not from an external source. Same provenance shape as `web-tool-architecture.md Card 1: Zero Build, Runs from file://`.

**WRONG:**
```css
.warning-box {
  color: #ffb454; /* invented inline — not the token, not traceable to one */
  border: 1px solid #29324699;
}
```

**RIGHT:**
```css
/* excerpt from web-level-editor/styles.css's :root block — already complies */
:root {
  --bg: #0f1420;
  --surface: #171d2b;
  --border: #29324699;
  --text: #eef2f8;
  --muted: #8a96ad;
  --accent: #5b9dff;
  --danger: #ff6f6f;
  --warn: #ffb454;
  --radius: 12px;
  --radius-sm: 8px;
  --shadow: 0 8px 30px rgba(0, 0, 0, 0.38);
  /* … additional tokens omitted: --bg-grad-1, --bg-grad-2, --surface-2, --surface-3,
     --border-solid, --border-strong, --faint, --accent-ink, --accent-2, --accent-2-ink,
     --shadow-sm, --ring … */
}
.disclaimer {
  color: var(--warn);
  border: 1px solid rgba(255, 180, 84, 0.22);
}
```

**GOTCHA:** A hardcoded `#ffb454` that happens to match `--warn` today silently drifts the moment someone retunes the theme's warning color in `:root` — every place that typed the hex directly stays the old color, and now the tool has two different "warning yellows" on screen at once with no diff that flags it, because a hex literal and a token reference are indistinguishable at a glance in a code review.

---

### Card 2: Fixed Spacing Scale

**WHEN:** Setting any `padding`, `margin`, or `gap` value.

> **Advisory:** The Task 1 research confirms the *concept* — "spacing should use a small constrained scale based on a base unit, not arbitrary linear values" (Refactoring UI, summarized at https://www.sglavoie.com/posts/2023/09/09/book-summary-refactoring-ui/, secondary) — but no source states the exact 4/8/12/16/24/32 numbers below. The set itself is a judgment call; the enforceable part is "a small fixed set, never arbitrary values."

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
.topbar { padding: 14px 28px; }  /* web-level-editor/styles.css:55 — off-scale, invented per rule */
```

**GOTCHA:** `14px 28px` is close enough to `12px 24px` (`--space-3 --space-6`) that nobody notices the drift in a screenshot review — but every subsequent element styled "to match the topbar" now has a coin-flip choice between the real scale and the one invented value that leaked in, and the gap compounds one component at a time until half the tool is off-scale and there is no single point value left to blame.

---

### Card 3: Control Type Derives from Data Type

**WHEN:** Choosing which HTML control to bind to a model field.

> **Advisory:** Two separate claims live in this card, with two separate provenances — do not conflate them. The **mapping** from data type to a specific control (bounded numeric → slider, unbounded numeric → unit suffix, enum ≤4 → segmented, enum >4 → select, boolean → toggle, free text → text input) is a conventional UI judgment call with no supporting research bullet, except the first row, which is backed by the reference tool's own `#exag` slider treatment. The enforceable part of the mapping is that control type is derived from data type, not chosen ad hoc — not the specific control assigned to each unsourced row. Separately, the **keyboard contract a custom widget owes once chosen** is not advisory — it derives from the Accessibility Floor below, which cites the WAI-ARIA Authoring Practices 1.2. Paraphrased, not quoted verbatim here: the Accessibility Floor states those contracts apply the moment a tool builds a custom version of a slider, dialog, or listbox instead of using the native element — see that section for the exact wording.

**WRONG:**
```html
<!-- bounded numeric field (0-8 range) given a free-text input — no min/max enforced, no visual sense of range -->
<input type="text" id="exag" />
```

**RIGHT:**

| Data | Control |
|---|---|
| Bounded numeric (min and max known) | Native `<input type="range">` **paired with** a numeric readout — a custom-drawn slider owes the Accessibility Floor's slider keyboard contract (Right/Up increase, Left/Down decrease, Home/End to min/max); the native element gets it for free |
| Unbounded numeric | Number input with unit suffix |
| Enum, ≤ 4 options | Segmented control **only if** the options must all be visible at once (a mode switch the author toggles constantly) — it is a **custom listbox** and owes the Accessibility Floor's full listbox contract itself (arrow-key roving focus, `role="listbox"`/`role="option"`, `aria-selected`, one tab stop for the group). `<select>` is the default: it satisfies the same contract with no work, so use it unless the always-visible requirement is real |
| Enum, > 4 options | Select |
| Boolean | Toggle |
| Free text | Text input |

```html
<!-- web-level-editor/index.html:32-33 — bounded numeric, slider + readout, exactly Card 3's first row -->
<input type="range" id="exag" min="1" max="8" step="0.1" value="1" />
<span class="note" id="exagVal">1.0×</span>
```

**GOTCHA:** A bounded numeric value exposed only as a plain number input carries no visual sense of where the current value sits in its range — a designer entering `47` into a field whose real ceiling is `50` has no way to tell they are near the edge without reading documentation, and typing `500` into an unclamped input silently produces a value the exporter will happily serialize and the C# importer will just as happily apply, off-scale, with nothing in the UI ever having said "that's out of range."

---

### Card 4: The Viewport Is First-Class

**WHEN:** Laying out a tool that previews the thing it edits (a 3D scene, a level, a composited image).

> Research: the Blender Manual's window-system introduction describes a creative/editing tool's viewport as occupying the majority of the window, with auxiliary panels (properties, outliner/hierarchy, tool options) docked to the sides rather than competing for center space — paraphrased; the page returned a 403 on re-fetch and the exact wording could not be re-verified verbatim. Blender Manual, https://docs.blender.org/manual/en/2.79/interface/window_system/introduction.html

**WRONG:**
```html
<!-- preview squeezed into a fixed-height side panel, competing with the form for the same column -->
<div class="col-left">
  <div class="card"><canvas id="preview" style="height:180px"></canvas></div>
  <div class="card">... twelve rows of form fields ...</div>
</div>
```

**RIGHT:**
```html
<!-- excerpt from web-level-editor/index.html — full-width sticky hero above the two-column form -->
<section class="preview-hero">
  <div class="hero-inner">
    <div class="canvas-wrap">
      <canvas id="preview"></canvas>
      <!-- … canvas-hint overlay omitted … -->
    </div>
    <!-- … preview-toolbar (reset view, exaggeration slider, legend, hero-note) omitted — see Card 5 … -->
  </div>
</section>
<main class="layout"> <!-- form columns start below, never compete with the preview for width; body deliberately truncated here -->
```
```css
/* web-level-editor/styles.css:222-224 — excerpt; the rule's background, border and shadow declarations (styles.css:225-232) are omitted */
canvas { width: 100%; height: 400px; }
```

**GOTCHA:** A cramped viewport pushed to a side panel is too small to judge the thing actually being authored — a designer tweaking a hill's peak height cannot tell from a 180px-tall canvas whether the slope now has a visible seam, so they export blind and only find the seam once it's imported into Unity and viewed at real size, at which point the round-trip to fix it costs a full export/import cycle instead of a glance.

---

### Card 5: Every Numeric Field Shows Unit and Real Scale

**WHEN:** This card has two parts, and they apply under different conditions — do not treat it as all-or-nothing. The unit-suffix requirement is unconditional: any numeric field whose unit is not already stated in its label needs one, in every tool, preview or not. The real-scale requirement applies only when the tool renders a preview of the value — a field or preview control representing a value that could be misread as a different scale than what will actually be exported.

> **Advisory:** No supporting research bullet on this exact rule — it generalizes from reference-tool code (`web-level-editor/index.html`'s `1.0× = true Unity scale` caption), not from an external source. The related "state the unit in a schema/comment" rule for exported data lives in `web-tool-data-contract.md Card 4: Units and Scale Are Written Down` — this card covers the same concern at the UI-surface level, not the export schema.

**WRONG:**
```html
<!-- What does 1 mean? 2? Nothing on screen says whether this is a multiplier, a raw height, or a percentage -->
<input type="range" id="exag" min="1" max="8" step="0.1" value="1" />
```

**RIGHT:**
```html
<!-- excerpt from web-level-editor/index.html — the real "1.0× = true Unity scale" treatment (real-scale half — needs a preview) -->
<input type="range" id="exag" min="1" max="8" step="0.1" value="1" />
<span class="note" id="exagVal">1.0×</span>
<!-- … legend-scale and spacer spans omitted … -->
<span class="hero-note"><b>1.0× = true Unity scale</b> — the preview matches the imported terrain exactly. Raise exaggeration only to inspect small bumps (visual only, never exported).</span>
```
```html
<!-- unit-suffix half — applies unconditionally, preview or not -->
<label for="duration">Spawn delay</label>
<input type="number" id="duration" step="1" />
<span class="unit-suffix">sec</span> <!-- unit stated once, next to the field, not relying on the label alone -->
```

**GOTCHA:** Without the "1.0× = true Unity scale" caption, a designer who cranks the height-exaggeration slider to `4` to make a subtle hill easier to see has no on-screen cue that they are now looking at a 4x-exaggerated preview, not the real terrain — they judge the hill's steepness against what's on screen, export at what looks right, and the imported level is one-quarter as steep as what they approved. The unit half fails differently and needs no preview to fail: the author types `500` into a duration field believing it is milliseconds, the tool stores seconds, the exported wave takes eight minutes to spawn, and nothing in the tool or the importer flags it, because `500` is a valid number in both units.

---

### Card 6: Destructive Actions Are Undoable or Confirmed

**WHEN:** An action is destructive **and** at least one of the following also holds: it is not covered by the undo stack (`Card 9: Authoring Work Is Recoverable`); it escapes the model (writes a file, calls a network endpoint, clears persisted storage); or it discards more than a single row's worth of work in one gesture. An in-model single-row delete that the undo stack captures does **not** get a `confirm()` — it gets an undo entry and, if the tool has one, a transient "Deleted — Undo" affordance.

> **Advisory:** No supporting research bullet covers destructive-action confirmation directly — the reference tool has no confirmation dialog anywhere in `index.html`/`styles.css`, so there is nothing to quote. This card is a gap identified by inspection, not a documented finding from Task 1. The *boundary* stated in WHEN — which actions are confirm-worthy versus undo-only — is itself a judgment call with no external citation; the enforceable residue is that a destructive action is never silent: it is either undoable **or** confirmed, and the tool must be able to say which for every destructive action it offers.

**WRONG:**
```js
// Deletes the spawn row immediately on click — no confirmation, no undo
deleteBtn.addEventListener("click", () => {
  model.spawns.splice(index, 1);
  renderSpawns();
});
```
```js
// confirm() on an in-model single-row delete the undo stack already covers — over-confirming, not the fix
deleteBtn.addEventListener("click", () => {
  if (!confirm(`Delete spawn ${index}? This cannot be undone.`)) return; // wrong claim: it CAN be undone, via Card 9
  model.spawns.splice(index, 1);
  renderSpawns();
});
```

**RIGHT:**
```js
// Escapes the model / has no undo path — confirm before an irreversible removal
deleteBtn.addEventListener("click", () => {
  if (!confirm(`Delete spawn ${index}? This cannot be undone.`)) return;
  model.spawns.splice(index, 1);
  renderSpawns();
});
```
```js
// In-model single-row delete the undo stack captures — no dialog, push a snapshot instead
deleteBtn.addEventListener("click", () => {
  mutate((m) => m.spawns.splice(index, 1)); // mutate() per Card 9: pushes a history snapshot before mutating
});
```

**GOTCHA:** Two failure modes, not one. Under-confirming: a designer double-clicking through a long list of spawn rows to tweak values fat-fingers the adjacent delete icon instead of the edit field — with no confirmation and no undo, the row is gone before the mouse button is released, and the only recovery is re-entering every field by hand from memory or from a stale exported file, if one still exists on disk. Over-confirming: the same designer, editing a 40-row table where every single-row delete pops a modal, dismisses each one and learns to hit Enter reflexively — then blows straight through the one dialog that actually guarded an irreversible "Clear all and re-import," because the dialog stopped carrying information the moment it fired on everything.

---

### Card 7: Keyboard Access and Visible Focus

**WHEN:** Any interactive element — button, toggle, list item — is added to the tool.

> Research: MDN notes that removing focus styles makes keyboard navigation inaccessible for sighted users, and recommends `:focus-visible` over removing the outline (https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible). WCAG 2.1 SC 2.4.7 Focus Visible (Level AA) and SC 1.4.11 Non-text Contrast (Level AA, ≥3:1) are the conformance floor.

**WRONG:**
```html
<!-- Not focusable by Tab, not a button semantically, and fires only on mouse click -->
<div onclick="deleteSpawn(i)" class="icon-btn">🗑</div>
```

**RIGHT:**
```html
<button type="button" class="icon" onclick="deleteSpawn(i)" aria-label="Delete spawn">🗑</button>
```
```css
button:focus-visible {
  outline: none;
  box-shadow: 0 0 0 3px rgba(91, 157, 255, 0.6); /* >= 3:1 against --surface-3, keyboard-only */
}
```

**GOTCHA:** `outline: none` with no replacement — which is exactly what `web-level-editor/styles.css:143` does on `input:focus`/`select:focus`, relying on `box-shadow: var(--ring)` as the (undocumented) replacement — makes the tool unusable by keyboard the moment the replacement is missing on a newly added control, and the breakage is invisible to whoever ships it: a mouse user never tabs through the UI, so nobody notices the missing focus ring until a keyboard-only user opens the tool and cannot tell which of the twelve fields on screen currently has focus.

---

### Card 8: State Must Be Visible

**WHEN:** The tool's data differs from what was last saved/exported, a field fails validation, or a list has nothing in it.

> **Advisory:** No supporting research bullet covers unsaved/validation/empty-state indicators — this is a gap identified by inspection of `index.html`/`styles.css`, which have none of the three. Written as runnable examples, not quoted from the reference tool.

**WRONG:**
```html
<!-- No unsaved-changes cue, no validation feedback, and an empty list renders as a blank <div> with nothing in it -->
<h1>Web Level Editor</h1>
<input type="number" id="wallHeight" step="0.01" />
<div id="spawns"></div>
```

**RIGHT:**
```html
<!-- 1. Unsaved-changes indicator -->
<h1>Web Level Editor <span id="dirtyDot" class="badge" hidden>● unsaved</span></h1>
```
```html
<!-- 2. Inline field validation -->
<input type="number" id="wallHeight" step="0.01" aria-invalid="true" />
<span class="note" style="color: var(--danger)">Must be greater than 0.</span>
```
```html
<!-- 3. Empty-state message -->
<div id="spawns">
  <p class="note">No spawns yet — click "+ Add Spawn" to place one.</p>
</div>
```

**GOTCHA:** `web-level-editor/index.html:110` already half-solves this with a text warning about exporting an empty spawn list ("Empty spawn list warns before download") but nothing on screen shows *whether the model currently has unsaved edits* — a designer who tweaks three fields, gets distracted, and comes back an hour later cannot tell by looking at the tool whether those edits were ever exported, and the only way to find out is to re-export and diff the file by hand.

---

### Card 9: Authoring Work Is Recoverable

**WHEN:** Any mutation to the model that a user might reasonably want to reverse — a delete, a wholesale replace, a batch operation like "roll layout."

> **Advisory:** No supporting research bullet in `docs/superpowers/research/2026-08-13-web-tool-research.md` covers undo/redo — this card is a gap identified by inspection of the reference tool (it has no history mechanism anywhere in `editor.js`) plus general editor-design practice, not a documented finding from Task 1. This card exists because Card 6 originally claimed "Actions Are Undoable" with nothing behind it — the undo half was split out here and given a real mechanism, and Card 6 was retitled twice to track what it actually enforces (see its own title for the current wording). An undo stack is the PRIMARY recovery mechanism; `confirm()` (`Card 6: Destructive Actions Are Undoable or Confirmed`) is the fallback for the narrow set of actions an undo stack cannot reach (e.g. a destructive action that also triggers an irreversible external side effect).

**The same rule, stated from the undo side:** every model mutation pushes a snapshot via `mutate()`; `confirm()` is added **only** when the mutation fails the `Card 6: Destructive Actions Are Undoable or Confirmed` test — it is not covered by the undo stack, it escapes the model, or it discards more than a single row's worth of work in one gesture. A reader arriving at this card first should reach the identical conclusion Card 6 states from the confirm side; this is one decision rule, not two.

**Row identity dependency:** an undo snapshot is only meaningful if it restores the same row identity it captured — see `web-tool-architecture.md Card 8: Every List Row Has a Stable Identity`. This is load-bearing, not decorative: this card's undo stack stores snapshots to replay, and if a row is identified by its position in the array rather than a stable key, a delete that shifts every later row's position means an undo snapshot taken before the delete no longer maps onto the same rows after a redo — it restores whatever row now happens to sit at that index, not the row the snapshot actually captured.

**WRONG:**
```js
// web-level-editor/editor.js:581 — "Roll Layout" mutates the model in place with zero history
$("rollLayout").addEventListener("click", () => { rollLayout(model); renderCourse(); renderTopFields(); redraw(); });
```

**RIGHT:**
```js
// Bounded history stack — a snapshot pushed before every mutation, popped on Ctrl+Z
const MAX_HISTORY = 50; // unbounded growth leaks memory for the life of the tab; 50 covers realistic backtracking depth
const history = [];

function mutate(fn) {
  history.push(structuredClone(model)); // deep snapshot — model per web-tool-architecture.md Card 2: One Model, One Source of Truth
  if (history.length > MAX_HISTORY) history.shift();
  fn(model);
  renderAll(); // idempotent per web-tool-architecture.md Card 6: Render Is Idempotent — safe to call after every mutation
}

function undo() {
  if (history.length === 0) return;
  model = history.pop();
  renderAll();
}

$("rollLayout").addEventListener("click", () => mutate((m) => rollLayout(m)));
document.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === "z") { e.preventDefault(); undo(); }
});
```

**GOTCHA:** A designer spends an hour placing spawns by hand, then fat-fingers "Roll Layout" while reaching for an adjacent button — `rollLayout(model)` at `editor.js:581` overwrites the entire course layout in a single synchronous call, with nothing between the click and the overwrite. There is no confirmation on this button and, until this card, no undo anywhere in the tool — the hour of placed spawns is gone, unrecoverable except by re-entering every value from memory or a stale export.

---

### Card 10: In-Progress Work Survives a Reload

**WHEN:** The model changes, in any tool that opens via `file://` with no server backing it.

> **Advisory:** No supporting research bullet in `docs/superpowers/research/2026-08-13-web-tool-research.md` covers autosave/draft persistence — this card is a gap identified by inspection (the reference tool has no `localStorage` usage anywhere in `editor.js`) plus general practice for offline-first authoring tools, not a documented finding from Task 1.

A `file://` tool has no server to persist to — a browser crash, an accidental tab close, or a refresh discards the entire in-memory model with no prompt, because there is nothing running to intercept the unload. `web-tool-design-system.md Card 8: State Must Be Visible` tells you to SHOW that the model has unsaved edits; this card tells you not to NEED that indicator to matter — the edits survive the reload that would otherwise lose them. Card 8 is about telling the user; Card 10 is about the user never having to find out the hard way.

**WRONG:**
```js
// Model lives only in memory. Refresh, crash, or accidental tab close discards it with no trace.
let model = { wallHeight: 0.30, spawns: [] };
```

**RIGHT:**
```js
// Debounced draft write, namespaced per tool, restored on load — never overwrites an explicitly opened file.
const DRAFT_KEY = "web-level-editor:draft:v1"; // namespaced: tool name + purpose + schema version
let saveTimer = null;

function scheduleAutosave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    localStorage.setItem(DRAFT_KEY, JSON.stringify({ savedAt: Date.now(), model }));
  }, 400); // debounced — not on every keystroke
}

function restoreDraftOnLoad(openedFromFile) {
  if (openedFromFile) return; // precedence rule: a file the user just opened always wins, never silently replaced
  const raw = localStorage.getItem(DRAFT_KEY);
  if (!raw) return;
  const { savedAt, model: draft } = JSON.parse(raw);
  if (!confirm(`Recovered a draft from ${new Date(savedAt).toLocaleString()}. Restore it?`)) return;
  model = draft;
  renderAll();
}
```

**Where `openedFromFile` comes from.** A `file://` page load can never arrive carrying a file — the browser gives the page no access to the filesystem, so the only way a file enters the tool is the user picking it in the import control, which cannot have happened before load. `openedFromFile` is therefore always `false` at load time, and the flag exists for the second call, not the first: the import handler sets it, and once set the tool stops offering the draft for the rest of the session.

```js
let openedFromFile = false;

// the tool's own import control (per web-tool-data-contract.md Card 7: The Tool Validates What It Imports)
importInput.addEventListener("change", async (e) => {
  hydrateFromJson(await e.target.files[0].text()); // throws and aborts on a bad file — flag stays false
  openedFromFile = true;                            // only set AFTER a successful hydrate
  renderAll();
});

restoreDraftOnLoad(openedFromFile); // false at load; the offer happens here or never
```

Set the flag only after `hydrateFromJson` returns without throwing. Setting it before means a rejected import — wrong version, missing required field — leaves the tool believing a file was opened, and the draft that could still have rescued the session is never offered.

The one hazard this pattern must not create: a restored draft must never silently replace a file the user deliberately just opened via the tool's own import control. The precedence rule is fixed — an explicit file open always wins over a stored draft; the draft is offered only when the session starts with no file opened at all, and only with an explicit, visible confirmation naming when it was saved.

**GOTCHA:** A designer places twenty spawn points, gets pulled into a meeting, and the laptop sleeps and Chrome reclaims the tab. On return, the tab reloads to a blank model — every spawn is gone, with no draft to recover, because the tool never wrote anything outside its own in-memory `model` variable. The only trace of the hour of work is whatever was exported before the tab died, if anything was.

---

## Token Layers

Tokens separate into two layers, primitive first: raw values (`--accent: #5b9dff`, `--space-4: 16px`) carry no meaning about where they're used; semantic tokens (`color.danger`, `space.section-gap`) sit on top and reference the primitives by role, so a re-theme changes the primitive once and every semantic consumer follows without a find-and-replace across the CSS. `web-level-editor/styles.css`'s `:root` block (Card 1) is primitive-only — `--accent`, `--danger`, `--warn` name colors, not roles — which is adequate for a single-tool stylesheet with no re-theming requirement; a tool shared across multiple projects with different brand colors is the point at which adding a semantic layer on top becomes worth the indirection.

## Accessibility Floor

The non-negotiable minimum, all traceable to the WAI-ARIA Authoring Practices 1.2 (https://www.w3.org/TR/2021/NOTE-wai-aria-practices-1.2-20211129/) and WCAG 2.1:

- **Every interactive control is a real semantic element** (`<button>`, `<input>`, `<select>`) — never a `<div>`/`<span>` with a click handler bolted on (Card 7).
- **Focus is always visible**, with `:focus-visible` distinguishing keyboard focus from mouse click, and at least 3:1 contrast against the adjacent background (Card 7; WCAG 2.4.7, WCAG 1.4.11).
- **Slider keyboard contract:** Right/Up increase the value, Left/Down decrease it, Home jumps to minimum, End jumps to maximum.
- **Dialog keyboard contract:** Tab/Shift+Tab cycle focus only among the dialog's own focusable elements (a focus trap, wrapping at the ends), Escape closes the dialog, and opening a dialog moves focus to an element inside it.
- **Listbox keyboard contract:** Down/Up Arrow move focus to and select the next/previous option (selection follows focus, single-select), with Home/End optionally jumping to the first/last option.

None of these three keyboard contracts are implemented anywhere in `web-level-editor/index.html`/`styles.css` — the reference tool has no custom slider, dialog, or listbox widget, only native `<input type="range">` and `<select>`, which get the contract for free from the browser. The contracts above apply the moment a tool builds a **custom** version of any of these three widgets instead of using the native element.

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| Hardcoding a hex/rgba color, radius, or shadow value inline | Reference the `:root` token — never retype the literal (Card 1) |
| Using an arbitrary spacing value (`14px`, `28px`) that isn't on the scale | Use the fixed `--space-N` scale, even when the value is "close enough" (Card 2) |
| Binding a bounded numeric value to a plain text/number input | Slider + numeric readout for bounded ranges; see the decision table (Card 3) |
| Squeezing the preview/viewport into a small side panel | Give the viewport the majority of the window; dock panels to the sides (Card 4) |
| A numeric field or slider with no unit or scale annotation on screen | State the unit and real-scale meaning next to the control, always (Card 5) |
| A destructive action that is neither undoable nor confirmed — silent data loss | Confirm only when undo can't reach it: escapes the model, or discards more than one row (Card 6) |
| `<div onclick=...>` standing in for a real interactive element | Use the real semantic element (`<button>`, etc.) — it is focusable and keyboard-operable for free (Card 7) |
| `outline: none` with no replacement focus style | Replace with a `:focus-visible` style at ≥ 3:1 contrast — never remove outright (Card 7) |
| No indication that the model has unsaved edits, a field is invalid, or a list is empty | Show all three states explicitly in the UI (Card 8) |
| Relying on `confirm()` alone, with no way to reverse a mutation once it's confirmed | A bounded undo stack as the primary recovery path; confirmation is only the fallback (Card 9) |
| Model lives only in memory in a `file://` tool — a refresh or crash discards it | Debounced draft write to `localStorage`, restored on load with explicit confirmation (Card 10) |
