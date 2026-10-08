# Rule-Awareness Probe

Measures what the instruction-loading layout makes a **fresh session plan**, by grepping a planning answer for
rule-mandated markers. It exists because `reviewer-fixtures` cannot see this: the reviewer is handed its
criteria in the prompt, so it is independent of which rules are loaded.

Non-deterministic and costs one `claude -p` call per prompt per run. Compare means, never single runs.
Do not edit a prompt or a marker to make a run look better — that resets the baseline.

Run: `.claude/tests/rule-awareness-probe/run-probe.sh 3`

## Recorded runs

| Date | Layout | settings-persist | test-plan | milestone | heart-row | Note |
|---|---|---|---|---|---|---|
| 2026-10-08 | baseline — all 22 rules unscoped, `@` imports dead | 4.33/5 | 4.66/5 | 3.00/3 | 1.66/3 | 3 runs each; `/context` Memory files 185.2k tokens; startup warning 24 files / 469.5k chars |
