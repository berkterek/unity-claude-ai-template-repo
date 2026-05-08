# /graphics-setup — URP Platform Graphics Setup

Configures URP Pipeline Assets for Low/Medium/High quality tiers for the target platform, wires them into Quality Settings, and fills the URPQualityConfiguration ScriptableObject.

## Usage

```
/graphics-setup mobile   → Mobile preset (default tier: Medium)
/graphics-setup pc       → PC preset (default tier: High)
```

If no argument is given, ask: "Which platform? (mobile / pc)"

## Pipeline

```
[1] PLAN → show tier table, list assets to create → await approval
[2] APPLY → spawn graphics-setup-agent
[3] REPORT + commit option
```

---

## Step 0 — Parse Argument

```
$PLATFORM = $ARGUMENTS (mobile | pc)
```

If argument is missing, ask the user before continuing.

---

## Step 1 — Show Plan

Print the full tier table for the chosen platform and list every asset that will be created. Then ask:

```
Proceed with these settings? (yes / no)
```

Do NOT spawn any agent until the user confirms.

### Mobile Tier Table

| Setting | Low | Medium ★ | High |
|---------|-----|----------|------|
| HDR | Off | On | On |
| MSAA | Off | Off | 2x |
| Render Scale | 0.75 | 0.85 | 1.0 |
| Shadow Distance | 0 | 30 | 70 |
| Shadow Cascades | 0 | 1 | 2 |
| Soft Shadows | Off | Off | On |
| Post Processing | Off | Bloom only | Full |
| Additional Lights | 0 | 2 | 4 |
| SRP Batcher | On | On | On |
| Dynamic Batching | Off | Off | Off |

★ = default tier applied at first run

### PC Tier Table

| Setting | Low | Medium | High ★ |
|---------|-----|--------|--------|
| HDR | On | On | On |
| MSAA | Off | 2x | 4x |
| Render Scale | 0.85 | 1.0 | 1.0 |
| Shadow Distance | 30 | 70 | 150 |
| Shadow Cascades | 1 | 2 | 4 |
| Soft Shadows | Off | On | On |
| Post Processing | Minimal | On | Full |
| Additional Lights | 2 | 4 | 8 |
| SRP Batcher | On | On | On |
| Dynamic Batching | Off | Off | Off |

★ = default tier applied at first run

### Assets to Be Created

```
Assets/Settings/URP/URP_<Platform>_Low.asset
Assets/Settings/URP/URP_<Platform>_Medium.asset
Assets/Settings/URP/URP_<Platform>_High.asset
Assets/Settings/URP/URPQualityConfiguration_<Platform>.asset
```

---

## Step 2 — Spawn graphics-setup-agent

After user confirms, spawn **graphics-setup-agent** with this prompt:

```
You are the graphics-setup-agent. Configure URP quality tiers for the following platform.

## Platform
$PLATFORM

## Instructions
Follow your agent definition exactly:
1. Create the Assets/Settings/URP/ folder if it does not exist
2. Create Low/Medium/High UniversalRenderPipelineAsset files with correct settings
3. Create the Universal Renderer Data asset for each tier
4. Configure each Pipeline Asset with the values from the platform tier table
5. Create URPQualityConfiguration ScriptableObject and assign all three pipeline assets
6. Wire tiers into Project Settings → Quality (via QualitySettings API or direct asset edit)
7. Set the default tier as active
8. Report every asset created with its path

## Rules
- Read .claude/skills/systems/urp-quality-settings/SKILL.md before making any decisions
- Read .claude/skills/systems/urp-lighting-shadows/SKILL.md for shadow settings
- Read .claude/skills/systems/urp-post-processing/SKILL.md for post-processing decisions
- Use mcp__unityMCP__manage_asset to create and configure assets
- Use mcp__unityMCP__refresh_unity after all assets are created
- Use mcp__unityMCP__read_console to verify no errors
- Do NOT push anything to git

## When Done
List every asset created with a one-line summary. Report: DONE or BLOCKED.
```

---

## Step 3 — Report

After agent completes, print:

```
## ✓ Graphics Setup — $PLATFORM

Assets created:
  Assets/Settings/URP/URP_$PLATFORM_Low.asset
  Assets/Settings/URP/URP_$PLATFORM_Medium.asset
  Assets/Settings/URP/URP_$PLATFORM_High.asset
  Assets/Settings/URP/URPQualityConfiguration_$PLATFORM.asset

Default tier: [Medium (mobile) | High (pc)]
Active pipeline: URP_$PLATFORM_[tier].asset

Next steps:
  • Assign URPQualityConfiguration_$PLATFORM to your GraphicsInstaller in AppScope
  • Adjust shadow bias if acne/peter-panning appears (see urp-lighting-shadows skill)
  • Tune post-processing volumes per tier (see urp-post-processing skill)

Commit these changes? (yes / no)
```

If `yes`, spawn **committer** agent:

```
Commit URP graphics setup assets for $PLATFORM.

Files: all new .asset files under Assets/Settings/URP/
Commit message: "feat(graphics): add URP quality tier assets for $PLATFORM"
Do NOT push.
```

$ARGUMENTS
