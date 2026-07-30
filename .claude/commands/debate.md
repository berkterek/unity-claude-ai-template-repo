# /debate — Adversarial Design Stress-Test (Proposer ↔ Critic → Moderator)

Stress-tests **any idea, thesis, or plan** through an independent 3-agent debate and returns a rule-grounded, triaged verdict: **REFUTED / CONFIRMED / ESCALATE**.

This is a **standalone** command — it is not baked into any pipeline. Point it at a bare idea *before* a plan exists (when the cheapest design corrections are still available), or at an existing plan file. `/create-plan` and `/architect` MAY call it, but it never requires them.

## What it is NOT

- Not `unity-critic` — that is a single-pass reviewer of a Unity *implementation plan*, used inside `/architect`. This command debates an *arbitrary thesis* through an adversarial ensemble (a proposer defends, a separate critic attacks, a neutral moderator adjudicates).
- Not `grill-me` — that is an interactive, human-answers-every-branch interview. This runs **unattended** and only surfaces genuine human trade-offs (ESCALATE). Chain `/grill-me` on the ESCALATE items yourself if you want.

## Usage

```
/debate <idea | plan-file-path | one-line thesis>
/debate should we add an EnemyManager MonoBehaviour registry instead of an EnemyDirectorService
/debate Docs/PLAN_audio_spatial.md
```

If no argument is given, ask: "What idea, thesis, or plan file should I put on trial?"

## Pipeline

```
[0] GROUNDING DETECT → [1] PROPOSER → [2] CRITIC → [3] MODERATOR (triage) → [4] VERDICT
```

Single pass — one proposer brief, one critic attack, one moderator adjudication. (There is deliberately no rebuttal loop: a tool-equipped Opus moderator settles verifiable clashes itself and escalates genuine value calls, so a second round adds cost without changing the verdict.)

All three debate agents are **Opus** (Lead-tier: defend / attack / adjudicate are all decision work — model-tiers.md). The grounding scan is **Haiku**.

---

## Step 0 — Grounding Mode Detect

Classify the target so the debate is either grounded in real code or explicitly flagged as reasoning-only.

- **GROUNDED** — the target references a plan file, a real class/interface/event name, a file path, or a graph entity. Spawn an **Explore** subagent (`model: haiku`) to gather the real facts the debate must respect:
  ```
  You are grounding an adversarial debate for a Unity project.
  Target: [INSERT the /debate argument]
  Gather ONLY facts the debaters must not contradict:
  1. If a plan file path is given, read it in full.
  2. Real class/interface/event/installer names involved (query .claude/graph/graph.json if graph is enabled & fresh <24h, else scan source).
  3. The specific .claude/rules/*.md cards that govern this area (architecture, solid-oop, csharp-unity, bootstrap-pattern, etc.).
  4. Any existing plan in Docs/ that overlaps.
  Report facts only — no opinions, no debate. This becomes GROUNDING_CONTEXT.
  ```
  Keep the output as `GROUNDING_CONTEXT`.

- **UNGROUNDED** — the target is a pure abstract idea with no code anchor. Set `GROUNDING_CONTEXT` to `"UNGROUNDED — no code anchor; verdicts are reasoning-only and NOT verified against the codebase."` Do not fabricate file names or rules in this mode.

---

## Step 1 — Proposer

Spawn `subagent_type: "debate-proposer"` (`model: opus`):

```
You are the PROPOSER in a structured adversarial debate.

## Thesis on trial
[INSERT the /debate argument]

## Grounding
[INSERT GROUNDING_CONTEXT]

Build the STRONGEST possible case FOR the thesis (steelman). Follow your agent instructions.
Return: core value thesis + the top concrete arguments FOR + the exact gap/need it fills.
```

Keep the output as `PROPOSER_BRIEF`.

---

## Step 2 — Critic

Spawn `subagent_type: "debate-critic"` (`model: opus`):

```
You are the CRITIC in a structured adversarial debate. REFUTE the thesis.

## Thesis on trial
[INSERT the /debate argument]

## Grounding
[INSERT GROUNDING_CONTEXT]

## Proposer's defense (attack this specifically)
[INSERT PROPOSER_BRIEF]

Produce a NUMBERED list of DISTINCT objections. Each: claim + why it bites (cite a real rule/file when GROUNDED) + confidence tag (FACT vs OPINION). Default posture: skeptical. Follow your agent instructions.
```

Keep the output as `CRITIC_OBJECTIONS`.

---

## Step 3 — Moderator (triage)

Spawn `subagent_type: "debate-moderator"` (`model: opus`):

```
You are the MODERATOR (judge) of a structured adversarial debate.

## Thesis on trial
[INSERT the /debate argument]

## Grounding
[INSERT GROUNDING_CONTEXT]

## Proposer's defense
[INSERT PROPOSER_BRIEF]

## Critic's objections
[INSERT CRITIC_OBJECTIONS]

Triage EVERY objection into exactly one of REFUTED / CONFIRMED / ESCALATE using your adjudication rules. Settle any verifiable fact or rule clash yourself with Read/Glob/Grep — do not leave anything open. Follow your agent instructions for the output format.
```

The moderator's verdict is final in one pass → go to Step 4.

---

## Step 4 — Verdict

Print the moderator's final report in this shape:

```
## Debate Verdict — <target>
Mode: GROUNDED | UNGROUNDED

### CONFIRMED — survived refutation (real defects / real support)
- <point> — why it stands + rule/file cite (if grounded) + confidence

### ESCALATE — needs your judgment (genuine trade-off, rules can't decide)
- <question> — the fork + each side's cost

### REFUTED — raised but killed
- <objection> — how it was refuted

### Proposer's core thesis (reference)
- <one line>

Recommended next: /grill-me on the ESCALATE items · /create-plan · proceed · drop the idea
```

If **UNGROUNDED**, prefix the report with:
`⚠ UNGROUNDED debate — verdicts are reasoning-only and were NOT verified against the codebase. Re-run against a plan file or named code for grounded confidence.`

---

## Notes

- **No files are written or committed** by this command — it is pure analysis. The verdict is printed to the conversation only.
- **No hooks / settings.json changes** — commands and agents are plain `.md`.
- Cost envelope: GROUNDED = 1 Haiku (grounding) + 3 Opus (proposer, critic, moderator). UNGROUNDED = 3 Opus (grounding scan skipped).

$ARGUMENTS
