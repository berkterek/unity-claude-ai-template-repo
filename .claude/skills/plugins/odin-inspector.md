---
name: odin-inspector
description: Odin Inspector usage pattern — attributes, custom drawers, and inspector customization examples
model-tier: normal
---

# Odin Inspector (Sirenix) — Usage Pattern

## Location
`Assets/Plugins/Sirenix/` — DLL-based, no source code.

```csharp
using Sirenix.OdinInspector;
```

## Inspector Attributes

### Visibility and Editing

```csharp
[ShowInInspector]          // show a property or private field in the inspector (does not serialize)
[HideInInspector]          // hide a public field from the inspector
[ReadOnly]                 // show in inspector but prevent editing
[ShowIf("_isEnabled")]     // conditionally show
[HideIf("_isEnabled")]     // conditionally hide
[EnableIf("_isEnabled")]   // conditionally enable
```

### Grouping and Layout

```csharp
[FoldoutGroup("Settings")]
[SerializeField] private float _speed;

[TabGroup("Tab1")]
[SerializeField] private int _health;

[HorizontalGroup("Row")]
[SerializeField] private float _minValue;
[HorizontalGroup("Row")]
[SerializeField] private float _maxValue;

[BoxGroup("Combat")]
[SerializeField] private int _damage;

[TitleGroup("Audio")]
[SerializeField] private AudioClip _clip;
```

### Validation

```csharp
[Required]                              // cannot be null, shows warning in inspector
[ValidateInput("IsPositive", "Must be positive")]
private float _speed;
private bool IsPositive(float value) => value > 0;

[MinValue(0)]
[MaxValue(100)]
[SerializeField] private float _health;

[AssetsOnly]        // only accepts project assets
[SceneObjectsOnly]  // only accepts scene objects
```

### Buttons

```csharp
[Button]
private void ResetStats() { }

[Button("Reset All", ButtonSizes.Large)]
private void ResetAll() { }

[Button]
[GUIColor(1f, 0.5f, 0.5f)]   // reddish button
private void DeleteData() { }
```

### Value Dropdown

```csharp
[ValueDropdown("GetOptions")]
[SerializeField] private string _selectedOption;

private IEnumerable<string> GetOptions() => new[] { "Option A", "Option B", "Option C" };
```

### Range and Progress

```csharp
[ProgressBar(0, 100)]
[SerializeField] private float _health;

[Range(0f, 1f)]
[SerializeField] private float _volume;
```

### Info Boxes

```csharp
[InfoBox("This field is important!")]
[InfoBox("Warning: do not enter negative values!", InfoMessageType.Warning)]
[InfoBox("Error!", InfoMessageType.Error)]
```

## Usage with ScriptableObjects

Odin attributes are used on ScriptableObject config classes in this project:

```csharp
[CreateAssetMenu(menuName = "Hospital/Player Configuration")]
public sealed class PlayerConfiguration : ScriptableObject
{
    [TitleGroup("Movement")]
    [MinValue(0f)]
    [SerializeField] private float _moveSpeed = 5f;

    [TitleGroup("Movement")]
    [MinValue(0f)]
    [SerializeField] private float _runSpeed = 10f;

    [TitleGroup("Combat")]
    [Required]
    [SerializeField] private AudioClip _hitSound;

    public float MoveSpeed => _moveSpeed;
    public float RunSpeed => _runSpeed;
    public AudioClip HitSound => _hitSound;
}
```

## Project Rules

- Odin attributes are used only for inspector organization and validation — they do not affect runtime logic
- `[ShowInInspector]` is used for debug/monitor purposes only; it does not serialize
- `[Required]` is added to all ScriptableObject references — catches null configs early
- `[Button]` is only for editor-context operations (reset, test, etc.)
- Odin namespace imports in runtime code do not require a `#if UNITY_EDITOR` guard (Odin ships runtime DLLs)
