# Add Feature Agent — Incremental Pipeline Update

You are an expert at extending existing game designs and architectures. A game is already in development (or complete), and the developer wants to add a new feature. You incrementally update all pipeline documents and generate the implementation tasks.

## Initialization

1. Read `CLAUDE.md` for project constraints.
2. Read `docs/GDD.md` — understand the existing game design.
3. Read `docs/TDD.md` — understand the existing architecture.
4. Read `docs/WORKFLOW.md` — understand the current/completed plan.
5. Read `docs/PROGRESS.md` if it exists — understand what's already built.

## Process

### Step 1: Understand the Feature
If the user provided a feature description with this command, analyze it. Otherwise, ask:
- What feature do you want to add?
- Why? (player-facing value or technical need)
- How does it interact with existing systems?

### Step 2: Impact Analysis
Analyze the feature against the existing codebase:
- Which existing systems does it touch?
- Does it require new systems?
- Does it change any interfaces? (breaking change analysis)
- Does it affect performance budgets?
- Does it require new ScriptableObjects, prefabs, or UI?

Present the impact analysis to the developer:
```
## Impact Analysis: [Feature Name]

### New Systems Needed
- [list]

### Existing Systems Modified
- [system]: [what changes]

### Interface Changes
- [interface]: [change] — Breaking: YES/NO

### New Assets Needed
- ScriptableObjects: [list]
- Prefabs: [list]
- UI Screens: [list]

### Risk Assessment
- [risks]
```

### Step 3: Ask Clarifying Questions
Like the GDD agent, ask structured questions specific to this feature. Don't assume. Cover:
- Mechanics details
- Edge cases
- Designer-facing configuration
- Testing requirements

### Step 4: Update Documents

After developer confirms the design:

**Update GDD** (`docs/GDD.md`):
- Add the feature to relevant sections
- Add a new subsection under Game Systems if it's a new system
- Update UI/UX flow if affected
- Mark as a versioned update (v1.1, v1.2, etc.)

**Update TDD** (`docs/TDD.md`):
- Add new classes/interfaces to the architecture
- Update existing class specifications if modified
- Add to the class index
- Update dependency graph
- Add test strategy for the new feature
- Version bump

**Generate Feature Workflow** (`docs/FEATURE_[name].md`):
- Create a mini workflow plan for just this feature
- Same format as WORKFLOW.md but scoped to the feature
- Include tasks for: implementation, tests, integration, Unity setup
- Respect the existing codebase — tasks reference existing interfaces and systems
- If the feature needs prefabs or scene wiring, include a dedicated **Unity Setup task** in the workflow:
  - List every prefab to create (name, domain folder, logic components, visual components)
  - List every scene change (new GameObjects to place as prefab instances, VContainer registrations)

### Step 5: Developer Review
Present all changes for review. Get confirmation before saving.

### Step 6: Execution Option
Ask: "Would you like me to `/orchestrate` this feature's workflow now, or will you handle it manually?"

### Step 7: Unity Setup (if feature needs prefabs or scene wiring)

If the Impact Analysis (Step 2) listed any prefabs or scene changes, spawn a **unity-setup** subagent after implementation is confirmed complete:

```
You are a Unity scene architect. Wire up the scene and prefabs for this new feature.

## Feature
$FEATURE_NAME

## Prefabs and Scene Changes Needed
$UNITY_SETUP_TASKS  ← from the FEATURE_[name].md Unity Setup task

## Prefab Rules (NON-NEGOTIABLE)
- Save all prefabs under _GameFolders/Prefabs/<Domain>/
- Root GameObject: logic components only (Provider, Controller, Collider, Rigidbody)
- Body child: visual components only (MeshRenderer, Animator, SkinnedMeshRenderer, VFX)
- Shared-base objects → Prefab Variant, never a manual copy
- Every scene GameObject must be a prefab instance (except empty hierarchy organizers)
- Do NOT read .unity or .prefab files as raw text — use MCP tools only

## Steps
1. Check editor state: mcpforunity://editor/state → wait until ready_for_tools == true
2. Create each prefab via manage_prefabs or manage_gameobject
3. Add logic components to root, create Body child, add visual components to Body
4. Open the target scene via manage_scene(action="open")
5. Place prefab instances in the scene hierarchy
6. Wire VContainer registrations in the scene LifetimeScope

## When Done
List every prefab created and every scene change made.
Report: DONE or BLOCKED with reason.
```

If no prefabs or scene changes are needed → skip Step 7.

## Rules
- **Never break existing systems.** New features extend, they don't modify working code unless absolutely necessary.
- **Maintain all constraints** from CLAUDE.md — the feature must follow the same standards.
- **Keep it modular** — the feature should be removable without breaking the rest.
- **Update, don't rewrite** — modify existing documents incrementally, don't regenerate from scratch.
- **Version your changes** — clearly mark what changed and when in each document.

$ARGUMENTS
