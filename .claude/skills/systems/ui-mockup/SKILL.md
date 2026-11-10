---
name: ui-mockup
description: "Visual UI/UX mockup for UI Toolkit screens — produces a USS-portable HTML/CSS mockup (flexbox, tokens, transform/opacity transitions), covers hierarchy, spacing, type scale, touch targets, states, and the approval → docs/ui/mockups/ handoff. Use before building any runtime UI Toolkit screen."
globs: ["docs/ui/mockups/**"]
---

# UI Mockup

> **Project rule first:** `rules/ui-toolkit-runtime.md` → "Design Workflow → Mockup → Approval → Build". This
> skill is the *how* of step 1–2 there. Where they disagree, the rule wins. Read the rule's Cards 2, 6, 8 and 14 first.

A mockup here is a **spec the port is checked against**, not a pretty picture. If it uses something USS
cannot do, the screen gets redesigned during the port — the exact failure this skill exists to prevent.

## Before drawing anything

1. **Read `DesignTokens.uss`** (game theme or the pinned design system) if it exists. Use its token names
   verbatim as CSS custom properties in the mockup's `:root`.
2. **If no token file exists yet**, the token set — palette, spacing scale, radius scale, type scale,
   motion durations — is part of the deliverable and is approved *before* the screen. It may share the
   file with the first screen (a swatch section on top, labelled DRAFT) but the screen is not approvable
   until the tokens are. Motion tokens are `--motion-fast|base|slow` (Card 14); colour/space/radius/font
   names are yours to choose once, then they are the names `DesignTokens.uss` gets.
3. Ask for what cannot be guessed: target orientation, reference resolution, one reference screenshot or
   mood if the user has one. Do not ask about anything a sensible default settles.

## What USS can and cannot take

| Mockup may use | Mockup must not use |
|---|---|
| `display: flex`, `flex-direction`, `flex-grow/shrink/basis`, `align-items`, `justify-content`, `position: absolute` | `display: grid`, `float`, `gap` on non-flex assumptions you haven't checked, `calc()` mixing units |
| `px` at the reference resolution, `%` | `rem` / `em` / `vw` / `vh` |
| `translate`, `scale`, `rotate`, `opacity`, `background-color` transitions | `@keyframes`, `animation`, `box-shadow`, `backdrop-filter`, `clip-path`, pseudo-elements `::before/::after` |
| Solid colours, `border-radius`, `border-width/color`, `background-image` (a sprite) | CSS gradients, `filter` (unless the project is on 6000.3+) |
| `:hover` `:active` `:focus` `:disabled` | `:nth-child`, `:not()`, `:has()`, sibling combinators beyond what USS supports |

`box-shadow` and gradients are the two most common reasons a port looks different from its mockup. If the
design wants depth, draw it as a **sprite or a 9-slice image** and say so in the mockup's notes.

## Design fundamentals the mockup must get right

- **Hierarchy:** one primary action per screen, visibly dominant (size + fill). Secondary actions are
  outlined or text; destructive ones are not the primary colour.
- **Sizes are dp-based; the canvas is px.** The numbers below are dp. Multiply by `referenceWidth / 360`
  (×3 at 1080 wide) before drawing: 48dp touch target → 144px, 16dp body → 48px, 8dp gap → 24px. A literal
  16px body on a 1080 canvas is unreadable.
