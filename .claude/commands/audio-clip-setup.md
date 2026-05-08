# /audio-clip-setup — AudioClip Import Settings Optimizer

Scans AudioClip assets, categorizes them (Music / SFX / UI / Voice), and applies performance-optimized import settings via a temporary Unity Editor script.

## Usage

```
/audio-clip-setup                    → scans entire Assets/ folder
/audio-clip-setup Assets/Audio/SFX/ → scans a specific folder
/audio-clip-setup Assets/Audio/Music/theme.ogg → single clip
```

If no argument is given, default to `Assets/`.

## What It Does

1. Finds all `.wav`, `.mp3`, `.ogg`, `.aif`, `.flac` assets under the target path
2. Categorizes each clip: **folder name → filename prefix → duration → default SFX**
3. Writes a temporary `Assets/Editor/AudioClipBatchImporter.cs` with `AudioImporter` calls
4. Triggers Unity recompile via MCP — script auto-runs via `[InitializeOnLoadMethod]`
5. Reads console output to capture results
6. Deletes the temp script and refreshes
7. Prints detailed per-clip change list, then summary, then offers to commit

## Pipeline

```
[1] SCAN → [2] CATEGORIZE → [3] GENERATE SCRIPT → [4] APPLY (MCP) → [5] VERIFY → [6] CLEANUP → [7] REPORT
```

---

## Step 0 — Parse Argument

```
$TARGET_PATH = $ARGUMENTS if given, else "Assets/"
```

Print before proceeding:
```
Audio Clip Setup
Target : <TARGET_PATH>
```

---

## Step 1 — Spawn audio-clip-agent

Spawn the **audio-clip-agent** subagent with this prompt:

```
You are the audio-clip-agent. Apply optimized AudioClip import settings for this project.

## Target Path
$TARGET_PATH

## Instructions
Follow your agent definition exactly:
1. Scan all AudioClip files under the target path
2. Categorize each clip using: folder name → filename prefix → duration → default SFX
3. Generate Assets/Editor/AudioClipBatchImporter.cs with one ApplySettings() call per clip
4. Apply via MCP (refresh_unity → wait for compile → read_console)
5. Verify no errors in console
6. Delete the temp script and do a final refresh
7. Report: detailed per-clip list (changed + skipped), then summary, then ask about commit

## Rules
- Read .claude/skills/systems/audio-clip-settings/SKILL.md before deciding any settings
- Do NOT skip the cleanup step — always delete the temp script
- If MCP is unavailable, print the generated script and tell the user to run it manually
- If a compile error occurs in the generated script, show the error and do NOT delete the script

## When Done
Report: DONE with summary, or BLOCKED with reason.
```

---

## Completion

Print:
```
## ✓ Audio Clip Setup Complete
Target  : <TARGET_PATH>
Changed : <N> clips
Skipped : <N> clips (already optimal)
```

$ARGUMENTS
