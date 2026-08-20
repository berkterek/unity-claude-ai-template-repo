---
name: unity-uitoolkit
description: "Unity UI Toolkit patterns for custom Editor windows, custom inspectors, PropertyDrawers, and level editors. Use when building EditorWindow, custom Inspector, PropertyDrawer, UXML/USS layouts, VisualElement hierarchies, or SerializedProperty binding. Editor-only — NOT for runtime UI (this project uses UGUI; see unity-ugui skill for runtime UI)."
user-invocable: true
model-tier: normal
---

# Unity UI Toolkit — Editor & Runtime Guide

## When to Use UI Toolkit vs IMGUI

| Scenario | Use |
|----------|-----|
| New EditorWindow (level editor, tools) | UI Toolkit |
| New custom Inspector | UI Toolkit |
| New PropertyDrawer | UI Toolkit |
| Quick one-off Editor utility | IMGUI is fine |
| Runtime HUD / menus (Unity 2021.2+) | UI Toolkit |
| Existing IMGUI code you're extending | Leave as IMGUI |

---

## Core Concepts

### VisualElement Tree

UI Toolkit is a retained-mode UI. Every UI element is a `VisualElement` node in a tree — like the DOM.

```
root (EditorWindow.rootVisualElement)
└── ScrollView
    ├── Label "Level Name"
    ├── TextField
    └── Button "Build"
```

Build this tree in C# or UXML. USS styles it.

### Three Files per UI

```
Editor/
├── LevelEditorWindow.cs       ← C# logic + event handlers
├── LevelEditorWindow.uxml     ← Layout (optional but recommended)
└── LevelEditorWindow.uss      ← Styles (optional)
```

UXML and USS are optional — you can build purely in C#. For complex layouts, UXML is easier to read and iterate.

---

## EditorWindow

```csharp
using UnityEditor;
using UnityEngine.UIElements;

public sealed class LevelEditorWindow : EditorWindow
{
    [MenuItem("Tools/Level Editor")]
    public static void Open() => GetWindow<LevelEditorWindow>("Level Editor");

    public void CreateGUI()
    {
        // CreateGUI replaces OnGUI for UI Toolkit windows
        // Called once when the window is created or domain reloads
        
        var root = rootVisualElement;
        
        // Option A: Build in C#
        var label = new Label("Level Editor");
        root.Add(label);
        
        // Option B: Load from UXML (preferred for complex layouts)
        var visualTree = AssetDatabase.LoadAssetAtPath<VisualTreeAsset>(
            "Assets/Editor/LevelEditorWindow.uxml");
        visualTree.CloneInto(root);
        
        // Load USS
        var styleSheet = AssetDatabase.LoadAssetAtPath<StyleSheet>(
            "Assets/Editor/LevelEditorWindow.uss");
        root.styleSheets.Add(styleSheet);
        
        // Wire up events after tree is built
        WireEvents();
    }
    
    private void WireEvents()
    {
        var buildButton = rootVisualElement.Q<Button>("build-button");
        buildButton.clicked += OnBuildClicked;
    }
    
    private void OnBuildClicked() { /* ... */ }
}
```

**Key rule:** Use `CreateGUI()`, not `OnGUI()`. `OnGUI` is IMGUI — different system entirely.

---

## UXML Layout

```xml
<!-- LevelEditorWindow.uxml -->
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:ScrollView>
        <ui:Label text="Level Editor" name="title" class="title" />
        
        <ui:TextField label="Level Name" name="level-name-field" />
        <ui:IntegerField label="Width" name="width-field" value="10" />
        <ui:IntegerField label="Height" name="height-field" value="10" />
        
        <ui:VisualElement class="row">
            <ui:Button text="New Level" name="new-button" />
            <ui:Button text="Build" name="build-button" />
        </ui:VisualElement>
        
        <ui:ListView name="tiles-list" />
    </ui:ScrollView>
</ui:UXML>
```

**Common UXML elements:**

| Element | C# Type | Use |
|---------|---------|-----|
| `<ui:Label>` | `Label` | Read-only text |
| `<ui:Button>` | `Button` | Click action |
| `<ui:TextField>` | `TextField` | String input |
| `<ui:IntegerField>` | `IntegerField` | Int input |
| `<ui:FloatField>` | `FloatField` | Float input |
| `<ui:Toggle>` | `Toggle` | Bool checkbox |
| `<ui:EnumField>` | `EnumField` | Enum dropdown |
| `<ui:ObjectField>` | `ObjectField` | Unity Object reference |
| `<ui:ScrollView>` | `ScrollView` | Scrollable container |
| `<ui:ListView>` | `ListView` | Virtualized list |
| `<ui:VisualElement>` | `VisualElement` | Generic container |
| `<ui:Foldout>` | `Foldout` | Collapsible section |

