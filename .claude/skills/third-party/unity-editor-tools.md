---
name: unity-editor-tools
description: Unity Editor scripting patterns beyond UI: AssetDatabase operations, AssetPostprocessor, InitializeOnLoad, EditorPrefs, SessionState, Undo system, PrefabUtility, Selection, build pipeline hooks, ScriptableWizard, and editor-only utilities. Use when writing Editor tools, automating asset workflows, hooking into Unity's build or import pipeline, persisting editor state, or building any non-UI editor functionality.
user-invocable: true
model-tier: normal
---

# Unity Editor Tools — Scripting Reference

## Editor Script Basics

All editor scripts must be in an `Editor/` folder or an editor-only assembly (`"includePlatforms": ["Editor"]`). They are stripped from builds automatically.

```csharp
// Any .cs file inside Assets/.../Editor/ is editor-only
// No #if UNITY_EDITOR guard needed inside Editor/ folder
using UnityEditor;
using UnityEngine;
```

Outside `Editor/` folders, always guard:
```csharp
#if UNITY_EDITOR
using UnityEditor;
#endif
```

---

## InitializeOnLoad — Run Code at Editor Start

`[InitializeOnLoad]` runs static constructor code when Unity starts or scripts recompile. Use for registering editor callbacks, setting up editor state, or one-time initialization.

```csharp
[InitializeOnLoad]
public static class LevelEditorBootstrap
{
    static LevelEditorBootstrap()
    {
        // Called on editor start and after every domain reload (script recompile)
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
        EditorApplication.hierarchyChanged     += OnHierarchyChanged;
    }
    
    private static void OnPlayModeChanged(PlayModeStateChange state)
    {
        if (state == PlayModeStateChange.EnteredPlayMode)
            Debug.Log("Play mode started");
        if (state == PlayModeStateChange.ExitingPlayMode)
            SaveEditorState();
    }
    
    private static void OnHierarchyChanged() { /* ... */ }
    private static void SaveEditorState()    { /* ... */ }
}
```

`[InitializeOnLoadMethod]` — same but on a static method instead of a class:

```csharp
[InitializeOnLoadMethod]
private static void RegisterCallbacks()
{
    EditorApplication.update += OnEditorUpdate;
}
```

**Important:** These run on every domain reload (every script compile). Keep the code fast and idempotent — unsubscribe before re-subscribing if needed.

---

## EditorPrefs — Persist Editor Settings

`EditorPrefs` persists data across Unity sessions (stored in OS registry/pref files). Use for editor tool settings, last-used values, and user preferences.

```csharp
// Keys — use a unique prefix to avoid collisions
private const string PREF_LAST_LEVEL_PATH = "MyProject.LevelEditor.LastLevelPath";
private const string PREF_GRID_SIZE       = "MyProject.LevelEditor.GridSize";
private const string PREF_SHOW_GRID       = "MyProject.LevelEditor.ShowGrid";

// Write
EditorPrefs.SetString(PREF_LAST_LEVEL_PATH, levelPath);
EditorPrefs.SetInt(PREF_GRID_SIZE, gridSize);
EditorPrefs.SetBool(PREF_SHOW_GRID, showGrid);

// Read (with default fallback)
var lastPath = EditorPrefs.GetString(PREF_LAST_LEVEL_PATH, "");
var gridSize = EditorPrefs.GetInt(PREF_GRID_SIZE, 1);
var showGrid = EditorPrefs.GetBool(PREF_SHOW_GRID, true);

// Check existence
if (EditorPrefs.HasKey(PREF_LAST_LEVEL_PATH))
    LoadLevel(EditorPrefs.GetString(PREF_LAST_LEVEL_PATH, ""));

// Delete
EditorPrefs.DeleteKey(PREF_LAST_LEVEL_PATH);
```

**EditorPrefs vs SessionState:**

| | `EditorPrefs` | `SessionState` |
|--|--------------|---------------|
| Scope | Persists across sessions | Current session only (cleared on Unity restart) |
| Use for | User preferences, tool settings | Transient editor state, temp values |
| Storage | OS registry / pref files | Memory |

```csharp
// SessionState — same API, session-scoped
SessionState.SetString("MyProject.TempPath", path);
var temp = SessionState.GetString("MyProject.TempPath", "");
```

---

## AssetDatabase — Asset File Operations

`AssetDatabase` is the only correct way to create, move, copy, delete, and refresh Unity assets. Never use `System.IO` directly on asset files — Unity won't track changes.

