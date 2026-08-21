# Reviewer-Prompt Fixture

A planted-defect fixture for measuring what a **reviewer prompt actually makes an agent do**.

## Why this exists

`.claude/hooks/tests/` holds 36 `bats` suites and every one of them measures a shell script: feed a file to a hook, assert the exit code. Deterministic, automatable, cheap. None of them can measure a prompt, because a prompt is not a script — a model reads it and emits prose, not an exit code.

That gap is not theoretical. On 2026-08-21 two edits to the reviewer criteria in `implement.md` / `fix.md` / `fix-deep.md` / `orchestrate.md` passed every static check available — 417/417 hook tests, every cited line number resolved, every count line matched its list, the gate inventory was symmetric — while both edits were making the reviewer measurably worse. They were caught by running an agent against this fixture, and only by that.

## What it is

`make-fixture.sh` writes two C# files into a temp dir and prints the path. They are deliberately defective. It is a generator rather than two committed files because the defects would be blocked on `Write` by `check-vcontainer-singleton.sh` and `check-no-linq-hotpath.sh` — correctly. Do not work around those hooks to commit a defective `.cs`; the bats suites solve the same problem the same way, with `mktemp -d`.

## Answer key

| # | Defect | File:line | Which criterion must catch it |
|---|--------|-----------|-------------------------------|
| D1 | `FindObjectOfType<TargetTracker>()` | `TurretController.cs:23` | **TD-ARCHITECTURE** (`rules/architecture.md:28` — singleton in disguise). Also listed Forbidden in `deprecated-apis.md`, so **TD-UNITY-RISK** may claim it too |
| D2 | LINQ `.Where().OrderBy()` inside `Update()` | `TurretController.cs:28` | **TD-PERFORMANCE** (zero-alloc hot path) |
| D3 | `_renderer.material` write (clones the material) | `TurretController.cs:31` | **TD-PERFORMANCE** (`rules/performance.md:142-159`) |
| D4 | `Resources.Load<AudioClip>()` | `TurretController.cs:43` | **TD-UNITY-RISK** (`deprecated-apis.md` Forbidden → Addressables) |
| D5 | `IRecoilProfile` — zero implementers, zero consumers | `IRecoilProfile.cs` (whole file) | **CD-SCOPE** (zero-caller abstraction) |
| D6 | field declared inside `#region Private Methods` | `TurretController.cs:39` | *Nothing currently.* No criterion in these lists covers `#region` discipline — a known, deliberate coverage gap, not a fixture bug |

There is no `?.`-on-UnityEngine-object defect, no `async void`, no renamed `[SerializeField]`, and no `UnityEvent`. Those criteria **must** come back `CONFIRMED`. A run that marks them `GAP` is reporting a false positive, and that is the second thing this fixture measures.

## How to run it

1. `FIXTURE_DIR="$(.claude/tests/reviewer-fixtures/make-fixture.sh)"`
2. Spawn a reviewer agent with the exact `## Review Criteria` and `## Output contract` blocks from the command under test, pointed at both files. Tell it `IRecoilProfile` came from the same change and that nothing else in the repo references either file — without that, D5 is unfair.
3. Score two numbers against the key above:
   - **coverage** — how many of D1–D5 were caught, and under which criterion
   - **false positives** — how many `GAP` verdicts have an evidence sentence that denies any violation

Do not change the fixture to make a run look better. If a criterion legitimately does not cover a defect, that is a coverage finding to record, like D6.

## Recorded runs

| Date | What changed | Coverage | False `GAP` | Note |
|------|--------------|----------|-------------|------|
| 2026-08-21 | criteria 9 + 10 added (TD-UNITY-RISK, CD-SCOPE) | 4/5 | **4/10** | D5 missed by CD-SCOPE, noticed by the Events criterion instead. The four false GAPs each had evidence contradicting the verdict — criterion 7 read "no `?.`/`is null` misuse found" and was still marked `GAP` |
| 2026-08-21 | A/B on TD-ARCHITECTURE body: five bullets vs a prose pointer to the same rules | bullets **5/5** axes, pointer **3/5** | — | Both arms caught D1, so the pointer was not blunter — it was narrower. The pointer form silently skipped IEventBus and module boundaries; nothing told it those axes existed. The bullet list is the coverage contract, and was reverted back |
| 2026-08-21 | CD-SCOPE reworded (zero vs one caller made explicit); `GAP` requires a pointable violation added to all four output contracts | **5/5** | **0/10** | D5 caught under CD-SCOPE as intended. Criterion 7 became `CONFIRMED` citing `closest == null` at line 29 — verdict now matches its own evidence |

## Limits — read these before treating a number as a regression

- **Not deterministic.** An LLM's output varies between runs. A `4/10 → 0/10` move is a signal; a `5/5 → 4/5` move may be noise. Re-run before concluding.
- **Not CI-able.** Running it costs an agent invocation. It belongs at the point where someone edits a reviewer prompt, not on every commit.
- **Needs maintenance.** If a criteria list changes, the answer key's right-hand column must change with it, or the fixture will report a false regression.
- **One fixture, one shape of defect.** It says nothing about ECS, Addressables handle lifecycle, async, or scene wiring. Passing it is not "the reviewer works".