---

## USS Styling

USS is CSS-like. Use it instead of inline C# style assignments for anything beyond trivial cases.

```css
/* LevelEditorWindow.uss */

.title {
    font-size: 16px;
    -unity-font-style: bold;
    margin-bottom: 8px;
}

.row {
    flex-direction: row;
    justify-content: space-between;
    margin-top: 4px;
}

/* State pseudo-classes */
Button:hover {
    background-color: rgb(80, 120, 180);
}

Button:active {
    background-color: rgb(60, 90, 140);
}

/* Name selector */
#build-button {
    background-color: rgb(60, 140, 60);
    color: white;
}
```

**Key USS properties:**

| Property | Values | Notes |
|----------|--------|-------|
| `flex-direction` | `row`, `column` | Layout direction |
| `justify-content` | `flex-start`, `center`, `space-between` | Main axis |
| `align-items` | `flex-start`, `center`, `stretch` | Cross axis |
| `margin` / `padding` | `4px`, `4px 8px` | Box model |
| `width` / `height` | `100px`, `100%`, `auto` | Size |
| `background-color` | `rgb(r,g,b)`, `rgba(r,g,b,a)` | Background |
| `color` | `rgb(r,g,b)` | Text color |
| `-unity-font-style` | `normal`, `bold`, `italic` | Unity-specific |
| `border-radius` | `4px` | Rounded corners |

---

## Querying Elements

```csharp
// By name (fastest, use for unique elements)
var button = root.Q<Button>("build-button");

// By type (first match)
var label = root.Q<Label>();

// By class
var rows = root.Query<VisualElement>(className: "row").ToList();

// All of type
root.Query<Button>().ForEach(b => b.SetEnabled(false));

// Null-safe: Q returns null if not found — always check
var field = root.Q<TextField>("name-field");
if (field == null) Debug.LogError("name-field not found in UXML");
```

---

## Custom Inspector

```csharp
using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine.UIElements;

[CustomEditor(typeof(LevelConfiguration))]
public sealed class LevelConfigurationEditor : Editor
{
    public override VisualElement CreateInspectorGUI()
    {
        // Return a VisualElement — UI Toolkit replaces OnInspectorGUI
        var root = new VisualElement();
        
        // Auto-bind all fields from SerializedObject
        InspectorElement.FillDefaultInspector(root, serializedObject, this);
        
        // Or build custom layout:
        root.Add(new PropertyField(serializedObject.FindProperty("_levelName")));
        root.Add(new PropertyField(serializedObject.FindProperty("_width")));
        
        var previewButton = new Button(() => PreviewLevel()) { text = "Preview" };
        root.Add(previewButton);
        
        return root;
    }
    
    private void PreviewLevel() { /* ... */ }
}
```

**Key rule:** Return from `CreateInspectorGUI()`, not `OnInspectorGUI()`. Both can coexist on the same class but only one is used.

---

## SerializedProperty Binding

`PropertyField` automatically binds to a `SerializedProperty` and handles undo/redo, prefab overrides, and multi-object editing.

```csharp
// Method 1: PropertyField (recommended — handles everything)
var field = new PropertyField(serializedObject.FindProperty("_speed"));
root.Add(field);

// IMPORTANT: Call Bind after adding to root
root.Bind(serializedObject);

// Method 2: Manual binding on individual fields
var speedField = new FloatField("Speed");
speedField.BindProperty(serializedObject.FindProperty("_speed"));
root.Add(speedField);
```

**Binding rules:**
- Call `root.Bind(serializedObject)` after building the whole tree, not per-element
- `PropertyField` respects `[Header]`, `[Tooltip]`, `[Range]` attributes automatically
- Use `PropertyField` unless you need a completely custom control

---

## PropertyDrawer

