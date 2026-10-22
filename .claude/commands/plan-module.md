---
name: plan-module
description: Generates one module's spec+design+tasks trio just-in-time against the current codebase. Takes the module number assigned by /roadmap.
---

# /plan-module — Module Planner (Just-in-Time)

> **Rules to Read first** (path-scoped — not in context until a matching file is touched):
> `.claude/rules/roadmap-milestones.md`

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

### Preflight — Plan Templates (BLOCKING)

Before anything else, check that the three format templates exist:

```bash
for f in spec design tasks; do
  [ -f "docs/modules/_templates/$f.md" ] || echo "MISSING: docs/modules/_templates/$f.md"
done
```

Any `MISSING` line → stop and print:

```
⛔ /plan-module needs docs/modules/_templates/{spec,design,tasks}.md — missing: [list]
Copy them from the template repository, then re-run:
  cp -R <template-repo>/docs/modules/_templates docs/modules/
```

Do not copy the files yourself, and never take the format from another module's plan instead.

> **Why this blocks instead of falling back:** nothing installs `_templates/` into a downstream project — `/setup-project` does not copy it. Without the check, a missing template produced no error: the Plan agent silently used an earlier module's `tasks.md` as its format, and that module's extra bookkeeping (a status table, per-task `Result:` fields) spread into every new plan. Measured on a downstream project, Oct 2026.

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

### Step 1 — Read

1. Parse the module number/name from $ARGUMENTS
2. Read `docs/ROADMAP.md` — find this module's name, dependencies, **milestone** and priority
3. Read `docs/GDD.md` — find the section covering this module
4. Read `docs/TDD.md` — find the architecture decisions belonging to this module, **and
   read its Milestone Acceptance section** (the one carrying the per-milestone stub policy).
   If the module's milestone allows a stub for this system, that stub definition is the
   **scope ceiling for this plan** — not the module's full system section. Read it before
   the full section, not after: an agent holding a rich full spec first will rationalize
   its way back to it.
5. Scan the existing codebase: list the .cs files that already relate to this module

**Milestone scope check (`.claude/rules/roadmap-milestones.md`) — warn, do not block.**
If `docs/ROADMAP.md` carries a `Milestone` column:
- The module belongs to a milestone **other than the open one** → say so plainly and name
  the open milestone's still-Pending modules, then ask the developer to confirm before
  planning (rule Card 2: polish never outranks loop-closing work). Their `go` is the
  authority; this command does not enforce.
- The module belongs to the **open** milestone → the plan's scope ceiling is the
  intersection of two written things, and **both are read before the module's full system
  section**:
  1. the module's inline stub scope in the ROADMAP milestone entry — `15 (minimal — two
     panels, two buttons)`; the parenthetical, not the number
  2. the stub definition for this system in TDD's Milestone Acceptance section

  Plan to that ceiling and nothing beyond it. In the plan header, list what the full spec
  contains that this plan deliberately omits, and name the milestone that owns each omitted
  item. If neither document names a stub for this system, the module is planned in full —
  say so explicitly rather than leaving it ambiguous.

  **Why this is written as a ceiling and not an aspiration:** the source project flagged
  this exact layer as unmeasured — the rule demonstrably reordered the roadmap, but whether
  it survives into a plan's *scope* was never tested. The failure mode is specific: given a
  bare module number and a one-sentence milestone entry against a rich TDD system section,
  the full spec wins. Both inputs above exist to make the small scope the written one.

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

Spawn the `Plan` subagent (`subagent_type: "Plan"`, `model: opus`) — the same agent as `/create-plan` Step 2. **Do not use `lean-planner`:** by definition that agent produces no acceptance criteria, no `parallel_group` annotations and no code skeletons, and its output is a single 3-5 row table; this command needs three separate documents (spec/design/tasks), the Given/When/Then ACs the Step 4 reviewer looks for, and the `Callers:`/`Wiring:` lines Step 5's `validate-plan-facts.sh` requires.

Give the subagent a **context packet** built from what Step 1 already read. Paste the text itself, quoted under its original heading — never a file pointer:
- **ROADMAP:** this module's row (name, dependencies, milestone, priority), the open milestone's entry with its inline stub scope, and the suggested build order
- **TDD:** the Milestone Acceptance stub definition for this system (if any), then every section holding this module's architecture decisions
- **GDD:** the section(s) covering this module
- **Scope:** the scope ceiling decided in Step 1 and the list of deliberately omitted items with the milestone that owns each
- **Structure:** the ARCHITECTURE_GATE proposal as approved in Step 2, including any change the user asked for
- **Codebase:** the existing-file scan from Step 1, one line per file
- **Graph:** the Knowledge Graph block below (from Step 0)
- **Format:** the spec/design/tasks templates under `docs/modules/_templates/`

Add this instruction to the prompt, verbatim:

```
The context packet above is the authoritative extract of ROADMAP, GDD and TDD for this
module. Do not re-read those three documents in full — no `cat`, no full Read. Open one
only for a specific section the packet lacks, and list each such section under an
"Extra reads" heading at the end of your output. Source files, rules and templates you
may read as needed.

