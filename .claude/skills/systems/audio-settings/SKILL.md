---
name: audio-settings
description: Use when implementing audio settings UI (volume sliders, mute toggles), persisting audio preferences via PlayerPrefs or save system, or wiring AudioConfiguration ScriptableObject with VContainer for runtime volume control.
globs: ["**/*AudioConfig*.cs", "**/*AudioSettings*.cs", "**/*AudioService*.cs", "**/*SoundSettings*.cs"]
---

# Audio Settings System

## Architecture Overview

```
AudioConfiguration (ScriptableObject)
    ↓ registered in AudioInstaller
AudioSettingsService (implements IAudioSettingsService)
    ↓ VContainer injection
AudioSettingsView (MonoBehaviour — UI sliders/toggles)
    ↓ calls service methods
AudioMixerService (applies volumes to AudioMixer)
    ↓ fires events
IEventBus → AudioSettingsChangedEvent → other systems
```

Settings are **not** stored on the AudioMixer itself at runtime. The source of truth is the `AudioSettingsService`. Mixer parameters are a side effect of applying settings.

---

## AudioConfiguration ScriptableObject

```csharp
[CreateAssetMenu(menuName = "Game/Audio/Audio Configuration")]
public sealed class AudioConfiguration : ScriptableObject
{
    #region Fields

    [Header("Default Volumes (0–1)")]
    [SerializeField, Range(0f, 1f)] private float _masterVolumeDefault  = 1f;
    [SerializeField, Range(0f, 1f)] private float _musicVolumeDefault   = 0.8f;
    [SerializeField, Range(0f, 1f)] private float _sfxVolumeDefault     = 1f;
    [SerializeField, Range(0f, 1f)] private float _voiceVolumeDefault   = 1f;

    [Header("Persistence Keys")]
    [SerializeField] private string _masterKey  = "Audio_Master";
    [SerializeField] private string _musicKey   = "Audio_Music";
    [SerializeField] private string _sfxKey     = "Audio_SFX";
    [SerializeField] private string _voiceKey   = "Audio_Voice";
    [SerializeField] private string _muteKey    = "Audio_Muted";

    #endregion

    #region Properties

    public float MasterVolumeDefault  => _masterVolumeDefault;
    public float MusicVolumeDefault   => _musicVolumeDefault;
    public float SFXVolumeDefault     => _sfxVolumeDefault;
    public float VoiceVolumeDefault   => _voiceVolumeDefault;

    public string MasterKey => _masterKey;
    public string MusicKey  => _musicKey;
    public string SFXKey    => _sfxKey;
    public string VoiceKey  => _voiceKey;
    public string MuteKey   => _muteKey;

    #endregion

    #region Validation

    private void OnValidate()
    {
        if (string.IsNullOrEmpty(_masterKey))
        {
            Debug.LogError($"{nameof(AudioConfiguration)}: MasterKey cannot be empty.");
        }
    }

    #endregion
}
```

---

## IAudioSettingsService Interface

```csharp
public interface IAudioSettingsService
{
    float MasterVolume { get; }
    float MusicVolume  { get; }
    float SFXVolume    { get; }
    float VoiceVolume  { get; }
    bool  IsMuted      { get; }

    void SetMasterVolume(float normalizedValue);
    void SetMusicVolume(float normalizedValue);
    void SetSFXVolume(float normalizedValue);
    void SetVoiceVolume(float normalizedValue);
    void SetMuted(bool muted);

    void LoadSettings();
    void SaveSettings();
    void ResetToDefaults();
}
```

---

## AudioSettingsService Implementation