```csharp
using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine.UIElements;

[CustomPropertyDrawer(typeof(TileData))]
public sealed class TileDataDrawer : PropertyDrawer
{
    public override VisualElement CreatePropertyGUI(SerializedProperty property)
    {
        var container = new VisualElement();
        container.style.flexDirection = FlexDirection.Row;
        
        var typeField = new PropertyField(property.FindPropertyRelative("_type"), "");
        typeField.style.flexGrow = 1;
        
        var colorField = new PropertyField(property.FindPropertyRelative("_color"), "");
        colorField.style.width = 60;
        
        container.Add(typeField);
        container.Add(colorField);
        
        return container;
    }
}
```

**Key rule:** `CreatePropertyGUI` returns `VisualElement`. The old `OnGUI(Rect, ...)` is IMGUI — do not mix them in the same drawer.

---

## ListView (Virtualized Lists)

Use `ListView` for lists with many items — it virtualizes (only renders visible rows).

```csharp
var tilesList = new ListView();

// Data source
var tiles = new List<TileData> { /* ... */ };
tilesList.itemsSource = tiles;
tilesList.fixedItemHeight = 24;

// Factory: create each row element (called once per visible row)
tilesList.makeItem = () => new Label();

// Bind: fill row element with data (called each time a row scrolls into view)
tilesList.bindItem = (element, index) =>
{
    ((Label)element).text = tiles[index].Name;
};

// Selection
tilesList.selectionType = SelectionType.Single;
tilesList.onSelectionChange += objects =>
{
    var selected = objects.FirstOrDefault() as TileData;
    OnTileSelected(selected);
};

root.Add(tilesList);
```

For small lists (< 20 items), a plain `ScrollView` with manually added elements is simpler.

---

## Level Editor Pattern

A complete level editor typically has two grid approaches. Choose based on your use case:

| Approach | When to use |
|----------|------------|
| **VisualElement 2D Grid** | Top-down 2D tile map, grid is the primary editing surface, no 3D needed |
| **SceneView 3D Grid** | 3D world placement, working alongside existing scene objects, need camera control |
| **Both** | Complex editors: tile palette (2D UI) + 3D scene placement |

### Full EditorWindow Structure

```csharp
public sealed class LevelEditorWindow : EditorWindow
{
    private LevelData _levelData;
    private ListView _tileListView;
    private VisualElement _gridContainer;
    private TileData _selectedTile;
    
    [MenuItem("Tools/Level Editor")]
    public static void Open() => GetWindow<LevelEditorWindow>("Level Editor");

    public void CreateGUI()
    {
        var root = rootVisualElement;
        
        // Toolbar at top
        root.Add(BuildToolbar());
        
        // Main area: left panel (tile palette) + right panel (grid or scene view controls)
        var splitter = new TwoPaneSplitView(0, 200, TwoPaneSplitViewOrientation.Horizontal);
        splitter.Add(BuildTilePanel());
        splitter.Add(BuildGridPanel());
        root.Add(splitter);
    }
    
    private Toolbar BuildToolbar()
    {
        var toolbar = new Toolbar();
        toolbar.Add(new ToolbarButton(CreateNewLevel) { text = "New" });
        toolbar.Add(new ToolbarButton(SaveLevel) { text = "Save" });
        toolbar.Add(new ToolbarSpacer());
        toolbar.Add(new ToolbarButton(ClearLevel) { text = "Clear" });
        return toolbar;
    }
    
    private VisualElement BuildTilePanel()
    {
        var panel = new VisualElement();
        panel.style.minWidth = 200;
        panel.Add(new Label("Tile Palette"));
        
        _tileListView = new ListView
        {
            itemsSource       = TileDatabase.All,
            fixedItemHeight   = 48,
            selectionType     = SelectionType.Single
        };
        _tileListView.makeItem  = () => new TilePaletteRow();
        _tileListView.bindItem  = (e, i) => ((TilePaletteRow)e).Bind(TileDatabase.All[i]);
        _tileListView.onSelectionChange += objs =>
            _selectedTile = objs.FirstOrDefault() as TileData;
        
        panel.Add(_tileListView);
        return panel;
    }
    
    private VisualElement BuildGridPanel()
    {
        var panel = new VisualElement();
        panel.style.flexGrow = 1;
        
        // See "VisualElement 2D Grid" section below for _gridContainer
        _gridContainer = new VisualElement();
        _gridContainer.style.flexGrow = 1;
        panel.Add(_gridContainer);
        
        return panel;
    }
    
    private void CreateNewLevel() { RefreshGrid(); }
    private void SaveLevel()      { /* ... */ }
    private void ClearLevel()     { /* ... */ }
    private void RefreshGrid()    { /* ... */ }
    
    private void OnEnable()  => SceneView.duringSceneGui += OnSceneGUI;
    private void OnDisable() => SceneView.duringSceneGui -= OnSceneGUI;
    private void OnSceneGUI(SceneView sv) { /* see SceneView section */ }
}
```

