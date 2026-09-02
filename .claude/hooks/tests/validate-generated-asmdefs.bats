#!/usr/bin/env bats
#
# Tests the Layer-A validator, not a hook. It lives here so it runs with the
# rest of the suite — there is no second runner.
#
# The three "catches the real 2026-09-02 defect" tests below are regression
# tests against a bug that actually shipped: two asmdefs written while their
# folders were empty, left behind when code landed in them.

setup() {
    SCRIPT=".claude/scripts/validate-generated-asmdefs.py"
    T="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$T"; }

# Builds a minimal two-assembly markdown: Logging (owns Framework.Logging) and
# SaveLoad (whose source does `using Framework.Logging`).
# $1 = SaveLoad references JSON array, $2 = SaveLoad noEngineReferences,
# $3 = Logging noEngineReferences
fixture() {
    cat > "$T/doc.md" <<EOF
#### \`_Framework/Logging/FrameworkLogging.asmdef\`
\`\`\`json
{ "name": "FrameworkLogging", "references": [], "noEngineReferences": $3 }
\`\`\`

#### \`_Framework/Logging/DLog.cs\`
\`\`\`csharp
namespace Framework.Logging
{
    public static class DLog
    {
        public static void Log(string m) { UnityEngine.Debug.Log(m); }
    }
}
\`\`\`

#### \`_Framework/SaveLoadSystems/FrameworkSaveLoadSystems.asmdef\`
\`\`\`json
{ "name": "FrameworkSaveLoadSystems", "references": $1, "noEngineReferences": $2 }
\`\`\`

#### \`_Framework/SaveLoadSystems/SaveLoadService.cs\`
\`\`\`csharp
using Framework.Logging;

namespace Framework.SaveLoadSystems
{
    public sealed class SaveLoadService
    {
        public void Save() { DLog.Log("x"); }
    }
}
\`\`\`
EOF
    run python3 "$SCRIPT" "$T/doc.md"
}

@test "clean input passes" {
    fixture '["FrameworkLogging"]' false false
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "catches a cross-assembly using with no matching reference" {
    fixture '[]' false false
    [ "$status" -eq 2 ]
    [[ "$output" == *"using Framework.Logging"* ]]
    [[ "$output" == *"does not reference it"* ]]
}

@test "catches UnityEngine used under noEngineReferences: true" {
    fixture '["FrameworkLogging"]' false true
    [ "$status" -eq 2 ]
    [[ "$output" == *"noEngineReferences"* ]]
    [[ "$output" == *"DLog.cs"* ]]
}

@test "reports every finding at once, not just the first" {
    # Both defects are present: DLog.cs uses UnityEngine under noEngineReferences:true,
    # and SaveLoadService.cs has an unreferenced cross-assembly using. Two, not three —
    # SaveLoadService.cs itself contains no UnityEngine, so its assembly's
    # noEngineReferences:true is unused here and correctly produces no finding.
    fixture '[]' true true
    [ "$status" -eq 2 ]
    [[ "$output" == *"noEngineReferences"* ]]
    [[ "$output" == *"does not reference it"* ]]
    [[ "$output" == *"2 finding(s)"* ]]
}

@test "an assembly referencing itself's own namespace needs no reference entry" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{ "name": "FrameworkLogging", "references": [], "noEngineReferences": true }
```

#### `_Framework/Logging/DLog.cs`
```csharp
using Framework.Logging;

namespace Framework.Logging
{
    public static class DLog { }
}
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 0 ]
}

# Written originally listing VContainer and Cysharp here too, on the assumption that every
# package namespace is reference-free. The compile probe disproved that on 2026-09-02
# (CS0246 on `using VContainer.Unity`), so those two moved to the package tests above and
# this one keeps only what genuinely needs no reference.
@test "BCL, engine and auto-referenced namespaces need no project reference" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{ "name": "FrameworkLogging", "references": [], "noEngineReferences": false }
```

#### `_Framework/Logging/DLog.cs`
```csharp
using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using Newtonsoft.Json;
using TMPro;

namespace Framework.Logging
{
    public static class DLog { }
}
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 0 ]
}

@test "a using alias is not resolved as a dependency edge" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{ "name": "FrameworkLogging", "references": [], "noEngineReferences": false }
```

#### `_Framework/Logging/DLog.cs`
```csharp
using UCamera = UnityEngine.Camera;

namespace Framework.Logging
{
    public static class DLog { }
}
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 0 ]
}

@test "catches a reference to an assembly that is neither generated nor known-external" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{ "name": "FrameworkLogging", "references": ["FrameworkGhost"], "noEngineReferences": false }
```

#### `_Framework/Logging/DLog.cs`
```csharp
namespace Framework.Logging { public static class DLog { } }
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FrameworkGhost"* ]]
}

@test "malformed asmdef JSON is an error, never a skip" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{ "name": "FrameworkLogging", "references": [ }
```

#### `_Framework/Logging/DLog.cs`
```csharp
namespace Framework.Logging { public static class DLog { } }
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "a file with no asmdef blocks FAILS — silence is not a pass" {
    printf '# just prose\n' > "$T/doc.md"
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"NO ASMDEF BLOCKS FOUND"* ]]
}

@test "asmdefs but no C# also FAILS" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Logging/FrameworkLogging.asmdef`
```json
{ "name": "FrameworkLogging", "references": [] }
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"NO C# BLOCKS FOUND"* ]]
}

@test "a missing file is a usage error (1), not a pass" {
    run python3 "$SCRIPT" "$T/nope.md"
    [ "$status" -eq 1 ]
}

@test "catches a package using with no matching reference (the 2026-09-02 VContainer defect)" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Events/FrameworkEvents.asmdef`
```json
{ "name": "FrameworkEvents", "references": [], "noEngineReferences": true }
```

#### `_Framework/Events/EventBus.cs`
```csharp
using VContainer.Unity;

namespace Framework.Events
{
    public sealed class EventBus : IInitializable { }
}
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"package assembly 'VContainer'"* ]]
}

@test "a package using with the reference present passes" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/Events/FrameworkEvents.asmdef`
```json
{ "name": "FrameworkEvents", "references": ["VContainer"], "noEngineReferences": true }
```

#### `_Framework/Events/EventBus.cs`
```csharp
using VContainer.Unity;

namespace Framework.Events
{
    public sealed class EventBus : IInitializable { }
}
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 0 ]
}

@test "Newtonsoft needs no reference — Unity auto-references it (measured, not assumed)" {
    cat > "$T/doc.md" <<'EOF'
#### `_Framework/SaveLoadSystems/FrameworkSaveLoadSystems.asmdef`
```json
{ "name": "FrameworkSaveLoadSystems", "references": [], "noEngineReferences": false }
```

#### `_Framework/SaveLoadSystems/LocalSaveLoadDal.cs`
```csharp
using Newtonsoft.Json;

namespace Framework.SaveLoadSystems { public sealed class LocalSaveLoadDal { } }
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 0 ]
}

