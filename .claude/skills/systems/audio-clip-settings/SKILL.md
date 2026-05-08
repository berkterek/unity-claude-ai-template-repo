---
name: audio-clip-settings
description: Use when configuring AudioClip import settings for performance — choosing compression format (PCM/ADPCM/Vorbis), load type (Decompress On Load/Compressed In Memory/Streaming), platform overrides, or diagnosing audio-related memory spikes and frame hitches.
globs: ["**/*.wav", "**/*.mp3", "**/*.ogg", "**/*AudioClip*.cs", "**/*AudioImport*.cs"]
---

# AudioClip Import Settings — Performance Guide

## Decision Tree

```
Is the clip > 5 seconds?
├── YES → Is it music or ambient loop?
│         ├── YES → Streaming + Vorbis 40–60%
│         └── NO  → Compressed In Memory + Vorbis 70%
└── NO  → Is it played frequently (> 5x per second possible)?
          ├── YES → Decompress On Load + ADPCM (< 1 sec) or PCM (UI clicks)
          └── NO  → Decompress On Load + ADPCM
```

---

## Compression Formats

| Format | CPU Decode Cost | Memory | Quality | Best For |
|--------|----------------|--------|---------|----------|
| **PCM** | None | Very large (~10 MB/min) | Perfect | Short UI clicks, critical SFX ≤ 0.1 sec |
| **ADPCM** | Very low | ~3.5× smaller than PCM | Good | Short SFX ≤ 1 sec (gunshots, footsteps, impacts) |
| **Vorbis** | Medium | ~10× smaller than PCM | Good–Excellent | Music, ambient loops, voice |
| **MP3** | Medium | Same as Vorbis | Good | iOS only — Vorbis preferred everywhere else |

### Vorbis Quality Slider

| Quality | File Size | Use |
|---------|-----------|-----|
| 40–60% | ~64–96 kbps | Background music (difference inaudible) |
| 70% | ~112 kbps | VO dialogue, important SFX |
| 100% | ~320 kbps | Only if 70% is audibly degraded |

Never use 100% by default. Always A/B test at 70% before increasing.

---

## Load Types

### Decompress On Load
- Decompresses entire clip to PCM at load time
- **Memory:** full uncompressed size (largest)
- **CPU at runtime:** zero — raw PCM fed to audio hardware
- **Use:** short, frequently triggered SFX (gunshots, UI taps, footsteps)

### Compressed In Memory
- Stays compressed in RAM, decompresses on `Play()`
- **Memory:** compressed size (smaller)
- **CPU at runtime:** decode cost per play
- **Use:** medium-length clips played occasionally (explosions, special ability sounds)

### Streaming
- Reads from disk frame by frame during playback
- **Memory:** tiny buffer (~1 frame of audio)
- **CPU:** I/O per frame + decode
- **Use:** music, ambient loops, long VO (> 5 sec)
- **Caveat:** 15–30 ms startup latency. Do not stream short reaction sounds.

---

## Force To Mono

Enable when:
- Clip is a stereo recording but spatial (3D) audio is enabled — stereo information is meaningless in 3D space and wastes memory
- Clip plays on a pooled AudioSource with `spatialBlend = 1f`

Disable when:
- Music (stereo field is intentional)
- UI sounds (always 2D, stereo is fine)
- Voice with stereo room recording

Enabling Force To Mono halves memory for that clip at no quality cost in 3D contexts.

---

## Sample Rate Override

Default: 44100 Hz. Reducing sample rate saves memory and decode time.

| Rate | Use |
|------|-----|
| 44100 Hz | Music, critical voice |
| 22050 Hz | SFX, impacts, footsteps |
| 11025 Hz | Very short UI ticks, low-fidelity ambient detail |

Set per-platform. Never reduce music below 44100 Hz — high-frequency content (cymbals, consonants) becomes muddy.

---

## Platform Overrides

Configure per-platform in the AudioClip Inspector's platform tabs. Never use the same settings on mobile and PC.

### Recommended Overrides

```
Default (PC/Console):
  Format:    Vorbis 60% or ADPCM
  Load Type: Decompress On Load (SFX) / Streaming (music)
  Sample Rate: 44100 Hz

Android / iOS:
  Format:    Vorbis 50% (iOS: MP3 for long clips)
  Load Type: Compressed In Memory (SFX) / Streaming (music)
  Sample Rate: 22050 Hz (SFX), 44100 Hz (music)
```

Mobile rationale: smaller RAM, slower storage I/O, lower CPU budget. Always add Android and iOS overrides for any project targeting mobile.

---

## Preload Audio Data

Controls whether clip data loads when the containing Scene/AssetBundle loads.