---

## VisualElement 2D Grid (UI Toolkit Grid)

Use when the grid is embedded inside the EditorWindow panel — no 3D camera needed.

```csharp
// Builds an NxM grid of clickable cells inside a VisualElement container
private void BuildGrid(VisualElement container, int[,] map, int cellSize = 32)
{
    container.Clear();
    container.style.flexDirection = FlexDirection.Column;

    int rows = map.GetLength(0);
    int cols = map.GetLength(1);

    for (int row = 0; row < rows; row++)
    {
        var rowElement = new VisualElement();
        rowElement.style.flexDirection = FlexDirection.Row;

        for (int col = 0; col < cols; col++)
        {
            int r = row, c = col; // capture for closure
            
            var cell = new VisualElement();
            cell.style.width  = cellSize;
            cell.style.height = cellSize;
            cell.style.borderBottomWidth = cell.style.borderRightWidth = 1;
            cell.style.borderBottomColor = cell.style.borderRightColor = Color.gray;
            
            // Color cell based on tile type
            cell.style.backgroundColor = GetTileColor(map[row, col]);
            
            // Click to paint
            cell.RegisterCallback<MouseDownEvent>(evt =>
            {
                if (_selectedTile == null) return;
                map[r, c] = _selectedTile.Id;
                cell.style.backgroundColor = GetTileColor(_selectedTile.Id);
                evt.StopPropagation();
            });
            
            // Drag to paint (hold and drag across cells)
            cell.RegisterCallback<MouseMoveEvent>(evt =>
            {
                if (evt.pressedButtons != 1) return; // left mouse only
                if (_selectedTile == null) return;
                map[r, c] = _selectedTile.Id;
                cell.style.backgroundColor = GetTileColor(_selectedTile.Id);
            });
            
            rowElement.Add(cell);
        }
        container.Add(rowElement);
    }
}

private Color GetTileColor(int tileId) => tileId switch
{
    0 => Color.black,
    1 => Color.green,
    2 => new Color(0.5f, 0.3f, 0.1f),
    _ => Color.white
};
```

**Key points:**
- `RegisterCallback<MouseDownEvent>` / `MouseMoveEvent` — UI Toolkit's event system, not IMGUI
- `evt.StopPropagation()` prevents the click from bubbling up to parent elements
- `evt.pressedButtons` checks which mouse button is held (1 = left)
- For large maps (> 50×50), use `IMGUIContainer` + custom `GL` rendering instead — VisualElement cells have overhead

---

## SceneView 3D Grid (Handles + Event)

Use when tiles/objects need to be placed in 3D world space, snapped to a world-space grid.

```csharp
private void OnSceneGUI(SceneView sceneView)
{
    if (_selectedTile == null) return;
    
    var e = Event.current;
    
    // Get world position under cursor (plane-based, no collider needed)
    var ray = HandleUtility.GUIPointToWorldRay(e.mousePosition);
    var worldPos = Vector3.zero;
    var plane = new Plane(Vector3.up, Vector3.zero); // XZ plane at y=0
    if (plane.Raycast(ray, out float enter))
        worldPos = ray.GetPoint(enter);
    
    // Snap to grid
    float cellSize = 1f;
    var snapped = new Vector3(
        Mathf.Floor(worldPos.x / cellSize) * cellSize,
        0,
        Mathf.Floor(worldPos.z / cellSize) * cellSize
    );
    
    // Draw preview at snapped position
    Handles.color = new Color(1, 1, 0, 0.4f);
    Handles.DrawWireCube(snapped + Vector3.one * cellSize * 0.5f, Vector3.one * cellSize);
    
    // Draw grid lines around cursor
    DrawWorldGrid(snapped, 5, cellSize);
    
    // Place on left click
    if (e.type == EventType.MouseDown && e.button == 0)
    {
        PlaceTileAt(snapped);
        e.Use(); // Consume — prevents Unity from deselecting objects
    }
    
    // Erase on right click
    if (e.type == EventType.MouseDown && e.button == 1)
    {
        EraseTileAt(snapped);
        e.Use();
    }
    
    // Repaint so preview moves with cursor
    sceneView.Repaint();
}

private void DrawWorldGrid(Vector3 center, int radius, float cellSize)
{
    Handles.color = new Color(1, 1, 1, 0.15f);
    for (int x = -radius; x <= radius; x++)
    {
        var from = center + new Vector3(x * cellSize, 0, -radius * cellSize);
        var to   = center + new Vector3(x * cellSize, 0,  radius * cellSize);
        Handles.DrawLine(from, to);
    }
    for (int z = -radius; z <= radius; z++)
    {
        var from = center + new Vector3(-radius * cellSize, 0, z * cellSize);
        var to   = center + new Vector3( radius * cellSize, 0, z * cellSize);
        Handles.DrawLine(from, to);
    }
}

private void PlaceTileAt(Vector3 snappedPos)
{
    // Register undo so Ctrl+Z works
    Undo.RecordObject(_levelData, "Place Tile");
    _levelData.SetTile(snappedPos, _selectedTile.Id);
    EditorUtility.SetDirty(_levelData);
}

private void EraseTileAt(Vector3 snappedPos)
{
    Undo.RecordObject(_levelData, "Erase Tile");
    _levelData.ClearTile(snappedPos);
    EditorUtility.SetDirty(_levelData);
}
```

