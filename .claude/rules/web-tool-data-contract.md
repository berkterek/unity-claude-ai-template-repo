# Web Tool — Data Contract Rules (NON-NEGOTIABLE)

> **Scope:** Browser-based authoring/editor/config tools only. NOT runtime game UI (UGUI / UI Toolkit) — see rules/unity-prefabs.md and skills/core/unity-ugui.md for that.

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: One Schema, One Place

**WHEN:** The tool exports data another system reads.

> **Advisory:** No supporting research bullet — this rule generalizes from reference-tool code (web-level-editor/editor.js), not from an external source.

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

**GOTCHA:** `wallHeigth` (typo) deserializes to C#'s default `0f` for `wallHeight` — no exception, no console warning. The level loads with zero-height walls; a designer only notices when a playtester walks straight off the course edge, and by then the mistyped field has already shipped in the exported level file.

---

### Card 2: Enum Map in One Constant Block

**WHEN:** The web tool writes an integer that the C# side reads back as an enum.

> **Advisory:** No supporting research bullet — this rule generalizes from reference-tool code (web-level-editor/editor.js), not from an external source.

**WRONG:**
```js
// Same three enums re-typed inline at every call site that builds a <select> or writes JSON.
host.innerHTML = `<option value="0">None</option><option value="1">Apple</option>...`;
// ...and elsewhere, a second author adds a fourth collectable and forgets this second copy.
```

**RIGHT:**
```js
/* ---- enum int maps (verified against SpawnCategory/CollectableType/BlockerType) ---- */
const CATEGORY_OPTS = [["None", 0], ["Blocker", 1], ["Collectable", 2]];
const COLLECTABLE_OPTS = [["None", 0], ["Apple", 1], ["Coin", 2], ["Magnet", 3]];
const BLOCKER_OPTS = [["None", 0], ["Rock", 1], ["Sign", 2], ["Barrier", 3]];
```
— `editor.js`, `tools/web-level-editor/` (nile_hole_sphere_repo)

**GOTCHA:** A new C# enum member (`CollectableType.Gem = 4`) gets added, and someone updates the `<select>` markup at the one call site they know about but misses a second inline copy elsewhere in the file. The dropdown in the tool's UI now silently caps out at `Magnet = 3` — `Gem` is simply not selectable, with no build error and no runtime error, because the web tool has no compiler to catch the drift.

---

### Card 3: Every Export Carries a Version

**WHEN:** Defining the export format for any authoring tool.

> Research: "The foundational pattern for JSON document migration is embedding a `schemaVersion` integer in every document at creation time" — jsonic.io, https://jsonic.io/guides/json-migrations (secondary, spot-checked character-exact against the cited page).

**WRONG:**
```js
function buildExport(m) {
  return { _wallHeight: +m.wallHeight, _sections: m.sections /* ...no version field at all */ };
}
```
```csharp
// Importer assumes today's shape forever — a future field rename or type change has no way to be detected.
void Import(LevelDto dto) { _wallHeight = dto._wallHeight; }
```

**RIGHT:**
```js
function buildExport(m) {
  return {
    version: 3, // bump on any breaking change: renamed/removed field, changed type, tightened validation
    _wallHeight: +m.wallHeight,
    _sections: m.sections,
  };
}
```
```csharp
// Importer refuses to guess at an unknown version — hard error, not a best-effort parse.
switch (dto.version)
{
    case 1: return MigrateV1ToV3(dto);
    case 2: return MigrateV2ToV3(dto);
    case 3: return dto;
    default:
        Debug.LogError($"[LevelImporter] Unknown schema version {dto.version} — import aborted.");
        return null;
}
```

**GOTCHA:** A field is renamed on the export side six months from now with no version bump. The importer reads the old key name, gets `0`/`null` for everything downstream of the rename, and imports a level that "loads fine" — just with every wall at height zero and every hill flattened — and nobody connects the bug report to the export change made two releases ago, because there was never a version number to check against.

---

### Card 4: Units and Scale Are Written Down

**WHEN:** A field is a raw number with no unit implied by its name (a height, a length, a distance).

> **Advisory:** No supporting research bullet — this rule generalizes from reference-tool code (web-level-editor/editor.js), not from an external source.

**WRONG:**
```js
// Is 0.30 meters? A fraction? Percent? Nothing in the code or the export says so.
model.wallHeight = 0.30;
```

**RIGHT:**
```
* Exports a .json whose keys are the C# [SerializeField] backing-field names
* (case-sensitive) and whose enums are ints. All terrain SPATIAL MAGNITUDES are
* FRACTIONS of terrain size — the C# importer (Tools > NileHoleSphere >
* Import Level JSON) multiplies them by the target TerrainData.size.
```
— header comment, `editor.js`, `tools/web-level-editor/` (nile_hole_sphere_repo)

