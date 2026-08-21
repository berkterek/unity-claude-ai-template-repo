---
name: plan-module
description: Generates one module's spec+design+tasks trio just-in-time against the current codebase. Takes the module number assigned by /roadmap.
---

# /plan-module — Module Planner (Just-in-Time)

Creates a single module's `docs/modules/<n>-<name>/` folder: `spec.md`, `design.md`, `tasks.md`.

## Usage

```
/plan-module 01
/plan-module 01-core-loop
```

## Kurallar

- Plan only the named module — never touch the others
- `tasks.md` must be in the format `/orchestrate` consumes directly: checkboxes + `[parallel_group:N]` + file paths + code skeletons + acceptance criteria
- Scan the existing codebase: which files already exist and which are missing? Mark existing ones "Modify", not "Add"
- If `docs/modules/<n>-<name>/` already exists: stop with "this module is already planned" — never overwrite it

## Process

### Step 0 — Knowledge Graph Preload

Before any codebase scan or subagent spawn, decide whether the knowledge graph can speed up planning this module.

Check `.claude/project-features.json`:
- `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → leave `GRAPH_CONTEXT` empty and go to Step 1 (the existing file-scan behavior, unchanged).

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

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → leave `GRAPH_CONTEXT` empty and fall back to a file scan silently. Do not warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to a file scan:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated planning. Falling back to file scan.
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

Store this output as `GRAPH_CONTEXT` and embed it in the Step 3 `Plan` subagent prompt. If `GRAPH_CONTEXT` is empty, the planning stage behaves exactly as before — no regression.

### Step 1 — Okuma

1. Parse the module number/name from $ARGUMENTS
2. Read `docs/ROADMAP.md` — find this module's name, dependencies and priority
3. Read `docs/GDD.md` — find the section covering this module
4. Read `docs/TDD.md` — find the architecture decisions belonging to this module
5. Scan the existing codebase: list the .cs files that already relate to this module

If the module already exists under `docs/modules/<n>-<name>/`:
```
Module <n> is already planned: docs/modules/<n>-<name>/
Use /update-plan to change the existing plan.
```
diyerek dur.

### Step 2 — ARCHITECTURE_GATE

Show the user the following and ask for approval:

```
## ARCHITECTURE_GATE — Module <n>-<name>

**GDD summary:** [what this module does]
**Proposed structure:**
- Abstracts: [interface listesi]
- Concretes: [class listesi]
- Module installer: [Domain]Module.cs
- Events: [event listesi]

**Type `go` to approve, or describe what to change:**
```

Do not proceed to the next step until the gate is approved (the user types `go`).

### Step 3 — Planning Subagent

Spawn the `Plan` subagent (`subagent_type: "Plan"`, `model: opus`) — the same agent as `/create-plan` Step 2. **Do not use `lean-planner`:** by definition that agent produces no acceptance criteria, no `parallel_group` annotations and no code skeletons, and its output is a single 3-5 row table; this command needs three separate documents (spec/design/tasks), the Given/When/Then ACs the Step 4 reviewer looks for, and the `Callers:`/`Wiring:` lines Step 5's `validate-plan-facts.sh` requires. Give the subagent:
- The module's GDD summary
- TDD'deki ilgili mimari kararlar
- The results of the existing codebase scan
- The Knowledge Graph block below (from Step 0)
- The template format: the spec/design/tasks templates under `docs/modules/_templates/`

Add this block to the prompt:

```
## Knowledge Graph (inventory of existing classes/interfaces/events/installers — query this BEFORE scanning files)
[INSERT HERE: the GRAPH_CONTEXT output from the Step 0 preload step — if empty, write "No usable graph — scan source files directly."]
```

Instruction: if the graph inventory above is not empty, use it first — read existing interfaces/classes/installers/dependencies from the graph, and open a source file only for a specific line or detail. If the graph is empty (or says "No usable graph"), fall back to the codebase scan results as before.

Take the three document drafts as the subagent's output.

### Step 4 — REVIEWER

Spawn the `reviewer` subagent (`model: sonnet`). Ask it to check:
- Is every task in `tasks.md` `/orchestrate`-compatible? (checkbox + file path + acceptance)
- Are the `parallel_group` annotations correct?
- Are `spec.md`'s acceptance criteria testable? (Given/When/Then format)
- Do `design.md`'s interface signatures comply with the current architecture rules?

The reviewer must end with exactly one verdict line: `APPROVED` or `CHANGES NEEDED`.

On `CHANGES NEEDED`, show **QUALITY_GATE** — definition and exact format in `.claude/docs/director-gates.md` → QUALITY_GATE. Do not restate the options here; that file owns them. If the user picks `fix`, hand the feedback back to the Step 3 `Plan` subagent and re-review — at most **3 reviewer passes** total. Never reach Step 5 on an unresolved `CHANGES NEEDED`, and never fix the plan yourself instead of showing the gate: that decision is the user's.

### Step 5 — SAVE

Save the three files under `docs/modules/<n>-<name>/`:
- `spec.md`
- `design.md`
- `tasks.md`

**Then run, BLOCKING — the plan must exist on disk before either script can see it:**

```bash
.claude/scripts/validate-plan-paths.sh docs/modules/<n>-<name>/
.claude/scripts/validate-plan-facts.sh docs/modules/<n>-<name>/
```

- `validate-plan-paths.sh` exit 2 → the plan declares a folder that contradicts `rules/architecture.md`. Do not print the success block and do not update `docs/ROADMAP.md`. Show the conflict with three options (change the plan / write the exception into `.claude/path-allowlist.txt` **and** `rules/architecture.md` / stop). The user decides — never invent a folder of your own. `NO PATHS FOUND` is **not** a pass; confirm by hand.
- `validate-plan-facts.sh` exit 2 → at least one task creating a new `.cs` is missing `Callers:`/`Wiring:`, or a declared caller/module resolves neither on disk nor in this plan. Do not print the success block. Show the violation, then fix the plan or stop — the user decides. `NO TASKS FOUND` is **not** a pass — in the script's own words, "this is NOT a pass"; confirm by hand. `NO TASKS EXAMINED` is not a pass either — it means every task line found was `/Tests/`-exempt.
- Paste each script's `checked:` receipt line into the output. A silent hook is never evidence, and "compliant, verified" may not appear as an AC in the spec without one.

Only after both scripts pass (or the user explicitly accepts a declared exception), update the matching row in `docs/ROADMAP.md`: Status → `⏳ Pending`, and add a link in the Plan column.

Show the user:
```
✅ Module <n>-<name> planned

docs/modules/<n>-<name>/spec.md
docs/modules/<n>-<name>/design.md
docs/modules/<n>-<name>/tasks.md

Next step: `/orchestrate docs/modules/<n>-<name>/tasks.md`
```

$ARGUMENTS
