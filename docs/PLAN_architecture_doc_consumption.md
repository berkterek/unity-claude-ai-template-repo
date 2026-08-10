# PLAN — ARCHITECTURE.md Consumption: Make Agents and Commands Read the Docs

> **Complexity:** 0.45 — Medium
> **Version:** v1 — 2026-08-05
> **Status:** **BLOCKED** — waiting for the first 3 real domains under `_GameFolders/Scripts/Games/Concretes/`
> **Phase:** 2 of 2. Phase 1 (enforcement) is `docs/PLAN_domain_folder_convention.md`.
> **Scope:** Wire the *reading* side of the `Concretes/<Domain>/ARCHITECTURE.md` convention — agent Step 0 instructions, a three-tier research order in the graph-aware commands, and orphan/missing-doc reconciliation in `/build-knowledge-graph`. No new hooks. No rule-file changes. No Unity C# code.

---

## Unblock Condition

Do not implement this plan until **all** of the following hold:

1. `docs/PLAN_domain_folder_convention.md` is fully implemented, including its Task 10 (the human has registered both hooks in `.claude/settings.json`).
2. At least **3** domain folders exist under `_GameFolders/Scripts/Games/Concretes/`, each with a real, hook-passing `ARCHITECTURE.md`.
3. Those docs were written while doing actual work, not authored to satisfy this plan.

Check with:

```bash
find _GameFolders/Scripts/Games/Concretes -maxdepth 2 -name ARCHITECTURE.md | wc -l   # expect >= 3
```

**Why the gate exists.** Every task below configures an agent or command to read `## Boundary`. Written today, against zero examples, the instructions would be guesses about what that section turns out to contain. Written after three real domains, they can quote the actual shape and say something specific enough to change agent behaviour. Deferring costs nothing because there is nothing to read yet; writing it now and getting it wrong costs a revision across 15 files.

**Why this plan was written now anyway.** The reading side is not optional garnish — without it, Phase 1 enforces the format of a file nobody opens, which is ceremony. Verified at authoring time: `ARCHITECTURE.md` has **zero** references anywhere under `.claude/` (agents, commands, docs, rules). A deferred intention gets forgotten; a written plan sitting in `docs/` does not. Status `BLOCKED` is the honest state, not an excuse to skip it.

---

## Context

Phase 1 makes every `Concretes/<Domain>/` carry a 40-line, English, class-name-free `ARCHITECTURE.md` with four headings: `## Purpose`, `## Boundary`, `## How to extend`, `## Gotchas`. It enforces the shape mechanically and blocks malformed docs.

It does not make anything read them.

The one section that earns its keep is **`## Boundary`** — and specifically because it holds the one class of information `/knowledge-graph` structurally cannot produce. The graph reports facts derived from code: what exists, who depends on whom, who publishes which event, what breaks if a class changes. `## Boundary` records a *decision*: "this domain does not track score — that belongs to Score." No amount of static analysis recovers that, because a boundary violation looks exactly like a working dependency. The reading side is therefore not a convenience; it is the only way the information reaches a consumer at all.

There is a second, more mundane payoff. Graph-aware commands currently degrade to a full file scan whenever the graph is empty or stale (`/search`, `/catch-up`, `/create-plan`, and others all say "query graph first, fall back to file-scan"). Twenty-five domain docs are ~1000 lines total and describe the whole territory. That is a far cheaper fallback than reading thousands of lines of source, so the docs slot naturally between the graph and the file system as a second tier.

**Known limitation, accepted.** `## Boundary` can go stale when a domain's responsibility genuinely changes, and **no mechanism detects it** — unlike class names, which Phase 1's regex bans precisely because their rot is mechanically detectable. Intent rot is slower but invisible. The only defence is Task 3: the reviewer comparing the change against the stated boundary. When they disagree, either the code or the doc is wrong, and either way somebody updates something.

---

## Goals

1. Every agent that writes, fixes, tests or reviews code inside a domain has read that domain's `## Boundary` first.
2. Exploration agents surface `## Boundary` for the whole affected area, so planning lands work in the right domain.
3. Reviewers actively check changes against the stated boundary — the one check the graph cannot perform.
4. Research commands consult docs as a second tier, before falling back to a file scan.
5. Orphan and missing docs are reconciled periodically, closing the one rot vector a per-write hook structurally cannot see.
6. No agent's Step 0 grows by more than a few lines; total added context stays negligible.