**GOTCHA:** A second contributor reads `wallHeight: 0.30` with no unit comment and assumes it means "0.30 meters" (a plausible wall height), hardcodes a meters-based importer path, and the wall renders at 30% of the *entire terrain size* — a wall taller than the terrain itself is wide. The bug is invisible in the JSON diff; it only surfaces as a giant wall in the Scene view, and tracing it back to "the number was a fraction all along" costs an afternoon.

---

### Card 5: Replicated Logic Is Locked by a Parity Fixture

**WHEN:** The same math (a generator, a shaping function, a partition algorithm) is implemented twice — once in the web tool's preview, once in the C# runtime/editor path it's previewing.

**WRONG:**
```js
// preview-core.js reimplements the C# heightmap generator with no test tying the two together.
// A future edit to either side can silently diverge — the preview lies to the designer.
function buildHeightmap(model) { /* ...independently "looks right" in isolation... */ }
```

**RIGHT:**
```js
test("typed heightmap samples match the frozen contract (full surface, no noise)", () => {
  const { H } = PC.buildHeightmap(model);
  for (const s of fixture.samples) {
    const got = PC.sampleBilinear(H, s.zFrac, s.xFrac);
    assert.ok(
      Math.abs(got - s.expected) <= TOL,
      `sample (z=${s.zFrac}, x=${s.xFrac}, "${s.note}") = ${got.toFixed(6)}, expected ${s.expected} (tol ${TOL})`
    );
  }
});
```
— `preview-core.test.js`, `tools/web-level-editor/` (nile_hole_sphere_repo) — the same fixture file is also asserted against by the C# EditMode test, so both implementations are pinned to one frozen contract.

**GOTCHA:** A future change to the C# generator's easing curve (say, swapping `sin²` for a different smoothing function) has nothing forcing the JS preview to change with it. Without the shared fixture, both sides keep passing their own isolated tests while silently disagreeing — the web preview shows a smooth hill, the actual in-game terrain has a sharp corner, and the first person to notice is a designer wondering why the built level doesn't look like what they authored.

---

### Card 6: Importer Errors on Missing Fields

**WHEN:** The C# importer deserializes a JSON export.

> **Advisory:** No supporting research bullet on this exact rule — it generalizes from the failure mode `JsonUtility` produces on the C# side of the reference tool's contract (missing/null fields silently deserialize to defaults), not from an external source. The enforceable residue is "guard required fields and abort" — not any particular error-reporting mechanism.

**WRONG:**
```csharp
// Missing/null field silently becomes the C# default — no error, no log.
void Import(LevelDto dto)
{
    _wallHeight = dto._wallHeight; // null in JSON → silently 0f
    Spawn(dto._spawnData);          // null in JSON → silently empty list, nothing spawns
}
```

**RIGHT:**
```csharp
void Import(LevelDto dto)
{
    if (dto._spawnData == null)
    {
        Debug.LogError("[LevelImporter] _spawnData missing from export — import aborted.");
        return;
    }
    // ...proceed only once every required field is confirmed present
}
```

**GOTCHA:** A hand-edited or partially-exported JSON file omits `_spawnData` entirely. `JsonUtility` deserializes the missing array as `null`/empty rather than throwing, the importer proceeds anyway, and the level loads with the terrain intact but zero collectables and zero blockers — no console error, no exception, just an empty level that looks correct until a playtester notices there's nothing to collect.

---

### Card 7: The Tool Validates What It Imports

