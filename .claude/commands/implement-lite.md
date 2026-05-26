---
name: implement-lite
description: /implement-lite — Lightweight single-class implementation pipeline. Use when the user wants to add a field, method, property, or simple behavior to an existing class, or create a new single-class file with no new interfaces, no DI wiring changes, and no EventBus events. Faster than /implement: no test writer, no reviewer, no verifier. Auto-triggered by /implement when complexity score < 0.3. Also invoke directly when user says things like "add SerializeField", "implement IDisposable", "add a method to", "create a simple class", or any small targeted code addition to one or two files.
---

# /implement-lite — Lightweight Single-File Implementation

**Pipeline:** Read Files → unity-coder-lite → Compile Check → Committer

Fast pipeline for simple, single-class additions or changes. No test writer, no reviewer, no verifier, no silent failure audit.
`/implement` auto-routes here when complexity score < 0.3 — can also be called directly.

## Usage

```
/implement-lite "add _jumpForce [SerializeField] to PlayerController"
/implement-lite "implement IDisposable on AudioService, cancel CancellationTokenSource in Dispose"
/implement-lite "add OnHealthChanged C# event to HealthService"
```

If no argument given, ask: "What needs to be implemented?"

## When to use

| Situation | Command |
|-----------|---------|
| Single class, no new interface, no DI wiring, no events | `/implement-lite` |
| 2–4 classes, new interface, or touches EventBus | `/implement` |
| New module folder, cross-system, ECS, Addressables | `/implement` (full pipeline) |
| Needs TDD, reviewer loop, or verifier | `/implement` |

---

## Scope Check — Escalate if Any of These Are True

Before starting, verify the task does NOT involve:
- Creating a new module folder (new domain under `Games/Concretes/` or `Games/Abstracts/`)
- Adding or modifying a new `IEventBus` event
- Modifying `AppScope`, `AppInstaller`, `GameScope`, or any `ModuleInstaller`
- Touching more than 2 files

If any of the above are true:
```
This task exceeds /implement-lite scope.
→ Continue with /implement instead? (go / try implement-lite anyway)
```

---

## Step 0 — SCOPE_GATE

Show the user:

```
SCOPE_GATE — /implement-lite
=============================
File(s): <file path(s)>
Task:    <what will be added or changed>

Proceed? (go / stop)
```

Wait for `go`. Then write the gate file:

```bash
mkdir -p .claude/state && echo '{"gate":"SCOPE_GATE","pipeline":"implement-lite"}' > .claude/state/gate-cleared
```

---

## Step 1 — Read Target Files

Read only the file(s) directly involved in the task. No other reads, no codebase scanning.

If the target file does not exist yet (new class):
- Identify the correct folder from the task description (`Games/Concretes/<Domain>/`)
- Read any sibling files in that folder only if needed to understand the namespace or asmdef

---

## Step 2 — unity-coder-lite

Spawn **unity-coder-lite** agent with this prompt:

```
TASK: Single-class targeted implementation.

FILE(S): <file path(s)>
TASK: <user's description>

Implement only what is described. Do not refactor surrounding code.
Do not read files beyond what was provided. Do not add interfaces, installers, or events unless explicitly asked.

PROJECT RULES (non-negotiable):
- VContainer injection — no singletons, no FindObjectOfType
- UniTask — no coroutines, no async Task
- New Input System — no Input.GetKey / Input.GetAxis
- Unity null check: == null, not is null or ?.
- [SerializeField] for component references — not GetComponent in Awake
- sealed classes by default
- #region tags required in _GameFolders/Scripts/ files
- _camelCase private fields, PascalCase types and methods
```

---

## Step 3 — Compile Check

If MCP is connected → `read_console` to verify no compile errors.
If MCP is not connected → ask user: "Any errors in Unity?"

If errors remain → return to unity-coder-lite (max 2 iterations).
Still failing after 2 iterations:
```
implement-lite could not resolve compile errors.
→ Continue with /implement for a full validator loop? (go / stop)
```

---

## Step 4 — Committer

Run **committer** agent. Commit message format:

```
feat(<scope>): <what was added — one line>
```

After commit, delete the gate file:

```bash
rm -f .claude/state/gate-cleared
```

---

## Output Format

```
IMPLEMENTED: <file(s)>
TASK: <what was asked>
CHANGE: <what was added or modified>
COMPILE: clean
```