**Non-goals:** new hooks; changing the doc format (that is Phase 1's contract); touching `committer` or `unity-git-master` (diff and message work — domain boundaries are not their concern); any Unity C# code.

---

## Chosen Approach

### Differentiated instructions, not one shared sentence

Three roles need three different things. Giving all of them the same line would be genuinely wasteful duplication; splitting by role is what makes the redundancy worth paying for.

| Role | Agents | Instruction shape | Failure it prevents |
|---|---|---|---|
| **Breadth** | `unity-scout`, `Explore` | Read every relevant domain's doc; collect `## Boundary` under its own heading in the report | Work planned into the wrong domain |
| **Depth** | `unity-coder`, `coder`, `unity-fixer`, `tester` | Read the doc for the domain you are editing; apply `## Boundary` literally | Code added to a domain that explicitly disclaims that responsibility |
| **Audit** | `reviewer`, `unity-reviewer` | Check the change against `## Boundary`; flag violations | Boundary erosion landing unnoticed |

The depth tier is not made redundant by the breadth tier. Scout does not run in every pipeline — `/implement` goes straight to the coder — so a scout-only instruction leaves the most common path unread. And a summary is lossy: the agent writing the code should see the boundary verbatim, not paraphrased.

The audit tier is where the highest return sits. A reviewer holding `## Boundary` can ask a question no other tool in this repo can answer: *is this dependency legitimate, or did we just violate a documented decision?*

### Three-tier research order

Graph-aware commands get an explicit tier list rather than a vague "also read the docs":

| Tier | Source | Question it answers |
|---|---|---|
| 1 | `/knowledge-graph` | What exists; who depends on whom; blast radius |
| 2 | `Concretes/*/ARCHITECTURE.md` | What belongs where; what each domain refuses to do |
| 3 | Source files | Only the specific detail tiers 1 and 2 cannot give |

Stated as an ordered list because the point is *not reading tier 3* when tiers 1 and 2 suffice.

### Reconciliation in the graph builder, not a hook

Three cases are invisible to a per-write hook: a domain folder deleted with its doc left behind; a domain renamed, orphaning the old doc; all `.cs` files moved out, leaving a doc describing code that lives elsewhere. None of these produce an `Edit|Write` event — they happen through `Bash rm`, `git mv`, or an IDE. Trying to catch them with a hook means intercepting `rm` and `git mv`: fragile, leaky, and noisy.

`graph-builder.py` already walks the `Concretes/` tree. Two extra checks cost approximately nothing and, unlike any per-write hook, see the whole tree at once:

```
ORPHAN DOC   — Concretes/<X>/ARCHITECTURE.md exists, 0 .cs files in that folder
MISSING DOC  — Concretes/<X>/ contains .cs files, no ARCHITECTURE.md
```

**Accepted weakness:** `/build-knowledge-graph` is run manually. This guarantees "caught eventually", not "caught immediately". That is the correct trade for a rare, low-severity condition — and `MISSING DOC` is already covered immediately by Phase 1's Trigger A warning, so only the orphan case relies on the periodic pass.

---

## Status

| # | Task | parallel_group | Depends on |
|---|------|----------------|------------|
| 1 | Breadth: `unity-scout`, `Explore` Step 0 | A | unblock condition |
| 2 | Depth: `unity-coder`, `coder`, `unity-fixer`, `tester` Step 0 | A | unblock condition |
| 3 | Audit: `reviewer`, `unity-reviewer` review criteria | A | unblock condition |
| 4 | Three-tier Step 0 in the 7 graph-aware research commands | A | unblock condition |
| 5 | `graph-builder.py` — ORPHAN DOC / MISSING DOC reconciliation | A | unblock condition |
| 6 | `/knowledge-graph summary` — surface the reconciliation output | B | 5 |
| 7 | Docs: record the reading contract in `architecture.md` + `.claude/CLAUDE.md` | B | 1–5 |

Tasks 1–5 touch disjoint file sets and can run together. Task 6 depends on Task 5's output format. Task 7 documents what 1–5 established.

---

## File Map

| Path | Action |
|------|--------|
| `.claude/agents/unity-scout.md` | edit — Step 0 breadth instruction |
| `.claude/agents/Explore` equivalent (built-in overlay, if present under `.claude/agents/`) | edit — breadth instruction; skip if no overlay file exists |
| `.claude/agents/unity-coder.md` | edit — Step 0 depth instruction |
| `.claude/agents/coder.md` | edit — Step 0 depth instruction |
| `.claude/agents/unity-fixer.md` | edit — Step 0 depth instruction |
| `.claude/agents/tester.md` | edit — Step 0 depth instruction |
| `.claude/agents/reviewer.md` | edit — boundary check in review criteria |
| `.claude/agents/unity-reviewer.md` | edit — boundary check in review criteria |
| `.claude/commands/search.md` | edit — three-tier Step 0 |
| `.claude/commands/catch-up.md` | edit — three-tier Step 0 |
| `.claude/commands/context-prime.md` | edit — three-tier Step 0 |
| `.claude/commands/create-plan.md` | edit — three-tier Step 0 |
| `.claude/commands/plan-module.md` | edit — three-tier Step 0 |
| `.claude/commands/architect.md` | edit — three-tier Step 0 |
| `.claude/commands/fix-deep.md` | edit — three-tier Step 0 |
| `.claude/graph/graph-builder.py` | edit — reconciliation checks |
| `.claude/commands/knowledge-graph.md` | edit — surface reconciliation in `summary` |
| `.claude/rules/architecture.md` | edit — one paragraph on the reading contract |
| `.claude/CLAUDE.md` | edit — session-start guidance mentions domain docs |

Verify each agent and command filename against the live tree at implementation time; `.claude/docs/agents-index.md` is the authority for agent filenames, and some commands may have been renamed since this plan was written.

---

## Task 1 — Breadth: `unity-scout` and `Explore` read all relevant domain docs

**Files:** `.claude/agents/unity-scout.md`, and the `Explore` overlay under `.claude/agents/` if one exists

**Steps:**
1. [ ] Read the existing Step 0 of `unity-scout.md` and match its formatting and voice.
2. [ ] Add an instruction: for every domain the task touches or might touch, read `_GameFolders/Scripts/Games/Concretes/<Domain>/ARCHITECTURE.md`. Each is <= 40 lines; reading all of them is cheap.
3. [ ] Require a dedicated section in the report — `### Domain Boundaries` — quoting each domain's `## Boundary` verbatim, one bullet per domain. Verbatim, not summarized: the downstream planner needs the actual wording.
4. [ ] State what it is for: deciding which domain owns the work, and spotting when a request implies crossing a boundary a domain explicitly disclaims.
5. [ ] Note that a missing doc is a finding worth reporting, not an error to stop on.
6. [ ] If no `Explore` overlay file exists under `.claude/agents/`, note that in the plan and skip it — do not create an overlay solely for this.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n 'ARCHITECTURE.md' .claude/agents/unity-scout.md
grep -n 'Domain Boundaries' .claude/agents/unity-scout.md
```
Expected: both present; exit 0.

**Acceptance Criteria:**
- [ ] `unity-scout`'s Step 0 names the doc path pattern explicitly.
- [ ] The output format gains a `### Domain Boundaries` section requiring verbatim `## Boundary` text.
- [ ] A missing doc is described as reportable, not fatal.
- [ ] No other part of the agent prompt is altered.

---

## Task 2 — Depth: code-writing agents read the doc for the domain they touch

**Files:** `.claude/agents/unity-coder.md`, `.claude/agents/coder.md`, `.claude/agents/unity-fixer.md`, `.claude/agents/tester.md`

**Steps:**
1. [ ] For each agent, locate the existing Step 0 (they all read `.claude/docs/auto-loaded-skills.md` first — insert after that, before the skill-loading detail).
2. [ ] Add: before writing to any file under `Games/Concretes/<Domain>/` or `Games/Abstracts/<Domain>/`, read `Games/Concretes/<Domain>/ARCHITECTURE.md`.
3. [ ] Make the obligation concrete rather than advisory: `## Boundary` states what this domain must not do. If the task appears to require crossing it, stop and say so instead of writing the code — the correct move is usually a different domain or an event, not a boundary violation.
4. [ ] Keep it to 3–4 lines per agent. Step 0 is already long; this must not compete with skill loading.
5. [ ] Do **not** add this to `committer` or `unity-git-master` — their work is diffs and messages.
6. [ ] Verify each agent file still parses as a coherent prompt after the insertion (headings intact, no orphaned list numbering).

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
for a in unity-coder coder unity-fixer tester; do
  printf '%-14s %s\n' "$a" "$(grep -c 'ARCHITECTURE.md' .claude/agents/$a.md)"
done
for a in committer unity-git-master; do
  printf '%-18s %s (expect 0)\n' "$a" "$(grep -c 'ARCHITECTURE.md' .claude/agents/$a.md)"
done
```
Expected: 1+ for the first four, 0 for the last two.

**Acceptance Criteria:**
- [ ] All four agents instruct reading the touched domain's doc before writing.
- [ ] The instruction says to stop and report on an apparent boundary conflict rather than proceeding.
- [ ] `committer` and `unity-git-master` are untouched.
- [ ] No agent's Step 0 grew by more than ~4 lines.

---

## Task 3 — Audit: reviewers check the change against `## Boundary`

**Files:** `.claude/agents/reviewer.md`, `.claude/agents/unity-reviewer.md`

**Steps:**
1. [ ] Locate each agent's review-criteria list.
2. [ ] Add a numbered criterion: **Domain boundary** — for every domain touched, read its `ARCHITECTURE.md` and check whether the change violates the stated `## Boundary`.
3. [ ] Spell out the two outcomes so the reviewer does not have to invent them: if the code is wrong, report it as a violation with the quoted boundary line; if the boundary statement is now genuinely out of date, report that the doc needs updating. Both are findings; silence is not an option.
4. [ ] Explain why this criterion exists and cannot be replaced by a graph query: a boundary violation is indistinguishable from a working dependency at the code level. `/knowledge-graph impact` sees the edge; only the doc says whether the edge was supposed to exist.
5. [ ] Keep the criterion to 3–4 lines, consistent with the neighbouring criteria.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n -i 'boundary' .claude/agents/reviewer.md .claude/agents/unity-reviewer.md
```
Expected: at least one hit in each file.

**Acceptance Criteria:**
- [ ] Both reviewers carry an explicit domain-boundary criterion.
- [ ] Both outcomes (code wrong / doc stale) are named as reportable findings.
- [ ] The criterion states why a graph query cannot substitute for it.
- [ ] Existing criteria are unchanged and renumbering is consistent.

---

## Task 4 — Three-tier research order in the graph-aware commands

**Files:** `.claude/commands/search.md`, `catch-up.md`, `context-prime.md`, `create-plan.md`, `plan-module.md`, `architect.md`, `fix-deep.md`

**Steps:**
1. [ ] Confirm the current command list against `.claude/docs/commands.md` — some may have been renamed since this plan was written. Adjust the file list rather than editing a stale name.
2. [ ] In each command's Step 0 (the graph preload / graph-first block), insert the middle tier between the graph query and the file-scan fallback.
3. [ ] Write it as an **ordered** list, since the value is in *not* reaching tier 3: tier 1 graph → tier 2 `Concretes/*/ARCHITECTURE.md` → tier 3 source files, for the specific detail neither earlier tier provides.
4. [ ] State the fallback value explicitly: when the graph is empty or stale, ~25 docs at <= 40 lines each is a far cheaper territory map than a source scan, so tier 2 partly replaces the file-scan fallback rather than merely preceding it.
5. [ ] Pass domain-boundary text into any subagent prompt these commands construct, so the researcher/planner receives it rather than re-deriving it.
6. [ ] Keep each edit small and identically worded across the seven commands, so the pattern is recognizable and greppable.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
for c in search catch-up context-prime create-plan plan-module architect fix-deep; do
  printf '%-14s %s\n' "$c" "$(grep -c 'ARCHITECTURE.md' .claude/commands/$c.md 2>/dev/null || echo MISSING)"
done
```
Expected: 1+ for every command that exists; any `MISSING` means the filename changed and the list needs correcting.

**Acceptance Criteria:**
- [ ] All seven (or their current equivalents) carry the three-tier order.
- [ ] The tier list is ordered and states that tier 3 is a last resort.
- [ ] Commands that build subagent prompts pass the boundary text through.
- [ ] Wording is consistent across all seven, greppable with one pattern.

---

## Task 5 — `graph-builder.py`: ORPHAN DOC / MISSING DOC reconciliation

**Files:** `.claude/graph/graph-builder.py`

**Steps:**
1. [ ] Find where the builder walks `_GameFolders/Scripts/Games/Concretes/`. Reuse that walk — do not add a second traversal.
2. [ ] Respect `unity_project_folder` from `.claude/project-features.json` for the path prefix. Never hardcode `Assets/` or `_GameFolders/`.
3. [ ] For each immediate child directory of `Concretes/`, compute two booleans: does it contain at least one `.cs` (at any depth beneath it), and does it contain `ARCHITECTURE.md` at its own level.
4. [ ] Emit `ORPHAN DOC` when a doc exists with zero `.cs` beneath it, and `MISSING DOC` for the inverse.
5. [ ] Report as warnings, never as errors — the builder must not fail on a documentation gap.
6. [ ] Include the findings in the builder's stderr summary and, if the graph JSON carries a warnings collection, add them there too so `/knowledge-graph` can surface them (Task 6).
7. [ ] Do **not** treat a domain with only subfolders as orphaned — the `.cs` search is recursive beneath the domain, the `ARCHITECTURE.md` check is not.
8. [ ] Note in a code comment why this lives here rather than in a hook: file deletion and `git mv` produce no `Edit|Write` event, so no per-write hook can observe them.

**Test Type:** NoTest (python) — verified by running the builder against a scratch tree

**Manual verification:**
```bash
T=$(mktemp -d)
mkdir -p "$T/Games/Concretes/Orphan" "$T/Games/Concretes/Undocumented/Handlers"
printf '# Orphan\n' > "$T/Games/Concretes/Orphan/ARCHITECTURE.md"
printf 'class X {}\n' > "$T/Games/Concretes/Undocumented/Handlers/MoveHandler.cs"
# run the builder against $T and confirm one ORPHAN DOC (Orphan) and one MISSING DOC (Undocumented)
python3 .claude/graph/graph-builder.py --help   # confirm how to point it at a scratch root
```
Expected: exactly one `ORPHAN DOC` and one `MISSING DOC`; builder exit code 0.

**Acceptance Criteria:**
- [ ] Both conditions detected on a scratch tree, with the domain name in each message.
- [ ] The builder exits 0 despite findings.
- [ ] No second tree walk added.
- [ ] `unity_project_folder` respected; no hardcoded paths.
- [ ] A domain whose `.cs` files live only in subfolders is **not** flagged as orphaned.
- [ ] A code comment records why this is not a hook.

---

## Task 6 — `/knowledge-graph summary` surfaces the reconciliation

**Files:** `.claude/commands/knowledge-graph.md`
**Depends on:** Task 5

**Steps:**
1. [ ] Locate the `summary` subcommand's output section.
2. [ ] Add a `DOC RECONCILIATION` block listing `ORPHAN DOC` and `MISSING DOC` findings, or `none` when clean.
3. [ ] Since `.claude/CLAUDE.md` tells a new session to run `/knowledge-graph summary` at session start, this is the natural place for a stale-documentation signal to reach a human.
4. [ ] Keep it a short block — a count plus the offending domain names, not a wall of text.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n 'DOC RECONCILIATION\|ORPHAN DOC' .claude/commands/knowledge-graph.md
```
Expected: at least one hit.

**Acceptance Criteria:**
- [ ] `summary` documents the reconciliation block.
- [ ] The clean case prints `none` rather than nothing, so a reader can tell the check ran.
- [ ] Other subcommands are untouched.

---

## Task 7 — Record the reading contract in the rules

**Files:** `.claude/rules/architecture.md`, `.claude/CLAUDE.md`
**Depends on:** Tasks 1–5

**Steps:**
1. [ ] In `architecture.md`'s Domain Folder Convention section (added by Phase 1 Task 5), add a short **Who reads this** paragraph: which agent roles read the doc and what each does with it.
2. [ ] State the point that motivates the whole convention: `## Boundary` is the only part of this system that records a *decision* rather than a *fact*, which is exactly why the graph cannot produce it and why agents must read it.
3. [ ] Record the accepted limitation plainly: `## Boundary` can go stale when a domain's responsibility genuinely changes, and nothing detects that automatically — the reviewer's boundary check is the only defence.
4. [ ] In `.claude/CLAUDE.md`'s Session Start section, add domain docs to what a new session reads: after the graph summary, read the `ARCHITECTURE.md` of any domain the session will touch.
5. [ ] Update this plan's status from `BLOCKED` to `Complete` and note the date the unblock condition was met.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n -i 'who reads this' .claude/rules/architecture.md
grep -n 'ARCHITECTURE.md' .claude/CLAUDE.md
```
Expected: both present.

**Acceptance Criteria:**
- [ ] `architecture.md` names the reader roles and the fact-vs-decision distinction.
- [ ] The intent-rot limitation is stated, not hidden.
- [ ] `.claude/CLAUDE.md` Session Start mentions domain docs.
- [ ] This plan's status is updated.

---

## Revision History

**v1 — 2026-08-05** — created during the `/grill-me` stress-test of `docs/PLAN_domain_folder_convention.md`, from decisions D2 (differentiated reading instructions across breadth/depth/audit roles, plus the three-tier research order), D5 (orphan-doc reconciliation in the graph builder rather than a hook), and D7 (split Phase 1 enforcement from Phase 2 consumption).

Written immediately and held at `BLOCKED` rather than left as an intention, because the grill established that Phase 1 without Phase 2 is enforcement of a file nobody reads — and because deferred work that exists only as a plan in someone's head does not get done.
