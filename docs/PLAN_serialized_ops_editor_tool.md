# PLAN — Serialized-Ops Editor Tool (data-driven inspector wiring for MCP)

> **Version:** v1.2 — 2026-09-25 (v1 2026-09-24; v1.1: Task 9 param shape closed from vendored MCP source, cross-prefab setRef resolution and Enum index decision added to Task 2; Newtonsoft Editor-platform evidence from dll.meta; Task 10 probe `--run-tests` added; v1.2 2026-09-25: Task 11 framework-only emit mode for existing projects, test fixture moved out of Assets/Temp)
> **Status:** Active
> **Scope:** `.claude/commands/setup-project.md` (Step 3 asmdef reference line, Step 4 generated C#), `.claude/skills/core/unity-mcp-patterns/SKILL.md`, `.claude/docs/setup-checklist.md`, `.claude/hooks/check-no-throwaway-editor-script.sh` (message only), `_Framework/Editors/ARCHITECTURE.md` block. No runtime code anywhere.

## Complexity

**0.5 — Medium.** New module folder +0.0 (`_Framework/Editors/` and its `FrameworkEditor.asmdef` already ship in Step 3). IEventBus events +0.0. ECS/Addressables +0.0. Single file −0.0 (three generated C# blocks, one generated test block, one asmdef one-line change, three doc edits). The weight is not the code; it is that every generated block lives inside one markdown file, so the generated-code tasks cannot parallelise, and that a chunk of the surface (the test, the fixture) is deliberately outside what the compile probe measures.

## Context

This is the **template** repository, not a Unity project. Everything the tool "is" ships as fenced blocks inside `.claude/commands/setup-project.md`: Step 3 emits `.asmdef` JSON, Step 4 emits C#. `/setup-project` writes those blocks into a freshly created project. Therefore every "add file X" task below means *add a `#### \`relative/path\`` heading followed by a ```csharp or ```json fence to setup-project.md*, per the block-format contract recorded in `docs/PLAN_setup_compile_probe.md`. Forward slashes only; the heading path is the file path. Two tools read those blocks: `.claude/scripts/validate-generated-asmdefs.py` (text-level assembly coherence) and `.claude/tests/setup-compile-probe/run-probe.sh` (a real `Unity -batchmode` compile, reusing the validator's `--extract` parser).

The problem being solved: MCP for Unity cannot reliably assign an inspector reference — an object field on a prefab component, a nested `SerializedProperty`, a reference stored on a ScriptableObject. The current escape route is to write a throwaway `[InitializeOnLoad]` Editor script, run it once, delete it. `.claude/hooks/check-no-throwaway-editor-script.sh` already blocks exactly that pattern and, in its block message, points at "a PERMANENT tool under Assets/Editor/" — a tool that does not exist. This plan builds it, in the framework's own Editor assembly, and makes the hook's advice actionable.

The design constraint that shapes everything: **the tool must know `SerializedProperty` paths and nothing about any game's domain.** No `PlayerController`-style symbol may appear in its source. That is what makes it shippable from a template at all — a generic applier plus a JSON manifest the caller writes. The manifest is versioned and the unknown-version case is a hard abort, per `.claude/rules/web-tool-data-contract.md` Card 3; a missing required field aborts the op it belongs to, per Card 6. Editor code logs with `UnityEngine.Debug`, never `DLog` (`.claude/rules/logging.md` Card 2). `#region` at 3+ methods (`.claude/rules/csharp-unity.md` Card 4).

## Goals

- [ ] A permanent, domain-free Editor applier that reads a versioned JSON manifest and applies `setRef`, `setValue`, `addComponent` operations to prefabs and ScriptableObjects.
- [ ] A `[MenuItem]` entry point so MCP's `execute_menu_item` can trigger it without any file the agent has to delete afterwards.
- [ ] Loud per-op failure: a failed op logs `Debug.LogError` with its index and reason, other ops continue, the overall result is non-success.
- [ ] Read-back verification after save — the asset is reloaded fresh and the property re-read; a mismatch is a failure, not a pass.
- [ ] An EditMode test that builds its own fixture prefab from Unity built-in components only and exercises the applier as a pure `string json → result` function.
- [ ] Documentation that names the tool where the fallback used to be named: the MCP skill's tool-selection table, the setup checklist, and the throwaway-script hook's own block message.
- [ ] Zero runtime-assembly changes; zero domain symbols in generated tool code.

## Chosen Approach

Two axes were open. **Manifest parsing:** `JsonUtility` with typed DTOs, or Newtonsoft `JObject`. `JsonUtility` cannot represent the polymorphic `value` field (a scalar that is a float here, a string there, an object for `Vector3`) without a per-type DTO zoo and a pre-parse discriminator pass, and it deserializes a missing field to a silent default — precisely the failure Card 6 exists to prevent, and it would make "missing required field" undetectable. **Newtonsoft wins**: `JObject`/`JToken` distinguishes absent from null, `JToken.Type` carries the scalar kind for free, and `FrameworkSaveLoadSystems` already proves Newtonsoft compiles from a Framework assembly with *no* asmdef reference (precompiled DLL, auto-referenced; measured 2026-09-02 by the compile probe, and encoded as `Newtonsoft` in the validator's `NO_REFERENCE_NEEDED` prefix list at line ~38). Newtonsoft is Required Stack. **The Editor-platform case is now evidenced from disk, not inferred (2026-09-25):** `com.unity.nuget.newtonsoft-json@3.2.1/Runtime/Newtonsoft.Json.dll.meta` carries `isExplicitlyReferenced: 0` (auto-referenced by every asmdef that does not set `overrideReferences`) and a platform block `Editor: Editor → enabled: 1`. `FrameworkEditor.asmdef` has `overrideReferences: false`, so it receives the DLL without naming it. Version 3.2.1 is exactly what `run-probe.sh` line 100 pins, so the probe exercises the same DLL. The `JsonUtility` fallback stays written down but is no longer expected to be needed.

**Entry point:** a menu item reading a fixed path, versus a file dialog. `execute_menu_item` takes only a menu path — it cannot pass an argument — so a dialog would require a human click and defeat the purpose. **Fixed path wins**: `Temp/serialized-ops.json`, project-relative, with a second menu item (`.../Apply Serialized Ops (Choose File…)`) for the human case via `EditorUtility.OpenFilePanel`. The fixed path is resolved through a single constant so the test never depends on it.

**Separation:** the applier is a pure static class — `string json → SerializedOpsResult` — with no `MenuItem`, no dialog, no `EditorPrefs`. The menu class is a thin shell that reads the file, calls the applier, and logs a summary. That split is what makes the EditMode test possible without driving the menu, and it is the reason the test can be honest.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Result & op model block | ⏳ Pending | — |
| 1 | Task 2 — Applier block (parse, dispatch, save, read-back) | ⏳ Pending | — |
| 1 | Task 3 — Menu block | ⏳ Pending | — |
| 2 | Task 4 — EditMode test asmdef reference + test block | ⏳ Pending | — |
| 2 | Task 5 — `_Framework/Editors/ARCHITECTURE.md` one line | ⏳ Pending | — |
| 3 | Task 6 — MCP skill: tool-selection row + Rule 6 rewrite | ⏳ Pending | 1 |
| 3 | Task 7 — setup-checklist entry | ⏳ Pending | 1 |
| 3 | Task 8 — hook block message names the tool | ⏳ Pending | 1 |
| 3 | Task 9 — confirm `execute_menu_item` end-to-end (param source-verified 2026-09-25) | ⏳ Pending | — |
| 4 | Task 10 — compile probe `--run-tests` runs the generated EditMode tests | ⏳ Pending | — |
| 4 | Task 11 — `/setup-project` framework-only emit mode (existing projects) | ⏳ Pending | 2 |

Tasks 1–5 all write to `.claude/commands/setup-project.md` and are therefore mutually sequential regardless of compile dependency; within them there is also a real dependency chain (2 needs 1's types, 3 needs 2's entry point, 4 needs all three). Tasks 6–8 touch three different files and share group 1. Task 9 gates the acceptance of 6 but not its text, so it runs last and alone.

No task is marked **[RUNTIME]** — correctly. Nothing here touches a runtime assembly.

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/commands/setup-project.md` | Modify | Add 4 Step 4 blocks after the `GameScope.cs` block (~line 1342, immediately before the `---` / `### Step 5` boundary); add `"FrameworkEditor"` to the `[ProjectName]EditModeTest.asmdef` references in **both** variants (~line 449, with- and without-NSubstitute); add one line to the `_Framework/Editors/ARCHITECTURE.md` block (~line 1142). **Do not touch `FrameworkEditor.asmdef` (~line 379)** — it already has what the tool needs. |
| `.claude/skills/core/unity-mcp-patterns/SKILL.md` | Modify | Rule 4 table row; Rule 6 step 4 currently reads "fall back to writing an Editor script" — that is the sentence being replaced. |
| `.claude/docs/setup-checklist.md` | Modify | New bullet under `## MCP-Automated`, or a short subsection after it, describing the manifest route. |
| `.claude/hooks/check-no-throwaway-editor-script.sh` | Modify | Block message: "write it as a PERMANENT tool under Assets/Editor/" → name the shipped menu path. Verify current text first (quoted below) — it does **not** name a tool today, so this is a genuine Modify. |
| `.claude/hooks/tests/check-no-throwaway-editor-script.bats` | Modify | One new case asserting the menu-path line is present in the block output. Existing cases assert no exact message text and stay untouched. |
| `.claude/commands/setup-project.md` (Step 0 branch B) | Modify | Third option `framework`: emit missing `_Framework/**` files only, never overwrite (Task 11). This is how an existing project receives the tool. |
| `.claude/tests/setup-compile-probe/run-probe.sh`, `README.md` | Modify | `--run-tests` flag: emit `/Tests/`, swap `-quit` for `-runTests -testPlatform EditMode`, fail on any failed result (Task 10). |
| `.claude/agents/audio-clip-agent.md`, `graphics-setup-agent.md` | **Not in scope** | See the closing note. |

Generated (inside setup-project.md, not files in this repo):

| Generated path | Notes |
|---|---|
| `_Framework/Editors/SerializedOpsResult.cs` | DTOs: `SerializedOpsResult`, `SerializedOpStatus`. Compile-probed. |
| `_Framework/Editors/SerializedOpsApplier.cs` | Pure static applier. Compile-probed. |
| `_Framework/Editors/SerializedOpsMenu.cs` | `[MenuItem]` shell. Compile-probed. |
| `_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/SerializedOpsApplierTests.cs` | **Not compile-probed** — `run-probe.sh` passes `--skip "/Tests/"`. |

---

## Task 1 — Result and op-status model

**Files:** `.claude/commands/setup-project.md` (new block `#### \`_Framework/Editors/SerializedOpsResult.cs\``, inserted after the `GameScope.cs` block and before the `---` preceding `### Step 5`)

**Steps:**
1. [ ] Locate the `GameScope.cs` block (~line 1342) and the `> \`GameScope\` only calls...` callout that follows it; the insertion point is after that callout, before the `---`.
2. [ ] Add the `#### \`_Framework/Editors/SerializedOpsResult.cs\`` heading plus a ```csharp fence.
3. [ ] Namespace `Framework.Editor` (matches `rootNamespace` on the existing asmdef).
4. [ ] Define `SerializedOpStatus` (index, op kind, asset path, `Success` bool, `Message` string) and `SerializedOpsResult` (`Success` bool, `IReadOnlyList<SerializedOpStatus>`, `Aborted` bool + `AbortReason` for the unknown-version / unparseable-manifest case).
5. [ ] No `#region` needed — these are DTOs with fewer than 3 methods (Card 4 exemption). Add regions only if a helper pushes the count to 3.
6. [ ] `using System.Collections.Generic;` only. No `UnityEngine`, no `UnityEditor` — keeps the type trivially testable.

**Test Type:** NoTest — `_Framework/Editors/` is an Editor path; per the test matrix Editor code is NoTest. Coverage arrives through Task 4, which exercises these types as the applier's return value.

**Code Skeleton:**
```csharp
using System.Collections.Generic;

namespace Framework.Editor
{
    public sealed class SerializedOpStatus
    {
        public int Index;
        public string Op;
        public string Asset;
        public string Property;
        public bool Success;
        public string Message;
    }

    public sealed class SerializedOpsResult
    {
        public bool Success;          // false if ANY op failed or the manifest aborted
        public bool Aborted;          // true = whole manifest rejected, Statuses may be empty
        public string AbortReason;
        public List<SerializedOpStatus> Statuses = new List<SerializedOpStatus>();
    }
}
```

**Acceptance Criteria:**
- `python3 .claude/scripts/validate-generated-asmdefs.py .claude/commands/setup-project.md` exits 0 — the new file's `using System.Collections.Generic` resolves under the `System` prefix in `NO_REFERENCE_NEEDED`, so `FrameworkEditor.asmdef` needs no new reference.
- `.claude/tests/setup-compile-probe/run-probe.sh` exits 0 (this file is under `_Framework/Editors/`, so it *is* extracted and compiled).
- `grep -nE 'PlayerController|Enemy|Player\b'` over the new block returns nothing.

---

## Task 2 — The applier

**Files:** `.claude/commands/setup-project.md` (new block `#### \`_Framework/Editors/SerializedOpsApplier.cs\``, immediately after Task 1's block)

**Steps:**
1. [ ] `public static class SerializedOpsApplier` in `Framework.Editor`. Public surface is one method: `Apply(string json)` → `SerializedOpsResult`. Everything else private.
2. [ ] Parse with `JObject.Parse` inside a `try`; a `JsonException` → `Aborted = true`, `AbortReason`, `Debug.LogError`, return. Do not catch `Exception` broadly — a genuine `NullReferenceException` in the applier is a bug that must surface.
3. [ ] Read `version`. `!= SupportedVersion (1)` → abort the whole manifest with `Debug.LogError($"[SerializedOps] Unknown manifest version {v} — aborted.")`. Card 3: no best-effort parse.
4. [ ] Read `ops` as `JArray`. Missing or not an array → abort.
5. [ ] Group ops by `asset` so each asset is loaded, mutated and saved once — a per-op `LoadPrefabContents`/`SaveAsPrefabAsset` round trip is both slow and a correctness hazard when two ops target the same prefab.
6. [ ] Per asset, branch on the asset type: a `.prefab` path → prefab lifecycle; anything else loadable via `AssetDatabase.LoadAssetAtPath<UnityEngine.Object>` → ScriptableObject/asset lifecycle. Unresolvable path → every op in that group fails with a stated reason, loop continues.
7. [ ] Prefab lifecycle, exactly: `PrefabUtility.LoadPrefabContents(path)` → resolve target object → `new SerializedObject(target)` → apply ops → `ApplyModifiedPropertiesWithoutUndo()` → `PrefabUtility.SaveAsPrefabAsset(root, path)` → `PrefabUtility.UnloadPrefabContents(root)` **in `finally`**. The unload must not be skipped on an exception or the loaded scene leaks for the rest of the session.
8. [ ] SO lifecycle: `LoadAssetAtPath<UnityEngine.Object>` → `new SerializedObject(obj)` → apply → `ApplyModifiedPropertiesWithoutUndo()` → `EditorUtility.SetDirty(obj)` → `AssetDatabase.SaveAssets()`.
9. [ ] Object resolution inside a prefab: optional `object` field is a `/`-separated transform path relative to the root; absent = root. `component` names the component type on that transform (prefab case); absent = the `GameObject` itself. Resolve component types through `TypeCache.GetTypesDerivedFrom<Component>()` matched on `Name` **or** `FullName`, erroring on an ambiguous short name rather than picking the first — a silent wrong-type pick is worse than a failed op.
10. [ ] `setRef`: resolve the `ref` object and assign `property.objectReferenceValue`. **The ref is resolved against the ASSET, never against a `LoadPrefabContents` copy.** `LoadPrefabContents` returns a temporary scene copy that dies at `UnloadPrefabContents`; a reference stored to one of its components is dangling the moment the prefab is saved and reads back as `None`. So: `ref.asset` → `AssetDatabase.LoadAssetAtPath<UnityEngine.Object>`; if `ref.object`/`ref.component` are given, the asset must be a `GameObject` (a prefab asset) → `transform.Find(object)` → `GetComponent(type)` on that asset object. The one exception is a ref that points **into the same prefab currently open** (self-reference, e.g. a controller's `_rigidbody` on its own root): resolve that against the open `LoadPrefabContents` root, because the saved prefab will contain exactly those objects. Decide by comparing `ref.asset` with the group's `assetPath`. A required field missing (`asset`, `property`, `ref`) → that op fails, others continue (Card 6 applied per-op, since the manifest as a whole is still well-formed).
11. [ ] `setValue`: `switch (property.propertyType)` over `SerializedPropertyType.Float | Integer | Boolean | String | Enum | Vector2 | Vector3 | Color`; `default:` fails the op naming the unsupported type. `Enum` takes the JSON value as an **integer index** written to `enumValueIndex` — the same convention `nile_hole_sphere_repo`'s `WebLevelImporter.cs` already uses (`entry.FindPropertyRelative("_category").enumValueIndex = (int)spawn.Category`); a string name is rejected, not guessed, because `enumNames` order is display order and can differ from the declared value. This `switch` is on Unity's own enum, not a domain type — it is not the polymorphism smell the rules ban.
12. [ ] `addComponent`: resolve `type` via `TypeCache`, guard "already present" as a success no-op, `root.AddComponent(type)`. No `property` needed.
13. [ ] **Read-back**, after the save for each asset: reload the asset fresh from disk (`AssetDatabase.LoadAssetAtPath` / `LoadPrefabContents` a second time), `FindProperty(op.property)`, compare against the intended value; mismatch flips that op's status to failed with `Debug.LogError`. An op that reported success but did not persist is the exact bug this tool exists to make impossible.
14. [ ] `AssetDatabase.Refresh()` once at the end.
15. [ ] `#region` required — this class is well past 3 methods. Suggested: `Fields`, `Public Methods`, `Private Methods`.
16. [ ] Every log prefixed `[SerializedOps]`. `Debug`, never `DLog`.

**Test Type:** NoTest for the file itself (Editor path). Task 4 is the exception that covers it — say so explicitly rather than pretending the matrix was followed.

**Code Skeleton:**
```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;      // no asmdef reference needed — precompiled, auto-referenced
using UnityEditor;
using UnityEngine;

namespace Framework.Editor
{
    public static class SerializedOpsApplier
    {
        #region Fields
        private const int SupportedVersion = 1;
        #endregion

        #region Public Methods
        public static SerializedOpsResult Apply(string json)
        {
            var result = new SerializedOpsResult();
            JObject manifest;
            try { manifest = JObject.Parse(json); }
            catch (Newtonsoft.Json.JsonException e)
            {
                return Abort(result, $"manifest is not valid JSON: {e.Message}");
            }

            var version = manifest.Value<int?>("version");
            if (version == null) return Abort(result, "manifest has no 'version' field");
            if (version.Value != SupportedVersion)
                return Abort(result, $"unknown manifest version {version.Value} (supported: {SupportedVersion})");

            if (!(manifest["ops"] is JArray ops)) return Abort(result, "manifest has no 'ops' array");

            foreach (var group in GroupByAsset(ops))
                ApplyToAsset(group.Key, group.Value, result);

            AssetDatabase.Refresh();
            result.Success = !result.Aborted && result.Statuses.All(s => s.Success);
            return result;
        }
        #endregion

        #region Private Methods
        private static void ApplyToAsset(string assetPath, List<(int index, JObject op)> ops, SerializedOpsResult result)
        {
            if (assetPath.EndsWith(".prefab", StringComparison.OrdinalIgnoreCase))
            {
                GameObject root = null;
                try
                {
                    root = PrefabUtility.LoadPrefabContents(assetPath);
                    foreach (var (i, op) in ops) ApplyOne(root, op, i, result);
                    PrefabUtility.SaveAsPrefabAsset(root, assetPath);
                }
                finally { if (root != null) PrefabUtility.UnloadPrefabContents(root); }
                VerifyPrefab(assetPath, ops, result);   // fresh reload + FindProperty compare
                return;
            }
            // ScriptableObject / other asset: LoadAssetAtPath → SerializedObject →
            // ApplyModifiedPropertiesWithoutUndo → SetDirty → SaveAssets → VerifyAsset(...)
        }

        // ApplyOne dispatches on op["op"]: "setRef" | "setValue" | "addComponent".
        // SetValue switches on property.propertyType (Unity's enum, not a domain type):
        //   Float/Integer/Boolean/String/Enum/Vector2/Vector3/Color; default = op fails.
        // ResolveType uses TypeCache and errors on an ambiguous short name.
        // Fail(result, i, op, reason) → Debug.LogError($"[SerializedOps] op {i} ...") + status.Success=false.

        private static SerializedOpsResult Abort(SerializedOpsResult r, string reason)
        {
            r.Aborted = true; r.AbortReason = reason; r.Success = false;
            Debug.LogError($"[SerializedOps] Manifest aborted — {reason}");
            return r;
        }
        #endregion
    }
}
```

**Acceptance Criteria:**
- `python3 .claude/scripts/validate-generated-asmdefs.py .claude/commands/setup-project.md` exits 0. This is the load-bearing check for the Newtonsoft decision: the validator must accept `Newtonsoft.Json.Linq` against `FrameworkEditor.asmdef`'s unchanged `references: ["FrameworkEvents","FrameworkLogging"]`. If it reports a finding, the premise (`Newtonsoft` in `NO_REFERENCE_NEEDED`) is wrong and the approach falls back to `JsonUtility` — do not "fix" it by adding a reference to a precompiled DLL name.
- `.claude/tests/setup-compile-probe/run-probe.sh` exits 0. The probe's manifest already installs `com.unity.nuget.newtonsoft-json`, so this genuinely exercises the Newtonsoft path against a real compiler.
- No `DLog` token anywhere in the block; every log line starts `[SerializedOps]`.
- No domain symbol: the block contains only BCL, `UnityEngine`, `UnityEditor` and `Newtonsoft` types.
- `PrefabUtility.UnloadPrefabContents` appears inside a `finally`.

---

## Task 3 — Menu entry point

**Files:** `.claude/commands/setup-project.md` (new block `#### \`_Framework/Editors/SerializedOpsMenu.cs\``, after Task 2's block)

**Steps:**
1. [ ] `public static class SerializedOpsMenu` in `Framework.Editor`.
2. [ ] `[MenuItem("Tools/Framework/Apply Serialized Ops")]` → read `DefaultManifestPath` (`const string "Temp/serialized-ops.json"`, relative to the project root, resolved with `Path.Combine(Directory.GetCurrentDirectory(), ...)`), call `SerializedOpsApplier.Apply`, log the summary.
3. [ ] A missing manifest file is a `Debug.LogError` naming the resolved absolute path — not a silent return. "Nothing happened and no message" is the failure mode that costs the most time.
4. [ ] `[MenuItem("Tools/Framework/Apply Serialized Ops (Choose File...)")]` → `EditorUtility.OpenFilePanel`; empty return = user cancelled, log nothing.
5. [ ] Shared `Run(string absolutePath)` private helper — this is the third method, so `#region` becomes mandatory.
6. [ ] Summary log: `Debug.Log($"[SerializedOps] {ok}/{total} ops applied.")` on full success; on any failure a `Debug.LogError` with the same counts, so `read_console` surfaces it to the calling agent.
7. [ ] The menu class never parses JSON and never touches `SerializedObject` — it is file I/O plus logging only. That boundary is why the test needs no menu.

**Test Type:** NoTest — `[MenuItem]` code cannot be driven from an EditMode test without invoking the Editor menu system, and what it would cover (file reading, logging) is not where the bugs are.

**Code Skeleton:**
```csharp
using System.IO;
using UnityEditor;
using UnityEngine;

namespace Framework.Editor
{
    public static class SerializedOpsMenu
    {
        #region Fields
        private const string DefaultManifestPath = "Temp/serialized-ops.json";
        private const string MenuRoot = "Tools/Framework/Apply Serialized Ops";
        #endregion

        #region Public Methods
        [MenuItem(MenuRoot)]
        public static void ApplyDefaultManifest()
            => Run(Path.Combine(Directory.GetCurrentDirectory(), DefaultManifestPath));

        [MenuItem(MenuRoot + " (Choose File...)")]
        public static void ApplyChosenManifest()
        {
            var picked = EditorUtility.OpenFilePanel("Serialized ops manifest", "Temp", "json");
            if (string.IsNullOrEmpty(picked)) return;   // cancelled — not an error
            Run(picked);
        }
        #endregion

        #region Private Methods
        private static void Run(string absolutePath)
        {
            if (!File.Exists(absolutePath))
            {
                Debug.LogError($"[SerializedOps] No manifest at {absolutePath}");
                return;
            }
            var result = SerializedOpsApplier.Apply(File.ReadAllText(absolutePath));
            // summary: Debug.Log on success, Debug.LogError with per-op reasons otherwise
        }
        #endregion
    }
}
```

**Acceptance Criteria:**
- `python3 .claude/scripts/validate-generated-asmdefs.py .claude/commands/setup-project.md` exits 0.
- `.claude/tests/setup-compile-probe/run-probe.sh` exits 0 — a real compile is the only thing that proves `[MenuItem]` with a `const` argument and the ellipsis in the second path are accepted.
- The literal menu path string in this block is character-identical to the one written into `SKILL.md` in Task 6 and the hook message in Task 8. Verify with `grep -rn 'Tools/Framework/Apply Serialized Ops' .claude/` — three files, matching text. A drifted menu path is a tool that silently does nothing when `execute_menu_item` is called.

---

## Task 4 — EditMode test (and the one asmdef line it needs)

**Files:** `.claude/commands/setup-project.md` — (a) the `[ProjectName]EditModeTest.asmdef` blocks (~line 449), **both** the with-NSubstitute and without-NSubstitute variants; (b) a new block `#### \`_GameFolders/Scripts/Tests/[ProjectName]EditModeTest/SerializedOpsApplierTests.cs\`` in Step 5, next to `SampleEditModeTests.cs`.

**Steps:**
1. [ ] Add `"FrameworkEditor"` to the `references` array in *both* EditModeTest asmdef variants. This is chosen over a new `FrameworkEditorTests` assembly: the EditMode assembly is already `includePlatforms: ["Editor"]`, so it can legally reference an Editor-only assembly, and a new asmdef would be a fourth thing to keep in sync for one test file.
2. [ ] Test class `SerializedOpsApplierTests` in namespace `Game.EditModeTest` (matches the asmdef `rootNamespace`).
3. [ ] `[SetUp]` builds the fixture **at runtime**: `new GameObject("SerializedOpsFixture")` → `AddComponent<BoxCollider>()` → `PrefabUtility.SaveAsPrefabAsset` under `Assets/SerializedOpsFixtures/SerializedOpsFixture.prefab` → `Object.DestroyImmediate` the scene copy. A prefab cannot be shipped as a fenced text block: its YAML carries GUIDs and a `.meta` file that `/setup-project` has no way to author correctly.
4. [ ] `new GameObject()` is forbidden in **runtime** code only — `check-no-runtime-instantiate.sh` calls `should_skip_path` and exits 0 for Editor and test paths (verified at line 42-43 of the hook). Note this in a comment in the test so the next reader does not "fix" it.
5. [ ] `[TearDown]` deletes the fixture with `AssetDatabase.DeleteAsset` and removes `Assets/SerializedOpsFixtures` if empty. A leaked fixture turns the next run's `[SetUp]` into an overwrite that hides a failure.
5b. [ ] **Do not name this folder `Assets/Temp`.** The manifest lives in the project-root `Temp/` — Unity's own scratch directory, wiped on exit and gitignored in every Unity `.gitignore`. An `Assets/Temp` beside it is a different folder with different lifetime rules, and two things called Temp in one design is how someone eventually writes the manifest into `Assets/` and commits it.
6. [ ] Use **only Unity built-in component types** — `BoxCollider`, `Transform`. Never a project type: the applier is domain-free and its test must be too, or the template ships a test that cannot compile in a project that renamed its classes.
7. [ ] Cases, each calling `SerializedOpsApplier.Apply(json)` directly, no menu: (a) `setValue` on `BoxCollider.m_IsTrigger` → `Success`, and re-loading the prefab shows `true`; (b) `setValue` on a nonexistent property path → `Success == false`, one failed status, other ops in the same manifest still succeed; (c) `"version": 99` → `Aborted == true` and `Statuses` empty — the whole manifest refused; (d) malformed JSON → `Aborted`, no exception escapes; (e) `addComponent` of `SphereCollider` → present after reload; (f) `setRef` pointing at a second fixture asset → `objectReferenceValue` non-null after reload.
8. [ ] Expect the `Debug.LogError` calls with `LogAssert.Expect(LogType.Error, ...)` — an unexpected error log fails a Unity test, so the negative cases fail without it.

**Test Type:** **EditMode — this is the exception to the matrix.** Everything else in this plan is Editor-path NoTest; the applier is the one piece with real branching logic (version gate, type dispatch, read-back), and shipping it untested would mean the template's answer to "don't write throwaway Editor scripts" is itself unverified.

**Code Skeleton:**
```csharp
using NUnit.Framework;
using UnityEditor;
using UnityEngine;
using UnityEngine.TestTools;
using Framework.Editor;

namespace Game.EditModeTest
{
    public class SerializedOpsApplierTests
    {
        private const string FixturePath = "Assets/SerializedOpsFixtures/SerializedOpsFixture.prefab";

        [SetUp]
        public void SetUp()
        {
            // new GameObject() is banned in RUNTIME code only; test/Editor paths are exempt
            // (check-no-runtime-instantiate.sh skips them). Built-in types only — no domain types.
            AssetDatabase.CreateFolder("Assets", "SerializedOpsFixtures");
            var go = new GameObject("SerializedOpsFixture");
            go.AddComponent<BoxCollider>();
            PrefabUtility.SaveAsPrefabAsset(go, FixturePath);
            Object.DestroyImmediate(go);
        }

        [TearDown]
        public void TearDown() => AssetDatabase.DeleteAsset(FixturePath);

        [Test]
        public void Apply_WhenVersionUnknown_AbortsWholeManifest()
        {
            LogAssert.Expect(LogType.Error, new System.Text.RegularExpressions.Regex(@"\[SerializedOps\].*version"));
            var result = SerializedOpsApplier.Apply(@"{""version"":99,""ops"":[]}");
            Assert.IsTrue(result.Aborted);
            Assert.IsEmpty(result.Statuses);
        }

        [Test]
        public void Apply_WhenSetValueOnBuiltInComponent_PersistsAfterReload() { /* ... read back via a fresh LoadAssetAtPath */ }

        [Test]
        public void Apply_WhenOnePropertyPathIsWrong_FailsThatOpAndKeepsTheOthers() { /* ... */ }
    }
}
```

**Acceptance Criteria:**
- `python3 .claude/scripts/validate-generated-asmdefs.py .claude/commands/setup-project.md` exits 0 — it must see `using Framework.Editor;` satisfied by the `"FrameworkEditor"` reference just added. Confirm it *fails* before the asmdef edit and passes after; a validator that is green either way is not checking this edge.
- **`.claude/tests/setup-compile-probe/run-probe.sh` does NOT cover this file today** (Task 10 changes that with `--run-tests`; until Task 10 lands the next two bullets stand). The probe runs with `--skip "/Tests/"` (and `--skip "/Ecs/"`), so neither this test nor the fixture is compiled or executed by any automated layer in this repo. The only real verification is running `/setup-project` into a scratch project and executing the EditMode suite there. State this honestly in the plan's completion note; do not let a green probe be read as "the test passes".
- Manual verification, recorded with a date the way the Newtonsoft evidence is: generate a project, run the EditMode suite, all six cases green.

---

## Task 5 — One line in the Editors ARCHITECTURE.md block

**Files:** `.claude/commands/setup-project.md`, the `#### \`_Framework/Editors/ARCHITECTURE.md\`` block (~line 1142)

**Steps:**
1. [ ] Count the block's current lines first — it is ~26 and the cap is 40 (`.claude/rules/architecture.md`, `_Framework/<Subfolder>/` section: identical four headings, identical 40-line cap, identical ban on class-name-like symbols).
2. [ ] Add **one** sentence under `## How to extend`: a tool that applies serialized-property operations from a versioned manifest lives here, and new operation kinds are added to it rather than to a new one-off script.
3. [ ] Add **one** sentence under `## Gotchas`: a manifest-driven write that reports success without a read-back after save is not a success — the prefab save path can drop a change that the in-memory property already shows as applied.
4. [ ] **No class names.** `SerializedOpsApplier`, `SerializedOpsMenu`, `SerializedOpsResult` must not appear; the doc's own regex gate rejects class-name-like symbols. The menu path string is prose, not a symbol, and is acceptable — but prefer describing it to quoting it.
5. [ ] Do not add a fifth heading. Four headings, exactly, unchanged.

**Test Type:** NoTest.

**Code Skeleton:**
```markdown
## How to extend
Add the tool here and keep it self-contained. Editor code that needs to read runtime types
references the runtime assembly, never the reverse. Runtime code that needs an Editor-only
branch guards it with the Editor compilation symbol in place, instead of moving the file.
A tool here already applies serialized-property operations read from a versioned manifest;
a new kind of operation is added to that tool, never to a second script written to run once.

## Gotchas
The platform restriction lives in this folder's assembly definition, not in any file, so it
cannot be granted or waived per file. Moving one script out of this folder silently drops it
into a shipping build, with no error anywhere until something Editor-only is called at
runtime. A manifest-driven write that reports success without re-reading the asset from disk
afterwards has not verified anything — the save path can drop a change the in-memory
property already reports as applied.
```
Net effect: +2 lines under `How to extend`, +3 under `Gotchas` — 26 → 31, inside the 40-line cap. Symbols introduced: none.

**Acceptance Criteria:**
- The block is ≤ 40 lines: extract it and count.
- `.claude/hooks/check-architecture-doc.sh` passes over the generated block — run the repo's bats suite for that hook.
- `grep -E '\b[A-Z][A-Za-z0-9]*(Service|Manager|Controller|Handler|Provider|View|Event|Config|Configuration|Scope|Installer)\b'` over the five added lines returns nothing.

---

## Task 6 — MCP skill: name the tool where the fallback used to be

**Files:** `.claude/skills/core/unity-mcp-patterns/SKILL.md`

**Steps:**
1. [ ] Rule 4's tool-selection table (ends with the `C# scripts` row): add a row for the inspector-reference case.
2. [ ] Rule 6 step 4 currently reads *"If the error persists, fall back to writing an Editor script"*. That sentence is the thing this whole plan exists to delete. Replace it with the manifest route, and say plainly that writing a throwaway Editor script is blocked by a hook.
3. [ ] Add a short worked example under Rule 6: the manifest shape, the `execute_menu_item` call, then `read_console`. The `read_console` step is not optional — the menu item's return value is not visible to MCP, so the console **is** the result channel.
4. [ ] Document `execute_menu_item` itself. It is currently documented nowhere in this repo (`grep -rn execute_menu_item .claude/` returns nothing), so this is new documentation, not a cross-reference.
5. [ ] The parameter name `menu_path` is source-verified (Task 9 step 1, `ExecuteMenuItem.cs:25`) and needs no marker. What still carries `<UNVERIFIED — see Task 9>` is the end-to-end claim that the generated `[MenuItem]` is reachable after domain reload.

**Test Type:** NoTest.

**Code Skeleton:**
~~~markdown
<!-- Rule 4 table — append after the `C# scripts` row -->
| Inspector reference MCP cannot set | `execute_menu_item` | write `Temp/serialized-ops.json`, then invoke `Tools/Framework/Apply Serialized Ops` |

<!-- Rule 6, step 4 — REPLACES "If the error persists, fall back to writing an Editor script" -->
4. If the error persists on a **reference or serialized-field assignment**, do not write an
   Editor script — `check-no-throwaway-editor-script.sh` blocks it. Use the manifest route below.

### 6.1 Assigning what MCP cannot assign

`Temp/serialized-ops.json` (project-relative), then one menu invocation:

```json
{
  "version": 1,
  "ops": [
    { "op": "setRef",
      "asset": "Assets/_GameFolders/Prefabs/Example.prefab",
      "object": "Child/Grandchild",
      "component": "AudioSource",
      "property": "m_audioClip",
      "ref": { "asset": "Assets/_GameFolders/Audio/Example.wav" } },
    { "op": "setValue",
      "asset": "Assets/_GameFolders/Configs/ExampleConfig.asset",
      "property": "_volume",
      "value": 0.8 },
    { "op": "addComponent",
      "asset": "Assets/_GameFolders/Prefabs/Example.prefab",
      "type": "BoxCollider" }
  ]
}
```

```
execute_menu_item  menu_path<UNVERIFIED — see Task 9>: "Tools/Framework/Apply Serialized Ops"
read_console       → expect "[SerializedOps] N/N ops applied."
```

`read_console` is **not optional**: the menu item returns nothing to MCP, so the console is the
only result channel. A `[SerializedOps]` error line means at least one op failed; the whole
manifest was refused if the line says the manifest was aborted.

Order matters: write the manifest → confirm a clean compile with `read_console` → *then*
invoke. A `[MenuItem]` does not exist until the domain reload that follows a successful compile.
~~~

**Acceptance Criteria:**
- `grep -rn 'fall back to writing an Editor script' .claude/` returns nothing.
- `grep -rn 'execute_menu_item' .claude/skills/core/unity-mcp-patterns/SKILL.md` returns at least the table row and the worked example.
- The menu path string matches Task 3's `const` exactly: `grep -rn 'Tools/Framework/Apply Serialized Ops' .claude/` shows three files with identical text.
- Every parameter-name occurrence carries `<UNVERIFIED — see Task 9>`; the `UNVERIFIED` count equals the number of `execute_menu_item` invocation examples. Task 9 removes them.

---

## Task 7 — Setup checklist

**Files:** `.claude/docs/setup-checklist.md`

**Steps:**
1. [ ] Read the file first — it is 93 lines and, as of this writing, contains **no** "temporary Editor script" wording. The requirement to "replace the fallback wording" therefore resolves to *add* the route, not rewrite a sentence.
2. [ ] Add a bullet under `## MCP-Automated` (the list ending `Build Settings scene order (Bootstrap at index 0)`, before the `## Truly Manual` heading at line 14).
3. [ ] Point at the MCP skill section from Task 6 rather than duplicating the manifest schema. Two copies of a schema drift; the rule about one schema in one place applies to documentation too.

**Test Type:** NoTest.

**Code Skeleton:**
```markdown
- Inspector references MCP cannot assign directly (nested serialized fields, object
  references on prefabs and ScriptableObjects) — written as `Temp/serialized-ops.json` and
  applied by the `Tools/Framework/Apply Serialized Ops` menu item via `execute_menu_item`.
  Manifest shape and the required `read_console` check:
  `.claude/skills/core/unity-mcp-patterns/SKILL.md` §6.1. Automated, not manual — writing a
  throwaway Editor script for this is blocked by `check-no-throwaway-editor-script.sh`.
```

**Acceptance Criteria:**
- The new bullet sits under `## MCP-Automated`, not `## Truly Manual` — verify by reading the section boundaries at lines 5 and 14.
- No manifest schema is restated; only the pointer to `SKILL.md` §6.1. `grep -n '"version"' .claude/docs/setup-checklist.md` returns nothing.
- The menu path string matches Task 3's `const` exactly.

---

## Task 8 — The hook's block message names the tool

**Files:** `.claude/hooks/check-no-throwaway-editor-script.sh`, `.claude/hooks/tests/check-no-throwaway-editor-script.bats`

**Steps:**
1. [ ] Confirm the current message. It reads: `-> write it as a PERMANENT tool under Assets/Editor/, not a Temp/ file to delete`. It names a *location*, not a tool — so this is a real Modify, not a no-op.
2. [ ] Insert the named route **above** that line, inside the existing `unity_hook_block "..."` string, keeping the generic line beneath it for the bulk-`AssetImporter` cases the applier does not cover.
3. [ ] Preserve the quoting convention in force — the final line's `\"\$(git rev-parse ...)\"` shows that `$` and `"` are escaped inside this string. The inserted line contains neither, so no escaping is needed; do not introduce any.
4. [ ] Do not change any exit code, any signal regex, or the override-file path. This is text only.
5. [ ] Add one bats case asserting the new menu-path line appears in the block output.

**Test Type:** NoTest (shell). Covered by the bats case added in step 5.

**Code Skeleton:**
```bash
# inside the existing unity_hook_block "..." string, in the closing "If this genuinely needs C#" stanza:

If this genuinely needs C# (bulk AssetImporter work MCP does not cover):
  -> serialized-field / reference assignment is already solved: write the ops to
     Temp/serialized-ops.json and run the menu item Tools/Framework/Apply Serialized Ops
     (execute_menu_item), then read_console. See unity-mcp-patterns SKILL.md section 6.1.
  -> write it as a PERMANENT tool under Assets/Editor/, not a Temp/ file to delete
  -> or state the reason: echo 'why' > \"\$(git rev-parse --show-toplevel)/.claude/state/editor-script-override\"
Kill switch: DISABLE_HOOK_CHECK_NO_THROWAWAY_EDITOR_SCRIPT=1"
```

```bash
# .claude/hooks/tests/check-no-throwaway-editor-script.bats — new case, using the file's
# existing run_hook helper (jq -nc payload, $1 = file_path, $2 = content), same as every
# other case in that file. Place it under "--- Signal 1: scratch Editor path ---".
@test "block message names the serialized-ops menu item" {
    run_hook "Assets/Editor/Temp/Wire.cs" "class X { }"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Tools/Framework/Apply Serialized Ops"* ]]
}
```

**Acceptance Criteria:**
- `bash -n .claude/hooks/check-no-throwaway-editor-script.sh` exits 0.
- `.claude/hooks/tests/check-no-throwaway-editor-script.bats` **exists today and asserts on no exact message text**, so the wording change alone requires no bats edit — the existing suite must stay green unchanged before and after the message edit.
- The one new bats case above passes, and fails if the menu-path line is removed — verify by deleting the line locally and re-running. A case that passes either way is not testing the thing it names.
- `grep -n 'Tools/Framework/Apply Serialized Ops' .claude/hooks/check-no-throwaway-editor-script.sh` matches, character-identical to Task 3.
- Exit codes, signal regexes and `OVERRIDE_FILE` are byte-identical to before: `git diff` shows changes only inside the `unity_hook_block` string.

---

## Task 9 — Confirm `execute_menu_item` end-to-end (parameter shape is source-verified; one live run still owed)

**Files:** `.claude/skills/core/unity-mcp-patterns/SKILL.md` (the worked example written in Task 6)

**Steps:**
1. [x] **Parameter shape — resolved from source, 2026-09-25.** The MCP for Unity package (`com.coplaydev.unity-mcp`, version 9.7.3) is vendored in `nile_hole_sphere_repo/HoleSphere/Library/PackageCache/`. `Editor/Tools/ExecuteMenuItem.cs` line 25 reads `@params["menu_path"] ?? @params["menuPath"]` and line 38 passes it straight to `EditorApplication.ExecuteMenuItem(menuPath)` — so the parameter is `menu_path` (camelCase alias `menuPath`), the value is the **full** path including the leading `Tools/`, and the only blacklisted path is `File/Quit`. On failure the tool returns an error response *and* logs `[MenuItemExecutor] Failed to execute menu item '…'`, so a missing or not-yet-compiled `[MenuItem]` is visible in `read_console`. This closes the "guess written into a skill file" risk; Task 6 may drop the `<UNVERIFIED>` marker on the parameter name and cite this line instead.
2. [ ] Still owed: the Python-side tool schema is not vendored (only the C# handler is), so the exact MCP tool signature as the client sees it is inferred from the handler, not read. Confirm it once in a connected session; expect no surprise.
3. [ ] Confirm empirically that `execute_menu_item` can invoke a `[MenuItem]` defined in an Editor-platform assembly — a `[MenuItem]` only exists after a successful domain reload, so this also validates the ordering constraint (write manifest → confirm clean compile via `read_console` → *then* invoke). **This can be done before the tool exists**, against a menu that is already there: `nile_hole_sphere_repo` defines `[MenuItem("Tools/NileHoleSphere/Layout Import")]` inside `NileHoleSphereEditor.asmdef` (`includePlatforms: ["Editor"]`, the same shape as `FrameworkEditor`). In a **new** session (MCP tools are frozen at session start) with that project open, call `execute_menu_item` with `menu_path: "Tools/NileHoleSphere/Layout Import"` and check `read_console`: a window opening proves the mechanism generically; a `[MenuItemExecutor] Failed` line proves the opposite. Read-only against that repo — it opens a window, writes nothing. Record the result here with the date.
4. [ ] Replace the remaining `<UNVERIFIED — see Task 9>` marker (now only on the end-to-end claim, not on the parameter name) with the evidence record below.

**Test Type:** NoTest.

**Code Skeleton:**
```text
Evidence record — replaces the <UNVERIFIED> marker, written inline next to the parameter name.
Format mirrors the standard validate-generated-asmdefs.py sets for its `Newtonsoft` entry
("here on evidence, not assumption ... measured 2026-09-02").

  <param_name>   # read from the live execute_menu_item MCP tool schema, <YYYY-MM-DD>;
                 # full path including the leading "Tools/" — confirmed by one successful
                 # invocation that produced "[SerializedOps] N/N ops applied." in read_console.

Concretely, if the schema says menu_path:

  execute_menu_item  menu_path: "Tools/Framework/Apply Serialized Ops"
  # menu_path read from the live MCP tool schema 2026-09-__; leading "Tools/" required.
  # Verified end-to-end: console showed "[SerializedOps] 3/3 ops applied."

If the schema disagrees with the guess, correct Task 6's example; do NOT keep the guess
alongside the real name as an alternative.
```

**Acceptance Criteria:**
- The skill's worked example quotes a parameter name that was **read from the live MCP tool schema in a connected session**, with the date of that check written next to it in the format above.
- A transcript or console excerpt showing one successful `execute_menu_item` invocation of the menu path, and the `[SerializedOps]` summary line it produced in `read_console`.
- `grep -c 'UNVERIFIED' .claude/skills/core/unity-mcp-patterns/SKILL.md` returns 0.
- Until all three hold, this task stays open and Task 6's markers remain in place.

---

## Task 10 — Let the compile probe run the generated EditMode tests

**Files:** `.claude/tests/setup-compile-probe/run-probe.sh`, `.claude/tests/setup-compile-probe/README.md`

**Steps:**
1. [ ] Add a `--run-tests` flag. When set: (a) drop `--skip "/Tests/"` from the extraction call at line ~85 so the EditModeTest asmdef and test files are emitted into the throwaway project; (b) replace `-quit` with `-runTests -testPlatform EditMode -testResults "$OUT/editmode-results.xml"` on the Unity invocation at line ~119 (`-quit` and `-runTests` are mutually exclusive — Unity exits on its own when the run finishes); (c) parse the results XML for `result="Failed"` and fail the probe on any.
2. [ ] The probe must extract the **without-NSubstitute** EditModeTest asmdef variant — the probe project has no `NSubstitute.dll`, and `precompiledReferences` naming a missing DLL is a compile error. `SerializedOpsApplierTests` uses no NSubstitute, so this variant is sufficient. State in the README that the probe covers the tool's tests and **not** any test that needs NSubstitute.
3. [ ] Default stays compile-only: `--run-tests` costs minutes more and needs the test-framework package resolved. Document the flag and its cost in the README next to the existing "Excluded, and why" section (line ~39).
4. [ ] Update Task 4's acceptance criterion once this lands: the test IS then covered by an automated layer, and the "manual verification" bullet becomes "run `run-probe.sh --run-tests`".

**Test Type:** NoTest (shell harness). The harness is verified by running it: one run with the tests passing, one with a deliberately broken assertion to confirm the probe goes red.

**Code Skeleton:**
```bash
# run-probe.sh — flag
RUN_TESTS=0
case "$1" in --run-tests) RUN_TESTS=1 ;; esac

# extraction: skip /Tests/ only when not running them
SKIPS=(--skip "/Ecs/"); [ "$RUN_TESTS" -eq 0 ] && SKIPS+=(--skip "/Tests/")
python3 .claude/scripts/validate-generated-asmdefs.py --extract "$PROJ/Assets" \
    --project-name "Probe" "${SKIPS[@]}" "$SOURCE_MD"

# Unity: -quit XOR -runTests
if [ "$RUN_TESTS" -eq 1 ]; then
    "$UNITY_BIN" -batchmode -nographics -projectPath "$PROJ" \
        -runTests -testPlatform EditMode -testResults "$OUT/editmode-results.xml" -logFile "$LOG"
    grep -q 'result="Failed"' "$OUT/editmode-results.xml" && fail "EditMode tests failed — see $OUT/editmode-results.xml"
else
    "$UNITY_BIN" -batchmode -nographics -quit -projectPath "$PROJ" -logFile "$LOG"
fi
```

**Acceptance Criteria:**
- `run-probe.sh` (no flag) behaves byte-identically to today: same extraction skips, same `-quit` invocation, same exit codes.
- `run-probe.sh --run-tests` emits the EditModeTest asmdef (without-NSubstitute variant) and `SerializedOpsApplierTests.cs` into the probe project, runs EditMode, and exits 0 only when `editmode-results.xml` contains no `result="Failed"`.
- Negative check performed and recorded: a temporarily broken assertion in the test block turns the probe red. A harness that cannot go red is not measuring.
- README documents the flag, the NSubstitute exclusion, and the extra cost.

---

## Task 11 — A framework-only emit mode, so an EXISTING project can receive this tool

**Files:** `.claude/commands/setup-project.md` (Step 0 decision tree, branch B), `.claude/docs/setup-checklist.md`

**Steps:**
1. [ ] State the problem in the command, because it is the reason the branch exists: Step 4's blocks become `.cs` files **only when `/setup-project` runs**, and `/setup-project` runs once, at project creation. A project that was set up months ago receives the updated `setup-project.md` when its `.claude/` is refreshed and still has nothing on disk — measured 2026-09-25 against a real downstream project, whose `_Framework/Editors/` held one unrelated file and no serialized-ops tool.
2. [ ] Add a third option to Step 0 branch B, which today offers only "regenerate everything" or "sync settings only": **`framework` — emit missing `_Framework/**` files and nothing else.** Regenerating everything is not an option a live project can take, so today the honest answer for an existing project is "copy the blocks by hand", and a hand-copy is how a block drifts from its source.
3. [ ] The mode is **additive and non-destructive by construction**: for each `_Framework/**` block in Step 3 and Step 4, write the file only when it does not already exist. An existing file is reported as `kept` and never touched, never diffed, never merged — a merge would silently revert a local fix.
4. [ ] It touches `_Framework/**` only. `_GameFolders/**` is game code and belongs to the project, not the template; a new `AppScope.cs` landing on a project that has diverged is exactly the destructive regenerate this branch exists to avoid.
5. [ ] `.asmdef` files count as `_Framework/**` and follow the same "only if missing" rule — so a project whose `FrameworkEditor.asmdef` has picked up local references keeps them.
6. [ ] Print a receipt: one line per block, `wrote` or `kept`, then a total. A silent run is indistinguishable from a run that matched nothing.
7. [ ] Document it in `setup-checklist.md` next to the Task 7 bullet: this is how an existing project gets the serialized-ops tool, and how it will get every future `_Framework/` file.

**Test Type:** NoTest — `/setup-project` is a prompt, and a prompt has no exit code. The layer that *can* measure this is the compile probe: it already builds a throwaway project from the same blocks, so a project generated by the probe and then passed through this mode must be unchanged.

**Code Skeleton:**
```markdown
**B — project-features.json EXISTS and matches detected state**
→ Print: "Project already configured. Features: addressables=[x], testing=[x], ecs=[x]"
→ Ask: "Re-run setup to regenerate files, sync settings only, or emit missing _Framework files?"
→ If sync:      run Steps 5b + 5c only (update settings.json and CLAUDE.md header), then stop.
→ If framework: for every `_Framework/**` block in Steps 3 and 4, write it ONLY if the file
                does not exist. Never overwrite, never merge — an existing file is `kept`.
                Scope is `_Framework/**` alone; `_GameFolders/**` is the project's own code.
                Print one line per block and a total:

                  wrote  _Framework/Editors/SerializedOpsResult.cs
                  wrote  _Framework/Editors/SerializedOpsApplier.cs
                  wrote  _Framework/Editors/SerializedOpsMenu.cs
                  kept   _Framework/Editors/FrameworkEditor.asmdef   (exists)
                  kept   _Framework/Events/EventBus.cs               (exists)
                  --- 3 written, 2 kept

                Then stop. Do not continue to Step 1.
→ If regenerate: continue from Step 1.
```

**Acceptance Criteria:**
- Running the `framework` mode twice in a row is a no-op the second time: every line reads `kept`, and `git status` is clean.
- Against a project whose `_Framework/` file has a local edit, that file is reported `kept` and `git diff` shows no change to it.
- No file outside `_Framework/**` is written in this mode — verify with `git status` after a run on a project that is missing `_GameFolders` files too.
- The existing `sync` and `regenerate` branches behave exactly as before: their text is unchanged except for the added option in the question.
- `setup-checklist.md` names this mode as the route for an existing project.

---

## Not in scope

`.claude/agents/audio-clip-agent.md` and `.claude/agents/graphics-setup-agent.md` still use the `[InitializeOnLoad]` temporary-script pattern. **They stay out of scope, and legitimately so:** both drive `AssetImporter` settings (compression, load type, texture platform overrides), not `SerializedProperty` writes on prefab or ScriptableObject instances. The applier has no vocabulary for importer settings and giving it one would be a second tool wearing the first one's name. The hook's own comment already draws this line — "legitimate bulk `AssetImporter` work (audio-clip-agent, graphics-setup) belongs in a PERMANENT tool under Assets/Editor/" — and Task 8 preserves that clause rather than replacing it. A separate permanent importer tool is the right follow-up; it is a different plan, not a task in this one.