@test "UnityEngine.InputSystem is a package, not a free engine namespace" {
    cat > "$T/doc.md" <<'EOF'
#### `_GameFolders/Scripts/Games/Games.asmdef`
```json
{ "name": "Games", "references": [], "noEngineReferences": false }
```

#### `_GameFolders/Scripts/Games/Concretes/Inputs/InputService.cs`
```csharp
using UnityEngine.InputSystem;

namespace Game.Concretes.Inputs { public sealed class InputService { } }
```
EOF
    run python3 "$SCRIPT" "$T/doc.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unity.InputSystem"* ]]
}

@test "--extract writes the generated files and substitutes [ProjectName]" {
    run python3 "$SCRIPT" --extract "$T/out" --project-name Zed --skip "/Ecs/" --skip "/Tests/"         .claude/commands/setup-project.md
    [ "$status" -eq 0 ]
    [ -f "$T/out/_Framework/SaveLoadSystems/SaveLoadService.cs" ]
    [ -f "$T/out/_GameFolders/Scripts/Games/ZedGames.asmdef" ]
    [ ! -e "$T/out/_GameFolders/Scripts/Games/Ecs" ]
    grep -q '"name": "ZedGames"' "$T/out/_GameFolders/Scripts/Games/ZedGames.asmdef"
}

@test "--extract on a file with no blocks fails rather than writing nothing quietly" {
    printf '# prose only
' > "$T/empty.md"
    run python3 "$SCRIPT" --extract "$T/out2" "$T/empty.md"
    [ "$status" -eq 1 ]
    [[ "$output$stderr" == *"0 files"* ]] || [[ "$output" == *"0 files"* ]]
}

@test "the real setup-project.md passes" {
    run python3 "$SCRIPT" .claude/commands/setup-project.md
    [ "$status" -eq 0 ]
}
