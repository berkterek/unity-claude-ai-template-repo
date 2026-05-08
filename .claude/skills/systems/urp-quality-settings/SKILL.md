---
name: urp-quality-settings
description: Use when setting up multiple URP quality tiers (Low/Medium/High/Ultra), switching pipeline assets at runtime, exposing quality settings via ScriptableObject, or wiring quality selection to VContainer and IEventBus.
globs: ["**/URP*.asset", "**/*Quality*.cs", "**/*GraphicsSettings*.cs", "**/*RenderPipeline*.cs"]
---

# URP Quality Settings System

## Architecture Overview

```
URPQualityConfiguration (ScriptableObject)
    ↓ registered in AppInstaller
URPQualityService (implements IURPQualityService)
    ↓ applies pipeline asset at runtime
QualitySettings.renderPipeline = urpAsset
    ↓ fires event
IEventBus → URPQualityChangedEvent → other systems
```

---

## Quality Tier Design

Create one `UniversalRenderPipelineAsset` per tier. Never mutate a shared asset at runtime — swap the entire asset instead.

| Tier | Target Platform | Key Differences |
|------|----------------|-----------------|
| `URP_Low` | Low-end mobile | No shadows, MSAA off, no post-processing |
| `URP_Medium` | Mid-range mobile | Soft shadows 1 cascade, FXAA, minimal post |
| `URP_High` | High-end mobile / PC | 2 cascades, MSAA 2x, Bloom + Color Grading |
| `URP_Ultra` | PC / Console | 4 cascades, MSAA 4x, full post-processing |

### Pipeline Asset Settings Per Tier

| Setting | Low | Medium | High | Ultra |
|---------|-----|--------|------|-------|
| HDR | Off | On | On | On |
| MSAA | Off | Off | 2x | 4x |
| Render Scale | 0.75 | 0.85 | 1.0 | 1.0 |
| Shadow Distance | 0 | 30 | 70 | 150 |
| Shadow Cascades | 0 | 1 | 2 | 4 |
| Additional Lights | 0 | 2 | 4 | 8 |
| Soft Shadows | Off | Off | On | On |
| Post Processing | Off | Minimal | On | On |

---

## URPQualityConfiguration ScriptableObject

```csharp
[CreateAssetMenu(menuName = "Game/Graphics/URP Quality Configuration")]
public sealed class URPQualityConfiguration : ScriptableObject
{
    #region Fields

    [Header("Pipeline Assets (assign in Inspector)")]
    [SerializeField] private UniversalRenderPipelineAsset _lowAsset;
    [SerializeField] private UniversalRenderPipelineAsset _mediumAsset;
    [SerializeField] private UniversalRenderPipelineAsset _highAsset;
    [SerializeField] private UniversalRenderPipelineAsset _ultraAsset;

    [Header("Persistence")]
    [SerializeField] private string _qualityPrefsKey = "Graphics_QualityTier";

    [Header("Auto-Detect")]
    [SerializeField] private int _autoDetectRamThresholdMB = 3000;

    #endregion

    #region Properties

    public string QualityPrefsKey       => _qualityPrefsKey;
    public int    AutoDetectRamThreshold => _autoDetectRamThresholdMB;

    #endregion

    #region Public Methods

    public UniversalRenderPipelineAsset GetAsset(URPQualityTier tier)
    {
        return tier switch
        {
            URPQualityTier.Low    => _lowAsset,
            URPQualityTier.Medium => _mediumAsset,
            URPQualityTier.High   => _highAsset,
            URPQualityTier.Ultra  => _ultraAsset,
            _                     => _mediumAsset
        };
    }

    #endregion

    #region Validation

    private void OnValidate()
    {
        if (_lowAsset == null || _mediumAsset == null || _highAsset == null || _ultraAsset == null)
        {
            Debug.LogError($"{nameof(URPQualityConfiguration)}: All four pipeline assets must be assigned.");
        }
    }

    #endregion
}

public enum URPQualityTier { Low, Medium, High, Ultra }
```

---

## IURPQualityService Interface

```csharp
public interface IURPQualityService
{
    URPQualityTier CurrentTier { get; }

    void SetTier(URPQualityTier tier);
    void AutoDetect();
    void LoadSavedTier();
    void SaveCurrentTier();
}
```

---

## URPQualityService Implementation

