# /create-test-scene — Play Mode Test Scene Generator

Creates a complete Play Mode test scene for a given feature: test scene, TestBootstrap prefab wiring, TestScope, TestInstaller, and a PlayMode test stub.

## Usage

```
/create-test-scene PlayerMovement
/create-test-scene EnemyCombat "needs IEnemySpawner and IEventBus"
```

Argument: PascalCase feature name. Optional second argument: hint about which services/prefabs are needed.

---

## Step 1 — Parse Arguments

Extract from `$ARGUMENTS`:
- `FEATURE` — first word, PascalCase (e.g., `PlayerMovement`)
- `HINT` — remainder of the string (optional context)

If no feature name provided → stop:
```
Usage: /create-test-scene <FeatureName> [optional hint]
Example: /create-test-scene PlayerMovement
```

---

## Step 2 — Preflight

Check:
1. Does `_Scenes/TestScenes/` exist? If not, it will be created by the scene builder.
2. Does `_GameFolders/Scripts/Games/TestScopes/` exist? If not, note it for the agent.
3. Does `_Scenes/TestScenes/[Feature]Test.unity` already exist? If yes → stop:
   ```
   ⚠ Test scene already exists: _Scenes/TestScenes/[Feature]Test.unity
   To recreate it, delete the scene first.
   ```
4. Find the PlayTests assembly path for the project.
5. Find existing TestScope files to understand the project namespace.

---

## Step 3 — Spawn unity-test-scene-builder

Spawn a **unity-test-scene-builder** subagent with this prompt:

```
Build a complete Play Mode test scene for the following feature.

## Feature
Name: [FEATURE]
Hint: [HINT or "none provided"]

## Project Context
- PlayTests assembly: [path found in preflight]
- Existing TestScopes: [list found in preflight, or "none yet"]
- Project namespace: [from CLAUDE.md]

## Your Task
Follow the unity-test-scene-builder agent instructions exactly:
1. Read project context files
2. Generate TestScope and TestInstaller C# scripts
3. Generate PlayMode test stub
4. Create the test scene via MCP
5. Wire TestBootstrap in the scene
6. Create Empty.unity if missing
7. Report all created files and manual steps required

Feature name to use: [FEATURE]
```

---

## Step 4 — Post-generation Report

After the agent completes, print:

```
## ✓ Test Scene Ready: [FEATURE]Test

### Created
- Scene:     _Scenes/TestScenes/[FEATURE]Test.unity
- TestScope: _GameFolders/Scripts/Games/TestScopes/[FEATURE]TestScope.cs
- Installer: _GameFolders/Scripts/Games/TestScopes/[FEATURE]TestInstaller.cs
- Test stub: _GameFolders/Scripts/Tests/[Project]PlayTests/[FEATURE]Tests.cs

### You must do manually (Claude cannot do these)
1. Add _Scenes/TestScenes/[FEATURE]Test.unity to Build Settings
2. Add _Scenes/TestScenes/Empty.unity to Build Settings (if not already)
3. Open [FEATURE]Test scene in Unity Editor
4. Drag your feature prefabs into the scene
5. Wire any [SerializeField] config references in [FEATURE]TestInstaller
6. Fill in the [UnityTest] stub with real scenario assertions

### Run the test
Window → General → Test Runner → PlayMode → run [FEATURE]Tests
```

$ARGUMENTS