For a task whose output needs no test — a type the Test Type Decision Tree in
.claude/rules/testing.md sends to NoTest, or a non-code task (docs, assets, scene setup) —
write `Test type: NoTest` on the task. /orchestrate skips the tester step for it; do not
invent another way to skip it.

Before you return, check the drafts against the defects plan reviewers reject most often:
- The project compiles after EVERY task, not only at the end. A task that removes or
  renames a field, method or signature also updates every reader of it in the same task —
  never "T010 renames, T013 fixes the callers".
- A RED test task compiles against signatures that exist at that point. If the signature
  is new or changed, either add a stub/signature task before the tests, or write
  "RED = compile failure" on the test task explicitly.
- Every `git status` / "no other change" check names its paths
  (`git status --short HoleSphere docs/decisions`) — the tree is never assumed clean.
- Every `file:line` you cite was opened and verified in this run. Name each value's real
  source; never attribute a value to a document you did not see it in.
- Tasks in the same `parallel_group` share no output file and no work directory.
- A placeholder value in a task body is labelled `placeholder — set at <task id>`.
```

**Why a packet and not pointers:** measured on a downstream project (Oct 2026, 11 Plan runs): the prompt was ~2k tokens with no document text, and the Plan agent re-read ROADMAP/GDD/TDD itself through ~227 `cat` commands (~1.1M characters) — the same reads Step 1 had just done. Each run took 17-50 minutes. The "Extra reads" list makes any remaining re-read visible instead of silent.

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

Add this severity contract to the reviewer prompt, verbatim:

```
Classify every finding as exactly one of:
- BLOCKING — the plan as written would fail: /orchestrate cannot run a task, the project
  does not compile after some task, a task points at a wrong file/line/value that would
  produce wrong code, or an acceptance criterion cannot be tested — including a check
  that cannot pass on the real working tree (an unscoped `git status` on a dirty tree).
- MINOR — anything else worth changing: wording, missing tolerances that do not block a
  test, labelling, a citation off by a few lines that still lands on the right content.
Do not list items you checked and found correct — a confirmation is not a finding.

Output: a "BLOCKING" list and a "MINOR" list, each item with file:line. Then exactly one
verdict line: `CHANGES NEEDED` if the BLOCKING list is non-empty, otherwise `APPROVED`
(MINOR items do not block).
```

On `CHANGES NEEDED`, show **QUALITY_GATE** — definition and exact format in `.claude/docs/director-gates.md` → QUALITY_GATE. Do not restate the options here; that file owns them. If the user picks `fix`, hand **both** lists back to the Step 3 `Plan` subagent — MINOR items are fixed in the same pass, they never earn a pass of their own.

**A re-review is a delta review, not a fresh one.** Pass 2 and 3 get the previous BLOCKING list and the revised drafts, and answer only: is each previous BLOCKING item resolved, and did the fix introduce a new BLOCKING defect? A fresh full review on every pass finds new MINOR items every time and never converges. At most **3 reviewer passes** total. Never reach Step 5 on an unresolved `CHANGES NEEDED`, and never fix the plan yourself instead of showing the gate: that decision is the user's.

On `APPROVED` with a non-empty MINOR list, show the MINOR list to the user in one block before Step 5 — they may ask for a fix pass; it is not required.

> **Why severity and delta review:** measured on a downstream project (Oct 2026): 27 plan reviews across 16 modules, and **no module plan was approved on its first review**; 7 modules needed 2-3 passes. Module 41's first review listed 21 items, of which about 5 would actually have failed the run (a field renamed in one task while its readers changed three tasks later; RED tests written against signatures that did not exist yet; a `git status` check run on an already dirty tree; two wrong `file:line` citations). The rest were MINOR suggestions and confirmations — and with one verdict for all of them, each pass reopened the plan for everything and the next full review found new MINOR items. The checklist in the Step 3 prompt targets those five recurring BLOCKING kinds at the source.

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
