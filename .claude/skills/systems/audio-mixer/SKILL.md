---
name: audio-mixer
description: Use when setting up Unity AudioMixer groups, exposed parameters, snapshots, send/receive effects, ducking via sidechain, or transitioning between acoustic environments (cave, underwater, combat).
globs: ["**/*.mixer", "**/*AudioMixer*.cs", "**/*MixerService*.cs", "**/*Snapshot*.cs"]
---

# AudioMixer System

## Mixer Hierarchy

```
Master  (exposed: "MasterVolume")
├── Music   (exposed: "MusicVolume")
├── SFX     (exposed: "SFXVolume")
│   ├── Weapons   (exposed: "WeaponVolume")
│   ├── Footsteps
│   ├── Environment
│   └── UI
├── Voice   (exposed: "VoiceVolume")
├── ReverbBus   ← Receive effect, no exposed params
└── DelayBus    ← Receive effect, no exposed params
```

**Rules:**
- Every leaf group is routed to exactly one parent
- Expose only parameters you need to control at runtime
- Bus groups (Reverb/Delay) never have audio sources routed directly to them — they receive via Send effects

---

## Volume: Normalized → dB Conversion

AudioMixer parameters expect **decibels**. Never pass raw 0–1 slider values directly.

```csharp
// -80 dB = silence, 0 dB = full, +20 dB = boost
private const float MIN_DB = -80f;

public static float ToDecibels(float normalizedValue)
{
    return normalizedValue > 0.0001f
        ? Mathf.Log10(normalizedValue) * 20f
        : MIN_DB;
}

public static float ToNormalized(float dB)
{
    return dB <= MIN_DB ? 0f : Mathf.Pow(10f, dB / 20f);
}
```

```csharp
// IAudioMixerService implementation
public void SetGroupVolume(string exposedParam, float normalizedValue)
{
    float dB = ToDecibels(normalizedValue);
    bool success = _mixer.SetFloat(exposedParam, dB);

    if (!success)
    {
        Debug.LogWarning($"AudioMixer: exposed param '{exposedParam}' not found.");
    }
}

public float GetGroupVolume(string exposedParam)
{
    _mixer.GetFloat(exposedParam, out float dB);
    return ToNormalized(dB);
}
```

**Common mistake:** passing `0f` as normalizedValue maps to `MIN_DB` (-80 dB), not to `Mathf.Log10(0)` which is `-Infinity`. Always guard with the `0.0001f` threshold.

---

## Snapshots

Snapshots store a **complete state** of all mixer parameters. Transitioning between them smoothly adjusts every parameter simultaneously.

### Setup (Unity Editor)

1. Open AudioMixer window
2. Right-click in Snapshots panel → Create Snapshot
3. Select snapshot → adjust group volumes, effect parameters
4. Repeat for each acoustic environment

### Recommended Snapshots

| Snapshot | Purpose | Key Changes |
|----------|---------|-------------|
| `Default` | Normal gameplay | Baseline values |
| `Underwater` | Submerged | SFX lowpass cutoff 800 Hz, Music -6 dB |
| `Cave` | Indoor reverb heavy | ReverbBus send +6 dB, DelayBus -3 dB |
| `Combat` | Intense action | Music sidechain ducking aggressive |
| `Paused` | Game paused | SFX -80 dB, Music -12 dB |
| `Cutscene` | Cinematic | Voice +3 dB, SFX -18 dB, Music -6 dB |

### Runtime Transitions

```csharp
[SerializeField] private AudioMixerSnapshot _defaultSnapshot;
[SerializeField] private AudioMixerSnapshot _underwaterSnapshot;
[SerializeField] private AudioMixerSnapshot _caveSnapshot;
[SerializeField] private AudioMixer _mixer;

public void TransitionTo(AudioEnvironment environment, float transitionTime = 1.5f)
{
    AudioMixerSnapshot target = environment switch
    {
        AudioEnvironment.Default    => _defaultSnapshot,
        AudioEnvironment.Underwater => _underwaterSnapshot,
        AudioEnvironment.Cave       => _caveSnapshot,
        _ => _defaultSnapshot
    };

    target.TransitionTo(transitionTime);
}

// Weighted blend of multiple environments (e.g., half cave, half outdoor)
public void BlendEnvironments(
    AudioMixerSnapshot[] snapshots,
    float[] weights,
    float transitionTime)
{
    _mixer.TransitionToSnapshots(snapshots, weights, transitionTime);
}
```

### Snapshot for Pause Menu