```csharp
// Create a ScriptableObject asset
var config = ScriptableObject.CreateInstance<LevelConfiguration>();
AssetDatabase.CreateAsset(config, "Assets/Levels/NewLevel.asset");
AssetDatabase.SaveAssets();
AssetDatabase.Refresh();

// Load an asset
var level = AssetDatabase.LoadAssetAtPath<LevelConfiguration>("Assets/Levels/Level01.asset");

// Find assets by type
var guids = AssetDatabase.FindAssets("t:LevelConfiguration", new[] { "Assets/Levels" });
foreach (var guid in guids)
{
    var path = AssetDatabase.GUIDToAssetPath(guid);
    var asset = AssetDatabase.LoadAssetAtPath<LevelConfiguration>(path);
}

// Move / rename
AssetDatabase.MoveAsset("Assets/Old/Level01.asset", "Assets/New/Level01.asset");

// Copy
AssetDatabase.CopyAsset("Assets/Templates/DefaultLevel.asset", "Assets/Levels/Level02.asset");

// Delete
AssetDatabase.DeleteAsset("Assets/Levels/Unused.asset");

// Get path from object reference
var path = AssetDatabase.GetAssetPath(someAsset);

// Get GUID from path
var guid = AssetDatabase.AssetPathToGUID("Assets/Levels/Level01.asset");
```

**Rules:**
- Always call `AssetDatabase.SaveAssets()` after creating/modifying assets
- Call `AssetDatabase.Refresh()` after file system changes outside Unity
- Batch operations between `AssetDatabase.StartAssetEditing()` / `StopAssetEditing()` to avoid redundant imports

```csharp
// Batch import — much faster when creating many assets
AssetDatabase.StartAssetEditing();
try
{
    for (int i = 0; i < 100; i++)
    {
        var asset = ScriptableObject.CreateInstance<TileData>();
        AssetDatabase.CreateAsset(asset, $"Assets/Tiles/Tile_{i:D3}.asset");
    }
}
finally
{
    AssetDatabase.StopAssetEditing(); // Always call even if exception thrown
    AssetDatabase.SaveAssets();
}
```

---

## Undo System

Wrap every editor modification in `Undo` so Ctrl+Z works correctly. Unity's Undo system is deep — it tracks object state, component changes, and hierarchy modifications.

```csharp
// Record before modifying a Unity Object (SerializedObject, ScriptableObject, Component)
Undo.RecordObject(target, "Change Speed");
myComponent.speed = 10f;
EditorUtility.SetDirty(target); // Mark modified so Unity saves it

// Record before adding a component
Undo.AddComponent<Rigidbody>(gameObject);

// Record before destroying
Undo.DestroyObjectImmediate(gameObject);

// Record before creating a GameObject
var go = new GameObject("New Tile");
Undo.RegisterCreatedObjectUndo(go, "Create Tile");

// Record before changing parent
Undo.SetTransformParent(transform, newParent, "Reparent");

// Group multiple operations into one undo step
Undo.IncrementCurrentGroup();
Undo.SetCurrentGroupName("Place Tile");
int group = Undo.GetCurrentGroup();

Undo.RecordObject(levelData, "Place Tile");
levelData.SetTile(pos, tileId);

Undo.RecordObject(levelRoot, "Place Tile");
levelRoot.AddTileObject(pos);

Undo.CollapseUndoOperations(group); // Collapse to one undo step
```

**EditorUtility.SetDirty:** Call after every manual change to a non-serialized-via-SerializedObject asset. Without it, Unity won't know the asset changed and won't save it.

```csharp
// SetDirty is needed when you modify an asset directly (not via SerializedObject)
myScriptableObject.value = 42;
EditorUtility.SetDirty(myScriptableObject);
AssetDatabase.SaveAssets();
```

---

## Selection

`Selection` gives access to the currently selected objects in the Editor.

```csharp
// Get selected GameObjects
var selected = Selection.gameObjects;
var active   = Selection.activeGameObject;

// Get selected assets
var selectedObjects = Selection.objects;
var activePath = AssetDatabase.GetAssetPath(Selection.activeObject);

// Set selection programmatically
Selection.activeGameObject = myGameObject;
Selection.objects = new Object[] { obj1, obj2 };

// Ping (highlight in Project window)
EditorGUIUtility.PingObject(myAsset);

// Focus object in Scene view
SceneView.lastActiveSceneView?.FrameSelected();
```

---

## AssetPostprocessor — Import Pipeline Hooks

`AssetPostprocessor` runs automatically when Unity imports assets. Use for enforcing naming conventions, auto-configuring textures/audio/models, or generating companion assets on import.

