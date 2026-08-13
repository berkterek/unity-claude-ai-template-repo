# Web Authoring Tool — Research Notes

**Date:** 2026-08-13
**Purpose:** Source material for `.claude/rules/web-tool-*.md`. Every card in those
files either cites a bullet here or is marked `> **Advisory:**`.

## Visual language

### Findings
- **Spacing should use a small constrained scale based on a base unit, not arbitrary linear values** — Refactoring UI, summarized at https://www.sglavoie.com/posts/2023/09/09/book-summary-refactoring-ui/
- **Type scale values should be hand-picked for a constrained, consistent set rather than derived purely from a mathematical ratio** — Refactoring UI, https://www.sglavoie.com/posts/2023/09/09/book-summary-refactoring-ui/
- **Use px or rem units for the type scale, not em, so sizes always match the defined scale** — Refactoring UI, https://www.sglavoie.com/posts/2023/09/09/book-summary-refactoring-ui/
- **Design tokens should separate primitive tokens (raw values: color, size, weight) from semantic tokens (role-based: `color.danger`, `space.section-gap`) layered on top** — Design Systems Collective, https://www.designsystemscollective.com/cracking-design-foundations-primitives-semantic-tokens-and-beyond-c47dd4e03253
- **Increase spacing between unrelated element groups and decrease spacing within a related group to communicate hierarchy through proximity alone** — Refactoring UI summary, https://www.sglavoie.com/posts/2023/09/09/book-summary-refactoring-ui/
- **A slider control should be paired with a numeric input/readout because sliders cannot match a text field for precise value entry** — Nielsen Norman Group, https://www.nngroup.com/articles/sliders-knobs/
- **A slider's numeric field and track must stay synchronized — editing either one updates the other** — patent/UX synthesis via search digest citing slider+field coordination, https://www.setproduct.com/blog/slider-ui-design
- **Keyboard focus must remain visible at all times; removing the default outline without supplying a replacement indicator is an accessibility failure (WCAG 2.4.7 Focus Visible, Level A)** — MDN / WCAG summary, https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible and https://dev.to/colabottles/stop-removing-focus-2o7b
- **Where a custom focus style is needed, use `:focus-visible` to hide the outline for mouse/touch interaction while keeping it for keyboard interaction, rather than removing it outright** — MDN, https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible
- **A visible focus indicator must have at least 3:1 contrast against its background (WCAG 1.4.11 Non-Text Contrast)** — accessibility summary citing WCAG 1.4.11, https://dev.to/colabottles/stop-removing-focus-2o7b
- **Slider keyboard contract: Right/Up increase the value, Left/Down decrease it, Home jumps to minimum, End jumps to maximum** — W3C WAI-ARIA Authoring Practices 1.2, https://www.w3.org/TR/2021/NOTE-wai-aria-practices-1.2-20211129/
- **Dialog keyboard contract: Tab/Shift+Tab cycle focus only among the dialog's own focusable elements (wrapping at the ends — a focus trap), Escape closes the dialog, and opening a dialog must move focus to an element inside it** — W3C WAI-ARIA Authoring Practices 1.2, https://www.w3.org/TR/2021/NOTE-wai-aria-practices-1.2-20211129/
- **Listbox keyboard contract: Down/Up Arrow move focus to and select the next/previous option (selection follows focus, single-select), with optional Home/End jumping to first/last option** — W3C WAI-ARIA Authoring Practices 1.2, https://www.w3.org/TR/2021/NOTE-wai-aria-practices-1.2-20211129/
- **A creative/editing tool's viewport should occupy the majority of the window, with auxiliary panels (properties, outliner/hierarchy, tool options) docked to the sides rather than competing for center space** — Blender Manual / interface docs, https://docs.blender.org/manual/en/2.79/interface/window_system/introduction.html
- **Related properties inside a panel should be grouped under headings — headings reduce repeated label text and make the panel faster to scan** — Blender Developer Documentation (Human Interface Guidelines — Layouts), https://developer.blender.org/docs/features/interface/human_interface_guidelines/layouts/

### Rejected
- **Typographic scale should always follow a strict mathematical ratio (e.g. a fixed modular scale multiplier)** — Refactoring UI explicitly argues the opposite: hand-picked, not purely ratio-derived; adopting a rigid ratio-only rule would contradict the primary source.
- **A pure mathematical/geometric spacing progression is sufficient on its own** — the same source states "a linear scale won't work" and that perceptual/manual tuning is needed; a naive geometric-only scale claim was dropped in favor of "small constrained set, hand-tuned."

