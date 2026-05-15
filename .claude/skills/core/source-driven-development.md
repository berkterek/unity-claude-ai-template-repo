---
name: source-driven-development
description: Fetch official Unity documentation before writing API calls and cite the source URL. Required for fast-changing APIs such as URP, DOTS, Addressables, and Input System.
model-tier: normal
---

# Source-Driven Development (Unity)

## Overview

Every Unity API decision must be grounded in official documentation. Training data can be stale — Unity 6 significantly changed URP Renderer Features, DOTS APIs, Input System, and Addressables. This skill adds reliability to the code you write because every decision is traceable to a verifiable source.

## When to Use

- Before writing any Unity API call
- For APIs that change across versions: URP, DOTS, Addressables, Input System, Cinemachine, Physics
- When writing Unity-specific patterns in `/implement`, `/fix`, `/add-feature`, `/scene-setup` pipelines
- Whenever "is this still correct?" comes to mind about existing code

**When NOT to Use:**
- Pure C# logic (loops, data structures, math) — version-independent
- File moves, renames, typo fixes
- When the user says "do it fast, skip verification"

## Process

```
DETECT → FETCH → APPLY → CITE
```

### Step 1: Detect Stack and Version

Read the project's Unity version and relevant package versions:

```
ProjectSettings/ProjectVersion.txt  → Unity version
Packages/manifest.json              → All package versions
Packages/packages-lock.json         → Locked versions
```

State what you find explicitly:

```
STACK DETECTED:
- Unity 6000.0.x (from ProjectVersion.txt)
- com.unity.render-pipelines.universal: 17.0.x
- com.unity.inputsystem: 1.x
→ Fetching URP 17 documentation.
```

If the version is ambiguous, ask the user — do not guess.

### Step 2: Fetch Official Documentation

Fetch the relevant page — not the main documentation landing page, but the specific feature page.

**Source hierarchy (in priority order):**

| Priority | Source | Example |
|----------|--------|---------|
| 1 | Unity official documentation | docs.unity3d.com/6000.0/Documentation/Manual/ |
| 2 | Unity Packages documentation | docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/ |
| 3 | Unity Blog / Changelog | blog.unity.com, unity.com/releases |
| 4 | Unity Forum — official Unity replies | forum.unity.com |

**Non-authoritative sources — do not use as primary sources:**
- Stack Overflow
- Blog posts, YouTube tutorials
- Your own training data (without verification)

**Fetch specifically:**

```
WRONG: Fetch the Unity documentation main page
RIGHT: Fetch docs.unity3d.com/6000.0/Documentation/Manual/urp/renderer-feature-how-to-add.html

WRONG: Search "URP Renderer Feature best practices"
RIGHT: Fetch docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/manual/renderer-features/intro-to-renderer-features.html
```

After fetching: note deprecation warnings, migration notes, and API signature changes.

If official sources conflict (migration guide vs API reference), report this to the user and verify which applies to the current version.

### Step 3: Apply According to Documentation

- Use the API signature from the docs, not from memory
- If the docs show a new approach, use the new approach
- If the docs mark a pattern as deprecated, don't use it
- If the docs don't cover something, say so explicitly

**If there is a conflict with existing code:**

```
CONFLICT DETECTED:
Existing code uses the OnRenderObject() callback,
but URP 17 documentation states this callback does not
work in URP and RenderPipelineManager.beginCameraRendering
should be used instead.
(Source: docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/...)

Options:
A) New approach — aligned with current documentation
B) Existing code — consistent with project but outside docs
→ Which do you prefer?
```

Do not decide silently — present the conflict to the user.

### Step 4: Cite Sources

Cite the source for every Unity-specific pattern. The user should be able to verify every decision.

**In code comments:**

```csharp
// URP 17 Renderer Feature registration
// Source: https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/api/UnityEngine.Rendering.Universal.ScriptableRendererFeature.html
public override void Create() { }
```

**In conversation:**

```
Using the performed callback in InputSystem 1.x, not started —
because the performed trigger waits for the full press + release cycle to complete.
Source: https://docs.unity3d.com/Packages/com.unity.inputsystem@1.x/manual/Actions.html#started-performed-and-canceled-callbacks
```

**Citation rules:**
- Full URL, not shortened
- Deep link with anchor where possible (`#usage`, `#api-reference`)
- Quote the relevant passage for non-obvious decisions
- If you can't find it in the docs, say so explicitly:

```
UNVERIFIED: No official documentation found for this pattern.
This is based on training data and may be outdated.
Verify before using in production.
```

## Unity-Specific Verification Checklist

- [ ] Unity version and package versions read from `ProjectVersion.txt` / `manifest.json`
- [ ] Official documentation fetched for the relevant Unity API
- [ ] Deprecated APIs checked against migration guide
- [ ] API signature matches documentation (not memory)
- [ ] Source URL added for every Unity-specific pattern
- [ ] User notified about any existing code that conflicts with documentation
- [ ] Unverifiable patterns explicitly marked