```csharp
public sealed class TextureImportProcessor : AssetPostprocessor
{
    // Called before Unity imports the texture
    private void OnPreprocessTexture()
    {
        if (!assetPath.Contains("/UI/")) return;
        
        var importer = assetImporter as TextureImporter;
        importer.textureType          = TextureImporterType.Sprite;
        importer.spriteImportMode     = SpriteImportMode.Single;
        importer.mipmapEnabled        = false;
        importer.filterMode           = FilterMode.Point; // pixel art
        importer.maxTextureSize       = 512;
    }
    
    // Called after Unity imports the texture
    private void OnPostprocessTexture(Texture2D texture)
    {
        if (!assetPath.Contains("/Icons/")) return;
        Debug.Log($"Icon imported: {assetPath} ({texture.width}x{texture.height})");
    }
    
    // Called after ALL assets in a batch are imported
    private static void OnPostprocessAllAssets(
        string[] importedAssets,
        string[] deletedAssets,
        string[] movedAssets,
        string[] movedFromAssetPaths)
    {
        foreach (var path in importedAssets)
        {
            if (path.EndsWith(".leveldata"))
                GenerateCompanionAsset(path);
        }
    }
    
    private static void GenerateCompanionAsset(string path) { /* ... */ }
}
```

**Common postprocessor callbacks:**

| Method | Trigger |
|--------|---------|
| `OnPreprocessTexture` | Before texture import |
| `OnPostprocessTexture` | After texture import |
| `OnPreprocessAudio` | Before audio import |
| `OnPostprocessAudio` | After audio import |
| `OnPreprocessModel` | Before model (FBX) import |
| `OnPostprocessModel` | After model import |
| `OnPostprocessAllAssets` | After any batch of assets imports |

---

## AssetModificationProcessor — File Operation Hooks

Intercept asset file operations (save, delete, move) before they happen.

```csharp
public sealed class LevelAssetGuard : UnityEditor.AssetModificationProcessor
{
    // Called before an asset is deleted — return true to allow, false to block
    private static AssetDeleteResult OnWillDeleteAsset(string path, RemoveAssetOptions options)
    {
        if (path.Contains("/Levels/") && path.EndsWith(".asset"))
        {
            var confirmed = EditorUtility.DisplayDialog(
                "Delete Level?",
                $"Are you sure you want to delete {path}?",
                "Delete", "Cancel");
            
            return confirmed
                ? AssetDeleteResult.DidNotDelete
                : AssetDeleteResult.FailedDelete;
        }
        return AssetDeleteResult.DidNotDelete;
    }
    
    // Called before assets are saved
    private static string[] OnWillSaveAssets(string[] paths)
    {
        // Return only the paths you want to actually save
        // Returning empty array cancels the save
        return paths;
    }
    
    // Called before an asset is moved
    private static AssetMoveResult OnWillMoveAsset(string sourcePath, string destinationPath)
    {
        return AssetMoveResult.DidNotMove; // Allow the move
    }
}
```

---

## EditorUtility — Dialogs and Progress

```csharp
// Confirmation dialog
bool confirmed = EditorUtility.DisplayDialog(
    "Build Level",
    "This will overwrite the existing level data. Continue?",
    "Build",   // OK button
    "Cancel"); // Cancel button

// Three-button dialog
int choice = EditorUtility.DisplayDialogComplex(
    "Unsaved Changes",
    "Save changes before closing?",
    "Save",    // returns 0
    "Discard", // returns 1
    "Cancel"); // returns 2

// Progress bar (for long operations)
try
{
    for (int i = 0; i < tiles.Count; i++)
    {
        EditorUtility.DisplayProgressBar(
            "Baking Level",
            $"Processing tile {i}/{tiles.Count}",
            (float)i / tiles.Count);
        
        ProcessTile(tiles[i]);
    }
}
finally
{
    EditorUtility.ClearProgressBar(); // Always clear, even on exception
}

// Open file/folder picker
var path = EditorUtility.OpenFilePanel("Open Level", "Assets/Levels", "asset");
var folder = EditorUtility.OpenFolderPanel("Select Output Folder", "Assets", "");
var savePath = EditorUtility.SaveFilePanel("Save Level As", "Assets/Levels", "NewLevel", "asset");
```

---

## ScriptableWizard — Simple Modal Tool Windows

`ScriptableWizard` is faster than `EditorWindow` for one-shot tools: fill form → click button → done.