## Vanilla architecture

### Findings
- **Event delegation (one listener on a stable parent container) should be preferred over binding a listener to every dynamically-created row/item** — vanilla JS architecture piece, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a and https://javascript.plainenglish.io/mastering-event-delegation-for-large-scale-javascript-applications-fd2b52c06afd
- **Event delegation avoids the need to rebind listeners after re-rendering dynamic content — the parent listener naturally covers newly inserted children** — same source, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a
- **Prefer an idempotent, full-rebuild render function driven entirely by current state over incremental/manual DOM patching, for single-purpose tools** — same source, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a
- **Do not derive application state by reading back from the DOM (except to locate an event-delegation target) — state should be the single source of truth that render() reads from** — same source, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a
- **An IIFE (or equivalent single-scope wrapper) gives module-like encapsulation without a bundler — no globals, no namespace collisions — for zero-build tools** — same source, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a
- **Full-rebuild rendering trades granular DOM efficiency for simplicity, and the trade-off is acceptable for small, single-purpose tools (author's own stated threshold: under ~500 lines)** — same source, https://dev.to/mackmoneymaker/how-to-build-a-zero-dependency-web-tool-with-vanilla-javascript-69a
- **ES6 classes + template literals + the Custom Elements API can deliver component-style boundaries without a framework, with each module keeping a clean, zero-global-pollution boundary** — vanilla JS patterns piece, https://devdecodes.medium.com/building-modular-web-apps-with-vanilla-javascript-no-frameworks-needed-631710bae703

### Rejected
- **State should always be managed via reactive proxies/observers even in small tools** — the primary source explicitly frames plain-variable state + manual `updateAll()` trigger as sufficient, and calls out that reactive subscriber patterns are only needed once state has "deeply nested state with many independent subscribers" — not the common case for a single-purpose authoring tool. Rejected as a default rule; kept as an escalation path only.

## Data contract

### Findings
- **Every persisted/exchanged schema should carry an explicit version field (e.g. `schemaVersion`) embedded in the document itself** — schema versioning guidance, https://developer.couchbase.com/tutorial-schema-versioning?learningPath=learn/json-document-management-guide and https://jsonic.io/guides/json-migrations
- **On load, compare the document's version field against the current version; if different, run an incremental chain of migration functions (v1→v2→v3…) rather than special-casing every old version directly to the newest** — https://jsonic.io/guides/json-migrations
- **The consumer/loader should have an explicit, decided support window for how many old schema versions it still accepts — versions outside that window should be explicitly rejected, not silently guessed at** — https://jsonic.io/guides/json-migrations
- **Removing/renaming a required field, changing a field's type or meaning, or tightening validation enough to reject previously-valid data are all version-bump events** — https://jsonic.io/guides/json-migrations
- **Schema tests verify one system's compatibility with a schema at a point in time; contract tests verify two systems (producer/consumer) can actually communicate and allow the contract to evolve over time — these are different guarantees, not interchangeable** — Pactflow, https://pactflow.io/blog/contract-testing-using-json-schemas-and-open-api-part-1/
- **Consumer-driven contract testing has each consumer publish a contract describing only the fields/behaviors it actually depends on; the provider must satisfy every registered consumer contract before it can change** — contract testing overview, https://medium.com/@subham11/consumer-driven-contract-testing-stop-breaking-your-consumers-376895cf969c and https://pactflow.io/blog/contract-testing-using-json-schemas-and-open-api-part-1/
- **A schema-only compatibility check cannot guarantee a system fully implements the spec — it can confirm shape compatibility but not full behavioral correctness; code-executed (contract) tests close that gap** — Pactflow, https://pactflow.io/blog/contract-testing-using-json-schemas-and-open-api-part-1/
- **When two independent implementations must produce the same output from the same input (e.g. two parsers/renderers of one data format), a parity/contract test comparing their outputs on shared fixtures is the way to catch silent divergence** — inferred generalization of the contract-testing principle above (producer/consumer parity via shared examples), https://pactflow.io/blog/contract-testing-using-json-schemas-and-open-api-part-1/

### Rejected
- **Schema validation alone (no version field, "just validate shape on every read") is sufficient for a data contract** — rejected; the versioning guidance is explicit that schema evolution without an embedded version field makes it impossible to distinguish "old-format-but-valid" from "new-format" documents, and additive-only evolution silently breaks the moment a genuinely breaking change is needed.
- **Contract testing should replace schema validation entirely** — rejected; sources frame them as complementary (schema tests are cheap/fast for shape, contract tests are stronger for behavior), not as one replacing the other.