**WHEN:** The web tool itself parses a user-chosen JSON file back into its model (an "Import" / "Load" control, not the C# importer).

> **Advisory:** No supporting research bullet in `docs/superpowers/research/2026-08-13-web-tool-research.md` covers the tool's own import path — this card is a gap identified by inspection of `web-level-editor/editor.js`'s `hydrateFromJson` (line 333) and its call site (the `importFile` change handler, `editor.js:596-606`), not a documented finding from Task 1.

`web-tool-data-contract.md Card 3: Every Export Carries a Version` requires every export to carry a `version` field, and `web-tool-data-contract.md Card 6: Importer Errors on Missing Fields` requires the C# side's importer to error on a missing required field. Nothing holds the *tool's own* import path to that same standard — and in the reference tool it visibly isn't: the `importFile` handler at `editor.js:596-606` does wrap the call in `try { hydrateFromJson(...) } catch (err) { alert(...) }`, so a malformed-JSON parse failure is caught. But `hydrateFromJson` itself (`editor.js:333`) never reads or checks a `version` field, and every value it pulls off the parsed object is defaulted through `num(...)`/`|| {}`/`| 0` fallbacks rather than validated — a field that is missing or the wrong shape does not throw, it just silently becomes `0`, `""`, or an empty array. The tool is held to a *lower* standard than the C# code it exports to: the C# importer (Card 6) is required to abort on a missing field, while the tool's own importer silently absorbs the same gap.

**WRONG:**
```js
// editor.js:333 — no version check, and every field silently defaults through num()/|| {} rather than being validated
function hydrateFromJson(json) {
  const data = JSON.parse(json);
  const cfg = data._terrainGenConfig || {};
  model.levelIndex = data._levelIndex | 0;
  model.wallHeight = num(cfg._wallHeight);
  // ...remaining fields follow the same pattern; body truncated here, see editor.js:333-350 for the rest
  model.spawns = (data._spawnData || []).map((sp) => ({ /* ... */ }));
  renderAll();
}
```

**RIGHT:**
```js
const KNOWN_VERSION = 3;
const REQUIRED_FIELDS = ["_spawnData", "_terrainGenConfig"];

function hydrateFromJson(json) {
  let data;
  try {
    data = JSON.parse(json);
  } catch (err) {
    throw new Error("Not valid JSON: " + err.message); // caller's catch turns this into a visible alert
  }

  if (data.version !== KNOWN_VERSION) {
    throw new Error(`Unknown schema version ${data.version} — expected ${KNOWN_VERSION}. Import aborted.`);
  }

  for (const field of REQUIRED_FIELDS) {
    if (data[field] == null) {
      throw new Error(`Missing required field "${field}" — import aborted.`);
    }
  }

  // ...proceed to hydrate the model only once version and required fields are confirmed present
}
```

**GOTCHA:** A hand-edited or partially-exported JSON file is missing `_spawnData` entirely. The WRONG version's `(data._spawnData || []).map(...)` swallows this without complaint — the model hydrates with zero spawns, `renderAll()` runs, and the screen shows a perfectly normal-looking course with an empty spawn list. A half-hydrated model that *looks* complete is worse than a refused import: the designer has no on-screen signal that anything went wrong, keeps editing on top of a silently incomplete model, and only discovers the missing spawns after re-exporting and having the level fail review — or not at all, if nobody checks.

---

## Why the Contract Is the First Rule

The web tool and the Unity importer are two independent programs that never share a compiler — nothing stops a field rename, an enum reorder, or a unit change on one side from silently going unnoticed on the other until a level fails to load correctly at runtime. Treating the exported JSON shape as a first-class, explicitly-versioned, explicitly-typed contract — rather than "whatever object literal the exporter happens to produce today" — is the only thing standing between a schema drift and a level that loads wrong with no error anywhere in the pipeline.

## Versioning Strategy

Every export carries an integer `version` field, embedded in the document itself. On import, the C# importer compares the document's `version` against the current version; if it differs, it runs the version's migration function (`v1→v2→v3…`) rather than special-casing every old version directly against the newest shape. An unrecognized/unknown `version` is a hard error — `Debug.LogError` and abort the import — never a best-effort parse. The migration registry only grows: once a migration function exists for a version, it is never deleted, because exported files at that old version may still exist on disk or in source control. Do not introduce a cutoff that stops accepting versions below some number — that discards the ability to import legitimately old files that nobody has re-exported yet.

## Parity Fixture Pattern

When two independent implementations (a JS preview, a C# runtime generator) must compute the same result from the same input, lock them together with a shared fixture file: a frozen set of `{input, expected output, tolerance}` samples that both implementations are asserted against — one test in the JS suite (`preview-core.test.js`), one test in the C# EditMode suite, both reading the identical fixture file. The fixture is regenerated only when the underlying algorithm is *intentionally* changed on both sides at once, with the new expected values reviewed as part of that change. Regenerating the fixture to make a failing parity test pass — without first confirming both implementations were deliberately updated together — defeats the entire purpose of the fixture: it converts "the two sides disagree, investigate" into "silence the alarm," which is exactly the silent divergence this pattern exists to catch.

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| Typing the same field-name list by hand on the export side and the import side | One schema table both sides derive their field list from (Card 1) |
| Re-declaring an enum's option list at more than one call site in the tool | One constant block per enum, referenced everywhere (Card 2) |
| Shipping an export format with no `version` field | Embed an integer `version` at creation time; bump on any breaking change (Card 3) |
| A bare number field with no comment stating its unit (fraction, meters, degrees) | State the unit in a comment at the point of definition, and in the field's schema entry (Card 4) |
| Two implementations of the same math tested only in isolation from each other | A shared parity fixture asserted against by both test suites (Card 5) |
| Importer defaults a missing/null field to zero and proceeds | Guard-check required fields; `Debug.LogError` + abort on any missing field (Card 6) |
| The tool's own JSON import silently defaults missing/malformed fields instead of validating them | Check `version` and required fields before hydrating; throw and refuse rather than half-hydrate (Card 7) |
| Defining an explicit support window that rejects old schema versions outright | Never delete old migration entries — the registry only grows (Versioning Strategy) |
| Regenerating the parity fixture to make a failing test pass | Regenerate only when both implementations are intentionally changed together, with new values reviewed (Parity Fixture Pattern) |
