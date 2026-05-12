---
name: odin-inspector
description: Odin Inspector kullanım paterni — attribute'lar, custom drawer'lar ve inspector özelleştirme örnekleri
model-tier: normal
---

# Odin Inspector (Sirenix) — Kullanım Paterni

## Konum
`Assets/Plugins/Sirenix/` — DLL tabanlı, kaynak kodu yok.

```csharp
using Sirenix.OdinInspector;
```

## Inspector Attribute'ları

### Görünürlük ve Düzenleme

```csharp
[ShowInInspector]          // property veya private field'ı inspector'da göster (serialize etmez)
[HideInInspector]          // public field'ı inspector'dan gizle
[ReadOnly]                 // inspector'da göster ama düzenlemeyi engelle
[ShowIf("_isEnabled")]     // koşullu göster
[HideIf("_isEnabled")]     // koşullu gizle
[EnableIf("_isEnabled")]   // koşullu aktifleştir
```

### Gruplama ve Layout

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

### Validasyon

```csharp
[Required]                              // null olamaz, inspector'da uyarı gösterir
[ValidateInput("IsPositive", "Pozitif olmalı")]
private float _speed;
private bool IsPositive(float value) => value > 0;

[MinValue(0)]
[MaxValue(100)]
[SerializeField] private float _health;

[AssetsOnly]    // sadece project asset'i kabul et
[SceneObjectsOnly]  // sadece sahnedeki object'i kabul et
```

### Buton

```csharp
[Button]
private void ResetStats() { }

[Button("Sıfırla", ButtonSizes.Large)]
private void ResetAll() { }

[Button]
[GUIColor(1f, 0.5f, 0.5f)]   // kırmızımsı buton
private void DeleteData() { }
```

### Değer Dropdown

```csharp
[ValueDropdown("GetOptions")]
[SerializeField] private string _selectedOption;

private IEnumerable<string> GetOptions() => new[] { "Option A", "Option B", "Option C" };
```

### Range ve Progress

```csharp
[ProgressBar(0, 100)]
[SerializeField] private float _health;

[Range(0f, 1f)]
[SerializeField] private float _volume;
```

### Info Kutuları

```csharp
[InfoBox("Bu alan çok önemli!")]
[InfoBox("Dikkat: negatif değer girme!", InfoMessageType.Warning)]
[InfoBox("Hata!", InfoMessageType.Error)]
```

## ScriptableObject ile Kullanım

Bu projede ScriptableObject config sınıflarında Odin attribute'ları kullanılır:

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

## Bu Projedeki Kurallar

- Odin attribute'ları sadece inspector organizasyonu ve validasyon için kullanılır — runtime logic'e karışmaz
- `[ShowInInspector]` sadece debug/monitor amacıyla kullanılır, serialize etmez
- `[Required]` tüm ScriptableObject referanslarına eklenir — null config'i önceden yakalar
- `[Button]` sadece Editor context'te anlamlı işlemler için (reset, test vb.)
- Runtime kodunda Odin namespace import'u `#if UNITY_EDITOR` guard'ı gerektirmez (Odin runtime DLL'leri var)