| Setting | Behavior | Use |
|---------|----------|-----|
| Enabled (default) | Loaded at scene start | Frequently used SFX, UI sounds |
| Disabled | Loaded on first `Play()` | Rare sounds, cutscene-only VO |

**Warning:** Disabling Preload Audio Data on frequently used SFX causes a 1–2 frame hitch on first play as Unity loads the clip synchronously.

For large sound banks: disable Preload + load via Addressables explicitly:

```csharp
// Load before it is needed (e.g., in a preload phase)
AsyncOperationHandle<AudioClip> handle =
    Addressables.LoadAssetAsync<AudioClip>(AssetAddresses.BossRoar);

AudioClip clip = await handle.ToUniTask(cancellationToken: ct);

// Release when done
Addressables.Release(handle);
```

---

## Background Loading (LoadAudioData / UnloadAudioData)

For clips that are not Addressables-managed but need on-demand loading:

```csharp
public sealed class AudioPreloader : IDisposable
{
    private readonly List<AudioClip> _preloaded = new();

    public async UniTask PreloadAsync(AudioClip clip, CancellationToken ct)
    {
        if (clip.loadState == AudioDataLoadState.Unloaded)
        {
            clip.LoadAudioData();
        }

        // Wait until loaded (non-blocking)
        await UniTask.WaitUntil(
            () => clip.loadState == AudioDataLoadState.Loaded,
            cancellationToken: ct);

        _preloaded.Add(clip);
    }

    public void Dispose()
    {
        foreach (AudioClip clip in _preloaded)
        {
            clip.UnloadAudioData();
        }
        _preloaded.Clear();
    }
}
```

Never call `LoadAudioData()` synchronously on mobile in a hot path. Call during loading screens or background preload phases.

---

## Load State Guard

Always check `loadState` before playing clips loaded on demand:

```csharp
public void PlaySafe(AudioSource source, AudioClip clip, float volume = 1f)
{
    if (clip == null)
    {
        return;
    }

    if (clip.loadState != AudioDataLoadState.Loaded)
    {
        Debug.LogWarning($"AudioClip '{clip.name}' not loaded — skipping playback.");
        return;
    }

    source.PlayOneShot(clip, volume);
}
```

---

## Memory Budget Reference

Approximate uncompressed (PCM) size for reference:

```
Mono, 44100 Hz, 16-bit:  44100 × 2 bytes = ~86 KB/sec
Stereo, 44100 Hz, 16-bit: ~172 KB/sec
```

A 3-minute stereo music track uncompressed ≈ **30 MB**.  
With Vorbis 60% ≈ **3 MB**.

Mobile memory budget per platform (rough guideline):
- iOS: 150–300 MB total app RAM — audio should be < 20 MB
- Android: 256–512 MB — audio should be < 30 MB
- PC/Console: > 4 GB — less critical, but stream music regardless

---

## Audio Profiler Checklist

Open **Window → Audio → Audio Profiler** and check:

| Metric | Warning Threshold | Fix |
|--------|------------------|-----|
| DSP CPU | > 5% | Reduce voice count, switch to ADPCM |
| Voices | > 24 on mobile | Enable distance culling, lower pool size |
| Audio Memory | > 20 MB on mobile | Enable Force To Mono, lower sample rate, Streaming for music |
| Streaming I/O | Spikes | Pre-buffer or switch to Compressed In Memory |

---

## Quick Reference

| Clip Type | Format | Load Type | Mono | Sample Rate |
|-----------|--------|-----------|------|-------------|
| UI click (< 0.1 sec) | PCM | Decompress On Load | Yes | 44100 |
| Footstep / impact (< 1 sec) | ADPCM | Decompress On Load | Yes | 22050 |
| Weapon SFX (< 2 sec) | ADPCM | Decompress On Load | Yes | 22050 |
| Explosion / ability (2–5 sec) | Vorbis 70% | Compressed In Memory | Yes | 22050 |
| Ambient loop (> 5 sec) | Vorbis 60% | Streaming | No | 44100 |
| Background music | Vorbis 50% | Streaming | No | 44100 |
| VO dialogue | Vorbis 70% | Streaming | Yes | 44100 |

---

## Common Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| PCM on all clips | 10× memory waste | ADPCM for SFX, Vorbis for music |
| Streaming short SFX | 15–30 ms play delay | Decompress On Load for clips < 5 sec |
| No platform overrides | Mobile OOM crashes | Add Android + iOS overrides |
| Stereo SFX with spatialBlend=1 | Double memory, no benefit | Force To Mono |
| Vorbis 100% everywhere | Unnecessary file size | 60% music, 70% voice |
| Preload disabled on frequent SFX | Frame hitch on first play | Enable Preload for pool-loaded SFX |
| No loadState check before Play | Silent failure or crash | Guard with `AudioDataLoadState.Loaded` |