```csharp
public sealed class CreateLevelWizard : ScriptableWizard
{
    public string LevelName = "Level_01";
    public int    Width     = 10;
    public int    Height    = 10;
    public LevelTheme Theme;
    
    [MenuItem("Tools/Create Level")]
    private static void Open()
    {
        DisplayWizard<CreateLevelWizard>("Create New Level", "Create", "Create & Open");
    }
    
    // "Create" button (primary)
    private void OnWizardCreate()
    {
        CreateLevel(LevelName, Width, Height, Theme);
    }
    
    // "Create & Open" button (secondary — optional)
    private void OnWizardOtherButton()
    {
        var level = CreateLevel(LevelName, Width, Height, Theme);
        AssetDatabase.OpenAsset(level);
    }
    
    // Validate input — shown as error message, disables Create button if non-empty
    private void OnWizardUpdate()
    {
        errorString = "";
        if (string.IsNullOrEmpty(LevelName))
            errorString = "Level name cannot be empty.";
        else if (Width <= 0 || Height <= 0)
            errorString = "Width and Height must be greater than 0.";
    }
    
    private LevelConfiguration CreateLevel(string name, int w, int h, LevelTheme theme)
    {
        var config = CreateInstance<LevelConfiguration>();
        config.Initialize(name, w, h, theme);
        
        var path = $"Assets/Levels/{name}.asset";
        AssetDatabase.CreateAsset(config, path);
        AssetDatabase.SaveAssets();
        
        return config;
    }
}
```

---

## Build Pipeline Hooks

Hook into Unity's build process to validate, inject, or transform content at build time.

```csharp
using UnityEditor.Build;
using UnityEditor.Build.Reporting;

// Runs before the build starts
public sealed class PreBuildValidator : IPreprocessBuildWithReport
{
    public int callbackOrder => 0; // Lower = runs first

    public void OnPreprocessBuild(BuildReport report)
    {
        // Validate required assets exist
        var requiredLevels = new[] { "Assets/Levels/Level01.asset", "Assets/Levels/Level02.asset" };
        foreach (var path in requiredLevels)
        {
            if (!System.IO.File.Exists(path))
                throw new BuildFailedException($"Required level missing: {path}");
        }
        
        Debug.Log($"Pre-build validation passed. Target: {report.summary.platform}");
    }
}

// Runs after the build completes
public sealed class PostBuildHandler : IPostprocessBuildWithReport
{
    public int callbackOrder => 0;

    public void OnPostprocessBuild(BuildReport report)
    {
        if (report.summary.result == BuildResult.Succeeded)
        {
            Debug.Log($"Build succeeded: {report.summary.outputPath}");
            CopyBuildArtifacts(report.summary.outputPath);
        }
        else
        {
            Debug.LogError($"Build failed with {report.summary.totalErrors} errors");
        }
    }
    
    private void CopyBuildArtifacts(string outputPath) { /* ... */ }
}
```

**Build pipeline interfaces:**

| Interface | When |
|-----------|------|
| `IPreprocessBuildWithReport` | Before build starts |
| `IPostprocessBuildWithReport` | After build completes |
| `IProcessSceneWithReport` | For each scene being built |
| `IPreprocessShaders` | Before shaders compile |

---

## PrefabUtility

```csharp
// Check if a GameObject is a prefab instance
bool isPrefab = PrefabUtility.IsPartOfPrefabInstance(go);
bool isAsset  = PrefabUtility.IsPartOfPrefabAsset(go);

// Get prefab source asset
var source = PrefabUtility.GetCorrespondingObjectFromSource(go);

// Instantiate a prefab (respects prefab connection — use this, not Instantiate)
var instance = PrefabUtility.InstantiatePrefab(prefabAsset, parentTransform) as GameObject;
Undo.RegisterCreatedObjectUndo(instance, "Place Prefab");

// Apply instance changes back to prefab
PrefabUtility.ApplyPrefabInstance(instance, InteractionMode.UserAction);

// Revert instance to prefab state
PrefabUtility.RevertPrefabInstance(instance, InteractionMode.UserAction);

// Unpack (break prefab connection)
PrefabUtility.UnpackPrefabInstance(instance, PrefabUnpackMode.Completely, InteractionMode.UserAction);

// Save modifications to a prefab asset
using (var scope = new PrefabUtility.EditPrefabContentsScope("Assets/Prefabs/Tile.prefab"))
{
    var root = scope.prefabContentsRoot;
    root.GetComponent<TileComponent>().tileId = newId;
} // Automatically saves on scope exit
```

---

## EditorApplication Callbacks

Common editor lifecycle events to hook into:

