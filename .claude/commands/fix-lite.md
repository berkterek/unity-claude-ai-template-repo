# /fix-lite — Lightweight Single-File Fix

**Pipeline:** Stack Trace Pin → Read File → unity-fixer-lite → Compile Check → Committer

Fast pipeline for simple, single-file fixes. No analyzer, no scout, no test writer, no reviewer.
`/fix` auto-routes here when complexity score < 0.2 — can also be called directly.

## Usage

```
/fix-lite "NullReferenceException: AudioService.cs line 42"
/fix-lite "missing SerializeField on _playButton in MainMenuView"
```

If no argument given, ask: "Share the error message and stack trace."

## When to use

| Situation | Command |
|-----------|---------|
| NullRef, missing ref, typo, obvious one-liner | `/fix-lite` |
| 2+ files, logic bug | `/fix` |
| Intermittent, root cause unclear | `/fix-deep` |
| Legacy/large codebase, stuck in loop | `/fix-codex` |

---

## Step 1 — Pin the Target

Extract **file + line** from the stack trace or user description.

- Stack trace present → take the first Unity code line (skip UnityEngine internals)
- No stack trace → ask: "Which file, which line, or which component?"

If more than one file is identified:
```
2+ files detected — this fix exceeds /fix-lite scope.
→ Continue with /fix instead? (go / try fix-lite anyway)
```

---

## Step 2 — Read Only That File

Read the target file only. No other file reads, no codebase scanning.

---

## Step 3 — unity-fixer-lite

Spawn **unity-fixer-lite** agent with this prompt:

```
TASK: Single-file targeted fix.

FILE: <file path>
LINE: <line number or region>
ISSUE: <user's description>

Fix only the identified issue. Do not refactor surrounding code.
Do not read other files. Fix at root cause, not at symptom.

PROJECT RULES (non-negotiable):
- VContainer injection — no singletons, no FindObjectOfType
- UniTask — no coroutines, no async Task
- New Input System — no Input.GetKey / Input.GetAxis
- Unity null check: == null, not is null or ?.
- [SerializeField] for component references — not GetComponent in Awake
```

---

## Step 4 — Compile Check

If MCP is connected → `read_console` to verify no compile errors remain.
If MCP is not connected → ask user: "Any errors left in Unity?"

If errors remain → return to unity-fixer-lite (max 2 iterations).
Still unresolved after 2 iterations:
```
fix-lite could not resolve this issue.
→ Continue with /fix? (go / stop)
```

---

## Step 5 — Committer

Run **committer** agent. Commit message format:

```
fix(<scope>): <what was fixed — one line>
```

---

## Output Format

```
FIXED: <file:line>
ISSUE: <what was wrong>
FIX: <what changed>
COMPILE: clean
```