```csharp
// Pause: mute gameplay audio, keep music subtle
public void OnGamePaused()
{
    _pausedSnapshot.TransitionTo(0.05f); // Fast: 50 ms
}

public void OnGameResumed()
{
    _defaultSnapshot.TransitionTo(0.2f); // Slightly slower: 200 ms
}
```

**Do NOT** use `Time.timeScale = 0` to mute audio. Use a Paused snapshot instead. `Time.timeScale = 0` also stops `AudioSource.PlayScheduled` and can corrupt beat-sync timing.

---

## Send / Receive Effects (Reverb Bus)

### Setup in Unity Editor

1. **ReverbBus group:** Add a **Receive** effect. No other effects needed on the group itself.
2. **SFX group:** Add a **Send** effect → set target to `ReverbBus`.
3. **Weapons group:** Add its own **Send** → `ReverbBus` with a different send level (weapons echo more in indoor scenes).
4. Set `ReverbBus` volume in each Snapshot to control how wet each environment sounds.

### Why Bus Routing

| Without Buses | With Buses |
|--------------|------------|
| Reverb effect on every group | One Reverb on ReverbBus |
| Each group has independent reverb | All groups share same reverb room |
| Changing reverb = edit N groups | Change one snapshot parameter |
| Higher CPU (N DSP nodes) | Lower CPU (1 DSP node) |

---

## Ducking (Sidechain Compression)

Automatically lower Music when Voice/Dialogue plays. No manual volume fades needed.

### Setup in Unity Editor

1. Select **Music** group
2. Add effect: **Duck Volume**
3. Configure:
   - **Threshold:** -25 dB (triggers when Voice exceeds this)
   - **Ratio:** 4:1
   - **Attack:** 50 ms (how quickly it ducks)
   - **Release:** 600 ms (how quickly it recovers)
   - **Make-Up Gain:** 0 dB
4. In the Duck Volume effect, set **Send:** to the `Voice` mixer group

### Result

When a VO line plays above -25 dB on Voice:
- Music ducks within 50 ms
- When VO ends, Music returns to normal in 600 ms
- Fully automatic — no scripting required

### Combat Duck (Enemy Fire, Player Weapons)

Apply Duck Volume to **Music** group, sidechain from **Weapons** group. Lower ratio (2:1) and faster release (200 ms) for a subtle pumping effect during combat.

---

## Exposed Parameters — Naming Convention

Always use consistent naming. These strings are used in code and must match exactly.

```
"MasterVolume"    → Master group
"MusicVolume"     → Music group
"SFXVolume"       → SFX group
"WeaponVolume"    → Weapons group
"VoiceVolume"     → Voice group
"SFXCutoff"       → Lowpass effect on SFX (for underwater)
"ReverbWet"       → Reverb effect wet level on ReverbBus
```

Store as constants — never hardcode strings at call sites:

```csharp
public static class MixerParameters
{
    public const string Master  = "MasterVolume";
    public const string Music   = "MusicVolume";
    public const string SFX     = "SFXVolume";
    public const string Voice   = "VoiceVolume";
    public const string Weapons = "WeaponVolume";
    public const string SFXCutoff = "SFXCutoff";
}
```

---

## VContainer Wiring

```csharp
// AudioInstaller.cs
public override void Install(IContainerBuilder builder)
{
    builder.RegisterInstance(_audioMixer);     // AudioMixer asset
    builder.RegisterInstance(_config);          // AudioConfiguration SO

    builder.Register<AudioMixerService>(Lifetime.Singleton)
           .As<IAudioMixerService>();
}
```

```csharp
// IAudioMixerService.cs
public interface IAudioMixerService
{
    void SetGroupVolume(string exposedParam, float normalizedValue);
    float GetGroupVolume(string exposedParam);
    void TransitionToSnapshot(AudioEnvironment environment, float duration);
    void BlendEnvironments(AudioMixerSnapshot[] snapshots, float[] weights, float duration);
}
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing raw 0–1 to `SetFloat` | Convert with `Mathf.Log10(v) * 20f` |
| `exposedParam` string typo | Use `MixerParameters` constants class |
| `SetFloat` returns false silently | Log a warning and check Expose in Mixer window |
| Reverb on every group separately | Use Send → ReverbBus routing |
| `Time.timeScale = 0` for pause mute | Use Paused snapshot instead |
| Snapshot transition time 0f | Sounds jarring; minimum 50 ms for cuts |
| Ducking ratio too high (>6:1) | Audio pumps noticeably; use 3:1 to 4:1 |
