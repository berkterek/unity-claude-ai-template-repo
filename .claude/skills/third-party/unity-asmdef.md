---
name: unity-asmdef
description: Assembly Definition setup, reference wiring, and diagnosis for Unity projects. Use when adding a new assembly, fixing CS0246/CS0234 reference errors, or wiring test assemblies to game assemblies.
user-invocable: true
model-tier: normal
---

# Unity Assembly Definitions — Setup & Diagnosis

## What Assembly Definitions Do

Assembly definitions (`.asmdef`) split a Unity project into independently compiled assemblies. Each folder with an `.asmdef` file is its own assembly. Benefits:

- Faster incremental compilation (only changed assemblies recompile)
- Compile-time enforcement of dependency direction
- Test assemblies can reference game assemblies without polluting production builds

---

## Project Assembly Structure

```
Assets/
├── _Framework/
│   └── Framework.asmdef              ← Pure C#, no Unity game dep
└── _GameFolders/Scripts/
    ├── Games/
    │   └── [Project]Games.asmdef     ← References Framework
    └── Tests/
        ├── [ProjectName]EditModeTest/
        │   └── [ProjectName]EditModeTest.asmdef ← Edit Mode, references Games + NSubstitute
        └── [ProjectName]PlayModeTest/
            └── [ProjectName]PlayModeTest.asmdef ← Play Mode, references Games + NSubstitute
```

---

## Assembly File Templates

### Game Assembly (`[Project]Games.asmdef`)

```json
{
    "name": "MyProjectGames",
    "references": [
        "MyProjectFramework",
        "Unity.InputSystem",
        "VContainer",
        "UniTask"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": []
}
```

### Framework Assembly (`Framework.asmdef`)

```json
{
    "name": "MyProjectFramework",
    "references": [],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": []
}
```

`_Framework` must NOT reference `_GameFolders` assemblies. Dependency direction is enforced by the assembly graph.

### Edit Mode Test Assembly (`[ProjectName]EditModeTest.asmdef`)

```json
{
    "name": "MyProjectTests",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "MyProjectGames"
    ],
    "includePlatforms": ["Editor"],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": ["UNITY_INCLUDE_TESTS"],
    "versionDefines": []
}
```

### Play Mode Test Assembly (`[ProjectName]PlayModeTest.asmdef`)

Same as Edit Mode but with `"includePlatforms": []` (all platforms):

```json
{
    "name": "MyProjectPlayModeTest",
    "references": [
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "MyProjectGames"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll",
        "NSubstitute.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": ["UNITY_INCLUDE_TESTS"],
    "versionDefines": []
}
```

---

## Critical Fields

| Field | Value | Why |
|-------|-------|-----|
| `overrideReferences` | `true` in test asmdefs | Required to use `precompiledReferences` (NSubstitute, nunit) |
| `autoReferenced` | `false` in test asmdefs | Prevents test code from being included in production builds |
| `defineConstraints` | `["UNITY_INCLUDE_TESTS"]` | Strips test code from non-test builds |
| `includePlatforms` | `["Editor"]` for Edit Mode | Edit Mode tests only run in Editor |

---

## Diagnosing Reference Errors

### `CS0246` — type not found

The type's assembly is not referenced.

**Steps:**
1. Find which `.asmdef` owns the missing type (look at the folder containing its `.cs` file)
2. Open your assembly's `.asmdef`
3. Add the missing assembly name to `references`
4. Refresh Unity (`mcp__unityMCP__refresh_unity`)

### `CS0234` — namespace not found

Same as CS0246 — missing assembly reference.

### NSubstitute `CS0246` in test files

The test `.asmdef` is missing NSubstitute configuration. Fix:
1. Set `"overrideReferences": true`
2. Add `"NSubstitute.dll"` to `precompiledReferences`
3. Confirm `Assets/_GameFolders/Plugins/NSubstitute/NSubstitute.dll` exists

### Tests not visible in Test Runner

1. Check `defineConstraints` includes `"UNITY_INCLUDE_TESTS"`
2. Check `autoReferenced` is `false`
3. Check the assembly appears in Project Settings → Player → Scripting Assemblies
4. Refresh Unity

### Circular reference error

Assembly A references Assembly B which references Assembly A. Unity does not allow circular references.

**Fix:** Extract the shared types to a third assembly (e.g., `[Project]Shared.asmdef`) that both A and B reference.

---

## Adding a New Assembly (Checklist)

When creating a new module that needs its own assembly:

1. Create the `.asmdef` file in the module folder
2. Set `name` to match your naming convention (`[Project][Layer]`)
3. Add references to assemblies this module depends on
4. Do NOT add references from lower-level assemblies up to this one (dependency direction only goes downward)
5. If this assembly needs testing: add its name to the test assembly's `references`
6. Refresh Unity and check for compile errors

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `overrideReferences: false` on test asmdef | NSubstitute not found | Set to `true` |
| Missing game assembly in test references | Test cannot see classes under test | Add game assembly to test `references` |
| `autoReferenced: true` on test asmdef | Test code leaks into production build | Set to `false` |
| Circular reference between assemblies | CS0011 compile error | Extract shared types to a common assembly |
| `.asmdef` name does not match `name` field | Unity ignores the file | Ensure filename matches `"name"` value exactly |
| Script outside any `.asmdef` scope | Script goes into default Assembly-CSharp | Move script into a folder covered by an `.asmdef` |