```csharp
// Called every editor frame (use sparingly — runs constantly)
EditorApplication.update += OnEditorUpdate;

// Called when play mode state changes
EditorApplication.playModeStateChanged += state =>
{
    switch (state)
    {
        case PlayModeStateChange.EnteredEditMode:  OnEnteredEditMode();  break;
        case PlayModeStateChange.ExitingEditMode:  OnExitingEditMode();  break;
        case PlayModeStateChange.EnteredPlayMode:  OnEnteredPlayMode();  break;
        case PlayModeStateChange.ExitingPlayMode:  OnExitingPlayMode();  break;
    }
};

// Called after scripts recompile (domain reload)
// Note: [InitializeOnLoad] is usually cleaner for this
AssemblyReloadEvents.afterAssemblyReload += OnAfterReload;
AssemblyReloadEvents.beforeAssemblyReload += OnBeforeReload;

// Called when hierarchy changes (GameObjects added/removed/renamed)
EditorApplication.hierarchyChanged += OnHierarchyChanged;

// Called when project window changes (assets imported/deleted)
EditorApplication.projectChanged += OnProjectChanged;

// Delay a call to after the current frame (useful after domain reload)
EditorApplication.delayCall += () => Debug.Log("Runs next editor frame");
```

---

## Common Patterns

### Persist Window State Across Reloads

EditorWindows lose non-serialized fields on domain reload. Use `EditorPrefs` or `[SerializeField]` fields on the window:

```csharp
public sealed class LevelEditorWindow : EditorWindow
{
    // [SerializeField] fields survive domain reload automatically
    [SerializeField] private string _lastOpenedPath;
    [SerializeField] private int    _selectedTileIndex;
    
    // Non-serialized fields must be restored in CreateGUI / OnEnable
    private LevelConfiguration _levelData;
    
    public void CreateGUI()
    {
        // Re-load after domain reload
        if (!string.IsNullOrEmpty(_lastOpenedPath))
            _levelData = AssetDatabase.LoadAssetAtPath<LevelConfiguration>(_lastOpenedPath);
        
        BuildUI();
    }
}
```

### Create Asset from ScriptableObject Template

```csharp
[MenuItem("Assets/Create/Level Configuration")]
private static void CreateLevelConfig()
{
    var asset = ScriptableObject.CreateInstance<LevelConfiguration>();
    
    // Create in currently selected folder
    var selectedPath = AssetDatabase.GetAssetPath(Selection.activeObject);
    if (string.IsNullOrEmpty(selectedPath))
        selectedPath = "Assets";
    else if (!AssetDatabase.IsValidFolder(selectedPath))
        selectedPath = System.IO.Path.GetDirectoryName(selectedPath);
    
    var path = AssetDatabase.GenerateUniqueAssetPath($"{selectedPath}/NewLevel.asset");
    AssetDatabase.CreateAsset(asset, path);
    AssetDatabase.SaveAssets();
    
    // Select and rename in Project window
    Selection.activeObject = asset;
    EditorGUIUtility.PingObject(asset);
}
```

### Validate MenuItem Availability

```csharp
[MenuItem("Tools/Build Selected Level")]
private static void BuildSelectedLevel()
{
    var level = Selection.activeObject as LevelConfiguration;
    BuildLevel(level);
}

// Same path + "_validate" suffix — return false to gray out the menu item
[MenuItem("Tools/Build Selected Level", true)]
private static bool BuildSelectedLevelValidate()
{
    return Selection.activeObject is LevelConfiguration;
}
```

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Modifying assets with `System.IO` | Unity doesn't track changes | Use `AssetDatabase` methods |
| Forgetting `EditorUtility.SetDirty` | Changes lost on Unity restart | Call after every direct asset modification |
| Forgetting `AssetDatabase.SaveAssets` | Asset changes not written to disk | Call after `SetDirty` |
| Not clearing progress bar on exception | Progress bar stuck on screen | Use `try/finally` with `ClearProgressBar()` |
| Subscribing in `[InitializeOnLoad]` without unsubscribing | Double callbacks after recompile | Unsubscribe before subscribing, or check with `-=` first |
| Using `Instantiate` for prefabs in Editor | Breaks prefab connection | Use `PrefabUtility.InstantiatePrefab` |
| Not wrapping editor changes in `Undo` | Ctrl+Z doesn't work | Always use `Undo.RecordObject` before changes |
| Calling `AssetDatabase.Refresh()` inside import callback | Infinite import loop | Never call Refresh inside `AssetPostprocessor` |
