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

> **Advisory:** Only the first decision-table row (bounded numeric → slider paired with a numeric readout) is backed by a research bullet, sourced from the reference tool's own `#exag` slider treatment. The remaining five rows (unbounded numeric → unit suffix, enum ≤4 → segmented, enum >4 → select, boolean → toggle, free text → text input) are conventional UI judgment calls with no supporting research bullet. The enforceable part of this card is that control type is derived from data type, not chosen ad hoc — not the specific control assigned to each of the five unsourced rows.

**WRONG:**
```html
<!-- bounded numeric field (0-8 range) given a free-text input — no min/max enforced, no visual sense of range -->
<input type="text" id="exag" />
```

**RIGHT:**

| Data | Control |
|---|---|
| Bounded numeric (min and max known) | Range slider **paired with** a numeric readout |
| Unbounded numeric | Number input with unit suffix |
| Enum, ≤ 4 options | Segmented control |
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

> Research: "A creative/editing tool's viewport should occupy the majority of the window, with auxiliary panels (properties, outliner/hierarchy, tool options) docked to the sides rather than competing for center space" — Blender Manual, https://docs.blender.org/manual/en/2.79/interface/window_system/introduction.html

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
/* web-level-editor/styles.css:220-233 */
canvas { width: 100%; height: 400px; }
```

**GOTCHA:** A cramped viewport pushed to a side panel is too small to judge the thing actually being authored — a designer tweaking a hill's peak height cannot tell from a 180px-tall canvas whether the slope now has a visible seam, so they export blind and only find the seam once it's imported into Unity and viewed at real size, at which point the round-trip to fix it costs a full export/import cycle instead of a glance.

---

### Card 5: Every Numeric Field Shows Unit and Real Scale

**WHEN:** A numeric field or preview control represents a value that could be misread as a different unit or a different scale than it actually is.

> **Advisory:** No supporting research bullet on this exact rule — it generalizes from reference-tool code (`web-level-editor/index.html`'s `1.0× = true Unity scale` caption), not from an external source. The related "state the unit in a schema/comment" rule for exported data lives in `web-tool-data-contract.md Card 4: Units and Scale Are Written Down` — this card covers the same concern at the UI-surface level, not the export schema.

**WRONG:**
```html
<!-- What does 1 mean? 2? Nothing on screen says whether this is a multiplier, a raw height, or a percentage -->
<input type="range" id="exag" min="1" max="8" step="0.1" value="1" />
```

**RIGHT:**
```html
<!-- excerpt from web-level-editor/index.html — the real "1.0× = true Unity scale" treatment -->
<input type="range" id="exag" min="1" max="8" step="0.1" value="1" />
<span class="note" id="exagVal">1.0×</span>
<!-- … legend-scale and spacer spans omitted … -->
<span class="hero-note"><b>1.0× = true Unity scale</b> — the preview matches the imported terrain exactly. Raise exaggeration only to inspect small bumps (visual only, never exported).</span>
```

**GOTCHA:** Without the "1.0× = true Unity scale" caption, a designer who cranks the height-exaggeration slider to `4` to make a subtle hill easier to see has no on-screen cue that they are now looking at a 4x-exaggerated preview, not the real terrain — they judge the hill's steepness against what's on screen, export at what looks right, and the imported level is one-quarter as steep as what they approved.

---

### Card 6: Destructive Actions Confirm; Actions Are Undoable

**WHEN:** An action deletes data, replaces existing data wholesale, or cannot be trivially redone by re-entering the same input.

> **Advisory:** No supporting research bullet covers destructive-action confirmation directly — the reference tool has no confirmation dialog anywhere in `index.html`/`styles.css`, so there is nothing to quote. This card is a gap identified by inspection, not a documented finding from Task 1.

**WRONG:**
```js
// Deletes the spawn row immediately on click — no confirmation, no undo
deleteBtn.addEventListener("click", () => {
  model.spawns.splice(index, 1);
  renderSpawns();
});
```

**RIGHT:**
```js
// Confirms before an irreversible removal; a non-destructive action needs no confirmation
deleteBtn.addEventListener("click", () => {
  if (!confirm(`Delete spawn ${index}? This cannot be undone.`)) return;
  model.spawns.splice(index, 1);
  renderSpawns();
});
```

**GOTCHA:** A designer double-clicking through a long list of spawn rows to tweak values fat-fingers the adjacent delete icon instead of the edit field — with no confirmation, the row is gone before the mouse button is released, and because the tool has no undo, the only recovery is re-entering every field by hand from memory or from a stale exported file, if one still exists on disk.

---

### Card 7: Keyboard Access and Visible Focus

**WHEN:** Any interactive element — button, toggle, list item — is added to the tool.

> Research: "Keyboard focus must remain visible at all times; removing the default outline without supplying a replacement indicator is an accessibility failure (WCAG 2.4.7 Focus Visible, Level A)" and "Where a custom focus style is needed, use `:focus-visible`... rather than removing it outright" — MDN, https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible. Contrast floor: "A visible focus indicator must have at least 3:1 contrast against its adjacent background when focused (WCAG 2.1 SC 1.4.11 Non-text Contrast)" — W3C WAI, https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html.

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
| Deleting/overwriting data with a single click, no confirmation | Confirm before any irreversible action (Card 6) |
| `<div onclick=...>` standing in for a real interactive element | Use the real semantic element (`<button>`, etc.) — it is focusable and keyboard-operable for free (Card 7) |
| `outline: none` with no replacement focus style | Replace with a `:focus-visible` style at ≥ 3:1 contrast — never remove outright (Card 7) |
| No indication that the model has unsaved edits, a field is invalid, or a list is empty | Show all three states explicitly in the UI (Card 8) |