```csharp
public sealed class URPQualityService : IURPQualityService, IInitializable, IDisposable
{
    #region Fields

    private readonly URPQualityConfiguration _config;
    private readonly IEventBus               _eventBus;
    private URPQualityTier                   _currentTier;

    #endregion

    #region Constructor

    public URPQualityService(URPQualityConfiguration config, IEventBus eventBus)
    {
        _config   = config;
        _eventBus = eventBus;
    }

    #endregion

    #region Properties

    public URPQualityTier CurrentTier => _currentTier;

    #endregion

    #region Lifecycle

    public void Initialize()
    {
        LoadSavedTier();
    }

    public void Dispose()
    {
        SaveCurrentTier();
    }

    #endregion

    #region Public Methods

    public void SetTier(URPQualityTier tier)
    {
        _currentTier = tier;

        UniversalRenderPipelineAsset asset = _config.GetAsset(tier);
        QualitySettings.renderPipeline = asset;

        _eventBus.Publish(new URPQualityChangedEvent { Tier = tier });
    }

    public void AutoDetect()
    {
        int ramMB = SystemInfo.systemMemorySize;

        URPQualityTier tier = ramMB switch
        {
            < 2000  => URPQualityTier.Low,
            < 3000  => URPQualityTier.Medium,
            < 6000  => URPQualityTier.High,
            _       => URPQualityTier.Ultra
        };

        // Also check GPU tier
        if (SystemInfo.graphicsMemorySize < 1024)
        {
            tier = URPQualityTier.Low;
        }

        SetTier(tier);
    }

    public void LoadSavedTier()
    {
        int saved = PlayerPrefs.GetInt(_config.QualityPrefsKey, -1);

        if (saved < 0)
        {
            AutoDetect();
            return;
        }

        SetTier((URPQualityTier)saved);
    }

    public void SaveCurrentTier()
    {
        PlayerPrefs.SetInt(_config.QualityPrefsKey, (int)_currentTier);
        PlayerPrefs.Save();
    }

    #endregion
}
```

---

## Event

```csharp
public struct URPQualityChangedEvent : IEvent
{
    public URPQualityTier Tier;
}
```

---

## Runtime Render Scale (Dynamic Resolution)

Adjust render scale without swapping assets — useful for adaptive performance:

```csharp
public void SetRenderScale(float scale)
{
    // scale: 0.5 (very low) → 1.0 (native) → 1.5 (supersampled)
    float clamped = Mathf.Clamp(scale, 0.5f, 1.5f);

    var urpAsset = QualitySettings.renderPipeline as UniversalRenderPipelineAsset;
    if (urpAsset != null)
    {
        urpAsset.renderScale = clamped;
    }
}
```

**Warning:** Mutating the shared pipeline asset affects all instances. Only do this for properties designed to be tweaked at runtime (renderScale, shadowDistance). Never change structural properties (MSAA mode, renderer type) at runtime.

---

## Adaptive Performance (Mobile)

On mobile, monitor frame time and throttle quality dynamically:

```csharp
public sealed class AdaptiveQualityController : MonoBehaviour, IInitializable
{
    private IURPQualityService _qualityService;
    private float              _frameTimeBuffer;
    private const float        TARGET_FRAME_MS   = 33.3f; // 30 fps
    private const float        THRESHOLD_HIGH_MS = 40f;
    private const float        THRESHOLD_LOW_MS  = 25f;

    [Inject]
    public void Construct(IURPQualityService qualityService)
    {
        _qualityService = qualityService;
    }

    public void Initialize() { }

    private void Update()
    {
        _frameTimeBuffer = Mathf.Lerp(_frameTimeBuffer, Time.deltaTime * 1000f, 0.1f);

        if (_frameTimeBuffer > THRESHOLD_HIGH_MS && _qualityService.CurrentTier > URPQualityTier.Low)
        {
            _qualityService.SetTier(_qualityService.CurrentTier - 1);
        }
        else if (_frameTimeBuffer < THRESHOLD_LOW_MS && _qualityService.CurrentTier < URPQualityTier.Ultra)
        {
            _qualityService.SetTier(_qualityService.CurrentTier + 1);
        }
    }
}
```

---

## VContainer Registration

```csharp
public sealed class GraphicsInstaller : ModuleInstaller
{
    [SerializeField] private URPQualityConfiguration _config;

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
            throw new InvalidOperationException($"{nameof(GraphicsInstaller)}: _config not assigned.");

        builder.RegisterInstance(_config);
        builder.Register<URPQualityService>(Lifetime.Singleton).As<IURPQualityService>();
    }
}
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Mutating pipeline asset properties at runtime | Only mutate `renderScale` and `shadowDistance`; swap assets for structural changes |
| One shared URP asset for all quality levels | Create 4 separate assets — never share |
| No auto-detect fallback | Always provide auto-detect via RAM + GPU memory check |
| Saving quality as string | Save as `int` enum value via PlayerPrefs |
| Switching quality mid-frame | Call `SetTier` outside Update (e.g., from settings UI callback) |
