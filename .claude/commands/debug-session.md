# Debug Session — Structured Bug Investigation

You are starting a structured debugging session. Follow the Debugger agent protocol.

## Initialization

Ask the developer:

1. **Symptom** — Exact error message or unexpected behavior?
2. **Reproduction** — When does it happen? Always or intermittent?
3. **Recent changes** — What changed before this appeared?
4. **Stack trace** — Paste it if available.

Do not proceed until you have at least the symptom and reproduction condition.

## Process

### Step 1 — Understand the symptom
Read the stack trace or behavior description. Identify:
- Which file and line is the immediate failure point?
- Which system/module is involved? (VContainer, ECS, UniTask, Input, etc.)

### Step 2 — Reproduce mentally
Trace the code path that leads to the symptom. Read the relevant files:
- Service registration in installer
- Constructor/inject chain
- Where the failing method is called from

### Step 3 — State root cause
Before touching any code, write:
```
ROOT CAUSE: [one sentence]
EVIDENCE: [specific lines or patterns that confirm it]
```

### For Automated Fix

Once root cause is identified:
- **Simple/obvious bug** (null ref, missing using, typo) → spawn **unity-fixer-lite** subagent for a quick targeted fix
- **Complex bug** (lifecycle issue, async race, ECS structural) → spawn **unity-fixer** subagent (reads surrounding context before patching)

Both agents report: DONE or BLOCKED with reason.

### Step 4 — Fix
Apply the minimal change. Verify:
- No new singletons introduced
- No coroutines introduced
- No direct Unity API in service classes
- VContainer registrations are correct

### Step 5 — Verify plan
Describe to the developer exactly how to confirm the fix works.

## Common Patterns to Check First

| Symptom | Likely Cause |
|---------|-------------|
| `VContainerException: Unable to find type` | Missing `.As<IInterface>()` or wrong scope |
| `NullReferenceException` on Unity object | Object destroyed, or Inject called after Awake |
| `OperationCanceledException` in UniTask | CancellationToken fired — usually not a bug |
| ECS system not executing | Wrong `[UpdateInGroup]`, archetype mismatch |
| Input not working | `OnEnable()` missing `.Enable()` call |
| `InvalidOperationException` in ECS job | Structural change without ECB |
