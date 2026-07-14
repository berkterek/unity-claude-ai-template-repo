# Debug Session — Structured Bug Investigation

You are starting a structured debugging session. Follow the Debugger agent protocol.

## Plugin Preflight

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:systematic-debugging` | Step 1 — root cause analysis | Proceed with manual investigation |

Print availability status before proceeding:
```
Plugins: superpowers:systematic-debugging [✓/✗]
```

---

## Step 0 — Knowledge Graph Preload

Before reading any source files, decide whether the knowledge graph can accelerate this investigation. This follows the graph-first spirit of `/implement`, `/create-plan`, `/fix`, and `/search`, but is deliberately **stricter on staleness**: a stale graph can point at a call path that no longer exists, which would send the debugging session down the wrong trail — so a stale or empty graph falls back to a fresh file scan rather than risk a wrong diagnosis.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, skip to Initialization (file-scan behavior, unchanged).

If it is a candidate, verify the graph is **usable** (fresh AND non-empty):

```bash
python3 -c "
import json, os, time
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
n = len(cb.get('classes', []))
lb = '.claude/graph/.last-build'
age_h = (time.time() - os.path.getmtime(lb)) / 3600 if os.path.exists(lb) else 1e9
print('classes=%d age_h=%.1f' % (n, age_h))
"
```

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, fall back to file scan. Do NOT warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to file scan:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated debugging. Falling back to file scan.
  ```
- Otherwise (fresh AND non-empty) → build `GRAPH_CONTEXT` from the graph inventory:

```bash
python3 -c "
import json
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
classes = cb.get('classes', [])
interfaces = cb.get('interfaces', [])
events = cb.get('events', [])
installers = cb.get('vcontainer', {}).get('installers', [])
print('CLASSES (%d):' % len(classes))
for c in classes:
    print('  %s | mono=%s | deps=%s | pub=%s | sub=%s' % (
        c['name'], c.get('is_mono_behaviour', False),
        c.get('dependencies', []), c.get('events_published', []), c.get('events_subscribed', [])))
print('INTERFACES (%d):' % len(interfaces))
for i in interfaces: print('  %s' % i['name'])
print('EVENTS (%d):' % len(events))
for e in events: print('  %s' % e['name'])
print('INSTALLERS (%d):' % len(installers))
for inst in installers:
    regs = [r.get('type','') for r in inst.get('registrations', [])]
    print('  %s | registrations=%s' % (inst['name'], regs))
"
```

Keep this output as `GRAPH_CONTEXT` and embed it into Step 2 below. When `GRAPH_CONTEXT` is empty, the investigation behaves exactly as before — no regression.

---

## Initialization

Ask the developer:

1. **Symptom** — Exact error message or unexpected behavior?
2. **Reproduction** — When does it happen? Always or intermittent?
3. **Recent changes** — What changed before this appeared?
4. **Stack trace** — Paste it if available.

Do not proceed until you have at least the symptom and reproduction condition.

## Process

### Step 1 — Understand the symptom

**If `superpowers:systematic-debugging` is available:** Invoke it now with the symptom, reproduction condition, recent changes, and stack trace. Use its structured output (root cause hypothesis, confidence, injection plan) before proceeding to Step 2.

Read the stack trace or behavior description. Identify:
- Which file and line is the immediate failure point?
- Which system/module is involved? (VContainer, ECS, UniTask, Input, etc.)

### Step 2 — Reproduce mentally

## Knowledge Graph (class/interface/event/installer inventory — query this BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0 — if empty, write "No usable graph — scan source files directly."]

If a knowledge graph inventory is provided above (non-empty), use it FIRST to trace the fault path fast — do not re-scan folders for what it already answers:
- "who calls the failing method" → the graph's callers data
- "what breaks if this class changes" / blast radius → the graph's impact/dependencies data
- "who publishes/subscribes to the event involved" → the graph's pub/sub data
- "what does the installer register" → the graph's registrations data
Only read source files for the exact suspect lines (the specific logic body) the graph cannot provide.

If the graph inventory is empty (or absent), trace the code path that leads to the symptom the usual way. Read the relevant files:
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
- **Simple/obvious bug** (null ref, missing using, typo) → spawn **unity-fixer** subagent for a quick targeted fix
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
