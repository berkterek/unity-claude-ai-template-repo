---
name: mcp-preflight
description: "3-state MCP availability check for all pipeline commands. Run before spawning any MCP agent. Determines: (1) MCP connected → full pipeline, (2) MCP disconnected → stop and warn, (3) MCP not installed → code-only fallback."
model-tier: light
---

# MCP Preflight Check

Run this check at the start of any command that spawns MCP agents (unity-setup, unity-scene-builder, unity-verifier, graphics-setup-agent, audio-clip-agent, etc.).

---

## How to Run the Check

Call `mcp__unityMCP__unity_get_project_info` with no arguments.

---

## 3 States

### State 1 — MCP Connected ✅
**Signal:** `unity_get_project_info` returns a valid project info response.

**Action:** Proceed with full pipeline. All MCP agents can be spawned normally.

---

### State 2 — MCP Installed but Disconnected ⚠️
**Signal:** `unity_get_project_info` call fails, times out, or returns an error such as "Unity Editor not responding" / "connection refused".

**Action:** STOP. Print this message and do not proceed with MCP operations:

```
⛔ MCP connection unavailable — [COMMAND_NAME] cannot start.

Unity Editor must be open and the MCP plugin must be active.

Checklist:
  1. Is Unity Editor open?
  2. Is the MCP plugin active? (Edit → Project Settings → MCP or Window → MCP)
  3. Restart the Editor and try again.

Alternative:
  Generate C# files only, skipping scene / prefab / wiring steps?
  Manual steps will be listed for you to complete in the Editor.
  Reply yes to continue in code-only mode, or no to cancel.
```

Wait for user response before continuing.

---

### State 3 — MCP Not Installed ❌
**Signal:** The tool call fails with "tool not found" / "unknown tool", or the `mcp__unityMCP__` prefix is not recognized in this session.

**Action:** Silently switch to code-only mode. Do NOT stop the pipeline. Print this once:

```
ℹ️  MCP tools are not available in this session.
   Continuing in code-generation mode.
   Manual Editor steps will be listed for scene / prefab work.
```

Then continue the pipeline, replacing every MCP step with:
- C# script generation (installers, providers, components)
- A numbered checklist of manual Unity Editor steps

---

## How to Distinguish State 2 from State 3

| Symptom | State |
|---------|-------|
| Tool returns error about Unity Editor / connection | State 2 |
| Tool returns timeout or no response | State 2 |
| Tool name not recognized / "tool not found" | State 3 |
| `mcp__unityMCP__*` prefix absent from tool list | State 3 |

---

## Code-Only Fallback Template (State 2 user says yes / State 3)

When continuing without MCP, every command must output:

```
### Manual Steps (complete in Unity Editor)
- [ ] [Specific step 1 — exact menu path or drag-drop instruction]
- [ ] [Specific step 2]
- [ ] ...

### Generated C# Files
- [file path] — [purpose]
```

Be specific. "Open the scene" is not enough — write "File → Open Scene → _Scenes/[SceneName].unity".

---

## Usage in Commands

At the start of each relevant command step, add:

```
### Step N — MCP Preflight
Read and apply `.claude/skills/core/mcp-preflight.md`.
- State 1 → continue with full pipeline
- State 2 → stop, offer code-only alternative, wait for user
- State 3 → switch to code-only mode silently, continue
```