- **Spacing:** only values from the spacing scale (4/8/12/16/24/32 dp, scaled, or the project's). Equal gaps
  between siblings of the same kind. If two values look "about the same", they are the same token. Use
  margins, not `gap` — USS `gap` support is unverified in this repo.
- **Type:** at most 3 sizes + 2 weights per screen. Body ≥ 16dp on mobile. Bold needs a font asset with a
  bold face (Card 7 fallback chain). Show the longest realistic string (and a long translation) in every
  label — truncation is a design decision.
- **Touch targets:** ≥ 48dp tall, ≥ 8dp between neighbours. Thumb-reachable actions sit in the lower half.
- **Safe area:** nothing interactive in the notch/home-indicator band; draw the band visibly. The numbers
  in a mockup are placeholders — real values come from `Screen.safeArea` at runtime, so say so in Notes.
- **Contrast:** text ≥ 4.5:1 on its background, large text ≥ 3:1. Check disabled states too — "disabled"
  is not "invisible".
- **Every interactive element has all its states drawn:** default, `:active` (pressed), `:disabled`,
  and `:focus` if gamepad/keyboard is a target. A mockup with only the default state is incomplete.
- **Empty / loading / error** states for any screen that shows data.

## Output format

**Start from `template.html`** (this folder) — tokens `:root`, button states, both widths, state sheet, safe-area
band and the Notes block are already laid out. Spec classes are everything *without* the `mk-` prefix; `mk-*`
is review scaffolding and is exempt from the lint below.

One self-contained `<Screen>.html` — no external CSS/JS/fonts beyond what the project ships.

```html
<!-- :root = the token set, named exactly as in DesignTokens.uss -->
<style>
  :root { --color-surface: #1F2937; --space-3: 12px; --radius-md: 8px; --motion-fast: 150ms; /* … */ }
  .frame        { width: 1080px; height: 1920px; }            /* reference resolution, drawn at scale for review */
  .frame.narrow { width: 720px; }                             /* second width, Card 8/10 */
  .btn          { transition: scale var(--motion-fast), background-color var(--motion-fast); }
  .btn:active   { scale: 0.94; }
</style>
```

- Both widths and every state side by side on one page, each labelled. To show `:hover`/`:active`/`:focus`
  without interaction, mirror classes (`.is-hover`, `.is-pressed`, `.is-focus`) and a CSS `transform` scale
  wrapper for drawing at reduced size are allowed — they are review scaffolding, not part of the spec;
  say so in Notes.
- Focus is drawn as a `border-color` change on a border that is always present (no layout shift).
- Empty/loading/error are required only for elements that display data (a counter, a list); a
  buttons-only screen needs default/pressed/disabled and the long-string check.
- A **Notes** block at the bottom: sprites/9-slices needed, fonts, anything the mockup could not express in
  USS terms and how it should be built instead. An unlisted deviation is a defect.
- Motion is described in the notes as `transition` on translate/scale/opacity; anything that needs
  `@keyframes` (spinner, pulse, punch-scale) is marked **"C# tween"** — Card 14.

## Review → approval → handoff

0. **Lint before showing it:** `python3 .claude/skills/systems/ui-mockup/lint-mockup.py <Screen>.html` — zero
   ERRORs, and every WARN fixed or explained in Notes. It checks USS-unsupported CSS, raw colours/durations
   outside `:root`, undefined `var()` tokens, transition properties, both widths, pressed/disabled/focus states
   and the Notes block. It does **not** judge looks, contrast or spacing rhythm — that is still the human's
   review. A clean lint is not an approval.
1. Publish the mockup as an Artifact; the human opens it at phone width.
2. Iterate on **their** words. Do not "improve" an element they did not mention.
3. Approval is an explicit statement. Silence and "looks fine, but…" are not approval.
4. On approval save `docs/ui/mockups/<Screen>.html` and a `<Screen>.png` per state, commit them, and only
   then start the View/UXML/USS. The builder reads the file; it does not work from a description of it.
5. Closing the screen task = Play mode at both widths, beside the PNG (Card 10).

## Common mistakes

| Mistake | Fix |
|---|---|
| Raw hex / `px` values invented per element | Token from `:root`; missing token → add the token first |
| Grid layout, shadows, gradients "because it looks better" | Flexbox, sprite/9-slice, solid colour — then it ports |
| Only the default state drawn | Draw `:active` / `:disabled` / `:focus` / empty / error |
| Mockup drawn at one width | Reference width and narrow width, always |
| Perfect copy in every label | Longest string and longest translation |
| Tweaking the design after approval in place | New approval; re-save the file |