```csharp
public sealed class AudioSettingsService : IAudioSettingsService, IInitializable, IDisposable
{
    #region Fields

    private readonly AudioConfiguration  _config;
    private readonly IAudioMixerService  _mixerService;
    private readonly IEventBus           _eventBus;
    private CancellationTokenSource      _cts;

    private float _masterVolume;
    private float _musicVolume;
    private float _sfxVolume;
    private float _voiceVolume;
    private bool  _isMuted;

    #endregion

    #region Constructor

    public AudioSettingsService(
        AudioConfiguration config,
        IAudioMixerService mixerService,
        IEventBus eventBus)
    {
        _config       = config;
        _mixerService = mixerService;
        _eventBus     = eventBus;
    }

    #endregion

    #region Properties

    public float MasterVolume => _masterVolume;
    public float MusicVolume  => _musicVolume;
    public float SFXVolume    => _sfxVolume;
    public float VoiceVolume  => _voiceVolume;
    public bool  IsMuted      => _isMuted;

    #endregion

    #region Lifecycle

    public void Initialize()
    {
        _cts = new CancellationTokenSource();
        LoadSettings();
    }

    public void Dispose()
    {
        SaveSettings();
        _cts?.Cancel();
        _cts?.Dispose();
    }

    #endregion

    #region Public Methods

    public void SetMasterVolume(float normalizedValue)
    {
        _masterVolume = Mathf.Clamp01(normalizedValue);
        ApplyVolumes();
        PublishChanged();
    }

    public void SetMusicVolume(float normalizedValue)
    {
        _musicVolume = Mathf.Clamp01(normalizedValue);
        ApplyVolumes();
        PublishChanged();
    }

    public void SetSFXVolume(float normalizedValue)
    {
        _sfxVolume = Mathf.Clamp01(normalizedValue);
        ApplyVolumes();
        PublishChanged();
    }

    public void SetVoiceVolume(float normalizedValue)
    {
        _voiceVolume = Mathf.Clamp01(normalizedValue);
        ApplyVolumes();
        PublishChanged();
    }

    public void SetMuted(bool muted)
    {
        _isMuted = muted;
        ApplyVolumes();
        PublishChanged();
    }

    public void LoadSettings()
    {
        _masterVolume = PlayerPrefs.GetFloat(_config.MasterKey, _config.MasterVolumeDefault);
        _musicVolume  = PlayerPrefs.GetFloat(_config.MusicKey,  _config.MusicVolumeDefault);
        _sfxVolume    = PlayerPrefs.GetFloat(_config.SFXKey,    _config.SFXVolumeDefault);
        _voiceVolume  = PlayerPrefs.GetFloat(_config.VoiceKey,  _config.VoiceVolumeDefault);
        _isMuted      = PlayerPrefs.GetInt(_config.MuteKey, 0) == 1;

        ApplyVolumes();
    }

    public void SaveSettings()
    {
        PlayerPrefs.SetFloat(_config.MasterKey, _masterVolume);
        PlayerPrefs.SetFloat(_config.MusicKey,  _musicVolume);
        PlayerPrefs.SetFloat(_config.SFXKey,    _sfxVolume);
        PlayerPrefs.SetFloat(_config.VoiceKey,  _voiceVolume);
        PlayerPrefs.SetInt(_config.MuteKey,     _isMuted ? 1 : 0);
        PlayerPrefs.Save();
    }

    public void ResetToDefaults()
    {
        _masterVolume = _config.MasterVolumeDefault;
        _musicVolume  = _config.MusicVolumeDefault;
        _sfxVolume    = _config.SFXVolumeDefault;
        _voiceVolume  = _config.VoiceVolumeDefault;
        _isMuted      = false;

        ApplyVolumes();
        SaveSettings();
        PublishChanged();
    }

    #endregion

    #region Private Methods

    private void ApplyVolumes()
    {
        float muteMultiplier = _isMuted ? 0f : 1f;

        _mixerService.SetGroupVolume(MixerParameters.Master, _masterVolume * muteMultiplier);
        _mixerService.SetGroupVolume(MixerParameters.Music,  _musicVolume);
        _mixerService.SetGroupVolume(MixerParameters.SFX,    _sfxVolume);
        _mixerService.SetGroupVolume(MixerParameters.Voice,  _voiceVolume);
    }

    private void PublishChanged()
    {
        _eventBus.Publish(new AudioSettingsChangedEvent
        {
            MasterVolume = _masterVolume,
            MusicVolume  = _musicVolume,
            SFXVolume    = _sfxVolume,
            VoiceVolume  = _voiceVolume,
            IsMuted      = _isMuted
        });
    }

    #endregion
}
```

---

## Event Definition

```csharp
// AudioEvents.cs
public struct AudioSettingsChangedEvent : IEvent
{
    public float MasterVolume;
    public float MusicVolume;
    public float SFXVolume;
    public float VoiceVolume;
    public bool  IsMuted;
}
```

---

## AudioSettingsView (UI Binding)