**Key points:**
- `Plane.Raycast` — snap to a mathematical plane (no collider needed on the floor)
- `e.Use()` — critical: without it, clicks pass through and deselect your GameObject
- `Undo.RecordObject` — always wrap placement in undo so Ctrl+Z works
- `EditorUtility.SetDirty` — marks the asset as modified so Unity saves it
- `sceneView.Repaint()` — forces SceneView to redraw every frame so preview follows cursor
- `OnSceneGUI` uses IMGUI `Event` — this is intentional, not a mistake

Note: EditorWindow UI (panels, buttons) uses UI Toolkit; scene interaction uses Handles/Event. They live side by side in the same window class.

---

## Runtime UI Toolkit

For runtime UI (not Editor), the setup is different:

1. Add `UIDocument` component to a GameObject in the scene
2. Assign a `PanelSettings` asset and a `VisualTreeAsset` (UXML)
3. Access the root in C#:

```csharp
public sealed class MainMenuView : MonoBehaviour
{
    private UIDocument _document;
    private Button _playButton;
    
    private void Awake()
    {
        _document = GetComponent<UIDocument>();
    }
    
    [Inject]
    public void Construct(IMenuService menuService)
    {
        _menuService = menuService;
    }
    
    private void OnEnable()
    {
        var root = _document.rootVisualElement;
        _playButton = root.Q<Button>("play-button");
        _playButton.clicked += OnPlayClicked;
    }
    
    private void OnDisable()
    {
        if (_playButton != null)
            _playButton.clicked -= OnPlayClicked;
    }
    
    private void OnPlayClicked() => _menuService.StartGame();
}
```

Subscribe in `OnEnable`, unsubscribe in `OnDisable` — same pattern as a UGUI View.

---

## Assembly Definition for Editor UI

Editor code must live in an `Editor/` folder or be in an editor-only assembly:

```json
{
    "name": "MyProjectEditor",
    "references": [
        "MyProjectGames",
        "UnityEditor.UIElements",
        "UnityEngine.UIElements"
    ],
    "includePlatforms": ["Editor"],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "autoReferenced": true,
    "defineConstraints": []
}
```

Runtime UI Toolkit assemblies don't need `UnityEditor.UIElements` — only `UnityEngine.UIElements`.

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Using `OnGUI` instead of `CreateGUI` | Window flickers, IMGUI mixed in | Replace with `CreateGUI()` |
| Forgetting `root.Bind(serializedObject)` | Fields show but don't update | Call `Bind` after building tree |
| Calling `Q<T>()` before tree is built | Returns null | Query inside/after `CreateGUI` |
| Not using `e.Use()` in `OnSceneGUI` | Mouse clicks pass through to scene | Call `e.Use()` after handling |
| `EditorWindow` reference lost after domain reload | Null refs after script recompile | Re-query elements in `CreateGUI` — it's called again after reload |
| Modifying `itemsSource` list without `RefreshItems()` | ListView doesn't update | Call `listView.RefreshItems()` after changing the list |
| Runtime `UIDocument` not found | `NullReferenceException` | Access root in `OnEnable`, not `Awake` — document may not be ready |
