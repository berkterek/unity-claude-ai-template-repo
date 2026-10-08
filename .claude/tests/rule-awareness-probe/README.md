# Rule-Awareness Probe

Measures what the instruction-loading layout makes a **fresh session plan**, by grepping a planning answer for
rule-mandated markers. It exists because `reviewer-fixtures` cannot see this: the reviewer is handed its
criteria in the prompt, so it is independent of which rules are loaded.

Non-deterministic and costs one `claude -p` call per prompt per run. Compare means, never single runs.
Do not edit a prompt or a marker to make a run look better — that resets the baseline.

Run: `.claude/tests/rule-awareness-probe/run-probe.sh 3`

**Score the whole answer, not the final message.** In plan mode the full plan is written through a `Write` /
`ExitPlanMode` tool input and the final message is a summary; grading only the summary under-counted at random
(2026-10-08: a plan with all 5 markers scored 3/5). The runner reads `stream-json` and scores both. The first
recorded row below used the old summary-only scoring and is **not comparable** to later rows.

**Compare layouts with a worktree, never against an old row.** Run the same runner against the old commit
(`git worktree add <dir> <commit>` then run its copy of this script from there) so both sides share the scorer,
the model version and the day.

## Recorded runs

| Date | Layout | settings-persist | test-plan | milestone | heart-row | Note |
|---|---|---|---|---|---|---|
| 2026-10-08 | baseline — all 22 rules unscoped, `@` imports dead | 4.33/5 | 4.66/5 | 3.00/3 | 1.66/3 | **v1 scorer (summary only) — not comparable.** `/context` Memory files 185.2k tokens; startup warning 24 files / 469.5k chars |
| 2026-10-08 | baseline (worktree @ 3477aa5), v2 scorer | 4.66/5 | 4.33/5 | 2.66/3 | 1.66/3 | 3 runs each, run in parallel with the row below |
| 2026-10-08 | scoped rules + 3 awareness nets (@ 2516c64), v2 scorer | 4.33/5 | 4.33/5 | 3.00/3 | 1.00/3 | `/context` Memory files 60.6k tokens; no startup warning. heart-row: see note |

**heart-row markers are invalid for a Unity 6 template — fix before the next comparison.** `LayoutGroup` and
`Raycast Target` are UGUI-only. Both layouts route a HUD to UI Toolkit (Card 1); the baseline scored only because
its answer mentioned `HorizontalLayoutGroup` in the UGUI fallback paragraph. A verbose trace of the new layout
showed it Read `ui-toolkit-runtime.md` and `unity-prefabs.md` and applied more cards (one heart template driven by
config — the prefab-DRY rule the markers were proxying for —, event-patterns Card 5, ui-toolkit Cards 10/11/13).
The markers were deliberately not changed after seeing these results; replace them with UI-system-independent
ones (e.g. "one definition / template", "not three copies") and re-run **both** layouts.