```csharp
public sealed class AudioSettingsView : MonoBehaviour, IInitializable, IDisposable
{
    #region Fields

    [SerializeField] private Slider  _masterSlider;
    [SerializeField] private Slider  _musicSlider;
    [SerializeField] private Slider  _sfxSlider;
    [SerializeField] private Slider  _voiceSlider;
    [SerializeField] private Toggle  _muteToggle;
    [SerializeField] private Button  _resetButton;

    private IAudioSettingsService _settingsService;
    private bool _isApplyingSettings; // Prevents feedback loop

    #endregion

    #region Injection

    [Inject]
    public void Construct(IAudioSettingsService settingsService)
    {
        _settingsService = settingsService;
    }

    #endregion

    #region Lifecycle

    public void Initialize()
    {
        RefreshUI();
        RegisterListeners();
    }

    public void Dispose()
    {
        UnregisterListeners();
    }

    #endregion

    #region Private Methods

    private void RegisterListeners()
    {
        _masterSlider.onValueChanged.AddListener(OnMasterChanged);
        _musicSlider.onValueChanged.AddListener(OnMusicChanged);
        _sfxSlider.onValueChanged.AddListener(OnSFXChanged);
        _voiceSlider.onValueChanged.AddListener(OnVoiceChanged);
        _muteToggle.onValueChanged.AddListener(OnMuteChanged);
        _resetButton.onClick.AddListener(OnResetClicked);
    }

    private void UnregisterListeners()
    {
        _masterSlider.onValueChanged.RemoveListener(OnMasterChanged);
        _musicSlider.onValueChanged.RemoveListener(OnMusicChanged);
        _sfxSlider.onValueChanged.RemoveListener(OnSFXChanged);
        _voiceSlider.onValueChanged.RemoveListener(OnVoiceChanged);
        _muteToggle.onValueChanged.RemoveListener(OnMuteChanged);
        _resetButton.onClick.RemoveListener(OnResetClicked);
    }

    private void RefreshUI()
    {
        // Guard prevents slider callbacks firing during programmatic set
        _isApplyingSettings = true;

        _masterSlider.value = _settingsService.MasterVolume;
        _musicSlider.value  = _settingsService.MusicVolume;
        _sfxSlider.value    = _settingsService.SFXVolume;
        _voiceSlider.value  = _settingsService.VoiceVolume;
        _muteToggle.isOn    = _settingsService.IsMuted;

        _isApplyingSettings = false;
    }

    private void OnMasterChanged(float value)
    {
        if (_isApplyingSettings) return;
        _settingsService.SetMasterVolume(value);
    }

    private void OnMusicChanged(float value)
    {
        if (_isApplyingSettings) return;
        _settingsService.SetMusicVolume(value);
    }

    private void OnSFXChanged(float value)
    {
        if (_isApplyingSettings) return;
        _settingsService.SetSFXVolume(value);
    }

    private void OnVoiceChanged(float value)
    {
        if (_isApplyingSettings) return;
        _settingsService.SetVoiceVolume(value);
    }

    private void OnMuteChanged(bool muted)
    {
        if (_isApplyingSettings) return;
        _settingsService.SetMuted(muted);
    }

    private void OnResetClicked()
    {
        _settingsService.ResetToDefaults();
        RefreshUI();
    }

    #endregion
}
```

**Why `_isApplyingSettings` flag:** Setting `slider.value` programmatically fires `onValueChanged`. Without the guard, calling `SetMasterVolume` from code triggers the slider callback, which calls `SetMasterVolume` again — creating an infinite loop.

---

## AudioInstaller Registration

```csharp
public sealed class AudioInstaller : ModuleInstaller
{
    [SerializeField] private AudioConfiguration _config;
    [SerializeField] private AudioMixer         _mixer;

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
            throw new InvalidOperationException($"{nameof(AudioInstaller)}: _config is not assigned.");
        if (_mixer == null)
            throw new InvalidOperationException($"{nameof(AudioInstaller)}: _mixer is not assigned.");

        builder.RegisterInstance(_config);
        builder.RegisterInstance(_mixer);

        builder.Register<AudioMixerService>(Lifetime.Singleton)
               .As<IAudioMixerService>();

        builder.Register<AudioSettingsService>(Lifetime.Singleton)
               .As<IAudioSettingsService>();
    }
}
```

---

## Persistence: PlayerPrefs vs Save System

| Approach | When to Use |
|----------|------------|
| `PlayerPrefs` | Simple games, no cloud save, settings only |
| Custom Save System (JSON/binary) | Save system already exists in project; settings bundled with other preferences |
| `ISaveLoadService` (project pattern) | When `_Framework/SaveLoadSystems/` is implemented; wire into `LoadSettings`/`SaveSettings` |

To migrate to the project's save system, replace `PlayerPrefs.GetFloat`/`SetFloat` calls inside `LoadSettings` and `SaveSettings` with `ISaveLoadService.Load<AudioSaveData>()` / `Save(data)`. The rest of the service is identical.

---

## Save-on-Change vs Save-on-Exit

Default pattern above: **save on `Dispose()`** (when scope ends / scene unloads).

For mobile (app can be force-killed):

```csharp
private void ApplyVolumes()
{
    // ... apply to mixer ...
    SaveSettings(); // Save immediately on every change
    PublishChanged();
}
```

Adds disk I/O on every slider drag — acceptable for settings, not for gameplay state.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing raw slider value to `SetFloat` | Always convert to dB via `Mathf.Log10` |
| No `_isApplyingSettings` guard | Programmatic slider set fires callback loop |
| Saving on `OnDisable` of View | Save in Service `Dispose`, not in View |
| `PlayerPrefs.Save()` every frame | Call only in `SaveSettings()`, not `ApplyVolumes()` |
| Mute by setting Master to 0 | Apply mute multiplier to Master only; preserve slider value |
| No `Clamp01` on incoming volume | Out-of-range values cause unexpected dB results |
| Settings ScriptableObject stores runtime state | SO defaults only; runtime values live in service fields |
